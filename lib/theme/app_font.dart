// lib/theme/app_font.dart
//
// The app's typeface and text weight, chosen in Settings > Appearance.
//
// Every glass/common text style goes through [AppFont.style], which has the
// exact signature of a `GoogleFonts.<family>(...)` call, so moving a call site
// over is a rename. The default (Plus Jakarta Sans, weight unchanged) takes the
// same `GoogleFonts.plusJakartaSans` path as before, from the bundled files in
// assets/google_fonts: nothing changes for anyone who never opens the setting.
//
// Other families are fetched once from Google Fonts and cached on the device
// by the google_fonts package. Settings preloads a family before switching to
// it (see [AppFont.preload]) so the app never flashes a fallback face.
//
// Material You screens keep their own typography and do not read this.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One choice in the font picker.
@immutable
class AppFontFamily {
  const AppFontFamily(this.name, this.note);

  /// The Google Fonts family name.
  final String name;

  /// One line on what it looks like, for the picker.
  final String note;
}

abstract final class AppFont {
  static const String defaultFamily = 'Plus Jakarta Sans';

  /// Screen-first sans families, all in google_fonts 6.3.3. Chosen for small
  /// sizes on a phone (open apertures, a tall x-height) and for a bold weight
  /// that holds up in a 34sp heading.
  static const List<AppFontFamily> families = [
    AppFontFamily(defaultFamily, 'Default. Friendly and geometric'),
    AppFontFamily('Inter', 'Neutral, the most legible at small sizes'),
    AppFontFamily('Manrope', 'Modern and compact'),
    AppFontFamily('Figtree', 'Clean, a little warmer'),
    AppFontFamily('DM Sans', 'Low contrast, soft'),
    AppFontFamily('Onest', 'Crisp, made for screens'),
    AppFontFamily('Hanken Grotesk', 'Classic grotesque'),
    AppFontFamily('Schibsted Grotesk', 'Editorial, sharp in bold'),
    AppFontFamily('Instrument Sans', 'Narrow and precise'),
  ];

  /// Lighter / Default / Bolder, one weight step each way.
  static const int minWeightDelta = -1;
  static const int maxWeightDelta = 1;

  static String _family = defaultFamily;
  static int _weightDelta = 0;

  static String get family => _family;
  static int get weightDelta => _weightDelta;
  static bool get isDefault => _family == defaultFamily && _weightDelta == 0;

  /// Bumped on every change, for anything that caches a style.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool isKnown(String family) => families.any((f) => f.name == family);

  /// Switches the family and weight. Unknown families fall back to the
  /// default; the delta is clamped. The caller rebuilds the tree.
  static void apply({String? family, int? weightDelta}) {
    final f = family != null && isKnown(family) ? family : (family == null ? _family : defaultFamily);
    final d = (weightDelta ?? _weightDelta).clamp(minWeightDelta, maxWeightDelta);
    if (f == _family && d == _weightDelta) return;
    _family = f;
    _weightDelta = d;
    revision.value++;
  }

  @visibleForTesting
  static void debugReset() {
    _family = defaultFamily;
    _weightDelta = 0;
  }

  /// [weight] moved by the weight setting (null reads as regular, w400).
  static FontWeight? shift(FontWeight? weight) {
    if (_weightDelta == 0) return weight;
    // FontWeight.values runs w100..w900; value is 100..900.
    final base = ((weight ?? FontWeight.w400).value / 100).round() - 1;
    final i = (base + _weightDelta).clamp(0, FontWeight.values.length - 1);
    return FontWeight.values[i];
  }

  /// A text style in the chosen family. Same parameters as
  /// `GoogleFonts.plusJakartaSans`.
  static TextStyle style({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    TextBaseline? textBaseline,
    double? height,
    Locale? locale,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) {
    final weight = _weightDelta == 0 ? fontWeight : shift(fontWeight ?? textStyle?.fontWeight);
    if (_family == defaultFamily) {
      return GoogleFonts.plusJakartaSans(
        textStyle: textStyle,
        color: color,
        backgroundColor: backgroundColor,
        fontSize: fontSize,
        fontWeight: weight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        textBaseline: textBaseline,
        height: height,
        locale: locale,
        foreground: foreground,
        background: background,
        shadows: shadows,
        fontFeatures: fontFeatures,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        decorationThickness: decorationThickness,
      );
    }
    return GoogleFonts.getFont(
      _family,
      textStyle: textStyle,
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontWeight: weight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textBaseline: textBaseline,
      height: height,
      locale: locale,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
    );
  }

  /// [base] in the chosen family, every weight moved by the setting (unless
  /// [shiftWeights] is false: the caller sets weights and shifts afterwards).
  static TextTheme textTheme(TextTheme base, {bool shiftWeights = true}) {
    final themed = _family == defaultFamily
        ? GoogleFonts.plusJakartaSansTextTheme(base)
        : GoogleFonts.getTextTheme(_family, base);
    return shiftWeights ? shiftTextTheme(themed) : themed;
  }

  /// Moves every weight in [t] by the setting (identity when it is 0).
  static TextTheme shiftTextTheme(TextTheme t) {
    if (_weightDelta == 0) return t;
    TextStyle? s(TextStyle? x) => x?.copyWith(fontWeight: shift(x.fontWeight));
    return t.copyWith(
      displayLarge: s(t.displayLarge),
      displayMedium: s(t.displayMedium),
      displaySmall: s(t.displaySmall),
      headlineLarge: s(t.headlineLarge),
      headlineMedium: s(t.headlineMedium),
      headlineSmall: s(t.headlineSmall),
      titleLarge: s(t.titleLarge),
      titleMedium: s(t.titleMedium),
      titleSmall: s(t.titleSmall),
      bodyLarge: s(t.bodyLarge),
      bodyMedium: s(t.bodyMedium),
      bodySmall: s(t.bodySmall),
      labelLarge: s(t.labelLarge),
      labelMedium: s(t.labelMedium),
      labelSmall: s(t.labelSmall),
    );
  }

  /// The weights the app draws with, fetched before a family is applied.
  static const List<FontWeight> _preloadWeights = [
    FontWeight.w300,
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
    FontWeight.w800,
    FontWeight.w900,
  ];

  /// Downloads (or reads from the device cache) [family] in every weight the
  /// app uses. Completes with false when it could not be had - offline on
  /// first use, say - so the caller can stay on the current face.
  static Future<bool> preload(String family, {Duration timeout = const Duration(seconds: 20)}) async {
    if (family == defaultFamily) return true;
    if (!isKnown(family)) return false;
    try {
      for (final w in _preloadWeights) {
        GoogleFonts.getFont(family, fontWeight: w);
      }
      await GoogleFonts.pendingFonts().timeout(timeout);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('AppFont: could not load $family: $e');
      return false;
    }
  }

  /// Rebuilds every element in place (no state is lost), so styles built
  /// from [style] in `build` methods pick the new face up.
  static void rebuildAll() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    root.visitChildren(visit);
  }
}
