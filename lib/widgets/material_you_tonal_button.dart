import 'package:flutter/material.dart';

/// Material You Tonal Button
/// Material 3 tonal button with container color and surface tint
/// Used for secondary actions
class MaterialYouTonalButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool isCompact;

  const MaterialYouTonalButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    if (icon != null) {
      return FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: isCompact ? 18 : 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 16 : 24,
            vertical: isCompact ? 8 : 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isCompact ? 20 : 24),
          ),
          textStyle: TextStyle(
            fontSize: isCompact ? 13 : 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.onSecondaryContainer,
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 16 : 24,
          vertical: isCompact ? 8 : 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isCompact ? 20 : 24),
        ),
        textStyle: TextStyle(
          fontSize: isCompact ? 13 : 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }
}

/// Icon-only tonal button (circular)
class MaterialYouTonalIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool isSelected;

  const MaterialYouTonalIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    final backgroundColor = isSelected
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceVariant;
    
    final foregroundColor = isSelected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;

    final button = Material(
      elevation: isSelected ? 1 : 0,
      surfaceTintColor: isSelected ? colorScheme.surfaceTint : null,
      color: backgroundColor,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          height: 48,
          width: 48,
          alignment: Alignment.center,
          child: Icon(icon, size: 24, color: foregroundColor),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}

/// Row of tonal icon buttons (for player controls, etc.)
class MaterialYouTonalButtonRow extends StatelessWidget {
  final List<MaterialYouTonalIconButton> buttons;
  final MainAxisAlignment alignment;

  const MaterialYouTonalButtonRow({
    super.key,
    required this.buttons,
    this.alignment = MainAxisAlignment.spaceEvenly,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: alignment,
      children: buttons.map((button) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: button,
        );
      }).toList(),
    );
  }
}
