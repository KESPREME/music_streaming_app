import 'package:flutter/material.dart';
import 'explore_tokens.dart';

/// Deterministic deck geometry: viewport in, exact spec out.
/// Priority under pressure: drop prev peek → shrink artwork (floor 150)
/// → (render hides reason). Never overflows by construction — so pages
/// need no scroll view inside the vertical PageView.
class ExploreLayoutSpec {
  const ExploreLayoutSpec({
    required this.artworkSize,
    required this.showPrevPeek,
    required this.showReason,
    required this.prevPeekHeight,
    required this.nextPeekHeight,
    required this.gapAfterArtwork,
    required this.contentMaxWidth,
  });

  final double artworkSize;
  final bool showPrevPeek;
  final bool showReason;
  final double prevPeekHeight;
  final double nextPeekHeight;
  final double gapAfterArtwork;
  final double contentMaxWidth;
}

class ExploreLayout {
  /// Pure planner: PageView constraints → deterministic spec.
  static ExploreLayoutSpec plan(Size viewport) {
    final w = viewport.width, h = viewport.height;
    final contentW =
        (w - ExploreTokens.pagePadding * 2).clamp(0.0, double.infinity);
    var art = (contentW * ExploreTokens.artworkFraction)
        .clamp(ExploreTokens.artworkMinSize, ExploreTokens.artworkMaxWidth);
    art = art.clamp(ExploreTokens.artworkMinSize,
        (h * 0.44).clamp(ExploreTokens.artworkMinSize, double.infinity));
    // Fixed chrome estimate: text ~132 + rail 56 + next peek 64 + gaps 46.
    const chrome = 132.0 +
        ExploreTokens.railHeight +
        ExploreTokens.nextPeekHeight +
        46.0;
    var showPrev = true;
    var total = ExploreTokens.prevPeekHeight + 10 + art +
        ExploreTokens.gapAfterArtwork + chrome;
    if (total > h) {
      showPrev = false;
      total -= (ExploreTokens.prevPeekHeight + 10);
    }
    if (total > h) {
      art = (art - (total - h))
          .clamp(ExploreTokens.artworkMinSize, ExploreTokens.artworkMaxWidth);
    }
    return ExploreLayoutSpec(
      artworkSize: art,
      showPrevPeek: showPrev,
      showReason: true,
      prevPeekHeight: ExploreTokens.prevPeekHeight,
      nextPeekHeight: ExploreTokens.nextPeekHeight,
      gapAfterArtwork: ExploreTokens.gapAfterArtwork,
      contentMaxWidth: ExploreTokens.contentMaxWidth,
    );
  }

  /// Render-time reason gate: subtle context only when confident.
  static bool shouldShowReason(double confidence) =>
      confidence >= ExploreTokens.reasonConfidenceFloor;
}
