// lib/theme/amoled_theme.dart
//
// PURE BLACK (AMOLED), carried in the Theme.
//
// The setting lives in `ThemeProvider`, but widgets that need to know ("is the
// canvas black?") must not depend on a provider: that makes every one of them
// throw `ProviderNotFoundException` in a test, or in any subtree mounted without
// the provider, for the sake of a boolean. A `ThemeExtension` is the Material
// mechanism for exactly this - app-specific theme data that travels with
// `Theme.of(context)`, rebuilds dependants when it changes, and is interpolated
// by `AnimatedTheme` for free.
//
// `GlassTheme.build(..., amoled: true)` attaches it; everything else reads it
// through [AmoledTheme.isOn] / [AmoledTheme.gradient] / [AmoledTheme.surface].
//
// What "pure black" means here, and what it does not:
//
//   * The CANVAS is `#000000` - the screen's background, the ambient backdrop
//     behind every tab, the gradient grounds of the full-screen pages. An OLED
//     panel switches those pixels off, which is where the battery saving is.
//   * RAISED surfaces (dialogs, sheets, snack bars) are NOT black. A black
//     dialog on a black canvas is invisible, so they sit one step up
//     (`#0A0A0A`) and are outlined with a hairline, the way every true-black
//     theme separates layers once elevation tint is gone.
//   * Artwork is never darkened or recoloured: it is content, not chrome. The
//     full-bleed art washes on Now Playing and the queue are the player's own
//     surface and are left as they are.

import 'package:flutter/material.dart';

@immutable
class AmoledTheme extends ThemeExtension<AmoledTheme> {
  const AmoledTheme({this.enabled = false});

  /// Whether pure-black mode is on.
  final bool enabled;

  /// The canvas colour in pure-black mode.
  static const Color canvas = Colors.black;

  /// A raised surface in pure-black mode: one step above the canvas so it can be
  /// seen, still dark enough to cost almost nothing on an OLED panel.
  static const Color surface = Color(0xFF0A0A0A);

  /// The outline that replaces elevation tint on raised surfaces (white at 12%).
  static const Color hairline = Color(0x1FFFFFFF);

  /// Whether pure black is on for [context]'s theme. False when the theme was not
  /// built by `GlassTheme` (a bare `MaterialApp` in a test, the Material You
  /// theme), so reading it is always safe.
  static bool isOn(BuildContext context) =>
      Theme.of(context).extension<AmoledTheme>()?.enabled ?? false;

  /// [normal], or - in pure-black mode - the same number of stops, all black.
  /// Keeps a gradient's stop list valid without each screen rebuilding it.
  static List<Color> gradient(BuildContext context, List<Color> normal) =>
      isOn(context) ? List<Color>.filled(normal.length, canvas) : normal;

  /// [normal], or [surface] in pure-black mode: for a dialog, sheet or panel that
  /// names its own background. Its shape (and so its hairline) comes from the
  /// theme, which `GlassTheme.build` sets for pure-black mode.
  static Color surfaceOf(BuildContext context, Color normal) =>
      isOn(context) ? surface : normal;

  /// [normal], or [canvas] in pure-black mode: for an opaque page background that
  /// is a near-black of its own (`#0A0A0C`).
  static Color canvasOf(BuildContext context, Color normal) =>
      isOn(context) ? canvas : normal;

  /// The outline for a raised surface that sets its own `shape`: [hairline] in
  /// pure-black mode, none otherwise. A surface that takes the theme's shape
  /// already has it.
  static BorderSide edge(BuildContext context) =>
      isOn(context) ? const BorderSide(color: hairline) : BorderSide.none;

  @override
  AmoledTheme copyWith({bool? enabled}) =>
      AmoledTheme(enabled: enabled ?? this.enabled);

  /// A flag has no in-between. Switching at the midpoint keeps the theme's own
  /// cross-fade (which carries every colour that does interpolate) in step with
  /// the backdrop's, which animates the fade itself.
  @override
  AmoledTheme lerp(ThemeExtension<AmoledTheme>? other, double t) {
    if (other is! AmoledTheme) return this;
    return t < 0.5 ? this : other;
  }

  @override
  bool operator ==(Object other) =>
      other is AmoledTheme && other.enabled == enabled;

  @override
  int get hashCode => enabled.hashCode;
}
