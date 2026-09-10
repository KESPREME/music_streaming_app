import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// Floating liquid-glass circle button - the shared chrome atom.
///
/// Same treatment everywhere: nav circles, home settings, deck actions.
/// Optional [glow] tints the icon with the accent and adds a soft halo
/// (used for primary actions like the deck play button).
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
  }) : assert(icon != null || child != null, 'Either icon or child must be provided');

  final IconData? icon;
  final Widget? child;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final bool glow;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final iconColor = glow ? accent : Colors.white.withValues(alpha: 0.9);

    return GlassSurface(
      tier: GlassTier.chrome,
      borderRadius: size / 2,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: child ??
                  (icon != null
                      ? Icon(
                          icon,
                          color: iconColor,
                          size: iconSize,
                          semanticLabel: semanticLabel,
                        )
                      : const SizedBox.shrink()),
            ),
          ),
        ),
      ),
    );
  }
}
