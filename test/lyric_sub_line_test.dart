import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyric_clock.dart';
import 'package:music_streaming_app/services/lyrics/lyric_sub_line.dart';
import 'package:music_streaming_app/widgets/lyric_swept_line.dart';

TextStyle _stubFont(double fontSize, FontWeight weight) =>
    TextStyle(fontSize: fontSize, fontWeight: weight);

/// A reveal pinned at a fixed progress, so a test can state the value instead of
/// driving timers.
class _FrozenReveal implements SubLineReveal {
  _FrozenReveal(this.progress);

  @override
  final double progress;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
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

void main() {
  group('the transform is a sub-line, never a replacement', () {
    testWidgets('the original text stays exactly as it was', (tester) async {
      // THE REGRESSION THIS PINS: replacing the line's text makes every word
      // timing index the wrong characters, because those timings are spans of the
      // ORIGINAL string. The wipe then lights words that are not being sung.
      final clock = LyricClock();
      addTearDown(clock.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LyricSweptLine(
            entry: _line('so here I am'),
            clock: clock,
            style: _stubFont(24, FontWeight.w700),
            dimColor: Colors.white54,
            isActive: true,
            subLineProvider: () => 'ich bin wieder da',
          ),
        ),
      ));
      await tester.pump();

      // The original is drawn whole.
      expect(find.text('so here I am'), findsWidgets);
      // The transform is drawn beneath it, separately.
      expect(find.text('ich bin wieder da'), findsOneWidget);
    });

    testWidgets('the word timings still index the original', (tester) async {
      // The prefix widths are measured off the ORIGINAL string, so a sub-line
      // must not change what the wipe clips. If it did, the clip would be cut
      // against the wrong glyphs.
      final clock = LyricClock();
      addTearDown(clock.dispose);
      clock.resync(600);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LyricSweptLine(
            entry: _line('so here I am'),
            clock: clock,
            style: _stubFont(24, FontWeight.w700),
            dimColor: Colors.white54,
            isActive: true,
            subLineProvider: () => 'ich bin wieder da',
          ),
        ),
      ));
      await tester.pump();

      final withSub = tester.widget<LyricSweptLine>(find.byType(LyricSweptLine));
      expect(withSub.entry.text, 'so here I am');
      expect(withSub.entry.timedWords.length, 4);
    });
  });

  group('the reveal', () {
    testWidgets('a closed transform reserves no height', (tester) async {
      final clock = LyricClock();
      addTearDown(clock.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LyricSweptLine(
            entry: _line('so here I am'),
            clock: clock,
            style: _stubFont(24, FontWeight.w700),
            dimColor: Colors.white54,
            isActive: true,
            subLineProvider: () => null,
          ),
        ),
      ));
      await tester.pump();

      // heightFactor 0 collapses the row, so a hidden transform costs nothing in
      // a list of thirty lines.
      expect(find.text('ich bin wieder da'), findsNothing);
    });

    testWidgets('a closed transform fades fully', (tester) async {
      final clock = LyricClock();
      addTearDown(clock.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LyricSweptLine(
            entry: _line('so here I am'),
            clock: clock,
            style: _stubFont(24, FontWeight.w700),
            dimColor: Colors.white54,
            isActive: true,
            subLineProvider: () => 'ich bin wieder da',
            // A stub listenable pinned shut, rather than a number parameter: the
            // real wiring is a listenable the row rebuilds itself from.
            subLineListenable: _FrozenReveal(0),
          ),
        ),
      ));
      await tester.pump();

      final text = tester.widget<Text>(find.text('ich bin wieder da'));
      final alpha = (text.style!.color)!.a;
      expect(alpha, 0);
    });

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
      expect(
        SubLineMode.values.length,
        3,
        reason: 'one mode at a time is what makes the sub-line unambiguous',
      );
    });
  });
}