import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import 'material_you_tokens.dart';
import 'glassmorphism_tokens.dart';

/// Manages design tokens for both themes
class DesignTokenManager {
  /// Get tokens for the current theme
  static Map<String, dynamic> getTokensForTheme(
    AppThemeMode theme,
    ColorScheme? dynamicColorScheme,
  ) {
    switch (theme) {
      case AppThemeMode.glassmorphism:
        return GlassmorphismTokens.tokens;
      case AppThemeMode.materialYou:
        final colorScheme = dynamicColorScheme ?? 
            MaterialYouTokens.getDefaultDarkColorScheme();
        return MaterialYouTokens.generateTokens(colorScheme);
    }
  }

  /// Get color from tokens by path (e.g., 'surface.primary')
  static Color? getColor(Map<String, dynamic> tokens, String path) {
    final parts = path.split('.');
    dynamic current = tokens;
    
    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    
    return current is Color ? current : null;
  }

  /// Get double value from tokens by path (e.g., 'borderRadius.medium')
  static double? getDouble(Map<String, dynamic> tokens, String path) {
    final parts = path.split('.');
    dynamic current = tokens;
    
    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    
    return current is double ? current : null;
  }

  /// Get duration from tokens by path (e.g., 'durations.medium')
  static Duration? getDuration(Map<String, dynamic> tokens, String path) {
    final parts = path.split('.');
    dynamic current = tokens;
    
    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    
    return current is Duration ? current : null;
  }

  /// Get curve from tokens by path (e.g., 'curves.standard')
  static Curve? getCurve(Map<String, dynamic> tokens, String path) {
    final parts = path.split('.');
    dynamic current = tokens;
    
    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    
    return current is Curve ? current : null;
  }
}
