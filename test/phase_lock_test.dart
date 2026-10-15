import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/transition/phase_lock.dart';

/// THE BEAT LOCK THIS FILE PINS.
///
/// A small simulator stands in for the two decks: the outgoing one advances with
/// the wall clock, the incoming one starts [lagMs] late and advances at the
/// speed the lock last asked for. The lock sees only positions, as it does in
/// the app, and has to find the beat from them.

class Sim {
  Sim({
    required this.lagMs,
    this.rate = 1.0,
    this.startAt = 93000,
    this.cue = 4000,
    this.bias = 0,
  }) : lock = PhaseLock(startAtMs: 93000, cueMs: 4000, rate: rate);

  final int lagMs;
  final double rate;
  final int startAt;
  final int cue;

  /// A constant error in the READING of the incoming position (what a deck that
  /// reports itself ahead or behind would do), not in the sound.
  final double bias;
  final PhaseLock lock;

  double speed = 1.0; // multiplier the lock last asked for
  double outPos = 93000;
  double inPos = 4000;
  int wall = 0;

  /// The true misalignment of the SOUND: positive = the incoming is late.
  double get trueError => (outPos - startAt) - (inPos - cue) / rate;

  void step(int ms) {
    wall += ms;
    outPos += ms;
    if (wall > lagMs) {
      inPos += ms * rate * speed;
    }
    final next = lock.update(
      wallMs: wall,
      outPosMs: outPos.round(),
      inPosMs: (inPos + bias).round(),
    );
    if (next != null) speed = next;
  }

  void run(int ms, {int stepMs = 30}) {
    for (var t = 0; t < ms; t += stepMs) {
      step(stepMs);
    }
  }
}

void main() {
  group('finding the beat', () {
    for (final lag in [30, 80, 120]) {
      test('a start $lag ms late is pulled back onto the beat', () {
        final s = Sim(lagMs: lag);
        s.run(6000);
        expect(s.trueError.abs(), lessThan(PhaseLock.deadbandMs * 1.5),
            reason: 'within a few ms after six seconds');
        expect(s.lock.peakTrim, lessThanOrEqualTo(PhaseLock.maxTrim + 1e-9));
      });
    }

    test('a bigger error is worked off as fast as the bound allows', () {
      // 3 % is 30 ms of correction per second: a start 220 ms late is not fixed
      // in a six-second mix, but it is worked off every second the lock has
      // and never made worse.
      final s = Sim(lagMs: 220);
      s.run(1500);
      final early = s.trueError.abs();
      s.run(4500);
      expect(s.trueError.abs(), lessThan(early));
      expect(s.trueError.abs(), lessThan(100));
    });

    test('it works with a stretched tempo', () {
      final s = Sim(lagMs: 90, rate: 1.04);
      s.run(5000);
      expect(s.trueError.abs(), lessThan(PhaseLock.deadbandMs * 1.5));
    });

    test('a song that starts early is slowed, not sped up', () {
      // A deck that reports itself AHEAD of the plan.
      final s = Sim(lagMs: 0)..inPos = 4000 + 60;
      s.run(900);
      expect(s.lock.trim, lessThan(0), reason: 'behind-by-negative means slow down');
      s.run(5000);
      expect(s.trueError.abs(), lessThan(PhaseLock.deadbandMs * 1.5));
    });

    test('an aligned start is left completely alone', () {
      final s = Sim(lagMs: 0);
      s.run(5000);
      expect(s.lock.corrections, 0);
      expect(s.speed, 1.0);
      expect(s.trueError.abs(), lessThan(PhaseLock.deadbandMs));
    });

    test('the trim goes back to nothing once the error is gone', () {
      final s = Sim(lagMs: 100);
      s.run(6000);
      expect(s.lock.trim, 0.0);
      expect(s.speed, 1.0);
    });
  });

  group('not trusting what it cannot trust', () {
    test('it waits for the incoming deck to be playing before it reads it', () {
      final lock = PhaseLock(startAtMs: 93000, cueMs: 4000, rate: 1.0);
      // The incoming deck has not moved: it is still at its cue.
      for (var t = 0; t < 600; t += 30) {
        expect(
            lock.update(wallMs: t, outPosMs: 93000 + t, inPosMs: 4000),
            isNull);
      }
      expect(lock.firstErrorMs, isNull);
    });

    test('it needs three readings, and acts on the middle one', () {
      final lock = PhaseLock(startAtMs: 0, cueMs: 0, rate: 1.0);
      // One wild reading among steady ones does not move it.
      expect(lock.update(wallMs: 0, outPosMs: 1000, inPosMs: 1000), isNull);
      expect(lock.update(wallMs: 100, outPosMs: 1100, inPosMs: 1100), isNull);
      expect(lock.update(wallMs: 200, outPosMs: 1200, inPosMs: 1200), isNull,
          reason: 'zero error: nothing to do');
      // A glitch reading of 150 ms late between good ones: the median is 0.
      expect(lock.update(wallMs: 300, outPosMs: 1300, inPosMs: 1150), isNull);
      expect(lock.lastErrorMs, closeTo(0, 1e-9));
    });

    test('an implausible error lets go instead of chasing it', () {
      final s = Sim(lagMs: 0)..inPos = 4000 + 900;
      s.run(1000);
      expect(s.lock.released, isTrue);
      expect(s.speed, 1.0, reason: 'and the mix plays as planned');
      final before = s.lock.corrections;
      s.run(2000);
      expect(s.lock.corrections, before, reason: 'it stays let go');
    });

    test('it never trims further than the bound, however large the error', () {
      final s = Sim(lagMs: 240);
      for (var i = 0; i < 300; i++) {
        s.step(30);
        expect(s.speed, inInclusiveRange(1 - PhaseLock.maxTrim - 1e-9, 1 + PhaseLock.maxTrim + 1e-9));
      }
    });

    test('readings are sampled at a sane rate, not on every tick', () {
      final lock = PhaseLock(startAtMs: 0, cueMs: 0, rate: 1.0);
      var accepted = 0;
      for (var t = 0; t < 2000; t += 10) {
        lock.update(wallMs: t, outPosMs: 1000 + t, inPosMs: 1000 + t + 50);
        accepted = lock.corrections;
      }
      expect(accepted, lessThan(20));
    });
  });
}
