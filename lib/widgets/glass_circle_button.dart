import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'jelly_press.dart';

/// Floating liquid-glass circle button - the shared chrome atom.
///
/// Floating glass flexes under the finger like the bottom bar (`JellyPress`,
/// chrome profile: compress, hold, stretch toward the finger, a light under it,
/// wobble on release), on the authentic chrome glass tier (`GlassSurface`),
/// with ONE haptic per tap.
///
/// [isActive] fills the circle solid white with a black glyph - the same
/// "white means on" language as the segmented-pill thumb. [haptic] lets
/// callers whose `onTap` already plays its own haptic (e.g. tab navigation)
/// opt out instead of double-buzzing.
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    this.icon,
    this.child,
    required this.onTap,
    this.size = 54,
    this.iconSize = 24,
    this.glow = false,
    this.semanticLabel,
    this.isActive = false,
    this.haptic = true,
  }) : assert(icon != null || child != null, 'Either icon or child must be provided');

  final IconData? icon;
  final Widget? child;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final bool glow;
  final String? semanticLabel;
  final bool isActive;
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final iconColor = isActive
        ? Colors.black
        : glow
            ? accent
            : Colors.white.withValues(alpha: 0.9);

    final content = SizedBox(
      width: size,
      height: size,
      child: Center(
        child: child ??
            (icon != null
                ? Icon(
                    icon,
                    color: iconColor,
                    size: iconSize,
                  )
                : const SizedBox.shrink()),
      ),
    );

    return Semantics(
      label: semanticLabel,
      button: true,
      selected: isActive,
      child: JellyPress(
        profile: JellyProfile.chrome,
        haptic: haptic ? JellyHaptic.light : JellyHaptic.none,
        borderRadius: size / 2,
        onTap: onTap,
        child: isActive
            ? Container(
                width: size,
                height: size,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: content,
              )
            : GlassSurface(
                tier: GlassTier.chrome,
                borderRadius: size / 2,
                child: content,
              ),
      ),
    );
  }
}
