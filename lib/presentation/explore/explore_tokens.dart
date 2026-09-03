/// Explore design tokens (spec #75). No magic numbers in widgets.
library;

/// Explore design tokens (spec #75). No magic numbers in widgets.
abstract class ExploreTokens {
  /// Artwork width = min(viewport width × fraction, maxWidth).
  static const double artworkFraction = 0.84;
  static const double artworkMaxWidth = 440.0;
  static const double artworkRadius = 24.0;

  /// Horizontal page padding.
  static const double pagePadding = 24.0;
  static const double metadataGap = 14.0;

  // Typography (spec #41): title > artist > metadata.
  static const double titleSize = 28.0;
  static const double artistSize = 17.0;
  static const double metaSize = 14.0;

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
