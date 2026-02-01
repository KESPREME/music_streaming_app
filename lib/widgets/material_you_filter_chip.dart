import 'package:flutter/material.dart';

/// Material You Filter Chip
/// Used for filtering content with checkmark when selected
/// Follows Material 3 specifications
class MaterialYouFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? leadingIcon;

  const MaterialYouFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    final backgroundColor = selected
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceVariant;
    
    final foregroundColor = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    
    final borderColor = selected
        ? colorScheme.secondary.withOpacity(0.3)
        : colorScheme.outline;

    return Material(
      elevation: selected ? 1 : 0,
      surfaceTintColor: selected ? colorScheme.surfaceTint : null,
      color: backgroundColor,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: selected 
                ? Border.all(color: Colors.transparent, width: 0) // No border when selected (filled)
                : Border.all(color: colorScheme.outline.withOpacity(0.5), width: 1), // Thin border unselected
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 18, color: foregroundColor),
                const SizedBox(width: 8),
              ],
              if (selected) ...[
                Icon(Icons.check, size: 18, color: foregroundColor),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: foregroundColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal scrollable list of filter chips
/// Horizontal scrollable list of filter chips in a single container
class MaterialYouFilterChipList extends StatelessWidget {
  final List<String> options;
  final String selectedOption;
  final Function(String) onSelected;
  final Map<String, IconData>? icons;

  const MaterialYouFilterChipList({
    super.key,
    required this.options,
    required this.selectedOption,
    required this.onSelected,
    this.icons,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 50, // Slightly shorter for segmented look
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: options.map((option) {
          final isSelected = option == selectedOption;
          final icon = icons?[option];

          return Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(option),
                borderRadius: BorderRadius.circular(28),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? colorScheme.secondaryContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          size: 16, // Smaller icon
                          color: isSelected 
                              ? colorScheme.onSecondaryContainer 
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        option,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13, // Slightly smaller text
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected 
                              ? colorScheme.onSecondaryContainer 
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
