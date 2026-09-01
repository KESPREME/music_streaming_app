import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as classic;

import '../../theme/glass_tokens.dart';
import '../tokens/space.dart';
import 'glass_materials.dart';

export 'glass_materials.dart' show GlassTier;

/// The one glass surface every screen should use.
///
/// Engine note: this widget routes every tier through the proven
/// liquid_glass_widgets shader container. For brand-new shell components
/// (nav morph pill, mini-player) that are authored with lens-safe children,
/// use [LiquidLens] from `lens_surface.dart` to get liquid_glass_easy's
/// live-backdrop refraction instead.
///
/// Rules encoded here (do not violate from call sites):
///  * GlassTier.none renders plain grounded content — no blur at all.
///  * cards are wrapped in RepaintBoundary to isolate shader repaints.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.tier = GlassTier.card,
    this.borderRadius = Radii.large,
    this.padding,
    this.accent,
    this.selected = false,
  });

  final Widget child;
  final GlassTier tier;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Override the theme accent (used for selected-state edge light).
  final Color? accent;

  /// Selected state — denser fill + stronger displacement (§21).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (tier == GlassTier.none) {
      return Padding(padding: padding ?? EdgeInsets.zero, child: child);
    }

    final scheme = Theme.of(context).colorScheme;
    final effectiveAccent = accent ?? scheme.primary;

    final bool isFloating = tier == GlassTier.floating;
    final bool isSheet = tier == GlassTier.sheet;
    final bool isRich = tier == GlassTier.rich;
    final bool isCard = tier == GlassTier.card;

    final settings = classic.LiquidGlassSettings(
      blur: isSheet
          ? GlassTokens.blurSheet
          : isFloating || isRich
              ? GlassTokens.blurFloating
              : GlassTokens.blurCard,
      thickness: isSheet
          ? GlassTokens.thicknessSheet
          : isFloating || isRich
              ? GlassTokens.thicknessFloating
              : GlassTokens.thicknessCard,
      glassColor: selected
          ? GlassTokens.glassTint(effectiveAccent).withValues(alpha: 0.22)
          : GlassTokens.glassTint(effectiveAccent),
      refractiveIndex: isSheet || isFloating || isRich
          ? GlassTokens.refractiveFloating
          : GlassTokens.refractiveCard,
      lightIntensity: isFloating || isSheet || isRich
          ? GlassTokens.lightChrome
          : GlassTokens.lightCard,
      fresnelStrength: isFloating || isSheet || isRich
          ? GlassTokens.fresnelChrome
          : GlassTokens.fresnelCard,
      edgeAbsorption: isFloating || isSheet || isRich
          ? GlassTokens.edgeAbsorptionChrome
          : GlassTokens.edgeAbsorptionCard,
      chromaticAberration: isFloating || isSheet || isRich
          ? GlassTokens.chromaticChrome
          : GlassTokens.chromaticCard,
      saturation: GlassTokens.glassSaturation,
      glowIntensity: GlassTokens.glassGlowIntensity,
      shadowElevation: isCard ? 0.6 : 1.0,
    );

    final quality =
        isCard ? classic.GlassQuality.minimal : classic.GlassQuality.standard;

    final surface = classic.GlassContainer(
      shape: classic.LiquidRoundedSuperellipse(borderRadius: borderRadius),
      settings: settings,
      quality: quality,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: child,
    );

    // Isolate repaints for scrollable cards so the shader doesn't rebuild
    // each frame.
    if (isCard) return RepaintBoundary(child: surface);
    return surface;
  }
}
