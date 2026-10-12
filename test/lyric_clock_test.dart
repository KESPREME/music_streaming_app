// Pins the lyric playhead (the steering engine) and the clock that drives it.
//
// The engine cases are ported from BitChord's `LyricClockTest.kt`, so the rules
// are the reference's rules and not this port's reading of them. The driver
// cases pin the bug the old clock shipped with: a ticker that was stopped once
// and never started again, which froze the lyrics after a provider switch.

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/lyrics/lyric_clock.dart';

const double _frameMs = 1000.0 / 60;

/// A song playing at [rate] from [startMs], read every 500ms. Each reading is
/// stamped when it is taken, and reaches the frame loop up to [maxDelayMs]
/// later - the way a reading did when the main thread was busy.
class _Playback {
  _Playback({
    this.startMs = 44500,
    this.rate = 1.0,
    this.maxDelayMs = 60.0,
    this.stamped = true,
    int seed = 7,
  })  : _random = math.Random(seed),
        report = startMs,
        sampledAt = stamped ? 0.0 : double.nan;

  final int startMs;
  final double rate;
  final double maxDelayMs;
  final bool stamped;
  final math.Random _random;

  double _nextPollMs = 0.0;
  final Queue<({double arrives, int reading, double at})> _inFlight = Queue();
  int report;
  double sampledAt;

  double trueAt(double nowMs) => startMs + nowMs * rate;

  /// Advances deliveries to [nowMs]; afterwards [report] and [sampledAt] are
  /// what the frame sees.
  void deliver(double nowMs) {
    while (_nextPollMs <= nowMs) {
      final reading = trueAt(_nextPollMs).toInt();
      final arrives = _nextPollMs + _random.nextDouble() * maxDelayMs;
      _inFlight.addLast((arrives: arrives, reading: reading, at: _nextPollMs));
      _nextPollMs += 500.0;
    }
    while (_inFlight.isNotEmpty && _inFlight.first.arrives <= nowMs) {
      final r = _inFlight.removeFirst();
      report = r.reading;
      if (stamped) sampledAt = r.at;
    }
  }
}

class _Run {
  _Run(this.frames, this.shown, this.truth);
  final List<double> frames;
  final List<int> shown;
  final List<double> truth;
}

/// Frames at 60Hz, with a stall of up to [maxStallMs] - no frames at all - now
/// and then.
_Run _run(
  _Playback playback, {
  required double seconds,
  double maxStallMs = 0.0,
  int seed = 11,
}) {
  final random = math.Random(seed);
  final head = LyricPlayhead(startMs: playback.startMs);
  final frames = <double>[];
  final shown = <int>[];
  final truth = <double>[];
  var now = 0.0;
  while (now <= seconds * 1000) {
    playback.deliver(now);
    frames.add(now);
    shown.add(head.frame(now, playback.report, playback.sampledAt, 0));
    truth.add(playback.trueAt(now));
    now += _frameMs;
    if (maxStallMs > 0 && random.nextDouble() < 0.02) {
      now += random.nextDouble() * maxStallMs;
    }
  }
  return _Run(frames, shown, truth);
}

void _expectNeverBack(_Run run) {
  for (var i = 1; i < run.shown.length; i++) {
    expect(run.shown[i], greaterThanOrEqualTo(run.shown[i - 1]),
        reason: 'went back at ${run.frames[i]}');
  }
}

/// Drives a playhead on a song at 1x from 10s, with [readingAt] deciding what
/// each 500ms reading says.
int _steady({
  required double until,
  LyricPlayhead? head,
  int Function(double now)? discontinuity,
  int Function(double taken)? readingAt,
  void Function(double now, int shown)? onFrame,
}) {
  final h = head ?? LyricPlayhead(startMs: 10000);
  final disc = discontinuity ?? (_) => 0;
  final reading = readingAt ?? (taken) => 10000 + taken.toInt();
  var now = 0.0;
  var shown = 0;
  while (now <= until) {
    final taken = (now / 500).floor() * 500.0;
    shown = h.frame(now, reading(taken), taken, disc(now));
    onFrame?.call(now, shown);
    now += _frameMs;
  }
  return shown;
}

void main() {
  group('LyricPlayhead', () {
    test('late readings never move the words back', () {
      final run = _run(_Playback(maxDelayMs: 800.0),
          seconds: 90.0, maxStallMs: 600.0);
      _expectNeverBack(run);
    });

    test('late readings do not pull the words off the song', () {
      final run = _run(_Playback(maxDelayMs: 800.0),
          seconds: 60.0, maxStallMs: 600.0);
      for (var i = 0; i < run.frames.length; i++) {
        if (run.frames[i] < 2000) continue;
        final error = run.shown[i] - run.truth[i];
        expect(error.abs(), lessThan(40.0),
            reason: 'off by $error at ${run.frames[i]}');
      }
    });

    test('late readings never stall the words', () {
      final run = _run(_Playback(maxDelayMs: 800.0), seconds: 60.0);
      const window = 15;
      for (var i = window; i < run.shown.length; i++) {
        final moved = run.shown[i] - run.shown[i - window];
        final elapsed = run.frames[i] - run.frames[i - window];
        expect(moved, greaterThanOrEqualTo(elapsed * 0.5),
            reason: 'stalled near ${run.frames[i]}');
      }
    });

    test('unstamped readings never move the words back', () {
      final run = _run(_Playback(maxDelayMs: 800.0, stamped: false),
          seconds: 60.0, maxStallMs: 600.0);
      _expectNeverBack(run);
    });

    test('learns a faster playback rate', () {
      final run = _run(_Playback(rate: 1.25, maxDelayMs: 300.0), seconds: 30.0);
      for (var i = 0; i < run.frames.length; i++) {
        if (run.frames[i] < 4000) continue;
        final error = run.shown[i] - run.truth[i];
        expect(error.abs(), lessThan(40.0),
            reason: 'off by $error at ${run.frames[i]}');
      }
      _expectNeverBack(run);
    });

    test('one wrong reading is ignored', () {
      var previous = -1 << 31;
      final last = _steady(
        until: 8000.0,
        readingAt: (taken) =>
            10000 +
            taken.toInt() +
            (taken == 3000.0
                ? 1500
                : taken == 5000.0
                    ? -1500
                    : 0),
        onFrame: (now, shown) {
          expect(shown, greaterThanOrEqualTo(previous),
              reason: 'went back at $now');
          if (now > 1000) {
            expect((shown - (10000 + now)).abs(), lessThan(40),
                reason: 'followed the bad reading at $now');
          }
          previous = shown;
        },
      );
      expect((last - 18000).abs(), lessThan(40));
    });

    test('an announced backward seek glides back and lands', () {
      var shown = 0;
      var largestStep = 0;
      const seekAt = 4000.0;
      _steady(
        until: 5000.0,
        discontinuity: (now) => now >= seekAt ? 1 : 0,
        readingAt: (taken) =>
            10000 + taken.toInt() - (taken >= seekAt ? 1000 : 0),
        onFrame: (now, next) {
          if (now > seekAt) largestStep = math.max(largestStep, (next - shown).abs());
          shown = next;
        },
      );
      expect(largestStep, lessThan(150),
          reason: 'cut rather than glided: $largestStep ms in a frame');
      expect((shown - 14000).abs(), lessThan(40),
          reason: 'never landed: $shown');
    });

    test('an announced far seek jumps at once', () {
      final head = LyricPlayhead(startMs: 30000);
      head.frame(0.0, 30000, 0.0, 0);
      head.frame(16.0, 30000, 0.0, 0);
      expect(head.frame(33.0, 4000, 30.0, 1), 4003);
    });

    test('an unannounced small rewind slows down instead of reversing', () {
      var previous = -1 << 31;
      final last = _steady(
        until: 12000.0,
        readingAt: (taken) =>
            10000 + taken.toInt() - (taken >= 4000 ? 800 : 0),
        onFrame: (now, shown) {
          expect(shown, greaterThanOrEqualTo(previous),
              reason: 'went back at $now');
          previous = shown;
        },
      );
      expect((last - (22000 - 800)).abs(), lessThan(40),
          reason: 'never met the song: $last');
    });

    test('an unannounced far jump is followed', () {
      final last = _steady(
        until: 8000.0,
        readingAt: (taken) =>
            10000 + taken.toInt() - (taken >= 4000 ? 20000 : 0),
      );
      expect((last - (18000 - 20000)).abs(), lessThan(40),
          reason: 'stayed lost: $last');
    });

    test('an unannounced forward jump catches up', () {
      var previous = -1 << 31;
      final last = _steady(
        until: 8000.0,
        readingAt: (taken) =>
            10000 + taken.toInt() + (taken >= 4000 ? 1000 : 0),
        onFrame: (now, shown) {
          expect(shown, greaterThanOrEqualTo(previous),
              reason: 'went back at $now');
          previous = shown;
        },
      );
      expect((last - 19000).abs(), lessThan(40));
    });

    test('hold settles at once', () {
      final head = LyricPlayhead(startMs: 10000);
      head.frame(0.0, 10000, 0.0, 0);
      head.frame(400.0, 10400, 400.0, 0);
      head.hold(10380, 420.0);
      expect(head.displayedMs, 10380.0);
    });

    test('resuming after a pause starts where it stopped, however long ago', () {
      final head = LyricPlayhead(startMs: 10000);
      head.frame(0.0, 10000, 0.0, 0);
      head.hold(10000, 5.0);
      head.restart();
      expect(head.frame(60000.0, 10000, 0.0, 0), 10000);
      expect(head.frame(60016.0, 10000, 0.0, 0), 10016);
    });

    test('returning to the app extrapolates from the last reading', () {
      final head = LyricPlayhead(startMs: 10000);
      head.frame(0.0, 10000, 0.0, 0);
      head.restart();
      expect(head.frame(30000.0, 10000, 0.0, 0), 40000);
    });

    test('moving the lyrics offset is followed', () {
      final last = _steady(
        until: 5000.0,
        discontinuity: (now) => now >= 3000 ? 1 : 0,
        readingAt: (taken) =>
            10000 + taken.toInt() - (taken >= 3000 ? 1500 : 0),
      );
      expect((last - (15000 - 1500)).abs(), lessThan(40));
    });

    test('a speed the app set is believed from the first frame', () {
      final head = LyricPlayhead(startMs: 0)..seedRate(1.5);
      expect(head.rate, 1.5);
      head.frame(0.0, 0, 0.0, 0);
      expect(head.frame(1000.0, 1500, 1000.0, 0), closeTo(1500, 40));
    });
  });

  group('LyricClock (driver)', () {
    // A time source the test owns, so a pump of N ms means N ms to the clock.
    late double now;
    setUp(() => now = 0);

    LyricClock make({TickerProvider? vsync, int startMs = 0}) =>
        LyricClock(vsync: vsync, now: () => now, startMs: startMs);

    testWidgets('THE REGRESSION: start -> stop -> start ticks again',
        (tester) async {
      final clock = make(vsync: const TestVSync());
      addTearDown(clock.dispose);
      var notified = 0;
      void listener() => notified++;
      clock.addListener(listener);
      final painter = Object();
      clock.retainFrames(painter);

      Future<void> play(int ms) async {
        for (var i = 0; i < ms; i += 16) {
          now += 16;
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      clock.reset(10000);
      clock.setPlaying(true);
      await play(480);
      expect(clock.isRunning, isTrue);
      final first = clock.positionMs;
      expect(first, greaterThan(10300),
          reason: 'the first run advances: $first');

      // Pause (a provider switch, a buffering stall - anything that stops it).
      clock.setPlaying(false);
      expect(clock.isRunning, isFalse);
      final held = clock.positionMs;
      await play(320);
      expect(clock.positionMs, held, reason: 'paused means paused');

      // Resume. The old ticker was stopped but non-null, so this did nothing.
      clock.setPlaying(true);
      await play(480);
      expect(clock.isRunning, isTrue, reason: 'the ticker must restart');
      expect(clock.positionMs, greaterThan(held + 300),
          reason: 'it advanced after the restart: ${clock.positionMs}');
      expect(notified, greaterThan(10));
      clock.releaseFrames(painter);
      clock.removeListener(listener);
    });

    testWidgets('a pause with the frame loop STOPPED and restarted by demand '
        'also recovers', (tester) async {
      // The same bug through the other door: demand going away and coming back.
      final clock = make(vsync: const TestVSync());
      addTearDown(clock.dispose);
      void listener() {}
      clock.addListener(listener);
      clock.reset(0);
      clock.setPlaying(true);
      final painter = Object();

      clock.retainFrames(painter);
      expect(clock.isRunning, isTrue);
      clock.releaseFrames(painter);
      expect(clock.isRunning, isFalse);
      clock.retainFrames(painter);
      expect(clock.isRunning, isTrue, reason: 'demand again means frames again');

      clock.releaseFrames(painter);
      clock.removeListener(listener);
    });

    testWidgets('nothing runs unless somebody listens AND the song plays',
        (tester) async {
      final clock = make(vsync: const TestVSync());
      addTearDown(clock.dispose);
      final painter = Object();
      clock.reset(0);

      clock.setPlaying(true);
      clock.retainFrames(painter);
      expect(clock.isRunning, isFalse, reason: 'demand with no listener');
      expect(clock.isCoarse, isFalse);

      void listener() {}
      clock.addListener(listener);
      expect(clock.isRunning, isTrue);

      clock.setPlaying(false);
      expect(clock.isRunning, isFalse, reason: 'paused');
      expect(clock.isCoarse, isFalse);

      clock.setPlaying(true);
      clock.releaseFrames(painter);
      clock.removeListener(listener);
      expect(clock.isRunning, isFalse);
      expect(clock.isCoarse, isFalse, reason: 'the last listener leaving stops all');
    });

    testWidgets('a listener that needs no frames gets the COARSE tick, not the '
        'vsync loop', (tester) async {
      // The strip and the panel only need to know which line it is. Waking the
      // display sixty times a second for that kept the screen from ever idling.
      final clock = make(vsync: const TestVSync());
      addTearDown(clock.dispose);
      var heard = 0;
      void listener() => heard++;
      clock.addListener(listener);
      clock.reset(5000);
      clock.setPlaying(true);
      clock.report(5000);

      expect(clock.isRunning, isFalse, reason: 'no frame consumer');
      expect(clock.isCoarse, isTrue);

      final before = heard;
      for (var i = 0; i < 10; i++) {
        now += 100;
        await tester.pump(LyricClock.coarsePeriod);
      }
      expect(heard - before, inInclusiveRange(8, 11),
          reason: 'about ten notifications a second, not sixty');
      expect(clock.positionMs, closeTo(6000, 120),
          reason: 'and the position still advances');
      clock.removeListener(listener);
    });

    testWidgets('going from coarse to frames does not lose the position',
        (tester) async {
      final clock = make(vsync: const TestVSync());
      addTearDown(clock.dispose);
      void listener() {}
      clock.addListener(listener);
      clock.reset(5000);
      clock.setPlaying(true);
      clock.report(5000);
      for (var i = 0; i < 5; i++) {
        now += 100;
        await tester.pump(LyricClock.coarsePeriod);
      }
      final atSwitch = clock.positionMs;
      final painter = Object();
      clock.retainFrames(painter);
      expect(clock.isRunning, isTrue);
      expect(clock.isCoarse, isFalse);
      now += 16;
      await tester.pump(const Duration(milliseconds: 16));
      expect(clock.positionMs, closeTo(atSwitch + 16, 40));
      clock.releaseFrames(painter);
      clock.removeListener(listener);
    });
    testWidgets('a position read with no ticker is still the right one',
        (tester) async {
      final clock = make(vsync: const TestVSync());
      addTearDown(clock.dispose);
      clock.reset(5000);
      clock.setPlaying(true);
      clock.report(5000);
      now += 800;
      expect(clock.positionMs, closeTo(5800, 5),
          reason: 'a widget that builds before its first frame draws the '
              'right line');
    });

    test('a reading while paused moves the words (a seek made while paused)',
        () {
      final clock = make();
      addTearDown(clock.dispose);
      clock.reset(1000);
      clock.report(42000);
      expect(clock.positionMs, 42000);
    });

    test('pausing settles on what was on screen', () {
      final clock = make();
      addTearDown(clock.dispose);
      clock.reset(0);
      clock.setPlaying(true);
      clock.report(0);
      now += 1000;
      clock.setPlaying(false);
      expect(clock.positionMs, closeTo(1000, 5));
    });

    test('an announced jump while paused lands exactly', () {
      final clock = make();
      addTearDown(clock.dispose);
      clock.reset(0);
      clock.jump(65000);
      expect(clock.positionMs, 65000);
    });

    test('isAnimating has a millisecond of slack either side', () {
      expect(LyricClock.isAnimating(nowMs: 99, fromMs: 100, untilMs: 200), isTrue);
      expect(LyricClock.isAnimating(nowMs: 98, fromMs: 100, untilMs: 200), isFalse);
      expect(LyricClock.isAnimating(nowMs: 201, fromMs: 100, untilMs: 200), isTrue);
      expect(LyricClock.isAnimating(nowMs: 202, fromMs: 100, untilMs: 200), isFalse);
    });
  });
}
