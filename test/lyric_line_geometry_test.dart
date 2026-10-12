// Pins the per-ROW geometry of a laid-out lyric line.
//
// The old renderer measured one number per character - the caret's x - which is
// a fact about a single row. On a line that wrapped, x reset to about zero on
// row two, so the lit clip lit both rows at once and every lifted word was drawn
// at the top of the line ("You're going t|o put / ɛme outg   o" on a device).
// These tests lay a line out NARROWER than its text on purpose, so it wraps, and
// pin what a row means.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_line_geometry.dart';

// `flutter_test` renders text in Ahem: every glyph is exactly one em wide and
// one em tall, which makes the expected geometry exact arithmetic.
const double _em = 20;
const TextStyle _style = TextStyle(fontSize: _em, height: 1.0);

TextPainter _layout(String text, {required double width, int? maxLines, String? ellipsis}) {
  return TextPainter(
    text: TextSpan(text: text, style: _style),
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: ellipsis,
  )..layout(maxWidth: width);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a line that wraps', () {
    // 10 glyphs fit in 200px. "aaaa bbbb " fills row one; "cccc dddd" is row two.
    const text = 'aaaa bbbb cccc dddd';
    late LyricLineGeometry g;

    setUp(() {
      g = LyricLineGeometry.measure(_layout(text, width: 10 * _em), text);
    });

    test('is two rows, and the second does not start where the first does', () {
      expect(g.rowCount, 2);
      expect(g.rows[0].start, 0);
      expect(g.rows[1].start, greaterThan(g.rows[0].start));
      expect(g.rows[0].end, g.rows[1].start,
          reason: 'every character belongs to exactly one row');
      expect(g.rows[1].end, text.length);
    });

    test('rows are contiguous bands that tile the paragraph', () {
      expect(g.rows[0].top, 0);
      expect(g.rows[1].top, closeTo(g.rows[0].bottom, 0.01));
      expect(g.rows[0].height, closeTo(_em, 0.01));
      expect(g.rows[1].height, closeTo(_em, 0.01));
    });

    test('x RESTARTS on row two - which is exactly why a single x per '
        'character was wrong', () {
      final firstOfRowTwo = g.rows[1].start;
      expect(g.charLeft[firstOfRowTwo], closeTo(0, 0.01));
      expect(g.charLeft[firstOfRowTwo], lessThan(g.charLeft[g.rows[0].end - 2]),
          reason: 'row two begins left of where row one ends');
      expect(g.charRow[firstOfRowTwo], 1);
      expect(g.charRow[0], 0);
    });

    test('a position on row two answers with an x on row two, never row one\'s',
        () {
      final inRowTwo = g.rows[1].start + 2.5;
      // Row one is behind the voice, so its edge is its own right edge.
      expect(g.xAt(0, inRowTwo, const []), g.rows[0].right);
      // Row two is where the voice is: two and a half glyphs in.
      expect(g.xAt(1, inRowTwo, const []), closeTo(2.5 * _em, 0.5));
    });

    test('a row the voice has not reached is lit to nothing', () {
      expect(g.xAt(1, 3.0, const []), g.rows[1].left);
    });

    test('a span that lies entirely on one row moves at constant speed', () {
      // "cccc" is characters 10..14, all on row two.
      final span = [(g.rows[1].start, g.rows[1].start + 4)];
      final a = g.xAt(1, g.rows[1].start + 1.0, span);
      final b = g.xAt(1, g.rows[1].start + 2.0, span);
      final c = g.xAt(1, g.rows[1].start + 3.0, span);
      expect(b - a, closeTo(c - b, 0.5));
      expect(b - a, closeTo(_em, 0.5));
    });

    test('forEachRowSegment gives a wrapped range one segment PER ROW, each in '
        'its own row\'s x', () {
      // From the middle of row one into the middle of row two: "bbbb cccc".
      final start = g.rows[0].end - 4;
      final end = g.rows[1].start + 3;
      final seen = <(int, double, double)>[];
      g.forEachRowSegment(start, end, (row, x0, x1) => seen.add((row, x0, x1)));

      expect(seen.map((s) => s.$1), [0, 1],
          reason: 'one visit per row the range touches');
      for (final (row, x0, x1) in seen) {
        expect(x1, greaterThan(x0), reason: 'never a negative or empty width');
        expect(x0, greaterThanOrEqualTo(g.rows[row].left - 0.01));
        expect(x1, lessThanOrEqualTo(g.rows[row].right + 0.01));
      }
      // The row-two piece starts at the left margin, not at row one's x.
      expect(seen[1].$2, closeTo(0, 0.01));
    });
  });

  group('a word longer than the line', () {
    test('breaks across rows and every piece has a sensible box', () {
      const text = 'abcdefghijklmnopqrstuvwxyz'; // 26 glyphs, 10 per row
      final g = LyricLineGeometry.measure(_layout(text, width: 10 * _em), text);

      expect(g.rowCount, greaterThanOrEqualTo(3));
      final pieces = <(int, double, double)>[];
      g.forEachRowSegment(0, text.length, (r, x0, x1) => pieces.add((r, x0, x1)));
      expect(pieces.length, g.rowCount);
      for (final (row, x0, x1) in pieces) {
        expect(x1 - x0, greaterThan(0));
        expect(x1 - x0, lessThanOrEqualTo(10 * _em + 0.5),
            reason: 'row $row is no wider than the line');
      }
    });
  });

  group('an ellipsised line (the seek-bar strip)', () {
    test('never reports a wipe beyond what is visible', () {
      const text = 'this lyric line is far too long for one row to hold';
      final painter =
          _layout(text, width: 10 * _em, maxLines: 1, ellipsis: '\u2026');
      final g = LyricLineGeometry.measure(painter, text);

      expect(g.rowCount, 1);
      final row = g.rows.single;
      for (final revealed in [0.0, 3.5, 9.0, 20.0, text.length.toDouble()]) {
        final x = g.xAt(0, revealed, const []);
        expect(x, greaterThanOrEqualTo(row.left - 0.01));
        expect(x, lessThanOrEqualTo(row.right + 0.01),
            reason: 'at $revealed the wipe stays on the row');
      }
      // Characters the ellipsis hid have no box of their own: they sit at the
      // row's right edge, so the wipe stops there instead of going negative.
      expect(g.charRight[text.length - 1], lessThanOrEqualTo(row.right + 0.01));
      expect(g.charRight[text.length - 1], greaterThanOrEqualTo(g.charLeft[text.length - 1]));
    });
  });

  group('degenerate input', () {
    test('empty text measures to one empty row, not an empty list', () {
      final g = LyricLineGeometry.measure(_layout('', width: 200), '');
      expect(g.rowCount, 1);
      expect(g.length, 0);
    });

    test('a single character', () {
      final g = LyricLineGeometry.measure(_layout('a', width: 200), 'a');
      expect(g.rowCount, 1);
      expect(g.charRight[0] - g.charLeft[0], closeTo(_em, 0.01));
    });
  });
}
