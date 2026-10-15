// lib/services/transition/level_plan.dart
//
// Keeps two songs that are not equally loud in balance while they overlap.
//
// WHY A FADE ALONE IS NOT ENOUGH
//
// An equal-power crossfade is balanced only when the two songs are equally loud.
// Measured on sixteen songs from one listener's library (EBU R128 integrated
// loudness, ffmpeg): -5.6 LUFS at the loudest, -14.6 at the quietest. Fade the
// quiet one out under the loud one and, at the halfway point where the two gains
// are equal, one is nine times the power of the other: the blend is gone, the
// quiet song is simply masked until the loud one has finished arriving. A
// crossfade then sounds like a cut that happens to take six seconds.
//
// WHAT THIS DOES, using only attenuation (a player's volume cannot go above 1.0,
// and a limiter would pump on masters that already peak at full scale):
//
//   incoming louder  -> the incoming song starts attenuated by the difference and
//                       is released back to its own level over [releaseMs]
//                       once it is playing alone, so the listener hears a swell,
//                       not a step, and the overlap is balanced
//   incoming quieter -> the OUTGOING song is brought down by the difference
//                       early in the fade (it is leaving anyway), so the quiet
//                       song is not buried
//
// Pure functions: the engine and the offline mix lab (tool/mix_lab.dart) both
// call [mixGains], so what the lab measures is what the engine does.

import 'dart:math' as math;

import 'fade_curves.dart';
import 'loudness.dart';
import 'track_analysis.dart';
import 'transition_planner.dart';

class LevelPlan {
  const LevelPlan({
    this.outgoingDb = 0.0,
    this.incomingDb = 0.0,
    this.releaseMs = defaultReleaseMs,
    this.reason = 'off',
  });

  static const LevelPlan none = LevelPlan();

  /// Attenuation of the outgoing song reached by [outgoingRampEnd] of the fade
  /// (0 or negative).
  final double outgoingDb;

  /// Attenuation of the incoming song for the whole overlap (0 or negative).
  final double incomingDb;

  /// How long the incoming song takes to climb back to its own level once the
  /// fade is over. Only meaningful when [incomingDb] is under 0.
  final int releaseMs;

  final String reason;

  bool get isNone => outgoingDb == 0.0 && incomingDb == 0.0;

  static const int defaultReleaseMs = 8000;

  /// The share of the fade over which the outgoing attenuation is applied.
  static const double outgoingRampEnd = 0.35;

  /// Attenuation of the outgoing song at progress [p] (a linear multiplier).
  double outgoingGainAt(double p) {
    if (outgoingDb == 0.0) return 1.0;
    return _db(outgoingDb * _smooth(p / outgoingRampEnd));
  }

  /// Attenuation of the incoming song during the overlap (a linear multiplier).
  double get incomingGain => _db(incomingDb);

  /// The incoming song's multiplier [t] (0..1) of the way through its release.
  double incomingReleaseAt(double t) => _db(incomingDb * (1 - _smooth(t)));

  @override
  String toString() => 'LevelPlan($reason, out=${outgoingDb.toStringAsFixed(1)}dB '
      'in=${incomingDb.toStringAsFixed(1)}dB release=${releaseMs}ms)';

  static double _smooth(double x) {
    final t = x.isNaN ? 0.0 : x.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _db(double db) => math.pow(10, db / 20).toDouble();
}

class LevelPlanner {
  const LevelPlanner._();

  /// Differences under this are left alone: the ear does not hear them as a
  /// mismatch, and a correction that small is more likely measurement error
  /// (the meter is within 0.6 dB of ffmpeg on real songs).
  static const double deadbandDb = 1.5;

  /// The largest correction. Beyond this the songs are not meant to be blended.
  static const double maxDb = 12.0;

  static LevelPlan plan({
    required TransitionPlan mix,
    required TrackAnalysis? outgoing,
    required TrackAnalysis? incoming,
  }) {
    if (mix.isNone || outgoing == null || incoming == null) {
      return LevelPlan.none;
    }
    if (!outgoing.hasLoudness || !incoming.hasLoudness) return LevelPlan.none;

    // What is compared is what is HEARD at the crossover: the middle half of
    // the overlap, where both songs are audible, taken from each song's own
    // timeline (the incoming one runs [incomingRate] times faster).
    //
    // Not the song's average level, and not the stretch before the fade. Both
    // were tried first and both were wrong on real songs: a song that ends in a
    // fade-out is far quieter in the overlap than its average (one read -5 LUFS
    // on average and -27 over the fade), and a song that opens quietly is far
    // quieter in the overlap than its body. Comparing the averages "corrected" a
    // blend that was already balanced.
    final fade = mix.fadeMs;
    final outLevel =
        outgoing.lufsBetween(mix.startAtMs + fade ~/ 4, mix.startAtMs + fade * 3 ~/ 4);
    final span = (fade * mix.incomingRate).round();
    final inLevel =
        incoming.lufsBetween(mix.cueMs + span ~/ 4, mix.cueMs + span * 3 ~/ 4);
    if (outLevel <= LoudnessProfile.silent || inLevel <= LoudnessProfile.silent) {
      return LevelPlan.none;
    }
    final delta = (inLevel - outLevel).clamp(-maxDb, maxDb);
    if (delta.abs() < deadbandDb) return LevelPlan.none;
    return delta > 0
        ? LevelPlan(
            incomingDb: -delta,
            reason: 'incoming +${delta.toStringAsFixed(1)} LU')
        : LevelPlan(
            outgoingDb: delta,
            reason: 'incoming ${delta.toStringAsFixed(1)} LU');
  }
}

/// The two gains of a transition at progress [p] (0..1): the equal-power
/// curves, the level plan, and the headroom trim for the two together.
///
/// [incomingRelease] is non-null once the fade is over and the incoming song is
/// climbing back to its own level: it is how far through that climb (0..1).
({double outgoing, double incoming}) mixGains(
  double p, {
  LevelPlan level = LevelPlan.none,
  double? incomingRelease,
}) {
  var inG = riseGain(p);
  var outG = fallGain(p);
  final trim = headroomTrim(inG, outG);
  inG *= trim;
  outG *= trim;
  outG *= level.outgoingGainAt(p);
  inG *= incomingRelease == null
      ? level.incomingGain
      : level.incomingReleaseAt(incomingRelease);
  return (outgoing: outG, incoming: inG);
}
