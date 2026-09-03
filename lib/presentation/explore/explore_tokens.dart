/// Explore design tokens (spec #75). No magic numbers in widgets.
library;

/// Explore design tokens (spec #75). No magic numbers in widgets.
abstract class ExploreTokens {
  /// Artwork radius for rare rectangular uses (stream is circular).
  static const double artworkRadius = 24.0;

  /// Horizontal page padding.
  static const double pagePadding = 20.0;

  // Stream typography: pill title > artist; neighbors smaller.
  static const double titleSize = 20.0;
  static const double artistSize = 14.0;
  static const double neighborTitleSize = 15.0;
  static const double neighborArtistSize = 12.0;
  static const double farTitleSize = 13.0;
  static const double farArtistSize = 11.0;
  static const double playCapsuleLabelSize = 13.0;

  /// Stream chrome.
  static const double headerHeight = 56.0;
  static const double activeArtSize = 76.0;
  static const double neighborArtSize = 52.0;
  static const double farArtSize = 40.0;
  static const double activeRowHeight = 104.0;
  static const double neighborRowHeight = 76.0;
  static const double farRowHeight = 56.0;
  static const double slotDxFar = 56.0;
  static const double slotDxNear = 28.0;
  static const double railHeight = 48.0;
  static const double playCapsuleHeight = 44.0;
  static const double contentMaxWidth = 560.0;
  static const double controlSizeSmall = 36.0;

  /// Neighbor opacities (active always 1.0).
  static const double nearOpacity = 0.75;
  static const double farOpacity = 0.4;

  /// Reason gate (traces/future surfaces; no visible reason text).
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
