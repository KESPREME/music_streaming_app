import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyric_clock.dart';
import 'package:music_streaming_app/widgets/lyric_strip.dart';
import 'package:music_streaming_app/widgets/lyric_swept_line.dart';

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
/// Reference: `CurrentLyricStrip` and its three siblings,
/// PlayerLyrics.kt:2492-2681.

/// A ticker provider that never ticks.
///
/// The clock is never started: the tests move it with [LyricClock.resync], which
/// is exactly the "the song is not moving" path, so a ticker would only add
/// frames that prove nothing.
class _NoTickVsync implements TickerProvider {
  const _NoTickVsync();

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// A real clock, driven by hand.
LyricClock _manualClock() => LyricClock(vsync: const _NoTickVsync());

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

/// The same six lines with no timings at all.
List<LyricsEntry> _plainLyric() => [
      for (var i = 0; i < 6; i++)
        LyricsEntry(timeMs: i * 4000, endMs: i * 4000 + 3000, text: 'line ${i + 1} here'),
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

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('the handover spec matches the reference', () {
    test('340ms, sliding 35% of its own height', () {
      expect(stripHandoverDuration, const Duration(milliseconds: 340));
      expect(stripSlideFraction, 0.35);
      expect(stripUnsungAlpha, 0.55);
    });
  });

  group('the states are distinguishable', () {
    testWidgets('a loading lookup is dim and static', (tester) async {
      final clock = _manualClock();
      await tester.pumpWidget(
        _host(lyrics: null, clock: clock, isLoading: true, hasLyrics: false),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('lyric-strip-loading')), findsOneWidget);
      expect(find.byType(LyricSweptLine), findsNothing);
    });

    testWidgets('a word-synced line renders the sweep', (tester) async {
      final clock = _manualClock()..resync(1000);
      await tester.pumpWidget(
        _host(lyrics: _syncedLyric(), clock: clock),
      );
      await tester.pump();

      expect(find.byType(LyricSweptLine), findsOneWidget);
    });

    testWidgets('a line-synced lyric is PLAIN, never a dead sweep',
        (tester) async {
      // THE ONE THIS PINS. A lyric with no timings anywhere would still have
      // been drawn by the sweep path and would never have lit a word - a strip
      // that looks like it is following along and is not.
      final clock = _manualClock()..resync(1000);
      await tester.pumpWidget(
        _host(lyrics: _plainLyric(), clock: clock),
      );
      await tester.pump();

      expect(find.byType(LyricSweptLine), findsNothing);
      expect(find.textContaining('Open lyrics'), findsOneWidget,
          reason: 'nothing to sweep: say so and offer the way in');
    });

    testWidgets('before the first vocal line the intro phrase shows',
        (tester) async {
      // A lyric whose first word does not arrive until 6s: a position before it is
      // the intro, which is a different fact from "no lyrics".
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
      final clock = _manualClock()..resync(1000);
      await tester.pumpWidget(_host(lyrics: late, clock: clock));
      await tester.pump();

      expect(find.text('Let it breathe'), findsOneWidget);
      expect(find.byType(LyricSweptLine), findsNothing);
    });

    testWidgets('no lyrics at all is its own state, not an intro phrase',
        (tester) async {
      final clock = _manualClock()..resync(0);
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
  });

  group('the index and the wipe read one clock', () {
    testWidgets('a drag override shows the line being scrubbed TO',
        (tester) async {
      final clock = _manualClock()..resync(1000);
      await tester.pumpWidget(
        _host(lyrics: _syncedLyric(), clock: clock, positionOverrideMs: 17000),
      );
      await tester.pump();

      final swept = tester.widget<LyricSweptLine>(find.byType(LyricSweptLine));
      expect(swept.entry.timeMs, 16000,
          reason: 'the override must win over the playing position, or scrubbing '
              'previews the wrong line');
      // And it is the SAME clock the wipe draws from - one source of truth.
      expect(swept.clock, same(clock));
    });

    testWidgets('the line resolves off the clock, not a second stream',
        (tester) async {
      final clock = _manualClock()..resync(1000);
      await tester.pumpWidget(
        _host(lyrics: _syncedLyric(), clock: clock),
      );
      await tester.pump();
      expect(
        tester.widget<LyricSweptLine>(find.byType(LyricSweptLine)).entry.timeMs,
        0,
      );

      // No positionStream, no provider, no pump between: moving the clock is the
      // only thing that can change the answer.
      clock.resync(9000);
      await tester.pump();
      expect(
        tester.widget<LyricSweptLine>(find.byType(LyricSweptLine)).entry.timeMs,
        8000,
      );
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
      final clock = _manualClock()..resync(1000);
      await tester.pumpWidget(_host(lyrics: long, clock: clock));
      await tester.pump();

      final swept = tester.widget<LyricSweptLine>(find.byType(LyricSweptLine));
      expect(swept.maxLines, 1);
      expect(swept.overflow, TextOverflow.ellipsis);
      // And it is one line tall, not two.
      expect(tester.getSize(find.byType(LyricSweptLine)).height, lessThan(60));
    });

    testWidgets('no lift and no bloom on a pinned line', (tester) async {
      final clock = _manualClock()..resync(1000);
      await tester.pumpWidget(_host(lyrics: _syncedLyric(), clock: clock));
      await tester.pump();

      final swept = tester.widget<LyricSweptLine>(find.byType(LyricSweptLine));
      expect(swept.rise, isFalse,
          reason: 'a word rising on a fixed row once a second reads as the '
              'strip twitching; the reference passes rise = false here too');
      expect(swept.glow, isFalse);
    });
  });
}