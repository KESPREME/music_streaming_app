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

  /// Rotary wheel geometry. Arc: center-leftmost, edges curve right.
  static const double wheelMinExtent = 96.0;
  static const double wheelMaxExtent = 128.0;
  static const double wheelVisibleRows = 5.0;
  static const double arcA = 76.0;
  static const double arcMaxAngle = 0.24; // ~13.8 degrees
  static const double textFadeStart = 0.30;
  static const double glassFadeStart = 0.5;
  static const double vinylSize = 64.0;
  static const Duration spinDuration = Duration(seconds: 8);
  static const Duration snapDebounce = Duration(milliseconds: 120);
  static const Duration meshTransition = Duration(milliseconds: 800);
  static const Duration eqLoop = Duration(milliseconds: 700);

  /// Liquid pill geometry + light.
  static const double pillHeight = 80.0;
  static const double pillMarginH = 20.0;
  static const double pillRadius = 40.0;
  static const double pillFillAlpha = 0.88;
  static const double pillBorderTop = 0.95;
  static const double pillBorderBottom = 0.30;
  static const double pillBlurSigma = 24.0;
  static const double pillDiscSize = 76.0;
  static const double pillDiscOverlap = 16.0;

  /// Vinyl detail.
  static const double spindleSize = 14.0;
  static const int grooveCount = 5;

  /// Floating tab bar.
  static const double tabBarWidth = 220.0;
  static const double tabBarHeight = 56.0;

  /// Mesh glow blur.
  static const double glowBlurSigma = 60.0;

  /// Mesh scrim floor.
  static const double scrimBottom = 0.85;

  /// Vinyl glow shadow opacity.
  static const double artworkGlow = 0.20;
}
