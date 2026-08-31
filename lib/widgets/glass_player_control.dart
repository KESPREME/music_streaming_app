import 'package:flutter/material.dart';

import '../theme/glass_tokens.dart';
import 'glass_surface.dart';

class GlassPlayerControl extends StatelessWidget {
  const GlassPlayerControl({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.tooltip,
    this.selected = false,
    this.primary = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final String? tooltip;
  final bool selected;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final size = primary
        ? GlassTokens.playerPrimaryControlSize
        : GlassTokens.playerControlSize;
    final iconColor = selected || primary
        ? accent
        : onPressed == null
            ? Colors.white.withValues(alpha: 0.38)
            : Colors.white.withValues(alpha: 0.9);

    final controlContent = Material(
      color: selected
          ? accent.withValues(alpha: GlassTokens.playerControlFillOpacity)
          : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Icon(
              icon,
              color: iconColor,
              size: primary ? 30 : 24,
            ),
          ),
        ),
      ),
    );

    Widget control = Semantics(
      label: semanticLabel,
      button: true,
      enabled: onPressed != null,
      child: GlassSurface(
        tier: primary ? GlassTier.floating : GlassTier.chrome,
        borderRadius: size / 2,
        child: controlContent,
      ),
    );

    if (tooltip != null) {
      control = Tooltip(message: tooltip!, child: control);
    }

    return control;
  }
}
