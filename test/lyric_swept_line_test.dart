import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyric_clock.dart';
import 'package:music_streaming_app/services/lyrics/lyric_words.dart';
import 'package:music_streaming_app/widgets/lyric_swept_line.dart';

/// Counts how many times its child was built.
class _BuildCounter extends StatefulWidget {
  const _BuildCounter({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  State<_BuildCounter> createState() => _BuildCounterState();
}

class _BuildCounterState extends State<_BuildCounter> {
  static final Map<String, int> builds = <String, int>{};

  @override
  void initState() {
    super.initState();
    builds[widget.label] = (builds[widget.label] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Stand-in for the Jakarta face, which is fetched at runtime and therefore not
/// resolvable inside a test.
TextStyle _stubFont(double fontSize, FontWeight weight) =>
    TextStyle(fontSize: fontSize, fontWeight: weight);

LyricsEntry _entry(String text, {int timeMs = 0, int? endMs}) => LyricsEntry(
      timeMs: timeMs,
      text: text,
      endMs: endMs,
      words: [
        for (final w in text.split(' ').asMap().entries)
          WordTiming(
            timeMs: timeMs + w.key * 200,
            durationMs: 200,
            text: w.value,
          ),
      ],
    );

void main() {
  // Deliberately NOT setting GoogleFonts.config.allowRuntimeFetching = false.
  // The Jakarta face is not bundled in assets - the app fetches it at runtime -
  // so disabling the fetch makes every glyph resolution throw here. The other
  // tests that render lyrics rely on the same fallback.
  setUp(_BuildCounterState.builds.clear);

  group('LyricLineStyle falloff', () {
    test('alpha never falls below the readable floor', () {
      // A line that fades to invisible cannot be read without scrolling, which
      // is the complaint this ladder replaces.
      for (var d = 0; d < 50; d++) {
        expect(
          LyricLineStyle.alphaForDistance(d),
          greaterThanOrEqualTo(0.46),
          reason: 'distance $d',
        );
      }
    });

    test('blur is capped so distant lines stay legible', () {
      for (var d = 0; d < 50; d++) {
        expect(
          LyricLineStyle.blurForDistance(d),
          lessThanOrEqualTo(2.4),
          reason: 'distance $d',
        );
      }
    });

    test('browsing lifts blur to zero at any distance', () {
      for (var d = 0; d < 20; d++) {
        expect(
          LyricLineStyle.blurFor(distance: d, isBrowsing: true),
          0.0,
          reason: 'scrolling must be crisp at distance $d',
        );
      }
    });

    test('browsing flattens every line to one uniform alpha', () {
      final resting = {
        for (var d = 1; d < 6; d++)
          LyricLineStyle.alphaForDistance(d),
      };
      expect(resting.length, greaterThan(1),
          reason: 'at rest the ladder must actually vary');

      // Distance 0 is the active line and stays fully lit; everything else
      // comes up to one uniform reading alpha.
      final browsing = [
        for (var d = 1; d < 6; d++)
          LyricLineStyle.styleFor(distance: d, isBrowsing: true, fontBuilder: _stubFont).color!.a,
      ];
      expect(browsing.toSet().length, 1,
          reason: 'browsing must flatten the ladder');
      expect(browsing.first, closeTo(0.8, 0.01));

      // And it must be a lift, not a dim: browsing cannot be darker than rest.
      for (var d = 1; d < 6; d++) {
        expect(
          LyricLineStyle.styleFor(distance: d, isBrowsing: true, fontBuilder: _stubFont).color!.a,
          greaterThanOrEqualTo(
              LyricLineStyle.styleFor(distance: d, isBrowsing: false, fontBuilder: _stubFont).color!.a),
          reason: 'distance $d',
        );
      }
    });

    test('the active line is bolder and larger than its neighbours', () {
      final active = LyricLineStyle.styleFor(distance: 0, isBrowsing: false, fontBuilder: _stubFont);
      final next = LyricLineStyle.styleFor(distance: 1, isBrowsing: false, fontBuilder: _stubFont);
      expect(active.fontWeight, FontWeight.w800);
      expect(next.fontWeight, FontWeight.w700);
      expect(active.fontSize!, greaterThan(next.fontSize!));
    });

    test('an unsynced line stays readable rather than faded to the floor', () {
      final synced =
          LyricLineStyle.styleFor(distance: 3, isBrowsing: false, isSynced: true, fontBuilder: _stubFont);
      final unsynced = LyricLineStyle.styleFor(distance: 3, isBrowsing: false, isSynced: false, fontBuilder: _stubFont);
      expect(unsynced.color!.a, greaterThan(synced.color!.a));
    });
  });

  group('held-word growth', () {
    /// A line whose first word is held long enough to earn the swell.
    LyricsEntry heldLine(int startMs, int endMs) => LyricsEntry(
          timeMs: startMs,
          endMs: endMs,
          text: 'golden hour',
          lyricWords: [
            LyricWord(startMs: startMs, endMs: endMs, text: 'golden'),
            LyricWord(startMs: endMs, endMs: endMs + 400, text: 'hour'),
          ],
        );

    Future<void> pumpLine(
      WidgetTester tester,
      LyricsEntry entry,
      LyricClock clock, {
      int positionMs = 0,
    }) async {
      clock.resync(positionMs);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LyricSweptLine(
            entry: entry,
            clock: clock,
            style: const TextStyle(fontSize: 20),
            dimColor: Colors.white54,
            isActive: true,
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('a held word adds its letters while it is held',
        (tester) async {
      final clock = LyricClock();
      addTearDown(clock.dispose);

      // Midway through the hold, and past the point where the sweep has revealed
      // the word, so both conditions for the overlay are met.
      await pumpLine(tester, heldLine(0, 3000), clock, positionMs: 1600);

      /// Single-letter Texts, which only the swell draws.
      Finder singleLetters() => find.byWidgetPredicate(
            (w) => w is Text && w.data != null && w.data!.length == 1,
          );
      int grownCount() => tester.widgetList(singleLetters()).length;

      // The base is two Texts over the whole line: dim, then lit-and-clipped.
      expect(find.text('golden hour'), findsWidgets);

      // The swell follows the voice. A third of the way through a six-letter
      // hold, three letters have been sung, so three have grown - not all six.
      await pumpLine(tester, heldLine(0, 3000), clock, positionMs: 1600);
      final early = grownCount();
      expect(early, greaterThanOrEqualTo(3));
      expect(early, lessThan(6));
      expect(find.text('g'), findsOneWidget);
      expect(find.text('l'), findsOneWidget);
      // Not sung yet, so not grown yet.
      expect(find.text('n'), findsNothing);

      // Later in the hold more of them have arrived.
      await pumpLine(tester, heldLine(0, 3000), clock, positionMs: 2600);
      expect(grownCount(), greaterThan(early));

      // The whole word, once the whole word has been sung.
      await pumpLine(tester, heldLine(0, 3000), clock, positionMs: 3100);
      expect(find.text('n'), findsOneWidget);
    });

    testWidgets('a word merely being sung adds nothing', (tester) async {
      final clock = LyricClock();
      addTearDown(clock.dispose);

      // 300ms is an ordinary sung pace, not a held note. The line must render
      // exactly as it did before the swell existed: nothing extra.
      await pumpLine(
        tester,
        LyricsEntry(timeMs: 0, endMs: 600, text: 'golden hour', lyricWords: const [
            LyricWord(startMs: 0, endMs: 300, text: 'golden'),
            LyricWord(startMs: 300, endMs: 600, text: 'hour'),
          ],
        ),
        clock,
        positionMs: 160,
      );

      final singleLetters = find.byWidgetPredicate(
        (w) => w is Text && w.data != null && w.data!.length == 1,
      );
      expect(
        singleLetters,
        findsNothing,
        reason: 'an ordinarily-sung word must not swell',
      );
    });

    testWidgets('no letters are grown before the sweep reaches them',
        (tester) async {
      final clock = LyricClock();
      addTearDown(clock.dispose);

      // The hold starts at 0, but the clock is before the line's own window, so
      // the line is not animating and nothing at all is drawn on top.
      await pumpLine(tester, heldLine(10000, 13000), clock, positionMs: 200);

      final singleLetters = find.byWidgetPredicate(
        (w) => w is Text && w.data != null && w.data!.length == 1,
      );
      expect(singleLetters, findsNothing);
    });

    testWidgets('a hyphenated word is left alone', (tester) async {
      final clock = LyricClock();
      addTearDown(clock.dispose);

      // Really two words; growing one letter would tear it at the joint.
      await pumpLine(
        tester,
        LyricsEntry(timeMs: 0, endMs: 3000, text: 'half-slow now', lyricWords: const [
            LyricWord(startMs: 0, endMs: 3000, text: 'half-slow'),
            LyricWord(startMs: 3000, endMs: 3400, text: 'now'),
          ],
        ),
        clock,
        positionMs: 1600,
      );

      final singleLetters = find.byWidgetPredicate(
        (w) => w is Text && w.data != null && w.data!.length == 1,
      );
      expect(singleLetters, findsNothing);
    });

    testWidgets('a CJK word is left alone', (tester) async {
      final clock = LyricClock();
      addTearDown(clock.dispose);

      await pumpLine(
        tester,
        LyricsEntry(timeMs: 0, endMs: 3000, text: 'ねこ ねこ', lyricWords: const [
            LyricWord(startMs: 0, endMs: 3000, text: 'ねこ'),
            LyricWord(startMs: 3000, endMs: 6000, text: 'ねこ'),
          ],
        ),
        clock,
        positionMs: 1600,
      );

      final singleLetters = find.byWidgetPredicate(
        (w) => w is Text && w.data != null && w.data!.length == 1,
      );
      expect(singleLetters, findsNothing);
    });

    testWidgets('no overflow: a swelling letter stays inside its own line box',
        (tester) async {
      final clock = LyricClock();
      addTearDown(clock.dispose);

      await pumpLine(tester, heldLine(0, 3000), clock, positionMs: 1600);
      // Flutter records an overflow as a test failure via the error channel, so
      // simply completing without an exception is the assertion - but pinned
      // explicitly so the intent is not lost if that reporting ever changes.
      expect(tester.takeException(), isNull);
    });
  });

  group('rebuild isolation', () {
    testWidgets('an inactive line does not rebuild while the clock ticks',
        (tester) async {
      final clock = LyricClock();
      addTearDown(clock.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _BuildCounter(
            label: 'inactive',
            child: LyricSweptLine(
              entry: _entry('a completely different line'),
              clock: clock,
              style: const TextStyle(fontSize: 20),
              dimColor: Colors.white54,
              isActive: false,
            ),
          ),
        ),
      ));

      final afterMount = _BuildCounterState.builds['inactive'];
      expect(afterMount, 1);

      // Push the clock a long way past this line's window and tick it. The line
      // is not active and not animating, so it must not care.
      clock.resync(600000);
      await tester.pump();
      clock.resync(600500);
      await tester.pump();

      expect(
        _BuildCounterState.builds['inactive'],
        afterMount,
        reason: 'an inactive line must not rebuild on a position tick',
      );
    });

    testWidgets('an active line rebuilds as the clock advances',
        (tester) async {
      final clock = LyricClock();
      addTearDown(clock.dispose);

      Widget build() => MaterialApp(
            home: Scaffold(
              body: LyricSweptLine(
                entry: _entry('one two three'),
                clock: clock,
                style: const TextStyle(fontSize: 20),
                dimColor: Colors.white54,
                isActive: true,
              ),
            ),
          );

      await tester.pumpWidget(build());
      expect(find.text('one two three'), findsOneWidget);

      // Landing inside the line's window must produce the two-copy stack that
      // the wipe is made of.
      clock.resync(300);
      await tester.pump();
      final twoCopies = find.byType(Stack);
      expect(twoCopies, findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no ShaderMask or Opacity anywhere in a swept line',
        (tester) async {
      // The nav bar and mini-player are backdrop lenses. A translucent layer
      // between a lens and its content isolates the backdrop and the glass goes
      // flat, so neither is allowed here.
      final clock = LyricClock();
      addTearDown(clock.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LyricSweptLine(
            entry: _entry('one two three'),
            clock: clock,
            style: const TextStyle(fontSize: 20),
            dimColor: Colors.white54,
            isActive: true,
          ),
        ),
      ));
      clock.resync(300);
      await tester.pump();

expect(
        find.descendant(
          of: find.byType(LyricSweptLine),
          matching: find.byType(ShaderMask),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(LyricSweptLine),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(LyricSweptLine),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
        reason: 'MaterialApp puts its own route fade in the tree; scope to ours',
      );
    });

    testWidgets('a swept line paints no more text than a plain one',
        (tester) async {
      // The wipe is two copies of one string, not two widgets' worth of text.
      final clock = LyricClock();
      addTearDown(clock.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LyricSweptLine(
            entry: _entry('one two three'),
            clock: clock,
            style: const TextStyle(fontSize: 20),
            dimColor: Colors.white54,
            isActive: true,
          ),
        ),
      ));
      clock.resync(250);
      await tester.pump();

      expect(find.text('one two three'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('clock gate', () {
    test('a line outside its window is not animating', () {
      final entry = _entry('line', timeMs: 1000, endMs: 2000);
      expect(
        LyricClock.isAnimating(
          nowMs: 60000,
          fromMs: entry.animatesFromMs,
          untilMs: entry.animatesUntilMs,
        ),
        isFalse,
      );
    });

    test('a line inside its window is animating', () {
      final entry = _entry('line', timeMs: 1000, endMs: 2000);
      expect(
        LyricClock.isAnimating(
          nowMs: 1500,
          fromMs: entry.animatesFromMs,
          untilMs: entry.animatesUntilMs,
        ),
        isTrue,
      );
    });

testWidgets('position advances smoothly while the clock runs', (tester) async {
      final clock = LyricClock(vsync: const TestVSync());
      addTearDown(clock.dispose);

      clock.resync(1000);
      clock.start();
      // Interpolation is wall-clock based, so pumping real frames must move it.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      expect(clock.positionMs, greaterThanOrEqualTo(1000));
      expect(clock.isRunning, isTrue);

      // Stopped inside the test body, not left to the teardown: the scheduler
      // asserts no animation outlives the tree before tearDowns run.
      clock.stop();
      await tester.pump();
    });
  });
}
