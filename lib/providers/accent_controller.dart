import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Curated accent presets — the app's identity palette.
enum AccentPreset { peach, amber, rose, ice, mint, violet, custom }

/// Static color table for presets (usable without a controller instance).
class AccentColors {
  static const Color peach = Color(0xFFFFCBA4);
  static const Color amber = Color(0xFFFFC857);
  static const Color rose = Color(0xFFF8A0B8);
  static const Color ice = Color(0xFF9BD8FF);
  static const Color mint = Color(0xFF9FE7C0);
  static const Color violet = Color(0xFFC9B8FF);

  static Color of(AccentPreset preset) => switch (preset) {
        AccentPreset.peach => peach,
        AccentPreset.amber => amber,
        AccentPreset.rose => rose,
        AccentPreset.ice => ice,
        AccentPreset.mint => mint,
        AccentPreset.violet => violet,
        AccentPreset.custom => peach,
      };
}

/// Owns the app-wide accent color: a preset (peach by default) or a custom
/// hex, optionally overridden by the playing track's album-art color when
/// [isAlbumAdaptive] is on.
///
/// Rebuild discipline: [setAlbumAccent] is called at most once per track
/// change (caller debounces), so accent-driven rebuilds are rare by design.
class AccentController extends ChangeNotifier {
  static const String _presetKey = 'accent_preset';
  static const String _customHexKey = 'accent_custom_hex';
  static const String _adaptiveKey = 'accent_album_adaptive';

  static const Color peach = AccentColors.peach;

  AccentPreset _preset = AccentPreset.peach;
  Color _customColor = peach;
  bool _isAlbumAdaptive = false;
  Color? _albumAccent;
  bool _isInitialized = false;

  AccentPreset get preset => _preset;
  bool get isAlbumAdaptive => _isAlbumAdaptive;
  bool get isInitialized => _isInitialized;

  /// The effective accent: album color wins when adaptive is on and a
  /// color is available; otherwise the preset/custom color.
  Color get accent {
    if (_isAlbumAdaptive && _albumAccent != null) return _albumAccent!;
    return _preset == AccentPreset.custom ? _customColor : AccentColors.of(_preset);
  }

  /// Parse `RRGGBB`, `AARRGGBB`, or `#`-prefixed variants. Null on failure.
  static Color? tryParseHex(String hex) {
    var h = hex.trim().replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final value = int.tryParse(h, radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  static String _toHex(Color c) =>
      c.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0');

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final presetName = prefs.getString(_presetKey);
      if (presetName != null) {
        final parsed = AccentPreset.values
            .where((p) => p.name == presetName)
            .firstOrNull;
        if (parsed != null) _preset = parsed;
      }
      final hex = prefs.getString(_customHexKey);
      if (hex != null) {
        final parsed = tryParseHex(hex);
        if (parsed != null) _customColor = parsed;
      }
      _isAlbumAdaptive = prefs.getBool(_adaptiveKey) ?? false;
      _isInitialized = true;
      notifyListeners();
    } catch (_) {
      _isInitialized = true;
    }
  }

  Future<void> setPreset(AccentPreset preset) async {
    if (_preset == preset) return;
    _preset = preset;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetKey, preset.name);
  }

  Future<void> setCustomColor(Color color) async {
    _customColor = color;
    _preset = AccentPreset.custom;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetKey, AccentPreset.custom.name);
    await prefs.setString(_customHexKey, _toHex(color));
  }

  Future<void> setAlbumAdaptive(bool enabled) async {
    if (_isAlbumAdaptive == enabled) return;
    _isAlbumAdaptive = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adaptiveKey, enabled);
  }

  /// Feed the dominant album-art color here on track change (null when no
  /// art / extraction failed). Cheap: only notifies when the effective
  /// accent actually changes.
  void setAlbumAccent(Color? color) {
    final next = (color == null) ? null : color;
    if (_albumAccent == next) return;
    _albumAccent = next;
    if (_isAlbumAdaptive) notifyListeners();
  }
}
