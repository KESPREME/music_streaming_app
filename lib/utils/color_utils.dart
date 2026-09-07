import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class ColorUtils {
  /// Adjusts a color's HSL values to boost vibrancy and ensure visual harmony.
  static Color? boostColor(Color? color, {double hueShift = 0, double saturation = 0, double lightness = 0}) {
    if (color == null) return null;
    final hsl = HSLColor.fromColor(color);
    
    final newHue = (hsl.hue + hueShift) % 360;
    final newSat = (hsl.saturation + saturation).clamp(0.0, 1.0);
    final newLight = (hsl.lightness + lightness).clamp(0.0, 1.0);
    
    return hsl.withHue(newHue).withSaturation(newSat).withLightness(newLight).toColor();
  }

  /// Calculates a middle transition color for a background gradient based on a palette.
  static Color middleColorForPalette(PaletteGenerator? palette) {
    if (palette == null) return const Color(0xFF020617);
    
    final darkMuted = palette.darkMutedColor?.color;
    final muted = palette.mutedColor?.color;
    final dominant = palette.dominantColor?.color;

    return darkMuted?.withValues(alpha: 0.5) ?? 
           muted?.withValues(alpha: 0.3) ?? 
           dominant?.withValues(alpha: 0.2) ?? 
           const Color(0xFF020617);
  }

  /// Returns a list of background colors [top, middle, bottom] for a liquid UI.
  static List<Color> getLiquidBgColors(PaletteGenerator? palette) {
    if (palette == null) {
      return [
        const Color(0xFF0F172A), // Slate 900
        const Color(0xFF020617), // Slate 950
        const Color(0xFF000000), // Black
      ];
    }

    final darkVibrant = boostColor(palette.darkVibrantColor?.color, saturation: 0.1, lightness: -0.05);
    final darkMuted = boostColor(palette.darkMutedColor?.color, lightness: -0.1);
    final dominant = palette.dominantColor?.color;

    final topColor = darkVibrant?.withValues(alpha: 0.8) ?? 
                     darkMuted?.withValues(alpha: 0.8) ?? 
                     dominant?.withValues(alpha: 0.6) ?? 
                     const Color(0xFF0F172A);

    return [
      topColor,
      middleColorForPalette(palette),
      const Color(0xFF000000),
    ];
  }

  /// Returns a vibrant accent color derived from a palette.
  static Color getVibrantAccent(PaletteGenerator? palette, [Color defaultColor = const Color(0xFFE94560)]) {
    if (palette == null) return defaultColor;
    
    final vibrant = boostColor(palette.vibrantColor?.color, saturation: 0.2);
    final dominant = palette.dominantColor?.color;
    
    return vibrant ?? boostColor(dominant, saturation: 0.3) ?? defaultColor;
  }

  /// Returns deep background wash color for BitChord artwork backdrops
  static Color getBackgroundWash(PaletteGenerator? palette, [Color defaultColor = const Color(0xFF0D0B14)]) {
    if (palette == null) return defaultColor;
    return palette.darkMutedColor?.color ?? palette.darkVibrantColor?.color ?? defaultColor;
  }

  /// Returns dominant wash tint for BitChord ambient radial gradients
  static Color getDominantWash(PaletteGenerator? palette, [Color defaultColor = const Color(0xFFE94560)]) {
    if (palette == null) return defaultColor;
    return palette.dominantColor?.color ?? palette.vibrantColor?.color ?? defaultColor;
  }
}

