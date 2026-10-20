// lib/design/glass/chrome_glass.dart
//
// HOW THE BOTTOM CHROME (tab bar, pills, mini player) IS DRAWN.
//
// Two materials exist:
//
//   * REFRACTION - the live-backdrop shader pipeline. Content under the glass is
//     bent by a lens. Beautiful over artwork, and the heaviest thing in the app:
//     several passes, an unclamped sample of the backdrop, a geometry matte.
//   * FROSTED - blur, tint, a specular rim. No refraction.
//
// On PURE BLACK there is nothing for refraction to show except the list scrolling
// underneath, and that is exactly where it breaks (hard splits, smeared rows,
// mirrored text, a sharp - un-blurred - list through the glass). Black + white
// text + a saturated accent is the worst case for any sampling error, and the
// shader's content-adaptive maths also lifts saturation on a black backdrop.
// The right material there is dark frosted glass, so that is what Auto picks.
//
// The decision is a pure function so it can be tested and so a device-specific
// shader fault is one setting, not a release.

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart'
    show LiquidGlassLitePickup;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import '../../theme/amoled_theme.dart';

/// What the listener chose in Settings > Appearance > Glass rendering.
enum GlassRendering {
  /// Frosted on pure black, refraction otherwise.
  auto,

  /// Always the live refraction shader.
  refraction,

  /// Always dark frosted glass.
  frosted;

  String get label => switch (this) {
        GlassRendering.auto => 'Auto',
        GlassRendering.refraction => 'Refraction',
        GlassRendering.frosted => 'Frosted',
      };

  String get description => switch (this) {
        GlassRendering.auto =>
          'Frosted on pure black, refraction everywhere else',
        GlassRendering.refraction =>
          'Content bends through the glass. Richest, heaviest',
        GlassRendering.frosted =>
          'Soft blur and a crisp rim. Clean on any screen, lighter on the GPU',
      };

  static GlassRendering parse(String? raw) => GlassRendering.values.firstWhere(
        (v) => v.name == raw,
        orElse: () => GlassRendering.auto,
      );
}

/// Carries the chosen [GlassRendering] in the Theme, the way [AmoledTheme]
/// carries pure black: widgets read it without needing a Provider.
@immutable
class ChromeGlassTheme extends ThemeExtension<ChromeGlassTheme> {
  const ChromeGlassTheme({this.rendering = GlassRendering.auto});

  final GlassRendering rendering;

  static GlassRendering of(BuildContext context) =>
      Theme.of(context).extension<ChromeGlassTheme>()?.rendering ??
      GlassRendering.auto;

  @override
  ChromeGlassTheme copyWith({GlassRendering? rendering}) =>
      ChromeGlassTheme(rendering: rendering ?? this.rendering);

  @override
  ChromeGlassTheme lerp(ThemeExtension<ChromeGlassTheme>? other, double t) =>
      other is! ChromeGlassTheme ? this : (t < 0.5 ? this : other);

  @override
  bool operator ==(Object other) =>
      other is ChromeGlassTheme && other.rendering == rendering;

  @override
  int get hashCode => rendering.hashCode;
}

/// The resolved look of the bottom chrome.
@immutable
class ChromeGlassSpec {
  const ChromeGlassSpec._({
    required this.frosted,
    required this.quality,
    required this.indicatorPinch,
    required this.barBlur,
    required this.barThickness,
    required this.barTint,
    required this.barLight,
    required this.barAmbient,
    required this.barSaturation,
    required this.barChromatic,
    required this.indicatorChromatic,
    required this.lensLite,
    required this.lensBlur,
    required this.lensTint,
  });

  /// Whether this is the frosted material.
  final bool frosted;

  /// Tier for the bar, the pills and the sliding indicator. `null` leaves the
  /// package default (premium), which is exactly today's behaviour.
  final lgw.GlassQuality? quality;

  /// The indicator's concave pinch only exists in the refraction shader.
  final double indicatorPinch;

  final double barBlur;
  final double barThickness;
  final Color barTint;
  final double barLight;
  final double barAmbient;
  final double barSaturation;
  final double barChromatic;
  final double indicatorChromatic;

  /// Mini player: draw lite glass (no shader) instead of the refracting lens.
  final LiquidGlassLitePickup? lensLite;
  final double lensBlur;
  final Color lensTint;

  /// The look for a pure-black surface / a chosen [rendering].
  static ChromeGlassSpec resolve({
    required bool amoled,
    GlassRendering rendering = GlassRendering.auto,
  }) {
    final frosted = switch (rendering) {
      GlassRendering.auto => amoled,
      GlassRendering.refraction => false,
      GlassRendering.frosted => true,
    };
    return frosted ? _frosted(amoled: amoled) : _refraction;
  }

  static ChromeGlassSpec of(BuildContext context) => resolve(
        amoled: AmoledTheme.isOn(context),
        rendering: ChromeGlassTheme.of(context),
      );

  /// Exactly the values the bar and the pill used before this file existed.
  static const ChromeGlassSpec _refraction = ChromeGlassSpec._(
    frosted: false,
    quality: null,
    indicatorPinch: 0.45,
    barBlur: 24,
    barThickness: 24,
    barTint: Color(0x0EFFFFFF),
    barLight: 0.85,
    barAmbient: 0.9,
    barSaturation: 1.15,
    barChromatic: 0.04,
    indicatorChromatic: 0.05,
    lensLite: null,
    lensBlur: 16,
    lensTint: Color(0x14FFFFFF),
  );

  static ChromeGlassSpec _frosted({required bool amoled}) => ChromeGlassSpec._(
        frosted: true,
        // `standard`: a plain BackdropFilter blur plus a light fragment shader
        // that samples nothing outside its own box. The same tier the rest of
        // the app's glass (avatar disc, play discs, cards) already renders
        // cleanly with.
        quality: lgw.GlassQuality.standard,
        indicatorPinch: 0,
        // Wider than the refraction bar: on black the list underneath is white
        // text, and it has to melt into a soft glow rather than stay legible
        // behind the tab labels.
        barBlur: amoled ? 30 : 22,
        barThickness: 14,
        // A hair lighter than the canvas so the bar reads as an object on
        // black. Pure #000 glass is invisible; ~10% white is the lowest tint
        // that still reads as a surface on an OLED panel.
        barTint: amoled ? const Color(0x1CFFFFFF) : const Color(0x14FFFFFF),
        barLight: 1.0,
        barAmbient: 0.55,
        // No saturation boost: the accent is already saturated and black makes
        // it look louder still.
        barSaturation: 1.0,
        barChromatic: 0,
        indicatorChromatic: 0,
        lensLite: LiquidGlassLitePickup.blend,
        lensBlur: amoled ? 26 : 20,
        lensTint: amoled ? const Color(0x1AFFFFFF) : const Color(0x14FFFFFF),
      );
}
