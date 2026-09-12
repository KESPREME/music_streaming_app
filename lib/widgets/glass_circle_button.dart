import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// Floating liquid-glass circle button - the shared chrome atom.
///
/// Refactored with `liquid_glass_easy` for physical optical refraction,
/// `OpticalBorder` rim highlight, contact shadow, and `LiquidGlassTouch` soft-body flex.
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

    return SizedBox(
      width: size,
      height: size,
      child: LiquidGlassLens(
        touch: const LiquidGlassTouch(
          flex: LiquidGlassFlex.pronounced(),
        ),
        style: LiquidGlassStyle(
          shape: LiquidGlassShape.roundedRectangle(
            cornerRadius: size / 2,
            borderWidth: 1.2,
            lightColor: Colors.white.withValues(alpha: 0.70),
            lightIntensity: 1.1,
            lightDirection: 135,
            borderType: const OpticalBorder(
              borderSaturation: 1.4,
              ambientIntensity: 0.9,
              borderSolidity: 0.05,
              lightSpread: 1.0,
            ),
          ),
          appearance: LiquidGlassAppearance(
            color: glow ? accent.withValues(alpha: 0.20) : const Color(0x18FFFFFF),
            blur: const LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
            saturation: 1.1,
            shadow: const LiquidGlassShadow(blur: 3.5, opacity: 0.25),
          ),
          refraction: const LiquidGlassRefraction(
            distortion: 0.10,
            distortionWidth: 16,
            refractionType: OpticalRefraction(),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            customBorder: const CircleBorder(),
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
