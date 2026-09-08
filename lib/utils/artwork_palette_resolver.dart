import 'dart:collection';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// The finished color set an album, playlist or artist screen paints itself in.
/// Direct Flutter parity with BitChord's \ArtworkPalette.kt\.
@immutable
class ArtworkPalette {
  /// The page's background wash.
  final Color background;

  /// The colour the artwork's own bottom edge blurs down to.
  final Color wash;

  /// Fill for the glass buttons and chips that sit on [background].
  final Color elevated;

  /// The artwork's own colour, contrast-corrected — titles, icons, Play button.
  final Color accent;

  final Color onBackground;
  final Color onBackgroundVariant;
  final Color divider;

  const ArtworkPalette({
    required this.background,
    required this.wash,
    required this.elevated,
    required this.accent,
    required this.onBackground,
    required this.onBackgroundVariant,
    required this.divider,
  });

  /// BitChord default dark fallback palette when no artwork is loaded yet.
  static const ArtworkPalette defaultDark = ArtworkPalette(
    background: Color(0xFF0A080C),
    wash: Color(0xFF131018),
    elevated: Color(0xFF1D1824),
    accent: Color(0xFFFF5252),
    onBackground: Colors.white,
    onBackgroundVariant: Color(0xCCFFFFFF),
    divider: Color(0x1FFFFFFF),
  );
}

/// Helper that adjusts HSL values, matching BitChord's \withHsl\ in ArtworkPalette.kt.
Color _withHsl(
  Color color, {
  double Function(double)? saturation,
  double Function(double)? lightness,
}) {
  final hsl = HSLColor.fromColor(color);
  final newSat = saturation != null
      ? saturation(hsl.saturation).clamp(0.0, 1.0)
      : hsl.saturation;
  final newLight = lightness != null
      ? lightness(hsl.lightness).clamp(0.0, 1.0)
      : hsl.lightness;
  return hsl.withSaturation(newSat).withLightness(newLight).toColor();
}

/// Extracts and caches BitChord [ArtworkPalette] instances from artwork URLs.
class ArtworkPaletteResolver {
  static const int _kMaxCacheEntries = 128;
  static final LinkedHashMap<String, ArtworkPalette> _cache = LinkedHashMap();

  /// Synchronously returns cached palette if previously extracted.
  static ArtworkPalette? getCached(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    return _cache[imageUrl];
  }

  /// Manually seeds the cache (e.g. for testing or pre-warmed art).
  static void putCached(String imageUrl, ArtworkPalette palette) {
    _cache[imageUrl] = palette;
  }

  /// Extracts [ArtworkPalette] from [imageUrl] asynchronously.
  /// If cached, returns immediately.
  static Future<ArtworkPalette> resolve(
    String? imageUrl, {
    bool dark = true,
  }) async {
    if (imageUrl == null || imageUrl.isEmpty) {
      return ArtworkPalette.defaultDark;
    }

    final cached = _cache[imageUrl];
    if (cached != null) return cached;

    try {
      final imageProvider = CachedNetworkImageProvider(imageUrl);
      final paletteGen = await PaletteGenerator.fromImageProvider(
        imageProvider,
        size: const Size(128, 128),
        maximumColorCount: 24,
      ).timeout(const Duration(seconds: 4));

      final colors = paletteGen.paletteColors;
      if (colors.isEmpty) {
        return ArtworkPalette.defaultDark;
      }

      // 1. Dominant: Swatch with maximum population
      var dominantSwatch = colors.first;
      for (final swatch in colors) {
        if (swatch.population > dominantSwatch.population) {
          dominantSwatch = swatch;
        }
      }

      // 2. Vibrant: Score saturation against sqrt(population)
      // BitChord: hsl[1] * sqrt(swatch.population.toFloat())
      var vibrantSwatch = colors.first;
      var maxVibrantScore = -1.0;
      for (final swatch in colors) {
        final hsl = HSLColor.fromColor(swatch.color);
        final score = hsl.saturation * sqrt(swatch.population);
        if (score > maxVibrantScore) {
          maxVibrantScore = score;
          vibrantSwatch = swatch;
        }
      }

      // 3. Edge color: fallback to darkMuted or dominant
      final edgeColor = paletteGen.darkMutedColor?.color ??
          paletteGen.darkVibrantColor?.color ??
          dominantSwatch.color;

      final dominantColor = dominantSwatch.color;
      final vibrantColor = vibrantSwatch.color;

      final palette = fromColors(
        dominantColor,
        vibrantColor: vibrantColor,
        edgeColor: edgeColor,
        dark: dark,
      );

      _cache[imageUrl] = palette;
      if (_cache.length > _kMaxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      return palette;
    } catch (_) {
      return ArtworkPalette.defaultDark;
    }
  }

  /// Generates an [ArtworkPalette] directly from dominant, vibrant, and edge colors.
  static ArtworkPalette fromColors(
    Color dominantColor, {
    Color? vibrantColor,
    Color? edgeColor,
    bool dark = true,
  }) {
    final effectiveVibrant = vibrantColor ?? dominantColor;
    final effectiveEdge = edgeColor ?? dominantColor;
    return dark
        ? ArtworkPalette(
            background: _withHsl(
              dominantColor,
              saturation: (s) => s.clamp(0.20, 0.62),
              lightness: (_) => 0.13,
            ),
            wash: _withHsl(
              effectiveEdge,
              saturation: (s) => s.clamp(0.18, 0.58),
              lightness: (l) => l.clamp(0.14, 0.24),
            ),
            elevated: _withHsl(
              dominantColor,
              saturation: (s) => s.clamp(0.20, 0.62),
              lightness: (_) => 0.22,
            ),
            accent: _withHsl(
              effectiveVibrant,
              saturation: (s) => s.clamp(0.55, 1.0),
              lightness: (l) => l.clamp(0.62, 0.78),
            ),
            onBackground: Colors.white,
            onBackgroundVariant: Colors.white.withValues(alpha: 0.80),
            divider: Colors.white.withValues(alpha: 0.12),
          )
        : ArtworkPalette(
            background: _withHsl(
              dominantColor,
              saturation: (s) => s.clamp(0.14, 0.50),
              lightness: (_) => 0.91,
            ),
            wash: _withHsl(
              effectiveEdge,
              saturation: (s) => s.clamp(0.12, 0.46),
              lightness: (l) => l.clamp(0.78, 0.90),
            ),
            elevated: _withHsl(
              dominantColor,
              saturation: (s) => s.clamp(0.14, 0.50),
              lightness: (_) => 0.83,
            ),
            accent: _withHsl(
              effectiveVibrant,
              saturation: (s) => s.clamp(0.55, 1.0),
              lightness: (l) => l.clamp(0.30, 0.44),
            ),
            onBackground: Colors.black,
            onBackgroundVariant: Colors.black.withValues(alpha: 0.70),
            divider: Colors.black.withValues(alpha: 0.10),
          );
  }
}
