import 'dart:math';

import 'package:flutter/material.dart';
import 'explore_tokens.dart';

/// Deterministic rotary-wheel geometry: viewport in, exact spec out.
/// Rows flow along Δx = k·(1−cos(|t|·θmax)); scale/opacity/text/glass all
/// derive from centrality c = 1−|t|. Pure functions — fully unit-tested.
class ExploreWheelSpec {
  const ExploreWheelSpec({
    required this.itemExtent,
    required this.arcA,
    required this.contentMaxWidth,
  });

  final double itemExtent;
  final double arcA;
  final double contentMaxWidth;
}

class ExploreWheelMath {
  /// Uniform row height: ~5 rows visible, clamped for small/tablet.
  static double itemExtentFor(double viewportH) =>
      (viewportH / ExploreTokens.wheelVisibleRows)
          .clamp(ExploreTokens.wheelMinExtent, ExploreTokens.wheelMaxExtent);

  static ExploreWheelSpec plan(Size viewport) => ExploreWheelSpec(
        itemExtent: itemExtentFor(viewport.height),
        arcA: ExploreTokens.arcA,
        contentMaxWidth: ExploreTokens.contentMaxWidth,
      );

  /// Signed centrality t in [-1,1] from row-center distance to viewport
  /// center. Symmetric centering padding ⇒ centered offset = index·extent.
  static double tForIndex(int index, double offset, double extent,
      double viewportH, double padTop) {
    final rowCenter = padTop + index * extent + extent / 2 - offset;
    return ((rowCenter - viewportH / 2) / (viewportH / 2))
        .clamp(-1.0, 1.0);
  }

  static double centrality(double t) => (1.0 - t.abs()).clamp(0.0, 1.0);

  /// Arc lateral offset: center sweeps furthest right (0), top and
  /// bottom curve back left: x = −A·(1−cos(|t|·π/2)).
  static double arcDx(double t, double a) =>
      -a * (1 - cos(t.abs() * pi / 2));

  /// Anchors: c=1 → 1.0/1.0; neighbor band (c≈0.67) → ≈0.74/0.46;
  /// edge c=0 → 0.60/0.18.
  static double scaleFor(double c) {
    final u = ((1 - c) * 2).clamp(0.0, 1.0);
    return 1 - 0.40 * u;
  }

  static double opacityFor(double c) {
    final u = ((1 - c) * 2).clamp(0.0, 1.0);
    return 1 - 0.82 * u;
  }

  /// Text gone at edges (vinyl-only peripherals).
  static double textOpacityFor(double c) =>
      ((c - ExploreTokens.textFadeStart) / (1 - ExploreTokens.textFadeStart))
          .clamp(0.0, 1.0);

  /// Pill chrome only near center.
  static double glassFor(double c) =>
      ((c - ExploreTokens.glassFadeStart) / (1 - ExploreTokens.glassFadeStart))
          .clamp(0.0, 1.0);
}

/// Legacy planner shim: the stream-list spec now lives in the wheel math.
/// Kept so existing reason-gate callers don't churn.
class ExploreLayout {
  static bool shouldShowReason(double confidence) =>
      confidence >= ExploreTokens.reasonConfidenceFloor;
}
