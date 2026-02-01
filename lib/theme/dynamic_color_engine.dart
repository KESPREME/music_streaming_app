import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'dart:collection';

/// Engine for generating dynamic colors from album art
/// Works with both glassmorphism and Material You themes
class DynamicColorEngine {
  // LRU cache for color palettes
  static final _cache = LinkedHashMap<String, ColorScheme>();
  static const int _maxCacheSize = 50;

  /// Extract colors from image and generate Material 3 color scheme
  static Future<ColorScheme?> extractColorsFromImage(
    ImageProvider image, {
    Brightness brightness = Brightness.dark,
  }) async {
    try {
      // Generate cache key from image
      final cacheKey = image.toString();
      
      // Check cache first
      if (_cache.containsKey(cacheKey)) {
        return _cache[cacheKey];
      }

      // Extract palette from image
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        image,
        maximumColorCount: 16,
      );

      // Get vibrant color as seed
      Color seedColor = paletteGenerator.vibrantColor?.color ??
          paletteGenerator.dominantColor?.color ??
          const Color(0xFFFF1744); // Fallback to app accent

      // Generate Monet palette
      final colorScheme = generateMonetPalette(seedColor, brightness: brightness);

      // Cache the result
      _addToCache(cacheKey, colorScheme);

      return colorScheme;
    } catch (e) {
      debugPrint('Error extracting colors from image: $e');
      return null;
    }
  }

  /// Generate Monet palette from seed color
  static ColorScheme generateMonetPalette(
    Color seedColor, {
    Brightness brightness = Brightness.dark,
  }) {
    return ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
  }

  /// Harmonize colors for better visual consistency
  static ColorScheme harmonizeColors(ColorScheme base, Color accent) {
    // Use the accent color to generate a harmonized scheme
    return ColorScheme.fromSeed(
      seedColor: accent,
      brightness: base.brightness,
    );
  }

  /// Check if color scheme meets WCAG contrast requirements
  static bool meetsContrastRequirements(
    Color foreground,
    Color background, {
    double requiredRatio = 4.5, // WCAG AA for normal text
  }) {
    final ratio = _calculateContrastRatio(foreground, background);
    return ratio >= requiredRatio;
  }

  /// Calculate contrast ratio between two colors
  static double _calculateContrastRatio(Color color1, Color color2) {
    final luminance1 = color1.computeLuminance();
    final luminance2 = color2.computeLuminance();
    
    final lighter = luminance1 > luminance2 ? luminance1 : luminance2;
    final darker = luminance1 > luminance2 ? luminance2 : luminance1;
    
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Adjust color to meet contrast requirements
  static Color adjustForContrast(
    Color foreground,
    Color background, {
    double requiredRatio = 4.5,
  }) {
    if (meetsContrastRequirements(foreground, background, requiredRatio: requiredRatio)) {
      return foreground;
    }

    // Adjust luminance to meet contrast requirements
    final backgroundLuminance = background.computeLuminance();
    final targetLuminance = backgroundLuminance > 0.5
        ? (backgroundLuminance - 0.05) / requiredRatio - 0.05
        : (backgroundLuminance + 0.05) * requiredRatio - 0.05;

    return Color.lerp(
      foreground,
      targetLuminance > 0.5 ? Colors.white : Colors.black,
      0.5,
    )!;
  }

  /// Get fallback color scheme when no album art is available
  static ColorScheme getFallbackColorScheme({
    Brightness brightness = Brightness.dark,
  }) {
    return ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF1744), // App accent color
      brightness: brightness,
    );
  }

  /// Add color scheme to cache with LRU eviction
  static void _addToCache(String key, ColorScheme colorScheme) {
    if (_cache.length >= _maxCacheSize) {
      // Remove oldest entry
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = colorScheme;
  }

  /// Clear the color cache
  static void clearCache() {
    _cache.clear();
  }

  /// Get cache size
  static int getCacheSize() {
    return _cache.length;
  }
}
