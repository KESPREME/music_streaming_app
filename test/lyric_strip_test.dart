import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyric_clock.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_line.dart';
import 'package:music_streaming_app/widgets/lyric_strip.dart';

/// THE STRIP THIS FILE PINS.
///
/// The line above the seek bar used to collapse every situation into "an intro
/// phrase". A song with no lyrics anywhere cheerfully displayed *Let it breathe*
/// for the entire track while the row beneath it said **Lyrics unavailable** — two
/// truths on one line.
///
/// It also read its index off `positionStream` (≈200ms) while the wipe came off
/// `LyricClock`, so the line that switched and the line that swept could disagree
/// for up to a stream period.
///
/// And "unsynced" meant "no WORD timings", so every ordinary line-synced (LRC)
/// song showed "Open lyrics" instead of its current line.
///
/// Reference: `CurrentLyricStrip` and its siblings, PlayerLyrics.kt:2492-2681.

/// A ticker provider that never ticks: the tests move the clock by hand.
class _NoTickVsync implements TickerProvider {
  const _NoTickVsync();

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

LyricClock _manualClock() =>
    LyricClock(vsync: const _NoTickVsync(), now: () => 0);

/// Six word-synced lines, four seconds apart.
List<LyricsEntry> _syncedLyric() => [
      for (var i = 0; i < 6; i++)
        LyricsEntry(
          timeMs: i * 4000,
          endMs: i * 4000 + 3000,
          text: 'line ${i + 1} here',
          words: [
            WordTiming(timeMs: i * 4000, durationMs: 900, text: 'line'),
            WordTiming(timeMs: i * 4000 + 900, durationMs: 900, text: '${i + 1}'),
            WordTiming(timeMs: i * 4000 + 1800, durationMs: 900, text: 'here'),
          ],
        ),
    ];

/// The same six lines, line-synced only (an ordinary LRC).
List<LyricsEntry> _lineSyncedLyric() => [
      for (var i = 0; i < 6; i++)
        LyricsEntry(
            timeMs: i * 4000 + 1, endMs: i * 4000 + 3000, text: 'line ${i + 1} here'),
    ];

/// Plain text with no timestamps at all.
List<LyricsEntry> _unsyncedLyric() => [
      for (var i = 0; i < 6; i++) LyricsEntry(timeMs: 0, text: 'line ${i + 1} here'),
    ];

Widget _host({
  required List<LyricsEntry>? lyrics,
  required LyricClock clock,
  bool isLoading = false,
  bool hasLyrics = true,
  int? positionOverrideMs,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: LyricStrip(
            lyrics: lyrics,
            clock: clock,
            introPhrase: 'Let it breathe',
            isLoading: isLoading,
            hasLyrics: hasLyrics,
            positionOverrideMs: positionOverrideMs,
            onTap: () {},
          ),
        ),
      ),
    );

LyricLine _line(WidgetTester tester) =>
    tester.widget<LyricLine>(find.byType(LyricLine));

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  late LyricClock clock;
  setUp(() => clock = _manualClock());
  tearDown(() => clock.dispose());

  group('the handover spec matches the reference', () {
    test('340ms, sliding 35% of its own height', () {
      expect(stripHandoverDuration, const Duration(milliseconds: 340));
      expect(stripSlideFraction, 0.35);
      expect(stripUnsungAlpha, 0.55);
    });
  });

  group('the states are distinguishable', () {
    testWidgets('a loading lookup is dim and static', (tester) async {
      await tester.pumpWidget(
        _host(lyrics: null, clock: clock, isLoading: true, hasLyrics: false),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('lyric-strip-loading')), findsOneWidget);
      expect(find.byType(LyricLine), findsNothing);
    });

    testWidgets('a word-synced line renders the sweep', (tester) async {
      clock.reset(1000);
      await tester.pumpWidget(_host(lyrics: _syncedLyric(), clock: clock));
      await tester.pump();

      expect(find.byType(LyricLine), findsOneWidget);
      expect(_line(tester).entry.isWordSynced, isTrue);
    });

    testWidgets('a LINE-synced lyric shows its current line, plainly',
        (tester) async {
      // THE BUG THIS PINS. "Unsynced" used to mean "no word timings", so an
      // ordinary LRC (every line stamped, no words) showed "Open lyrics" on the
      // strip for the whole song instead of the line being sung.
      clock.reset(5000);
      await tester.pumpWidget(_host(lyrics: _lineSyncedLyric(), clock: clock));
      await tester.pump();

      expect(find.textContaining('Open lyrics'), findsNothing);
      expect(_line(tester).entry.text, 'line 2 here');
      expect(_line(tester).entry.isWordSynced, isFalse,
          reason: 'plain: nothing to sweep, and it does not pretend to');
    });

    testWidgets('a lyric with NO timestamps offers the way in', (tester) async {
      clock.reset(1000);
      await tester.pumpWidget(_host(lyrics: _unsyncedLyric(), clock: clock));
      await tester.pump();

      expect(find.byType(LyricLine), findsNothing);
      expect(find.textContaining('Open lyrics'), findsOneWidget,
          reason: 'nothing to follow: say so and offer the way in');
    });

    testWidgets('before the first vocal line the intro phrase shows',
        (tester) async {
      // A lyric whose first word does not arrive until 6s: a position before it
      // is the intro, which is a different fact from "no lyrics".
      final late = [
        for (var i = 0; i < 4; i++)
          LyricsEntry(
            timeMs: 6000 + i * 4000,
            endMs: 6000 + i * 4000 + 3000,
            text: 'line ${i + 1} here',
            words: [
              WordTiming(timeMs: 6000 + i * 4000, durationMs: 900, text: 'line'),
            ],
          ),
      ];
      clock.reset(1000);
      await tester.pumpWidget(_host(lyrics: late, clock: clock));
      await tester.pump();

      expect(find.text('Let it breathe'), findsOneWidget);
      expect(find.byType(LyricLine), findsNothing);
    });

    testWidgets('no lyrics at all is its own state, not an intro phrase',
        (tester) async {
      clock.reset(0);
      await tester.pumpWidget(
        _host(lyrics: null, clock: clock, isLoading: false, hasLyrics: false),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('lyric-strip-unavailable')),
          findsOneWidget);
      expect(find.text('Let it breathe'), findsNothing,
          reason: 'telling a reader to breathe while telling them there are no '
              'lyrics is the bug this state exists to fix');
      expect(find.text('No lyrics found'), findsOneWidget);
    });

    testWidgets('"no lyrics" is held, then fades with ONE implicit animation',
        (tester) async {
      await tester.pumpWidget(
        _host(lyrics: null, clock: clock, isLoading: false, hasLyrics: false),
      );
      await tester.pump();

      double opacity() => tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .opacity;

      expect(opacity(), closeTo(0.55, 0.001));
      await tester.pump(const Duration(seconds: 4));
      expect(opacity(), closeTo(0.55, 0.001), reason: 'still held at 4s');
      await tester.pump(const Duration(seconds: 2)); // the 5s hold ends
      expect(opacity(), 0.0, reason: 'then it fades out');
      await tester.pump(const Duration(milliseconds: 950));
    });
  });

  group('the index and the wipe read one clock', () {
    testWidgets('a drag override shows the line being scrubbed TO',
        (tester) async {
      clock.reset(1000);
      await tester.pumpWidget(
        _host(lyrics: _syncedLyric(), clock: clock, positionOverrideMs: 17000),
      );
      await tester.pump();

      expect(_line(tester).entry.timeMs, 16000,
          reason: 'the override must win over the playing position, or '
              'scrubbing previews the wrong line');
      // And it is the SAME clock the wipe draws from - one source of truth.
      expect(_line(tester).clock, same(clock));
    });

    testWidgets('the line resolves off the clock, not a second stream',
        (tester) async {
      clock.reset(1000);
      await tester.pumpWidget(_host(lyrics: _syncedLyric(), clock: clock));
      await tester.pump();
      expect(_line(tester).entry.timeMs, 0);

      // No positionStream, no provider, no pump between: moving the clock is the
      // only thing that can change the answer.
      clock.reset(9000);
      await tester.pump();
      await tester.pump(stripHandoverDuration + const Duration(milliseconds: 60));
      expect(_line(tester).entry.timeMs, 8000);
    });

    testWidgets('a clock tick inside the same line rebuilds NOTHING',
        (tester) async {
      clock.reset(1000);
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return SizedBox(
              width: 360,
              child: LyricStrip(
                lyrics: _syncedLyric(),
                clock: clock,
                introPhrase: 'Let it breathe',
                hasLyrics: true,
                onTap: () => builds++,
              ),
            );
          }),
        ),
      ));
      await tester.pump();
      final first = tester.widget<LyricLine>(find.byType(LyricLine));
      clock.reset(1200);
      await tester.pump();
      clock.reset(1400);
      await tester.pump();
      expect(identical(tester.widget<LyricLine>(find.byType(LyricLine)), first),
          isTrue,
          reason: 'the sweep repaints itself; the strip is not rebuilt for it');
    });
  });

  group('the handover', () {
    testWidgets('a provider switch with the same words does NOT slide the '
        'line out and back in', (tester) async {
      // Keyed on index + text, not on the start stamp: a different source hands
      // over the same words at a slightly different time.
      clock.reset(1000);
      final a = _syncedLyric();
      await tester.pumpWidget(_host(lyrics: a, clock: clock));
      await tester.pump();
      expect(find.byType(LyricLine), findsOneWidget);

      final b = [
        for (final e in a)
          LyricsEntry(
            timeMs: e.timeMs + (e.timeMs == 0 ? 0 : 40),
            endMs: e.endMs,
            text: e.text,
            words: e.words,
          ),
      ];
      await tester.pumpWidget(_host(lyrics: b, clock: clock));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LyricLine), findsOneWidget,
          reason: 'one line on screen - no outgoing duplicate sliding away');
    });

    testWidgets('a real line change slides, and is clipped to its row',
        (tester) async {
      clock.reset(1000);
      await tester.pumpWidget(_host(lyrics: _syncedLyric(), clock: clock));
      await tester.pump();

      clock.reset(5000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LyricLine), findsNWidgets(2),
          reason: 'the outgoing and the incoming line, mid-handover');
      expect(
        find.descendant(of: find.byType(LyricStrip), matching: find.byType(ClipRect)),
        findsWidgets,
        reason: 'nothing may travel outside the row',
      );

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LyricLine), findsOneWidget);
    });
  });

  group('the strip cannot resize the deck', () {
    testWidgets('a very long line is clamped to one row', (tester) async {
      final long = [
        LyricsEntry(
          timeMs: 0,
          endMs: 4000,
          text: 'a single lyric line so long that it would certainly wrap onto '
              'a second row and push the scrubber down the screen if it were '
              'allowed to',
          words: const [
            WordTiming(timeMs: 0, durationMs: 4000, text: 'a'),
          ],
        ),
      ];
      clock.reset(1000);
      await tester.pumpWidget(_host(lyrics: long, clock: clock));
      await tester.pump();

      expect(_line(tester).maxLines, 1);
      expect(_line(tester).ellipsis, isTrue);
      // And it is one line tall, not two.
      expect(tester.getSize(find.byType(LyricLine)).height, lessThan(40));
    });

    testWidgets('no lift, no bloom and no soft edge on a pinned line',
        (tester) async {
      clock.reset(1000);
      await tester.pumpWidget(_host(lyrics: _syncedLyric(), clock: clock));
      await tester.pump();

      expect(_line(tester).rise, isFalse,
          reason: 'a word rising on a fixed row once a second reads as the '
              'strip twitching; the reference passes rise = false here too');
      expect(_line(tester).glow, isFalse);
      expect(_line(tester).feather, isFalse);
      expect(_line(tester).tailAlpha, stripUnsungAlpha);
    });
  });
}
