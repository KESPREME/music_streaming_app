import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/services/lyrics/lyric_clock.dart';
import 'package:music_streaming_app/services/lyrics/lyric_clock_feed.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_line.dart';
import 'package:music_streaming_app/widgets/lyric_strip.dart';

/// WHAT THIS FILE PINS.
///
/// The lyric clock is demand-driven: it runs a timer (or a ticker) only while
/// something listens to it. Two things used to keep it alive for no reason:
///
///   * the seek-bar strip listened as soon as it was on screen, whether or not
///     there was anything to resolve - no lyrics, still loading, or plain text
///     with no times - so a coarse 100ms timer woke the CPU for the whole song;
///   * the timer is a plain `Timer.periodic`, which the scheduler does NOT mute
///     when the app goes to the background, so it kept waking the device with
///     the screen off.
///
/// Both must stop, and neither may change what a listener sees.

class _NoTickVsync implements TickerProvider {
  const _NoTickVsync();
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

LyricClock _clock() => LyricClock(vsync: const _NoTickVsync(), now: () => 0);

List<LyricsEntry> _timed() => [
      for (var i = 0; i < 4; i++)
        LyricsEntry(
            timeMs: i * 4000 + 1, endMs: i * 4000 + 3000, text: 'line $i'),
    ];

List<LyricsEntry> _plain() => [
      for (var i = 0; i < 4; i++) LyricsEntry(timeMs: 0, text: 'line $i'),
    ];

Widget _strip(
  LyricClock clock, {
  List<LyricsEntry>? lyrics,
  bool isLoading = false,
  bool hasLyrics = true,
  bool tickersEnabled = true,
}) =>
    MaterialApp(
      home: Scaffold(
        body: TickerMode(
          enabled: tickersEnabled,
          child: SizedBox(
            width: 360,
            child: LyricStrip(
              lyrics: lyrics,
              clock: clock,
              introPhrase: 'Let it breathe',
              isLoading: isLoading,
              hasLyrics: hasLyrics,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

class _FakeProvider extends ChangeNotifier implements MusicProvider {
  bool playing = true;
  Duration pos = Duration.zero;
  final positions = StreamController<Duration>.broadcast();
  final seeks = StreamController<Duration>.broadcast();

  @override
  bool get isPlaying => playing;
  @override
  Duration get position => pos;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration> get seekEvents => seeks.stream;
  @override
  double get playbackSpeed => 1.0;
  @override
  Track? get currentTrack => null;

  /// ChangeNotifier.notifyListeners is protected; tests get a door.
  void poke() => notifyListeners();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('LyricStrip asks for the clock only when it can use it', () {
    testWidgets('no lyrics yet: no listener, so no timer', (tester) async {
      final clock = _clock();
      await tester.pumpWidget(_strip(clock, lyrics: null, isLoading: true));
      expect(clock.hasListenersForTest, isFalse);
    });

    testWidgets('lyrics that came back empty: no listener', (tester) async {
      final clock = _clock();
      await tester
          .pumpWidget(_strip(clock, lyrics: const [], hasLyrics: false));
      expect(clock.hasListenersForTest, isFalse);
    });

    testWidgets('plain text with no times: no listener', (tester) async {
      final clock = _clock();
      await tester.pumpWidget(_strip(clock, lyrics: _plain()));
      expect(clock.hasListenersForTest, isFalse,
          reason: 'nothing to resolve against, so no wake-ups');
    });

    testWidgets('timed lyrics: listens', (tester) async {
      final clock = _clock();
      await tester.pumpWidget(_strip(clock, lyrics: _timed()));
      expect(clock.hasListenersForTest, isTrue);
    });

    testWidgets('lyrics arriving later turn the listener on, and off again',
        (tester) async {
      final clock = _clock();
      await tester.pumpWidget(_strip(clock, lyrics: null, isLoading: true));
      expect(clock.hasListenersForTest, isFalse);

      await tester.pumpWidget(_strip(clock, lyrics: _timed()));
      expect(clock.hasListenersForTest, isTrue);

      // The next track: nothing yet.
      await tester.pumpWidget(_strip(clock, lyrics: null, isLoading: true));
      expect(clock.hasListenersForTest, isFalse);
    });

    testWidgets('a strip in a dead subtree still lets go', (tester) async {
      final clock = _clock();
      await tester.pumpWidget(_strip(clock, lyrics: _timed()));
      expect(clock.hasListenersForTest, isTrue);
      await tester.pumpWidget(
          _strip(clock, lyrics: _timed(), tickersEnabled: false));
      expect(clock.hasListenersForTest, isFalse);
    });

    testWidgets('timed lyrics still resolve the line off the clock',
        (tester) async {
      final clock = _clock();
      await tester.pumpWidget(_strip(clock, lyrics: _timed()));
      clock.reset(1000);
      await tester.pump();
      expect(tester.widget<LyricLine>(find.byType(LyricLine)).entry.timeMs, 1);

      // Inside "line 2": moving the clock is the only thing that changes it.
      clock.reset(9000);
      await tester.pump();
      await tester
          .pump(stripHandoverDuration + const Duration(milliseconds: 60));
      expect(tester.widget<LyricLine>(find.byType(LyricLine)).entry.timeMs, 8001);
    });
  });

  group('LyricClockFeed follows the app lifecycle', () {
    late _FakeProvider provider;
    late LyricClock clock;
    late LyricClockFeed feed;

    setUp(() {
      provider = _FakeProvider();
      clock = _clock();
      feed = LyricClockFeed(clock: clock, provider: provider)..start();
    });

    tearDown(() {
      feed.dispose();
      provider.positions.close();
      provider.seeks.close();
    });

    testWidgets('a song that is playing runs the clock', (tester) async {
      expect(clock.isPlaying, isTrue);
    });

    testWidgets('going to the background stops the clock, not the song',
        (tester) async {
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(clock.isPlaying, isFalse);
      expect(provider.playing, isTrue, reason: 'the audio is untouched');
    });

    testWidgets('inactive (notification shade) is still on screen',
        (tester) async {
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(clock.isPlaying, isTrue);
    });

    testWidgets('readings are not fed to a clock nobody is looking at',
        (tester) async {
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = clock.displayedMs;
      provider.positions.add(const Duration(seconds: 5));
      await tester.pump();
      expect(clock.displayedMs, before);
    });

    testWidgets('coming back lands on where the player is, then runs',
        (tester) async {
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      provider.pos = const Duration(seconds: 90); // it played on meanwhile
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      expect(clock.isPlaying, isTrue);
      expect(clock.displayedMs, closeTo(90000, 50),
          reason: 'the first frame back shows the right line');
    });

    testWidgets('a paused song stays paused after the app comes back',
        (tester) async {
      provider.playing = false;
      provider.poke();
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(clock.isPlaying, isFalse);
    });

    testWidgets('once disposed the feed ignores the lifecycle',
        (tester) async {
      feed.dispose();
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(clock.isPlaying, isTrue, reason: 'nothing is driving it any more');
    });
  });
}
