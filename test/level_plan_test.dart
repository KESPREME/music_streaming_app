import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/transition/fade_curves.dart';
import 'package:music_streaming_app/services/transition/level_plan.dart';
import 'package:music_streaming_app/services/transition/track_analysis.dart';
import 'package:music_streaming_app/services/transition/transition_planner.dart';

/// THE LEVEL PLAN THIS FILE PINS.
///
/// Built from loudness profiles written by hand, so each rule is a number: a
/// song that is 9 LU louder than the one before it gets 9 dB less while they
/// overlap; a song that merely ENDS quietly (a fade-out) is not mistaken for a
/// quiet song. The second is the case the first version got wrong on real music.

TrackAnalysis song(String id, List<double> seconds, {int? durationMs}) {
  final energy = seconds
      .where((v) => v > -70)
      .map((v) => math.pow(10, (v + 0.691) / 10))
      .fold<double>(0, (a, b) => a + b);
  final integrated = seconds.isEmpty
      ? -70.0
      : -0.691 + 10 * math.log(energy / seconds.length) / math.ln10;
  return TrackAnalysis(
    trackId: id,
    durationMs: durationMs ?? seconds.length * 1000,
    integratedLufs: integrated,
    levelsLufs: seconds,
  );
}

List<double> flat(double lufs, int seconds) =>
    List<double>.filled(seconds, lufs);

const TransitionPlan fade6s = TransitionPlan(
  kind: PlanKind.crossfade,
  reason: 'test',
  startAtMs: 94000,
  endAtMs: 100000,
);

void main() {
  group('planning', () {
    test('a louder incoming song is held down by the difference', () {
      final out = song('a', flat(-14, 100));
      final inc = song('b', flat(-5, 100));
      final p = LevelPlanner.plan(mix: fade6s, outgoing: out, incoming: inc);
      expect(p.incomingDb, closeTo(-9.0, 0.05));
      expect(p.outgoingDb, 0.0);
      expect(p.isNone, isFalse);
    });

    test('a quieter incoming song brings the OUTGOING one down instead', () {
      final out = song('a', flat(-6, 100));
      final inc = song('b', flat(-15, 100));
      final p = LevelPlanner.plan(mix: fade6s, outgoing: out, incoming: inc);
      expect(p.outgoingDb, closeTo(-9.0, 0.05));
      expect(p.incomingDb, 0.0, reason: 'attenuation only: a player cannot boost');
    });

    test('songs within the deadband are left alone', () {
      final p = LevelPlanner.plan(
          mix: fade6s,
          outgoing: song('a', flat(-10, 100)),
          incoming: song('b', flat(-11.2, 100)));
      expect(p.isNone, isTrue);
    });

    test('the correction is capped', () {
      final p = LevelPlanner.plan(
          mix: fade6s,
          outgoing: song('a', flat(-30, 100)),
          incoming: song('b', flat(-4, 100)));
      expect(p.incomingDb, -LevelPlanner.maxDb);
    });

    test('what is compared is the overlap, not the song', () {
      // The case that broke the first version on real music: the outgoing song
      // is loud (-5) for 90 s and then fades out; over the fade it is at -27.
      // The incoming one opens quietly (-28) and is loud later. Their averages
      // differ by 20 LU; what the listener hears in the overlap differs by 1.
      final out = song('a', [...flat(-5, 94), ...flat(-27, 6)]);
      final inc = song('b', [...flat(-28, 6), ...flat(-6, 94)]);
      final p = LevelPlanner.plan(mix: fade6s, outgoing: out, incoming: inc);
      expect(p.isNone, isTrue);
    });

    test('the incoming side is read from its own cue, at its own speed', () {
      const stretched = TransitionPlan(
        kind: PlanKind.beatmatched,
        reason: 'test',
        startAtMs: 94000,
        endAtMs: 100000,
        cueMs: 20000,
        incomingRate: 1.04,
      );
      // Quiet until 20 s, loud from 20 s on: reading from 0 would see quiet.
      final inc = song('b', [...flat(-30, 20), ...flat(-6, 80)]);
      final p = LevelPlanner.plan(
          mix: stretched, outgoing: song('a', flat(-14, 100)), incoming: inc);
      expect(p.incomingDb, closeTo(-8.0, 0.1));
    });

    test('nothing is planned without a measurement of both songs', () {
      final a = song('a', flat(-10, 100));
      expect(LevelPlanner.plan(mix: fade6s, outgoing: a, incoming: null).isNone, isTrue);
      expect(LevelPlanner.plan(mix: fade6s, outgoing: null, incoming: a).isNone, isTrue);
      const unmeasured = TrackAnalysis(trackId: 'x', durationMs: 100000);
      expect(
          LevelPlanner.plan(mix: fade6s, outgoing: a, incoming: unmeasured).isNone, isTrue);
      expect(
          LevelPlanner.plan(
                  mix: const TransitionPlan.none('album'),
                  outgoing: a,
                  incoming: song('b', flat(-4, 100)))
              .isNone,
          isTrue);
    });

    test('a silent overlap is not a level to match', () {
      final out = song('a', [...flat(-8, 90), ...flat(-70, 10)]);
      final inc = song('b', flat(-5, 100));
      expect(LevelPlanner.plan(mix: fade6s, outgoing: out, incoming: inc).isNone, isTrue);
    });
  });

  group('the gains', () {
    test('with no plan they are the equal-power curves with the headroom trim', () {
      for (final p in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]) {
        final g = mixGains(p);
        final trim = headroomTrim(riseGain(p), fallGain(p));
        expect(g.outgoing, closeTo(fallGain(p) * trim, 1e-12));
        expect(g.incoming, closeTo(riseGain(p) * trim, 1e-12));
      }
    });

    test('a held-down incoming song is that much quieter all the way through', () {
      const level = LevelPlan(incomingDb: -6.0, reason: 'test');
      for (final p in [0.2, 0.5, 0.8]) {
        final plain = mixGains(p);
        final held = mixGains(p, level: level);
        expect(held.incoming / plain.incoming, closeTo(math.pow(10, -6 / 20), 1e-9));
        expect(held.outgoing, closeTo(plain.outgoing, 1e-12));
      }
    });

    test('a brought-down outgoing song gets there by the end of the ramp, smoothly', () {
      const level = LevelPlan(outgoingDb: -9.0, reason: 'test');
      expect(mixGains(0.0, level: level).outgoing, closeTo(1.0, 1e-12),
          reason: 'the fade starts from where the song was');
      final atEnd = mixGains(LevelPlan.outgoingRampEnd, level: level);
      final plainEnd = mixGains(LevelPlan.outgoingRampEnd);
      expect(atEnd.outgoing / plainEnd.outgoing, closeTo(math.pow(10, -9 / 20), 1e-9));
      // Monotonic: never a bump on the way down.
      var last = double.infinity;
      for (var i = 0; i <= 100; i++) {
        final g = mixGains(i / 100, level: level).outgoing;
        expect(g, lessThanOrEqualTo(last + 1e-12));
        last = g;
      }
    });

    test('after the fade the incoming song climbs back to full level, never past it', () {
      const level = LevelPlan(incomingDb: -9.0, reason: 'test');
      var last = 0.0;
      for (var i = 0; i <= 100; i++) {
        final g = mixGains(1.0, level: level, incomingRelease: i / 100).incoming;
        expect(g, greaterThanOrEqualTo(last - 1e-12), reason: 'only ever rising');
        expect(g, lessThanOrEqualTo(1.0 + 1e-12));
        last = g;
      }
      expect(mixGains(1.0, level: level, incomingRelease: 0.0).incoming,
          closeTo(level.incomingGain, 1e-12), reason: 'continuous with the mix');
      expect(last, closeTo(1.0, 1e-12));
    });

    test('no gain is ever above 1.0 or below 0', () {
      for (final level in const [
        LevelPlan.none,
        LevelPlan(incomingDb: -12),
        LevelPlan(outgoingDb: -12),
      ]) {
        for (var i = 0; i <= 100; i++) {
          final g = mixGains(i / 100, level: level);
          expect(g.outgoing, inInclusiveRange(0.0, 1.0));
          expect(g.incoming, inInclusiveRange(0.0, 1.0));
        }
      }
    });
  });
}
