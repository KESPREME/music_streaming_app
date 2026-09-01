import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../tokens/space.dart' show Radii;

/// GPU effect budget tiers. Only interaction surfaces earn shader glass;
/// dense/scrolling content stays grounded or subtle (§15/§229).
///
///  card      → subtle   : frosted panels in lists — cheap path, no lens shader
///  chrome    → standard : segmented controls, filter clusters
///  floating  → standard : navigation bar, mini-player
///  sheet     → rich     : sheets, menus, major transient surfaces
///  rich      → rich     : hero interaction surfaces (player play button)
///  none      → none     : fully grounded content, zero glass
enum GlassTier { none, card, chrome, floating, sheet, rich }

/// Semantic glass materials. Each surface role gets its own optical identity —
/// never one generic glass for everything (§12/§190).
///
/// Optical parameters live here as tokens (§179). Screens consume
/// [GlassMaterials.forTier] via [GlassSurface], never raw lens configs.
abstract final class GlassMaterials {
  // --- Shared optical constants ---------------------------------------------

  /// Ambient lighting direction (degrees). One consistent light source
  /// across all surfaces (§186): upper-left.
  static const double lightDirection = 135;

  /// Tint: barely-there smoked white over dark content. Glass stays quiet —
  /// music/content leads, material supports (§4).
  static const Color _tintDark = Color(0x14FFFFFF);

  /// Slightly denser fill for selected/pressed states.
  static const Color _tintSelected = Color(0x22FFFFFF);

  static const Color _tintSheet = Color(0x1FFFFFFF);

  // --- Material recipes ------------------------------------------------------

  /// LiquidGlassStyle for a tier. [accent] appears only as a restrained
  /// edge-light contribution on selected controls — never as tinted glass.
  static LiquidGlassStyle forTier(GlassTier tier, {Color? accent}) {
    switch (tier) {
      case GlassTier.none:
        // Should never be rendered as glass; GlassSurface short-circuits.
        return forTier(GlassTier.chrome, accent: accent);

      case GlassTier.card:
      case GlassTier.chrome:
        return LiquidGlassStyle(
          shape: _shape(borderRadius: 20, borderWidth: 1.0, lightIntensity: 0.9),
          appearance: const LiquidGlassAppearance(
            color: _tintDark,
            blur: LiquidGlassBlur(sigmaX: 7, sigmaY: 7),
            saturation: 1.05,
          ),
          refraction: const LiquidGlassRefraction(
            distortion: 0.06,
            distortionWidth: 22,
            magnification: 1.0,
            chromaticAberration: 0.0015,
          ),
        );

      case GlassTier.floating:
        return LiquidGlassStyle(
          shape: _shape(borderRadius: 28, borderWidth: 1.2, lightIntensity: 1.1),
          appearance: const LiquidGlassAppearance(
            color: _tintDark,
            blur: LiquidGlassBlur(sigmaX: 10, sigmaY: 10),
            saturation: 1.1,
          ),
          refraction: const LiquidGlassRefraction(
            distortion: 0.09,
            distortionWidth: 26,
            magnification: 1.02,
            chromaticAberration: 0.002,
          ),
        );

      case GlassTier.sheet:
        return LiquidGlassStyle(
          shape: _shape(borderRadius: 28, borderWidth: 1.4, lightIntensity: 1.25),
          appearance: const LiquidGlassAppearance(
            color: _tintSheet,
            blur: LiquidGlassBlur(sigmaX: 14, sigmaY: 14),
            saturation: 1.15,
          ),
          refraction: const LiquidGlassRefraction(
            distortion: 0.11,
            distortionWidth: 30,
            magnification: 1.02,
            chromaticAberration: 0.0025,
          ),
        );

      case GlassTier.rich:
        return LiquidGlassStyle(
          shape: _shape(borderRadius: 999, borderWidth: 1.6, lightIntensity: 1.5),
          appearance: const LiquidGlassAppearance(
            color: _tintSelected,
            blur: LiquidGlassBlur(sigmaX: 9, sigmaY: 9),
            saturation: 1.2,
          ),
          refraction: const LiquidGlassRefraction(
            distortion: 0.14,
            distortionWidth: 34,
            magnification: 1.05,
            chromaticAberration: 0.003,
          ),
        );
    }
  }

  /// Selected-state material (§21): denser fill, more distortion, stronger
  /// edge light. Feels like a small liquid displacement, not a pink pill.
  static LiquidGlassStyle selected({
    double borderRadius = 20,
    Color? accent,
  }) {
    return LiquidGlassStyle(
      shape: _shape(
        borderRadius: borderRadius,
        borderWidth: 1.8,
        lightIntensity: 1.7,
        lightColor: accent ?? const Color(0x66FFFFFF),
      ),
      appearance: const LiquidGlassAppearance(
        color: _tintSelected,
        blur: LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
        saturation: 1.2,
      ),
      refraction: const LiquidGlassRefraction(
        distortion: 0.13,
        distortionWidth: 30,
        magnification: 1.04,
        chromaticAberration: 0.0028,
      ),
    );
  }

  // --- Shape helper ----------------------------------------------------------

  static LiquidGlassShape _shape({
    required double borderRadius,
    required double borderWidth,
    required double lightIntensity,
    Color? lightColor,
  }) {
    final isPill = borderRadius >= Radii.pill;
    return LiquidGlassShape.continuousRoundedRectangle(
      cornerRadius: isPill ? 999 : borderRadius,
      borderWidth: borderWidth,
      lightColor: lightColor ?? const Color(0x40FFFFFF),
      lightIntensity: lightIntensity,
      lightDirection: lightDirection,
      borderType: const OpticalBorder(
        borderSaturation: 1.0,
        ambientIntensity: 0.9,
        borderSolidity: 0.0,
      ),
    );
  }
}
