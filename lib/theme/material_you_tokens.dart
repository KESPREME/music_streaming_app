import 'package:flutter/material.dart';

/// Material You (Material 3) design tokens
/// NO gradients, NO blur effects - flat, solid colors only
/// UPDATED: Vibrant, bold colors for Google Pixel aesthetic
class MaterialYouTokens {
  // Light Blue Accent Theme (replacing purple)
  static const Color primaryVibrant = Color(0xFF00B4D8); // Light blue
  static const Color secondaryVibrant = Color(0xFF0096C7); // Medium blue
  static const Color tertiaryVibrant = Color(0xFF0077B6); // Deep blue
  
  // Surface colors (deep black theme)
  static const Color surfaceDark = Color(0xFF000000); // Pure black
  static const Color surfaceVariantDark = Color(0xFF0A0A0A); // Very dark grey
  static const Color surfaceContainerDark = Color(0xFF121212); // Dark grey
  static const Color surfaceContainerHighestDark = Color(0xFF1A1A1A); // Lighter dark grey
  
  // Additional accent colors
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color accentTeal = Color(0xFF1DE9B6);
  static const Color accentOrange = Color(0xFFFF9100);
  static const Color accentGreen = Color(0xFF00E676);
  static const Color accentLightBlue = Color(0xFF00B4D8); // Replaced purple with light blue
  
  // Shape constants (border radius)
  static const double shapeSmall = 8.0;
  static const double shapeMedium = 16.0;
  static const double shapeLarge = 24.0;
  static const double shapeExtraLarge = 28.0;
  static const double shapeFull = 9999.0; // Fully rounded
  
  // Elevation shadows (no blur - proper Material 3 shadows)
  static const BoxShadow elevation1 = BoxShadow(
    color: Color(0x33000000),
    blurRadius: 4,
    offset: Offset(0, 2),
  );
  static const BoxShadow elevation2 = BoxShadow(
    color: Color(0x4D000000),
    blurRadius: 8,
    offset: Offset(0, 4),
  );
  static const BoxShadow elevation3 = BoxShadow(
    color: Color(0x66000000),
    blurRadius: 12,
    offset: Offset(0, 6),
  );
  static const BoxShadow elevation4 = BoxShadow(
    color: Color(0x80000000),
    blurRadius: 16,
    offset: Offset(0, 8),
  );
  static const BoxShadow elevation5 = BoxShadow(
    color: Color(0x99000000),
    blurRadius: 20,
    offset: Offset(0, 10),
  );

  /// Generate Material You tokens from a color scheme
  static Map<String, dynamic> generateTokens(ColorScheme colorScheme) {
    return {
      // Material 3 Color Roles (Flat, Solid Colors)
      'surface': {
        'primary': colorScheme.surface,
        'secondary': colorScheme.surfaceVariant,
        'tertiary': colorScheme.surfaceContainerHighest ?? colorScheme.surfaceVariant,
      },
      'container': {
        'primary': colorScheme.primaryContainer,
        'secondary': colorScheme.secondaryContainer,
        'tertiary': colorScheme.tertiaryContainer,
      },
      'onSurface': {
        'primary': colorScheme.onSurface,
        'secondary': colorScheme.onSurfaceVariant,
      },
      'accent': {
        'primary': colorScheme.primary,
        'secondary': colorScheme.secondary,
        'tertiary': colorScheme.tertiary,
      },
      'onAccent': {
        'primary': colorScheme.onPrimary,
        'secondary': colorScheme.onSecondary,
        'tertiary': colorScheme.onTertiary,
      },
      
      // Material 3 Shapes (Corner Radius)
      'borderRadius': {
        'small': 8.0,
        'medium': 16.0,
        'large': 24.0,
        'extraLarge': 28.0,
        'full': 9999.0, // Fully rounded
      },
      
      // Material 3 Elevations (NO blur - use shadow + surface tint)
      'elevation': {
        'level0': 0.0,
        'level1': 1.0,
        'level2': 3.0,
        'level3': 6.0,
        'level4': 8.0,
        'level5': 12.0,
      },
      
      // Material 3 Motion Tokens
      'durations': {
        'short1': const Duration(milliseconds: 50),
        'short2': const Duration(milliseconds: 100),
        'short3': const Duration(milliseconds: 150),
        'short4': const Duration(milliseconds: 200),
        'medium1': const Duration(milliseconds: 250),
        'medium2': const Duration(milliseconds: 300),
        'medium3': const Duration(milliseconds: 350),
        'medium4': const Duration(milliseconds: 400),
        'long1': const Duration(milliseconds: 450),
        'long2': const Duration(milliseconds: 500),
        'long3': const Duration(milliseconds: 550),
        'long4': const Duration(milliseconds: 600),
      },
      'curves': {
        'standard': Curves.easeInOut,
        'emphasized': Curves.easeOutCubic,
        'emphasizedDecelerate': Curves.easeOut,
        'emphasizedAccelerate': Curves.easeIn,
      },
      
      // Spacing tokens
      'spacing': {
        'xs': 4.0,
        'sm': 8.0,
        'md': 16.0,
        'lg': 24.0,
        'xl': 32.0,
        'xxl': 48.0,
      },
    };
  }

  /// Get default Material You color scheme (dark mode) with light blue accents
  static ColorScheme getDefaultDarkColorScheme() {
    return ColorScheme.fromSeed(
      seedColor: primaryVibrant, // Light blue
      brightness: Brightness.dark,
      primary: primaryVibrant,
      secondary: secondaryVibrant,
      tertiary: tertiaryVibrant,
      surface: surfaceDark, // Pure black
      surfaceVariant: surfaceVariantDark,
    );
  }

  /// Get default Material You color scheme (light mode) with light blue accents
  static ColorScheme getDefaultLightColorScheme() {
    return ColorScheme.fromSeed(
      seedColor: primaryVibrant, // Light blue
      brightness: Brightness.light,
      primary: primaryVibrant,
      secondary: secondaryVibrant,
      tertiary: tertiaryVibrant,
    );
  }
  
  /// Generate vibrant color scheme from seed color (for dynamic theming)
  static ColorScheme generateVibrantColorScheme(Color seedColor, {Brightness brightness = Brightness.dark}) {
    return ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      // Boost saturation for more vibrant colors
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
    );
  }
}
