import 'package:flutter/material.dart';

/// Centralized liquid-glass material tokens.
///
/// Single source of truth for blur, thickness, depth, borders, radii,
/// opacity and shadow. Screens import this instead of hardcoding.
///
/// Philosophy: dark premium physical glass — near-black / charcoal / smoked
/// graphite, soft white, restrained accent. No neon.
abstract class GlassTokens {
  GlassTokens._();

  // -----------------------------------------------------------------
  // Blur (frost) — logical pixels
  // -----------------------------------------------------------------
  static const double blurCard = 9.0;
  static const double blurChrome = 14.0;
  static const double blurFloating = 16.0;
  static const double blurSheet = 18.0;

  // -----------------------------------------------------------------
  // Thickness / depth
  // -----------------------------------------------------------------
  static const double thicknessCard = 9.0;
  static const double thicknessChrome = 17.0;
  static const double thicknessFloating = 19.0;
  static const double thicknessSheet = 20.0;

  // -----------------------------------------------------------------
  // Refraction (optical interaction — visible distortion, not just blur)
  // -----------------------------------------------------------------
  static const double refractiveCard = 1.12;
  static const double refractiveChrome = 1.18;
  static const double refractiveFloating = 1.20;

  // -----------------------------------------------------------------
  // Light & edge physics (premium depth)
  // -----------------------------------------------------------------
  static const double lightChrome = 0.42;
  static const double lightCard = 0.30;
  static const double fresnelChrome = 0.9;
  static const double fresnelCard = 0.65;
  static const double edgeAbsorptionChrome = 0.10;
  static const double edgeAbsorptionCard = 0.06;
  static const double chromaticCard = 0.006;
  static const double chromaticChrome = 0.008;

  // -----------------------------------------------------------------
  // Radii — restrained, not everything is 24
  // -----------------------------------------------------------------
  static const double radiusNav = 32.0;
  static const double radiusSheet = 28.0;
  static const double radiusCard = 20.0;
  static const double radiusChip = 20.0;
  static const double radiusButton = 30.0;
  static const double radiusSmall = 14.0;

  // -----------------------------------------------------------------
  // Opacity bands — 5 material layers
  //  1 grounded (no glass)  2 elevated (list bg)  3 interactive  4 floating  5 transient
  // -----------------------------------------------------------------
  static const double opacityElevated = 0.04;
  static const double opacityInteractive = 0.07;
  static const double opacityFloating = 0.09;
  static const double opacityTransient = 0.14;

  // -----------------------------------------------------------------
  // Player controls and glass defaults
  // -----------------------------------------------------------------
  static const double playerBackdropBlur = 24.0;
  static const double playerScrimOpacity = 0.68;
  static const double playerPillHeight = 64.0;
  static const double playerControlSize = 48.0;
  static const double playerPrimaryControlSize = 64.0;
  static const double playerControlFillOpacity = 0.14;
  static const double playerProgressGlowAlpha = 0.0;
  static const double glassGlowIntensity = 0.0;
  static const double glassSaturation = 1.12;

  // Glass tint itself (white overlay) — keep glass, not colored panel
  static Color glassTint(Color accent) => Colors.white.withValues(alpha: 0.06);

  // Border strengths
  static Color borderCard = Colors.white.withValues(alpha: 0.09);
  static Color borderChrome = Colors.white.withValues(alpha: 0.13);
  static Color borderFloating = Colors.white.withValues(alpha: 0.14);
  static Color borderInteractiveSelected(Color accent) =>
      accent.withValues(alpha: 0.28);
  static Color iconAccent(Color accent) => accent;

  // Shadows — subtle optical depth, not large halos
  static BoxShadow shadowFloating(Color accent) => BoxShadow(
        color: Colors.black.withValues(alpha: 0.38),
        blurRadius: 22,
        spreadRadius: -4,
        offset: const Offset(0, 8),
      );
  static BoxShadow shadowCard = BoxShadow(
    color: Colors.black.withValues(alpha: 0.22),
    blurRadius: 14,
    offset: const Offset(0, 4),
  );

  // -----------------------------------------------------------------
  // Ink diffusion — localized accent bloom (drop of ink in water)
  // -----------------------------------------------------------------
  static RadialGradient inkBloom(Color accent, {double strength = 0.22}) =>
      RadialGradient(
        center: const Alignment(0.0, 0.0),
        radius: 1.35,
        colors: [
          accent.withValues(alpha: strength),
          accent.withValues(alpha: strength * 0.32),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      );

  // -----------------------------------------------------------------
  // Typography & spacing tokens (optical, not rigid 8-grid)
  // -----------------------------------------------------------------
  static const double hMargin = 20.0;
  static const double vSectionGap = 28.0;
  static const double vCardGap = 14.0;
  static const double navBottomInset = 12.0;
  static const double playerBottomInset = 78.0;
}
