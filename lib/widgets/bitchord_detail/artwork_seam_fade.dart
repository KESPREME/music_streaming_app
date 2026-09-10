import 'package:flutter/material.dart';

/// Shared seam constants for the artwork-to-wash join on detail screens.
///
/// BitChord `DetailScreen.kt` parity notes:
/// - The foot gradient inside the artwork ends at `wash` 0.88 ([kFootPeakAlpha]),
///   starting from transparent at [kFootStart] — never opaque, so faint texture
///   survives at the edge and no flat opaque plug forms.
/// - [kSeamOverhang] is the flat-wash hold past the seam: both the foot fade's
///   arrival and the wash's departure must be slope ~0 across the clip edge, or
///   the eye finds the kink (see BitChord `ArtworkWash.kt` on gradient stops).
const double kFootStart = 0.55;
const double kFootPeakAlpha = 0.88;

/// How far past the artwork's bottom edge pure wash is held before the wash
/// is allowed to ramp or show mesh blobs. Covers the clip edge + veil tail.
const double kSeamOverhang = 48.0;

/// Ease-out cubic: steep over texture (invisible), flat at handoff (no kink).
double _easeOutCubic(double t) => 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);

/// Foot fade settling the artwork onto the wash (BitChord `PageBackground`
/// foot gradient parity).
///
/// Gradient-only on purpose: no `ShaderMask`/`BackdropFilter` (those caused a
/// worse seam + 20fps stutter; tests forbid them). Eased multi-stop ramp so no
/// slope kink bands across smooth skies/fields. Ends flat at [kFootPeakAlpha]
/// — the [MergeBand] veil carries it the rest of the way to opaque.
class ArtworkFootFade extends StatelessWidget {
  final Color washColor;

  const ArtworkFootFade({super.key, required this.washColor});

  @override
  Widget build(BuildContext context) {
    // Sample the 0.55 -> 1.0 ramp with ease-out: slope starts over busy
    // texture and decays to ~0 at the seam handoff.
    const stops = [0.0, 0.55, 0.66, 0.76, 0.84, 0.91, 0.96, 1.0];
    final colors = <Color>[Colors.transparent, Colors.transparent];
    for (var i = 2; i < stops.length; i++) {
      final u = (stops[i] - kFootStart) / (1.0 - kFootStart);
      colors.add(washColor.withValues(alpha: kFootPeakAlpha * _easeOutCubic(u)));
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: stops,
          colors: colors,
        ),
      ),
    );
  }
}
