import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/dynamic_color_engine.dart';

/// Theme modes available in the app
enum AppThemeMode {
  glassmorphism,
  materialYou,
}

/// Provider for managing theme state and switching between themes
class ThemeProvider extends ChangeNotifier {
  static const String _themePreferenceKey = 'app_theme_mode';
  static const String _dynamicColorPreferenceKey = 'dynamic_color_enabled';

  AppThemeMode _currentTheme = AppThemeMode.glassmorphism; // Default to glassmorphism
  bool _isDynamicColorEnabled = true;
  ColorScheme? _dynamicColorScheme;
  bool _isInitialized = false;

  AppThemeMode get currentTheme => _currentTheme;
  bool get isDynamicColorEnabled => _isDynamicColorEnabled;
  ColorScheme? get dynamicColorScheme => _dynamicColorScheme;
  bool get isInitialized => _isInitialized;

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

  /// Update dynamic color scheme from album art
  Future<void> updateDynamicColorsFromImage(ImageProvider? image) async {
    if (!_isDynamicColorEnabled || image == null) return;
    
    try {
      final colorScheme = await DynamicColorEngine.extractColorsFromImage(image);
      if (colorScheme != null) {
        _dynamicColorScheme = colorScheme;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating dynamic colors: $e');
    }
  }

  /// Update dynamic color scheme directly
  void updateDynamicColorScheme(ColorScheme? colorScheme) {
    if (!_isDynamicColorEnabled) return;
    
    _dynamicColorScheme = colorScheme;
    notifyListeners();
  }

  /// Clear dynamic color scheme
  void clearDynamicColorScheme() {
    _dynamicColorScheme = null;
    notifyListeners();
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
