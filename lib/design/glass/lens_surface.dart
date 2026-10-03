import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as easy;

import 'glass_materials.dart';

export 'glass_materials.dart' show GlassTier;
export 'package:liquid_glass_easy/liquid_glass_easy.dart' show LiquidGlassStyle;

/// liquid_glass_easy lens wrapper for shell-authored components.
///
/// Unlike [GlassSurface], this renders through liquid_glass_easy's
/// layout-driven [easy.LiquidGlassLens]: live backdrop refraction on
/// Impeller, frosted fallback on Skia. Use it only where children are
/// authored lens-safe (icons, text over transparent fills) — ListTiles and
/// Material ink surfaces inside will trigger framework warnings.
///
/// Tier → material mapping comes from [GlassMaterials.forTier] / [selected].
class LiquidLens extends StatelessWidget {
  const LiquidLens({
    super.key,
    required this.child,
    this.tier = GlassTier.floating,
    this.accent,
    this.selected = false,
    this.touch,
  });

  final Widget child;
  final GlassTier tier;
  final Color? accent;
  final bool selected;

  /// Package touch physics (press-compress, tap-pop, hold-swell, spring
  /// wobble) via liquid_glass_easy. Null = static lens.
  final easy.LiquidGlassTouch? touch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveAccent = accent ?? scheme.primary;

    final easy.LiquidGlassStyle style = selected
        ? GlassMaterials.selected(accent: effectiveAccent)
        : GlassMaterials.forTier(
            tier == GlassTier.none ? GlassTier.floating : tier,
            accent: effectiveAccent,
          );

    return easy.LiquidGlassLens(style: style, touch: touch, child: child);
  }
}
