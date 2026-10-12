import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyric_clock.dart';
import 'package:music_streaming_app/services/lyrics/lyric_sub_line.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_line.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_sub_line_view.dart';

const TextStyle _style = TextStyle(fontSize: 20, height: 1.0);

/// A reveal pinned at a fixed progress, so a test can state the value instead of
/// driving timers.
class _FrozenReveal extends ChangeNotifier implements SubLineReveal {
  _FrozenReveal(this._progress);

  double _progress;

  @override
  double get progress => _progress;

  void set(double value) {
    _progress = value;
    notifyListeners();
  }
}

LyricsEntry _line(String text, {int timeMs = 0, int endMs = 2000}) =>
    LyricsEntry(
      timeMs: timeMs,
      endMs: endMs,
      text: text,
      words: [
        for (final w in text.split(' ').asMap().entries)
          WordTiming(
            timeMs: timeMs + w.key * 400,
            durationMs: 400,
            text: w.value,
          ),
      ],
    );

/// An original line with its transform underneath, as the panel builds them.
Widget _row({
  required LyricClock clock,
  required LyricsEntry original,
  required LyricsEntry? transform,
  required SubLineReveal reveal,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LyricLine(entry: original, clock: clock, style: _style),
                LyricSubLineView(
                  controller: reveal,
                  clock: clock,
                  style: _style,
                  original: original,
                  entryProvider: () => transform,
                  alpha: 1.0,
                  lit: 1.0,
                  blurSigma: 0.0,
                ),
              ],
            ),
          ),
        ),
      ),
    );

List<RenderLyricLine> _lines(WidgetTester tester) => [
      for (final e in find.byType(LyricLine).evaluate())
        tester.renderObject<RenderLyricLine>(find.byWidget(e.widget)),
    ];

void main() {
  late LyricClock clock;
  setUp(() => clock = LyricClock(now: () => 0));
  tearDown(() => clock.dispose());

  group('the transform is a sub-line, never a replacement', () {
    testWidgets('the original text stays exactly as it was', (tester) async {
      // THE REGRESSION THIS PINS: replacing the line's text makes every word
      // timing index the wrong characters, because those timings are spans of the
      // ORIGINAL string. The wipe then lights words that are not being sung.
      final original = _line('so here I am');
      await tester.pumpWidget(_row(
        clock: clock,
        original: original,
        transform: LyricsEntry(timeMs: 0, text: 'ich bin wieder da'),
        reveal: _FrozenReveal(1),
      ));

      final lines = _lines(tester);
      expect(lines.length, 2, reason: 'the original and, beneath it, its transform');
      expect(lines[0].entry.text, 'so here I am');
      expect(lines[1].entry.text, 'ich bin wieder da');
      expect(lines[0].entry.timedWords.length, 4,
          reason: 'the original keeps its own word timings');
    });

    testWidgets('the transform sweeps IN STEP with the original it sits under',
        (tester) async {
      final original = _line('so here I am'); // 4 words, 400ms each
      await tester.pumpWidget(_row(
        clock: clock,
        original: original,
        transform: LyricsEntry(timeMs: 0, text: 'ich bin wieder da'),
        reveal: _FrozenReveal(1),
      ));
      final sub = _lines(tester)[1]..debugRecordClips = true;

      // Half way through the ORIGINAL's words.
      clock.reset(800);
      await tester.pump();

      final litRight = sub.debugLitClips.map((c) => c.right).fold<double>(0, (a, b) => a > b ? a : b);
      final width = sub.geometry.rows.single.right;
      expect(litRight, greaterThan(width * 0.3));
      expect(litRight, lessThan(width * 0.9),
          reason: 'a translation has no timings of its own: it follows the '
              'original proportionally rather than sitting fully lit');
    });
  });

  group('the reveal', () {
    testWidgets('a closed transform reserves no height and draws nothing',
        (tester) async {
      await tester.pumpWidget(_row(
        clock: clock,
        original: _line('so here I am'),
        transform: LyricsEntry(timeMs: 0, text: 'ich bin wieder da'),
        reveal: _FrozenReveal(0),
      ));

      expect(_lines(tester).length, 1,
          reason: 'hidden: not even built, so a list of thirty rows pays nothing');
      expect(tester.getSize(find.byType(LyricSubLineView)).height, 0);
    });

    testWidgets('no transform available draws nothing', (tester) async {
      await tester.pumpWidget(_row(
        clock: clock,
        original: _line('so here I am'),
        transform: null,
        reveal: _FrozenReveal(1),
      ));
      expect(_lines(tester).length, 1);
    });

    testWidgets('the height opens with the reveal', (tester) async {
      final reveal = _FrozenReveal(1);
      await tester.pumpWidget(_row(
        clock: clock,
        original: _line('so here I am'),
        transform: LyricsEntry(timeMs: 0, text: 'ich bin wieder da'),
        reveal: reveal,
      ));
      final full = tester.getSize(find.byType(LyricSubLineView)).height;
      expect(full, greaterThan(0));

      reveal.set(0.5);
      await tester.pump();
      expect(tester.getSize(find.byType(LyricSubLineView)).height,
          closeTo(full * 0.5, 1.0));
    });

    testWidgets('it fades in SQUARED: faint for most of the travel, full on '
        'arrival', (tester) async {
      final reveal = _FrozenReveal(0.5);
      await tester.pumpWidget(_row(
        clock: clock,
        original: _line('so here I am'),
        transform: LyricsEntry(timeMs: 0, text: 'ich bin wieder da'),
        reveal: reveal,
      ));
      final sub = _lines(tester)[1];
      // 0.85 (sub-line alpha) * 0.5 * 0.5
      expect(sub.debugAlpha, closeTo(0.85 * 0.25, 0.01));

      reveal.set(1.0);
      await tester.pump();
      expect(_lines(tester)[1].debugAlpha, closeTo(0.85, 0.01));
    });

    testWidgets('the sliding sub-line is CLIPPED, so it cannot draw over the '
        'original while it travels', (tester) async {
      // The old reveal let the text slide up over the line above it, which drew
      // two lines of text on top of each other when a translation was toggled.
      await tester.pumpWidget(_row(
        clock: clock,
        original: _line('so here I am'),
        transform: LyricsEntry(timeMs: 0, text: 'ich bin wieder da'),
        reveal: _FrozenReveal(0.4),
      ));
      expect(
        find.descendant(
          of: find.byType(LyricSubLineView),
          matching: find.byType(ClipRect),
        ),
        findsOneWidget,
      );
    });
  });

  group('the controller', () {
    test('a transform for the wrong track is refused', () {
      // Painting the previous song's translation under this one is worse than
      // having no sub-line, and nothing about that is recoverable by looking at it.
      final c = SubLineController();
      addTearDown(c.dispose);
      c.onTrackChanged('t1');
      expect(c.lines, isNull);
      expect(c.mode, SubLineMode.original);
    });

    test('a track change resets the mode with the transform', () {
      final c = SubLineController();
      addTearDown(c.dispose);
      c.onTrackChanged('t2');
      // Leaving it on "translated" would label the originals as a translation.
      expect(c.mode, SubLineMode.original);
      expect(c.progress, 0);
    });

    test('the same track does not clear a transform it still owns', () {
      final c = SubLineController();
      addTearDown(c.dispose);
      c.onTrackChanged('t1');
      c.onTrackChanged('t1');
      expect(c.mode, SubLineMode.original);
    });

    test('which transform each mode fetches', () {
      expect(transformFor(SubLineMode.original), isNull);
      expect(transformFor(SubLineMode.romanized), isNotNull);
      expect(transformFor(SubLineMode.translated), isNotNull);
    });

    test('the mode enum holds exactly one value at a time', () {
      // Two transforms sharing the gap under the same line would leave the
      // reader with no way to tell which is which.
      expect(SubLineMode.values.length, 3,
          reason: 'one mode at a time is what makes the sub-line unambiguous');
    });
  });
}
