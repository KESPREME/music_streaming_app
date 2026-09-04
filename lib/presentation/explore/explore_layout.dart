import 'dart:math';

import 'package:flutter/material.dart';
import 'explore_tokens.dart';

/// Deterministic rotary-wheel geometry: viewport in, exact spec out.
/// Rows flow along Δx = k·(1−cos(|t|·θmax)); scale/opacity/text/glass all
/// derive from centrality c = 1−|t|. Pure functions — fully unit-tested.
class ExploreWheelSpec {
  const ExploreWheelSpec({
    required this.itemExtent,
    required this.arcK,
    required this.maxTheta,
    required this.contentMaxWidth,
  });

  final double itemExtent;
  final double arcK;
  final double maxTheta;
  final double contentMaxWidth;
}

class ExploreWheelMath {
  /// Uniform row height: ~5 rows visible, clamped for small/tablet.
  static double itemExtentFor(double viewportH) =>
      (viewportH / ExploreTokens.wheelVisibleRows)
          .clamp(ExploreTokens.wheelMinExtent, ExploreTokens.wheelMaxExtent);

  static ExploreWheelSpec plan(Size viewport) => ExploreWheelSpec(
        itemExtent: itemExtentFor(viewport.height),
        arcK: ExploreTokens.arcK,
        maxTheta: ExploreTokens.arcThetaMax,
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

  /// Arc lateral offset, always +x (wheel curves right).
  static double arcDx(double t, double k, double maxTheta) =>
      k * (1 - cos(t.abs() * maxTheta));

  static double scaleFor(double c) =>
      ExploreTokens.scaleMin + (1 - ExploreTokens.scaleMin) * c;
  static double opacityFor(double c) =>
      ExploreTokens.opacityMin + (1 - ExploreTokens.opacityMin) * c;

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
