import 'package:flutter/material.dart';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    hide GlassTheme;

import '../theme/glass_theme.dart' as app;

/// App-wide glass quality tiers.
///
/// - [GlassTier.chrome]: fixed UI chrome (nav bar, player bar, sheets) —
///   full liquid-glass treatment; never inside scroll views.
/// - [GlassTier.card]: scrollable content — cheap frosted look, minimal
///   quality so lists stay at 60fps (per liquid_glass_widgets guidance).
enum GlassTier { chrome, card }

/// The one glass surface every screen should use.
///
/// Wraps liquid_glass_widgets' GlassContainer with app defaults: accent
/// tint from the active [app.GlassTheme], tier-based quality, and a flat
/// fallback on unsupported backends (handled by the package).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.tier = GlassTier.card,
    this.borderRadius = 20,
    this.padding,
    this.accent,
    this.borderColor,
  });

  final Widget child;
  final GlassTier tier;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Override the theme accent (rare — used for special surfaces).
  final Color? accent;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveAccent = accent ?? scheme.primary;
    final isChrome = tier == GlassTier.chrome;

    final settings = LiquidGlassSettings(
      blur: isChrome ? 14 : 8,
      thickness: isChrome ? 17 : 9,
      glassColor: app.GlassTheme.glassTint(effectiveAccent),
      refractiveIndex: isChrome ? 1.2 : 1.15,
      lightIntensity: isChrome ? 0.5 : 0.35,
    );

    final surface = GlassContainer(
      shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
      settings: settings,
      quality: isChrome ? GlassQuality.standard : GlassQuality.minimal,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: child,
    );

    // Cards scroll — isolate repaints so the glass layer doesn't rebuild
    // every frame while the list moves.
    if (isChrome) return surface;
    return RepaintBoundary(child: surface);
  }
}
