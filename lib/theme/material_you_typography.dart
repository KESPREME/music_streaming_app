import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Material You Typography
/// Large, bold fonts for Google Pixel aesthetic
/// Uses Spline Sans (similar to Google Sans)
class MaterialYouTypography {
  /// Display styles (largest - for hero text)
  static TextStyle displayLarge(Color color) => GoogleFonts.splineSans(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: color,
        height: 1.2,
      );

  static TextStyle displayMedium(Color color) => GoogleFonts.splineSans(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: color,
        height: 1.2,
      );

  static TextStyle displaySmall(Color color) => GoogleFonts.splineSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: color,
        height: 1.3,
      );

  /// Headline styles (for section headers)
  static TextStyle headlineLarge(Color color) => GoogleFonts.splineSans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: color,
        height: 1.3,
      );

  static TextStyle headlineMedium(Color color) => GoogleFonts.splineSans(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: color,
        height: 1.3,
      );

  static TextStyle headlineSmall(Color color) => GoogleFonts.splineSans(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: color,
        height: 1.4,
      );

  /// Title styles (for card titles, list items)
  static TextStyle titleLarge(Color color) => GoogleFonts.splineSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: color,
        height: 1.4,
      );

  static TextStyle titleMedium(Color color) => GoogleFonts.splineSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: color,
        height: 1.4,
      );

  static TextStyle titleSmall(Color color) => GoogleFonts.splineSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: color,
        height: 1.4,
      );

  /// Body styles (for content text)
  static TextStyle bodyLarge(Color color) => GoogleFonts.splineSans(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: color,
        height: 1.5,
      );

  static TextStyle bodyMedium(Color color) => GoogleFonts.splineSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        color: color,
        height: 1.5,
      );

  static TextStyle bodySmall(Color color) => GoogleFonts.splineSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        color: color,
        height: 1.5,
      );

  /// Label styles (for buttons, chips)
  static TextStyle labelLarge(Color color) => GoogleFonts.splineSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: color,
        height: 1.4,
      );

  static TextStyle labelMedium(Color color) => GoogleFonts.splineSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: color,
        height: 1.4,
      );

  static TextStyle labelSmall(Color color) => GoogleFonts.splineSans(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: color,
        height: 1.4,
      );

  /// Generate complete TextTheme for Material You
  static TextTheme generateTextTheme(ColorScheme colorScheme) {
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = colorScheme.onSurfaceVariant;

    return TextTheme(
      // Display
      displayLarge: displayLarge(onSurface),
      displayMedium: displayMedium(onSurface),
      displaySmall: displaySmall(onSurface),

      // Headline
      headlineLarge: headlineLarge(onSurface),
      headlineMedium: headlineMedium(onSurface),
      headlineSmall: headlineSmall(onSurface),

      // Title
      titleLarge: titleLarge(onSurface),
      titleMedium: titleMedium(onSurface),
      titleSmall: titleSmall(onSurface),

      // Body
      bodyLarge: bodyLarge(onSurface),
      bodyMedium: bodyMedium(onSurfaceVariant),
      bodySmall: bodySmall(onSurfaceVariant),

      // Label
      labelLarge: labelLarge(onSurface),
      labelMedium: labelMedium(onSurfaceVariant),
      labelSmall: labelSmall(onSurfaceVariant),
    );
  }

  /// Quick access to common text styles
  static TextStyle greeting(Color color) => displayLarge(color);
  static TextStyle sectionHeader(Color color) => headlineMedium(color);
  static TextStyle cardTitle(Color color) => titleMedium(color);
  static TextStyle cardSubtitle(Color color) => bodyMedium(color);
  static TextStyle buttonLabel(Color color) => labelLarge(color);
}
