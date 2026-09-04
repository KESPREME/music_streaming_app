/// Explore design tokens. No magic numbers in widgets.
library;

/// Explore design tokens. No magic numbers in widgets.
abstract class ExploreTokens {
  /// Horizontal page padding.
  static const double pagePadding = 20.0;

  // Rotary typography: row title > artist.
  static const double titleSize = 20.0;
  static const double artistSize = 14.0;

  /// Rotary chrome.
  static const double headerHeight = 56.0;
  static const double railHeight = 48.0;
  static const double contentMaxWidth = 560.0;
  static const double controlSizeSmall = 36.0;

  /// Reason gate (traces/future surfaces; no visible reason text).
  static const double reasonConfidenceFloor = 0.35;

  /// Rotary wheel geometry.
  static const double wheelMinExtent = 96.0;
  static const double wheelMaxExtent = 128.0;
  static const double wheelVisibleRows = 5.0;
  static const double arcK = 72.0;
  static const double arcThetaMax = 1.2;
  static const double scaleMin = 0.65;
  static const double opacityMin = 0.2;
  static const double textFadeStart = 0.35;
  static const double glassFadeStart = 0.5;
  static const double vinylSize = 56.0;
  static const double vinylHoleSize = 16.0;
  static const Duration spinDuration = Duration(seconds: 9);
  static const Duration snapDebounce = Duration(milliseconds: 180);
  static const Duration meshTransition = Duration(milliseconds: 600);
  static const Duration eqLoop = Duration(milliseconds: 700);

  /// Mesh scrim floor.
  static const double scrimBottom = 0.85;

  /// Vinyl glow shadow opacity.
  static const double artworkGlow = 0.25;
}
