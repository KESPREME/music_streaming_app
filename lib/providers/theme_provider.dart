import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/glass/chrome_glass.dart';
import '../theme/app_font.dart';

/// Theme modes available in the app
enum AppThemeMode {
  glassmorphism,
  materialYou,
}

/// Provider for managing theme state and switching between themes
class ThemeProvider extends ChangeNotifier {
  static const String _themePreferenceKey = 'app_theme_mode';
  static const String _dynamicColorPreferenceKey = 'dynamic_color_enabled';
  static const String _amoledPreferenceKey = 'amoled_black_enabled';
  static const String _fontFamilyKey = 'font_family';
  static const String _fontWeightDeltaKey = 'font_weight_delta';
  static const String _glassRenderingKey = 'glass_rendering';

  AppThemeMode _currentTheme = AppThemeMode.glassmorphism; // Default to glassmorphism
  bool _isDynamicColorEnabled = true;
  bool _isAmoled = false;
  bool _isInitialized = false;
  GlassRendering _glassRendering = GlassRendering.auto;

  AppThemeMode get currentTheme => _currentTheme;
  bool get isDynamicColorEnabled => _isDynamicColorEnabled;

  /// Pure-black (AMOLED) backgrounds. Off by default: the backdrop follows the
  /// album art until the listener asks for black. See `AmoledTheme`.
  bool get isAmoled => _isAmoled;
  bool get isInitialized => _isInitialized;

  /// How the bottom chrome (tab bar, pills, mini player) is drawn. Auto picks
  /// frosted glass on pure black and refraction elsewhere; see [ChromeGlassSpec].
  GlassRendering get glassRendering => _glassRendering;

  /// The app typeface and weight step (see [AppFont]).
  String get fontFamily => AppFont.family;
  int get fontWeightDelta => AppFont.weightDelta;

  /// Check if current theme is glassmorphism
  bool get isGlassmorphism => _currentTheme == AppThemeMode.glassmorphism;

  /// Check if current theme is Material You
  bool get isMaterialYou => _currentTheme == AppThemeMode.materialYou;

  /// Initialize theme from saved preferences
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load theme preference
      final themeIndex = prefs.getInt(_themePreferenceKey);
      if (themeIndex != null && themeIndex < AppThemeMode.values.length) {
        _currentTheme = AppThemeMode.values[themeIndex];
      }

      // Load dynamic color preference
      _isDynamicColorEnabled = prefs.getBool(_dynamicColorPreferenceKey) ?? true;

      // Load pure-black preference
      _isAmoled = prefs.getBool(_amoledPreferenceKey) ?? false;

      _glassRendering =
          GlassRendering.parse(prefs.getString(_glassRenderingKey));

      // Font: a family that is no longer offered falls back to the default.
      AppFont.apply(
        family: prefs.getString(_fontFamilyKey) ?? AppFont.defaultFamily,
        weightDelta: prefs.getInt(_fontWeightDeltaKey) ?? 0,
      );

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing theme: $e');
      _isInitialized = true;
    }
  }

  /// Switch to a specific theme
  Future<void> switchTheme(AppThemeMode theme) async {
    if (_currentTheme == theme) return;

    _currentTheme = theme;
    notifyListeners();

    // Persist theme preference
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themePreferenceKey, theme.index);
    } catch (e) {
      debugPrint('Error saving theme preference: $e');
    }
  }

  /// Toggle between glassmorphism and Material You
  Future<void> toggleTheme() async {
    final newTheme = _currentTheme == AppThemeMode.glassmorphism
        ? AppThemeMode.materialYou
        : AppThemeMode.glassmorphism;
    await switchTheme(newTheme);
  }

  /// Enable or disable dynamic color
  Future<void> setDynamicColorEnabled(bool enabled) async {
    if (_isDynamicColorEnabled == enabled) return;

    _isDynamicColorEnabled = enabled;
    notifyListeners();

    // Persist dynamic color preference
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dynamicColorPreferenceKey, enabled);
    } catch (e) {
      debugPrint('Error saving dynamic color preference: $e');
    }
  }

  /// Turn pure-black (AMOLED) backgrounds on or off.
  ///
  /// The change is applied and announced first, then written: the switch the
  /// listener just flipped must not wait on a disk write to move. A failed write
  /// costs only next launch's starting value, never this session's.
  Future<void> setAmoled(bool enabled) async {
    if (_isAmoled == enabled) return;

    _isAmoled = enabled;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_amoledPreferenceKey, enabled);
    } catch (e) {
      debugPrint('Error saving pure black preference: $e');
    }
  }

  /// Chooses how the bottom chrome is drawn. Applied first, written after, like
  /// [setAmoled].
  Future<void> setGlassRendering(GlassRendering value) async {
    if (_glassRendering == value) return;
    _glassRendering = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_glassRenderingKey, value.name);
    } catch (e) {
      debugPrint('Error saving glass rendering preference: ');
    }
  }

  /// Switches the app typeface. The face is fetched first (once; the device
  /// keeps it), so nothing redraws in a fallback; returns false and changes
  /// nothing when it cannot be had.
  Future<bool> setFontFamily(String family, {Future<bool> Function(String family)? preload}) async {
    if (family == AppFont.family) return true;
    if (!AppFont.isKnown(family)) return false;
    final ok = await (preload ?? AppFont.preload)(family);
    if (!ok) return false;
    AppFont.apply(family: family);
    _afterFontChange();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fontFamilyKey, family);
    } catch (e) {
      debugPrint('Error saving font preference: $e');
    }
    return true;
  }

  /// Lighter (-1), default (0) or bolder (+1) text.
  Future<void> setFontWeightDelta(int delta) async {
    final d = delta.clamp(AppFont.minWeightDelta, AppFont.maxWeightDelta);
    if (d == AppFont.weightDelta) return;
    AppFont.apply(weightDelta: d);
    _afterFontChange();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_fontWeightDeltaKey, d);
    } catch (e) {
      debugPrint('Error saving text weight preference: $e');
    }
  }

  void _afterFontChange() {
    notifyListeners();
    // Styles built in build methods (AppFont.style) are re-read on rebuild;
    // rebuild every element in place so no screen keeps the old face.
    WidgetsBinding.instance.addPostFrameCallback((_) => AppFont.rebuildAll());
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Get theme name for display
  String getThemeName() {
    switch (_currentTheme) {
      case AppThemeMode.glassmorphism:
        return 'Glassmorphism';
      case AppThemeMode.materialYou:
        return 'Material You';
    }
  }

  /// Get theme description for display
  String getThemeDescription() {
    switch (_currentTheme) {
      case AppThemeMode.glassmorphism:
        return 'Premium glass effects (High GPU Usage)';
      case AppThemeMode.materialYou:
        return 'Clean Material Design (Battery Efficient)';
    }
  }
}


