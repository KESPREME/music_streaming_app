// lib/services/transition/fade_curves.dart
//
// The gain laws of a transition. Pure functions, so the property that makes a
// crossfade sound like a blend instead of a dip is a test, not a hope.

import 'dart:math' as math;

/// Gain of the song arriving, at progress [p] in 0..1.
///
/// Equal-power: `sin`, not a straight line. Two DIFFERENT songs are
/// uncorrelated, so their powers add, and `sin² + cos² = 1` holds the summed
/// power constant the whole way through. A linear fade sums to 0.5 at the
/// midpoint - a 3 dB hole where the join should be.
double riseGain(double p) => math.sin(_clamp01(p) * math.pi / 2);

/// Gain of the song leaving, at progress [p] in 0..1.
double fallGain(double p) => math.cos(_clamp01(p) * math.pi / 2);

/// Headroom trim for the two decks while they overlap.
///
/// Equal-power gains sum to more than 1 in AMPLITUDE (up to 1.41 at the
/// midpoint), so two loud masters peaking together clip in the platform mixer.
/// `1 / sqrt(in + out)` takes at most 1.5 dB off both at the midpoint and holds
/// the summed peak to 1.19. A plain gain, not a limiter: a limiter would pump
/// on material that peaks near full scale, which is most of it now.
double headroomTrim(double incoming, double outgoing) {
  final sum = incoming + outgoing;
  return sum <= 1.0 ? 1.0 : 1.0 / math.sqrt(sum);
}

double _clamp01(double v) => v.isNaN ? 0.0 : v.clamp(0.0, 1.0);
