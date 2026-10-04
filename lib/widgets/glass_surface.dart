import 'package:flutter/material.dart';

import '../design/glass/glass_surface.dart' as design;

export '../design/glass/glass_surface.dart' show GlassTier;

/// Legacy facade kept so existing import paths keep compiling while the
/// screens migrate to `design/glass` directly. New code must import from
/// `design/glass/glass_surface.dart`.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.tier = design.GlassTier.card,
    this.borderRadius = 20,
    this.padding,
    this.accent,
  });

  final Widget child;
  final design.GlassTier tier;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return design.GlassSurface(
      tier: tier,
      borderRadius: borderRadius,
      padding: padding,
      accent: accent,
      child: child,
    );
  }
}
