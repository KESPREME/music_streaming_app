import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared preset colors (re-exported for theme consumers).
export 'package:music_streaming_app/providers/accent_controller.dart'
    show AccentColors;

/// Builds the Glass-family ThemeData: pure-black AMOLED canvas, one warm
/// accent, near-white text. The accent drives `primary`, selection, and
/// every glass tint via [GlassTheme.accentOf].
///
/// Pure function — no state, fully testable.
class GlassTheme {
  GlassTheme._();

  /// Contrast-aware foreground for a given accent: black on light accents
  /// (peach/amber/ice/mint), white on dark ones.
  static Color onAccent(Color accent) =>
      accent.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  /// Standard glass tint derived from the accent (subtle — glass must stay
  /// glass, not become a colored panel).
  static Color glassTint(Color accent) =>
      Colors.white.withValues(alpha: 0.06);

  /// Accent-tinted glass border for focus/active states.
  static Color accentBorder(Color accent) =>
      accent.withValues(alpha: 0.35);

  static ThemeData build(Color accent, {TextTheme? textTheme}) {
    final onAccentColor = onAccent(accent);
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: onAccentColor,
      secondary: accent,
      onSecondary: onAccentColor,
      error: const Color(0xFFCF6679),
      onError: Colors.black,
      surface: Colors.black,
      onSurface: Colors.white,
      surfaceContainerHighest: const Color(0xFF141414),
      onSurfaceVariant: const Color(0xFFB3B3B3),
      outline: Colors.white.withValues(alpha: 0.12),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.black,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return onAccentColor;
          return Colors.grey.shade600;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.white.withValues(alpha: 0.12);
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
        thumbColor: onAccentColor,
        overlayColor: accent.withValues(alpha: 0.15),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        selectedColor: accent.withValues(alpha: 0.25),
        labelStyle: const TextStyle(color: Colors.white),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      dividerTheme:
          DividerThemeData(color: Colors.white.withValues(alpha: 0.08)),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1C1C1E),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF161616),
        modalBackgroundColor: Color(0xFF161616),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }
}
