import 'package:flutter/material.dart';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' hide GlassTheme;

import '../theme/glass_tokens.dart';

/// App-wide glass quality tiers — maps to physical material layers.
///
/// 1 grounded (no glass, solid content)
/// 2 elevated (card lists — cheap frosted, minimal)
/// 3 interactive (segmented control thumb — standard)
/// 4 floating (nav bar, mini-player — full liquid, standard)
/// 5 transient (sheets/menus — strongest, standard)
///
/// Only chrome/floating/transient use real shader; card uses minimal for 60fps.
enum GlassTier { card, chrome, floating, sheet }

/// The one glass surface every screen should use.
///
/// Wraps `liquid_glass_widgets:GlassContainer` with premium physical values
/// from `GlassTokens` — thickness, refraction, edge absorption, Fresnel,
/// chromatic — not just a blur+border. Accent appears only as a restrained
/// ink bloom on selected states, not as tinted glass.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.tier = GlassTier.card,
    this.borderRadius = 20,
    this.padding,
    this.accent,
  });

  final Widget child;
  final GlassTier tier;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Override the theme accent (rare — used for special surfaces).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveAccent = accent ?? scheme.primary;

    final bool isFloating =
        tier == GlassTier.floating || tier == GlassTier.chrome;
    final bool isSheet = tier == GlassTier.sheet;
    final bool isCard = tier == GlassTier.card;

    final settings = LiquidGlassSettings(
      blur: isSheet
          ? GlassTokens.blurSheet
          : isFloating
              ? GlassTokens.blurFloating
              : GlassTokens.blurCard,
      thickness: isSheet
          ? GlassTokens.thicknessSheet
          : isFloating
              ? GlassTokens.thicknessFloating
              : GlassTokens.thicknessCard,
      glassColor: GlassTokens.glassTint(effectiveAccent),
      refractiveIndex: isSheet
          ? GlassTokens.refractiveFloating
          : isFloating
              ? GlassTokens.refractiveFloating
              : GlassTokens.refractiveCard,
      lightIntensity: isFloating || isSheet
          ? GlassTokens.lightChrome
          : GlassTokens.lightCard,
      fresnelStrength: isFloating || isSheet
          ? GlassTokens.fresnelChrome
          : GlassTokens.fresnelCard,
      edgeAbsorption: isFloating || isSheet
          ? GlassTokens.edgeAbsorptionChrome
          : GlassTokens.edgeAbsorptionCard,
      chromaticAberration: isFloating || isSheet
          ? GlassTokens.chromaticChrome
          : GlassTokens.chromaticCard,
      saturation: GlassTokens.glassSaturation,
      glowIntensity: GlassTokens.glassGlowIntensity,
      shadowElevation: isCard ? 0.6 : 1.0,
    );

    final quality = isCard ? GlassQuality.minimal : GlassQuality.standard;

    final surface = GlassContainer(
      shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
      settings: settings,
      quality: quality,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: child,
    );

    // Isolate repaints for scrollable cards so the shader doesn't rebuild each frame.
    if (isCard) return RepaintBoundary(child: surface);
    return surface;
  }
}
