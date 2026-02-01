import 'package:flutter/material.dart';

/// Material You Floating Action Button (FAB)
/// Large, prominent circular button with vibrant colors and elevation
/// Follows Material 3 specifications exactly
class MaterialYouFAB extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isLarge; // 64dp vs 56dp
  final String? label;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const MaterialYouFAB({
    super.key,
    required this.icon,
    required this.onPressed,
    this.isLarge = false,
    this.label,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = isLarge ? 64.0 : 56.0;
    final iconSize = isLarge ? 32.0 : 24.0;
    
    final bgColor = backgroundColor ?? colorScheme.primaryContainer;
    final fgColor = foregroundColor ?? colorScheme.onPrimaryContainer;

    if (label != null) {
      // Extended FAB with label
      return Material(
        elevation: 6,
        surfaceTintColor: colorScheme.surfaceTint,
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: size,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize, color: fgColor),
                const SizedBox(width: 12),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: fgColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Regular circular FAB
    return Material(
      elevation: 6,
      surfaceTintColor: colorScheme.surfaceTint,
      color: bgColor,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          height: size,
          width: size,
          alignment: Alignment.center,
          child: Icon(icon, size: iconSize, color: fgColor),
        ),
      ),
    );
  }
}

/// Small FAB variant (40dp) for secondary actions
class MaterialYouSmallFAB extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const MaterialYouSmallFAB({
    super.key,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = backgroundColor ?? colorScheme.secondaryContainer;
    final fgColor = foregroundColor ?? colorScheme.onSecondaryContainer;

    return Material(
      elevation: 3,
      surfaceTintColor: colorScheme.surfaceTint,
      color: bgColor,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          height: 40,
          width: 40,
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: fgColor),
        ),
      ),
    );
  }
}
