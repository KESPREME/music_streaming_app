import 'package:flutter/material.dart';
import 'explore_tokens.dart';

/// Deterministic stream geometry: viewport in, exact spec out.
/// Five slots (-2..+2) flow along fixed diagonal offsets; far peeks drop
/// on short viewports. Never overflows by construction — pages need no
/// scroll view inside the vertical PageView.
class ExploreStreamSpec {
  const ExploreStreamSpec({
    required this.activeArt,
    required this.nearArt,
    required this.farArt,
    required this.activeRowH,
    required this.nearRowH,
    required this.farRowH,
    required this.slotDx,
    required this.showFar,
    required this.contentMaxWidth,
  });

  final double activeArt;
  final double nearArt;
  final double farArt;
  final double activeRowH;
  final double nearRowH;
  final double farRowH;

  /// Lateral offsets for slots -2..+2 (top-right → bottom-left flow).
  final List<double> slotDx;
  final bool showFar;
  final double contentMaxWidth;
}

class ExploreLayout {
  /// Pure planner: PageView constraints → deterministic spec.
  static ExploreStreamSpec plan(Size viewport) {
    final h = viewport.height;
    // Fixed chrome without far rows: active 104 + 2×near 76 + rail 48 +
    // not-interested 28 + 5 gaps ×12 + vertical padding 24 = 416.
    const base = 104.0 + 2 * 76.0 + 48.0 + 28.0 + 5 * 12.0 + 24.0;
    const withFar = base + 2 * 56.0 + 2 * 12.0;
    return ExploreStreamSpec(
      activeArt: ExploreTokens.activeArtSize,
      nearArt: ExploreTokens.neighborArtSize,
      farArt: ExploreTokens.farArtSize,
      activeRowH: ExploreTokens.activeRowHeight,
      nearRowH: ExploreTokens.neighborRowHeight,
      farRowH: ExploreTokens.farRowHeight,
      slotDx: const [
        ExploreTokens.slotDxFar,
        ExploreTokens.slotDxNear,
        0,
        -ExploreTokens.slotDxNear,
        -ExploreTokens.slotDxFar,
      ],
      showFar: h >= withFar,
      contentMaxWidth: ExploreTokens.contentMaxWidth,
    );
  }

  /// Render-time reason gate (kept for traces/future surfaces).
  static bool shouldShowReason(double confidence) =>
      confidence >= ExploreTokens.reasonConfidenceFloor;
}
