// Pins what `LyricLine` actually DRAWS - the clips it makes per row - on a line
// that wraps, which is the case the old renderer got visibly wrong.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyric_clock.dart';
import 'package:music_streaming_app/services/lyrics/lyric_words.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_line.dart';

const double _em = 20;
const TextStyle _style = TextStyle(fontSize: _em, height: 1.0);

/// Four 400ms words, 100ms apart: "aaaa bbbb cccc dddd". In a 200px box (ten
/// Ahem glyphs) the first two words are row one and the last two are row two.
LyricsEntry _entry() {
  final words = wordsFromWordTimings([
    (timeMs: 0, durationMs: 400, text: 'aaaa'),
    (timeMs: 500, durationMs: 400, text: 'bbbb'),
    (timeMs: 1000, durationMs: 400, text: 'cccc'),
    (timeMs: 1500, durationMs: 400, text: 'dddd'),
  ]);
  return LyricsEntry(
    timeMs: 0,
    text: 'aaaa bbbb cccc dddd',
    endMs: 1900,
    lyricWords: words,
  );
}

Future<RenderLyricLine> _pump(
  WidgetTester tester, {
  required LyricsEntry entry,
  required LyricClock clock,
  bool rise = true,
  bool glow = false,
  bool feather = false,
  double alpha = 1.0,
  double blurSigma = 0.0,
  int? maxLines,
  bool ellipsis = false,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 10 * _em,
            child: LyricLine(
              entry: entry,
              clock: clock,
              style: _style,
              rise: rise,
              glow: glow,
              feather: feather,
              alpha: alpha,
              blurSigma: blurSigma,
              maxLines: maxLines,
              ellipsis: ellipsis,
            ),
          ),
        ),
      ),
    ),
  );
  final line = tester.renderObject<RenderLyricLine>(find.byType(LyricLine));
  line.debugRecordClips = true;
  return line;
}

/// Moves the song to [ms] and paints once.
Future<void> _at(WidgetTester tester, LyricClock clock, int ms) async {
  clock.reset(ms);
  await tester.pump();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late LyricClock clock;
  setUp(() => clock = LyricClock(now: () => 0));
  tearDown(() => clock.dispose());

  group('a wrapped line, with the voice on the SECOND row', () {
    testWidgets('lights row one whole and row two only up to the voice',
        (tester) async {
      final line = await _pump(tester, entry: _entry(), clock: clock);
      await _at(tester, clock, 1200); // inside "cccc", the first word of row two

      final g = line.geometry;
      expect(g.rowCount, 2);
      final row0 = g.rows[0];
      final row1 = g.rows[1];

      expect(line.debugLitClips, isNotEmpty);

      // EVERY lit clip is ONE row tall (plus a lift's headroom at most). The old
      // renderer made a single full-height rect, which is how both rows lit at
      // once.
      for (final clip in line.debugLitClips) {
        expect(clip.height, lessThanOrEqualTo(row0.height + 4),
            reason: 'a clip taller than a row lights two rows: $clip');
      }

      // Row one is behind the voice: lit across its whole width.
      final rowOne = line.debugLitClips.where((c) => c.center.dy < row0.bottom);
      expect(rowOne, isNotEmpty, reason: 'row one must be lit');
      expect(rowOne.map((c) => c.right).reduce((a, b) => a > b ? a : b),
          greaterThanOrEqualTo(row0.right));

      // Row two is lit only partway: nowhere near the end of "dddd".
      final rowTwo = line.debugLitClips.where((c) => c.center.dy >= row1.top);
      expect(rowTwo, isNotEmpty);
      final litRight =
          rowTwo.map((c) => c.right).reduce((a, b) => a > b ? a : b);
      expect(litRight, lessThan(row1.right - _em),
          reason: '"dddd" has not been sung yet');
      expect(litRight, greaterThan(row1.left),
          reason: 'but "cccc" is under way');
    });

    testWidgets('a lifted word rises on ITS OWN row, never over the other one',
        (tester) async {
      final line = await _pump(tester, entry: _entry(), clock: clock);
      await _at(tester, clock, 1200);

      final g = line.geometry;
      final row0 = g.rows[0];
      final row1 = g.rows[1];

      // The word being sung is "cccc". Find the lifted slices: those that reach
      // above their row's top, because a lift paints that far up.
      final lifted =
          line.debugLitClips.where((c) => c.top < row1.top - 0.01 && c.top >= row0.bottom - 4);
      expect(lifted, isNotEmpty, reason: '"cccc" is lifting on row two');
      for (final clip in lifted) {
        // Its x is inside "cccc" on row two...
        expect(clip.left, greaterThanOrEqualTo(row1.left - 0.5));
        expect(clip.right, lessThanOrEqualTo(row1.right + 0.5));
        // ...and it reaches at most a few px into row one's band - a lift is a
        // couple of dp, not a whole row.
        expect(row1.top - clip.top, lessThanOrEqualTo(6));
      }

      // Row one's "bbbb" ended 300ms ago and is still settling (a word falls back
      // over 700ms), so ITS slice is legitimately lifted - but only that word's
      // box. "aaaa" finished 800ms ago and is flat.
      final onRowOne = line.debugLitClips
          .where((c) => c.bottom <= row0.bottom + 0.01 && c.top < row0.top - 0.01)
          .toList();
      for (final clip in onRowOne) {
        expect(clip.left, greaterThanOrEqualTo(5 * _em - 0.5),
            reason: '"aaaa" has settled: only "bbbb" may still be lifted');
        expect(clip.right, lessThanOrEqualTo(9 * _em + 0.5));
      }
    });

    testWidgets('the dim pass covers both rows once', (tester) async {
      final line = await _pump(tester, entry: _entry(), clock: clock);
      await _at(tester, clock, 1200);
      final rows = line.geometry.rows;
      final covered = line.debugDimClips;
      expect(covered, isNotEmpty);
      for (final row in rows) {
        expect(
          covered.any((c) => c.top <= row.top + 0.01 && c.bottom >= row.bottom - 0.01),
          isTrue,
          reason: 'every row is drawn dim exactly where it needs to be',
        );
      }
    });
  });

  group('the sweep is continuous, not stepped', () {
    testWidgets('the leading edge moves a little every few milliseconds, not '
        'a glyph at a time', (tester) async {
      final line = await _pump(tester, entry: _entry(), clock: clock);

      // Inside "bbbb" (500..900ms) on row one: sample every 25ms.
      final edges = <double>[];
      for (var ms = 520; ms <= 880; ms += 25) {
        await _at(tester, clock, ms);
        final rowBottom = line.geometry.rows[0].bottom;
        final litOnRowOne =
            line.debugLitClips.where((c) => c.bottom <= rowBottom + 0.01);
        // The widest lit clip's right edge is the leading edge. (Row one's first
        // word is already sung, so the edge is in "bbbb".)
        edges.add(litOnRowOne.map((c) => c.right).reduce((a, b) => a > b ? a : b));
      }

      // Strictly increasing, and in steps far smaller than a glyph: a rounded
      // reveal would repeat the same value for ~90ms at a time.
      for (var i = 1; i < edges.length; i++) {
        expect(edges[i], greaterThan(edges[i - 1]),
            reason: 'edge stalled between samples ${i - 1} and $i');
        expect(edges[i] - edges[i - 1], lessThan(_em),
            reason: 'the edge jumped a whole glyph');
      }
    });
  });

  group('a held note swells its letters', () {
    // One word, "oooh", held for 3 seconds: long enough to earn the swell.
    LyricsEntry held() => LyricsEntry(
          timeMs: 0,
          text: 'oooh',
          endMs: 3000,
          lyricWords: wordsFromWordTimings([
            (timeMs: 0, durationMs: 3000, text: 'oooh'),
          ]),
        );

    testWidgets('the sung letters are the swell\'s, so a letter is never drawn '
        'twice', (tester) async {
      final line = await _pump(tester, entry: held(), clock: clock, glow: true);
      await _at(tester, clock, 1500); // half way: two letters sung

      expect(line.geometry.rowCount, 1);
      // Letters 0 and 1 occupy x 0..40. The plain passes must leave that hole,
      // or the original letter shows beside its swollen self.
      for (final clip in [...line.debugLitClips, ...line.debugDimClips]) {
        expect(clip.right <= 0.01 || clip.left >= 39.99, isTrue,
            reason: 'a plain-pass clip covers a letter the swell owns: $clip');
      }
      expect(line.debugLayers, greaterThanOrEqualTo(1),
          reason: 'the bloom is a blurred layer behind the letter');
    });

    testWidgets('reduced motion draws the held word plainly', (tester) async {
      final line = await _pump(
        tester,
        entry: held(),
        clock: clock,
        glow: true,
        reduceMotion: true,
      );
      await _at(tester, clock, 1500);

      // No hole: the plain pass covers the word from its first letter.
      expect(
        line.debugLitClips.any((c) => c.left <= 0.01 && c.right > 20),
        isTrue,
        reason: 'with motion off the word is just lit text',
      );
      expect(line.debugLayers, 0, reason: 'and there is no bloom');
    });

    testWidgets('a word merely being sung adds nothing extra', (tester) async {
      final quick = LyricsEntry(
        timeMs: 0,
        text: 'oooh',
        endMs: 400,
        lyricWords: wordsFromWordTimings([
          (timeMs: 0, durationMs: 400, text: 'oooh'),
        ]),
      );
      final line = await _pump(tester, entry: quick, clock: clock, glow: true);
      await _at(tester, clock, 200);
      expect(line.debugLayers, 0);
    });
  });

  group('repaint isolation', () {
    testWidgets('a line outside its window does not repaint on a clock tick',
        (tester) async {
      final line = await _pump(tester, entry: _entry(), clock: clock);
      await _at(tester, clock, 10000); // long after the line
      expect(line.debugNeedsPaint, isFalse);

      // A tick that stays outside the window costs a comparison, not a paint.
      clock.reset(10040);
      expect(line.debugNeedsPaint, isFalse,
          reason: 'a finished line must not repaint at 60Hz');
    });

    testWidgets('a line inside its window repaints as the clock moves',
        (tester) async {
      final line = await _pump(tester, entry: _entry(), clock: clock);
      await _at(tester, clock, 700);
      expect(line.debugNeedsPaint, isFalse);
      clock.reset(720);
      expect(line.debugNeedsPaint, isTrue);
    });

    testWidgets('a line repaints once when the voice leaves its window, so it '
        'lands in its final state', (tester) async {
      final line = await _pump(tester, entry: _entry(), clock: clock);
      await _at(tester, clock, 700);
      clock.reset(60000);
      expect(line.debugNeedsPaint, isTrue,
          reason: 'the edge of the window is a repaint');
      await tester.pump();
      clock.reset(60100);
      expect(line.debugNeedsPaint, isFalse);
    });

    testWidgets('a line-synced line never listens to the clock at all',
        (tester) async {
      final plain = LyricsEntry(timeMs: 1000, text: 'just a plain line');
      final line = await _pump(tester, entry: plain, clock: clock);
      expect(clock.hasListenersForTest, isFalse);
      expect(line.debugNeedsPaint, isFalse);
    });
  });

  group('the layer', () {
    testWidgets('alpha 1 and no blur takes NO layer - the active line is free',
        (tester) async {
      final line = await _pump(tester, entry: _entry(), clock: clock);
      await _at(tester, clock, 700);
      expect(line.debugLayers, 0,
          reason: 'a sharp, opaque line is painted straight to the canvas');
    });

    testWidgets('alpha and blur ride ONE layer, not one each', (tester) async {
      final line = await _pump(
        tester,
        entry: _entry(),
        clock: clock,
        alpha: 0.7,
        blurSigma: 1.4,
      );
      await _at(tester, clock, 700);
      // Exactly one: a second would be the old ImageFiltered + DefaultTextStyle
      // pair costing a layer per row.
      expect(line.debugLayers, 1,
          reason: 'the row\'s alpha and blur share a single saveLayer');
    });

    testWidgets('only the active line pays for its soft edge', (tester) async {
      final soft = await _pump(tester, entry: _entry(), clock: clock, feather: true);
      await _at(tester, clock, 700);
      expect(soft.debugLayers, 1, reason: 'the feather is one layer');

      final hard = await _pump(tester, entry: _entry(), clock: clock);
      await _at(tester, clock, 710);
      expect(hard.debugLayers, 0);
    });

    testWidgets('a line paints no more paragraph draws than it has segments',
        (tester) async {
      final line = await _pump(tester, entry: _entry(), clock: clock);
      await _at(tester, clock, 1200);
      // Two rows, one lifted word, dim + lit: a few slices, not one per glyph.
      expect(line.debugParagraphDraws, lessThanOrEqualTo(16));
      expect(line.debugParagraphDraws, greaterThan(0));
    });
  });

  group('semantics', () {
    testWidgets('the line is announced as its text', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, entry: _entry(), clock: clock);
      expect(find.bySemanticsLabel('aaaa bbbb cccc dddd'), findsOneWidget);
      handle.dispose();
    });
  });

  group('the strip configuration', () {
    testWidgets('one row, ellipsised, never wider than its box', (tester) async {
      final entry = LyricsEntry(
        timeMs: 0,
        text: 'aaaa bbbb cccc dddd eeee',
        endMs: 2400,
        lyricWords: wordsFromWordTimings([
          (timeMs: 0, durationMs: 400, text: 'aaaa'),
          (timeMs: 500, durationMs: 400, text: 'bbbb'),
          (timeMs: 1000, durationMs: 400, text: 'cccc'),
          (timeMs: 1500, durationMs: 400, text: 'dddd'),
          (timeMs: 2000, durationMs: 400, text: 'eeee'),
        ]),
      );
      final line = await _pump(
        tester,
        entry: entry,
        clock: clock,
        rise: false,
        maxLines: 1,
        ellipsis: true,
      );
      await _at(tester, clock, 1700);

      expect(tester.getSize(find.byType(LyricLine)).height, closeTo(_em, 0.5),
          reason: 'one row, so the deck cannot grow');
      expect(line.geometry.rowCount, 1);
      for (final clip in line.debugLitClips) {
        expect(clip.right, lessThanOrEqualTo(10 * _em + 16));
      }
    });
  });
}
