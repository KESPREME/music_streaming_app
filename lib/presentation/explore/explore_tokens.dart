/// Explore design tokens. No magic numbers in widgets.
library;

/// Explore design tokens. No magic numbers in widgets.
abstract class ExploreTokens {
  /// Horizontal page padding.
  static const double pagePadding = 20.0;

  // Rotary typography: row title > artist.
  static const double titleSize = 17.0;
  static const double artistSize = 13.0;

  /// Rotary chrome.
  static const double headerHeight = 56.0;
  static const double contentMaxWidth = 560.0;

  /// Reason gate (traces/future surfaces; no visible reason text).
  static const double reasonConfidenceFloor = 0.35;

  /// Rotary wheel geometry. Arc: center-rightmost, edges curve left.
  static const double wheelMinExtent = 96.0;
  static const double wheelMaxExtent = 128.0;
  static const double wheelVisibleRows = 5.0;
  static const double arcA = 32.0;
  static const double textFadeStart = 0.35;
  static const double glassFadeStart = 0.5;
  static const double vinylSize = 56.0;
  static const Duration spinDuration = Duration(seconds: 6);
  static const Duration snapDebounce = Duration(milliseconds: 180);
  static const Duration meshTransition = Duration(milliseconds: 600);
  static const Duration eqLoop = Duration(milliseconds: 700);

  /// Liquid pill geometry + light.
  static const double pillHeight = 80.0;
  static const double pillMarginH = 12.0;
  static const double pillRadius = 40.0;
  static const double pillFillAlpha = 0.08;
  static const double pillBorderTop = 0.5;
  static const double pillBorderBottom = 0.04;
  static const double pillBlurSigma = 12.0;
  static const double pillDiscSize = 72.0;
  static const double pillDiscOverlap = 14.0;

  /// Vinyl detail.
  static const double spindleSize = 14.0;
  static const int grooveCount = 5;

  /// Floating tab bar.
  static const double tabBarWidth = 230.0;
  static const double tabBarHeight = 58.0;

  /// Mesh glow blur.
  static const double glowBlurSigma = 30.0;

  /// Mesh scrim floor.
  static const double scrimBottom = 0.85;

  /// Vinyl glow shadow opacity.
  static const double artworkGlow = 0.25;
}
