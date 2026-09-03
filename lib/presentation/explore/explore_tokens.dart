/// Explore design tokens (spec #75). No magic numbers in widgets.
library;

/// Explore design tokens (spec #75). No magic numbers in widgets.
abstract class ExploreTokens {
  /// Artwork width = min(viewport width × fraction, maxWidth).
  /// 0.76 target keeps the 0.72–0.82 band (deck spec #8).
  static const double artworkFraction = 0.76;
  static const double artworkMaxWidth = 430.0;
  static const double artworkMinSize = 150.0;
  static const double artworkRadius = 24.0;

  /// Horizontal page padding.
  static const double pagePadding = 20.0;
  static const double metadataGap = 14.0;

  // Typography (title > artist > metadata).
  static const double titleSize = 28.0;
  static const double artistSize = 17.0;
  static const double metaSize = 14.0;
  static const double reasonSize = 13.0;

  /// Deck chrome.
  static const double headerHeight = 58.0;
  static const double prevPeekHeight = 46.0;
  static const double nextPeekHeight = 64.0;
  static const double gapAfterArtwork = 18.0;
  static const double railHeight = 56.0;
  static const double contentMaxWidth = 560.0;
  static const double progressHeight = 2.0;
  static const double controlSizeSmall = 42.0;

  /// Peek opacities (active always 1.0).
  static const double nextPeekOpacity = 0.8;
  static const double prevPeekOpacity = 0.45;

  /// Reason line only renders at/above this item confidence.
  static const double reasonConfidenceFloor = 0.35;

  /// Ambient background cross-fade (spec #32).
  static const Duration ambientTransition = Duration(milliseconds: 500);

  /// Blurred-artwork layer sigma.
  static const double blurSigma = 40.0;

  /// Blurred layer opacity (atmosphere strength).
  static const double backgroundStrength = 0.55;
  static const double scrimTop = 0.50;
  static const double scrimBottom = 0.85;

  /// Artwork glow shadow opacity.
  static const double artworkGlow = 0.25;

  /// CachedNetworkImage decode width for hero artwork.
  static const int artworkMemCacheWidth = 720;
}
