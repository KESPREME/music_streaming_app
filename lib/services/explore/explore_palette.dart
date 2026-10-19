import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:palette_generator/palette_generator.dart';

/// Tone-mapped ambient colors for one Explore item (spec #29–#31).
class ExplorePalette {
  const ExplorePalette({
    required this.background,
    required this.accent,
    required this.vibrant,
    required this.deep,
    required this.isBright,
  });

  /// Darkened dominant color — lightness clamped 0.08–0.16, saturation
  /// slightly reduced. Atmosphere, not RGB wallpaper.
  final Color background;
  final Color accent;

  /// Vivid tone → mesh blob 1. Dark tone → mesh blob 2 / base depth.
  final Color vibrant;
  final Color deep;

  /// Dominant luminance > 0.5 → glass surfaces darken themselves.
  final bool isBright;

  /// Neutral fallback (no artwork / decode failure) — near-black slate.
  static const ExplorePalette neutral = ExplorePalette(
    background: Color(0xFF101018),
    accent: Color(0xFF9E9EB8),
    vibrant: Color(0xFF6E6E96),
    deep: Color(0xFF08080F),
    isBright: false,
  );
}

/// Cached artwork → palette resolution (spec #87). One 100px decode per
/// artwork, keyed by item id; failures degrade to neutral, never throw.
class ExplorePaletteCache {
  ExplorePaletteCache._();

  static final Map<String, ExplorePalette> _cache = {};
  static final Map<String, Future<ExplorePalette>> _inFlight = {};
  static const int _cap = 30;

  @visibleForTesting
  static int decodeCount = 0;

  static ExplorePalette? cached(String itemId) => _cache[itemId];

  /// One resolve per card, however many ask while it runs. Read through the
  /// image disk cache at 100 px (the card already downloaded the artwork); it
  /// used to be a second download of the full image via `NetworkImage`.
  static Future<ExplorePalette> resolve(String itemId, String artworkUrl) {
    final hit = _cache[itemId];
    if (hit != null) return Future.value(hit);
    if (artworkUrl.isEmpty) return Future.value(_store(itemId, ExplorePalette.neutral));
    return _inFlight[itemId] ??= _resolve(itemId, artworkUrl).whenComplete(() => _inFlight.remove(itemId));
  }

  static Future<ExplorePalette> _resolve(String itemId, String artworkUrl) async {
    try {
      decodeCount++;
      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(CachedNetworkImageProvider(artworkUrl), width: 100, height: 100),
        size: const Size(100, 100),
        maximumColorCount: 15,
      );
      return _store(itemId, _toneMap(palette));
    } catch (_) {
      return _store(itemId, ExplorePalette.neutral);
    }
  }

  static ExplorePalette _store(String itemId, ExplorePalette palette) {
    if (_cache.length >= _cap) _cache.remove(_cache.keys.first);
    _cache[itemId] = palette;
    return palette;
  }

  @visibleForTesting
  static void clearForTest() {
    _cache.clear();
    _inFlight.clear();
  }

  static HSLColor _darken(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness(hsl.lightness.clamp(0.08, 0.16));
  }

  static ExplorePalette _toneMap(PaletteGenerator palette) {
    final dominant = palette.dominantColor?.color;
    if (dominant == null) return ExplorePalette.neutral;
    final vibrant = palette.vibrantColor?.color ??
        palette.lightVibrantColor?.color ??
        dominant;
    final hsl = HSLColor.fromColor(dominant);
    // Reduce saturation slightly for bright artwork so glass stays calm.
    final sat = hsl.lightness > 0.5 ? hsl.saturation * 0.7 : hsl.saturation;
    final background =
        _darken(dominant).withSaturation(sat.clamp(0.0, 0.7)).toColor();
    // Deep: darkest usable tone, banded to 0.03–0.08 lightness.
    final deepBase =
        palette.darkMutedColor?.color ?? palette.darkVibrantColor?.color ?? dominant;
    final deepBaseHsl = HSLColor.fromColor(deepBase);
    final deep = deepBaseHsl
        .withLightness(deepBaseHsl.lightness.clamp(0.03, 0.08))
        .toColor();
    final luminance = background.computeLuminance();
    return ExplorePalette(
      background: background,
      accent: vibrant,
      vibrant: vibrant,
      deep: deep,
      isBright: luminance > 0.18,
    );
  }
}
