import 'package:flutter/material.dart';
import '../theme/material_you_tokens.dart';

/// Material You (Material 3) navigation bar - REDESIGNED
/// Features:
/// - Material 3 Navigation Bar style
/// - Indicator pill for selected item (vibrant color)
/// - Proper spacing (24dp between items)
/// - Elevated surface with shadow
/// - NO blur, NO gradients - solid colors only
class MaterialYouNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavigationBarItem> items;

  const MaterialYouNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final itemCount = items.length;
    
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      height: 80,
      decoration: BoxDecoration(
        color: MaterialYouTokens.surfaceDark, // Pure black #000000
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeExtraLarge),
        boxShadow: const [
          MaterialYouTokens.elevation2,
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeExtraLarge),
        child: Material(
          color: Colors.transparent,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isSelected = index == currentIndex;
              
              return Expanded(
                child: _buildNavItem(
                  context,
                  colorScheme,
                  item,
                  isSelected,
                  () => onTap(index),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    ColorScheme colorScheme,
    BottomNavigationBarItem item,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MaterialYouTokens.shapeLarge),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Indicator pill + icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? MaterialYouTokens.primaryVibrant.withOpacity(0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(MaterialYouTokens.shapeFull),
              ),
              child: IconTheme(
                data: IconThemeData(
                  color: isSelected
                      ? MaterialYouTokens.primaryVibrant
                      : colorScheme.onSurfaceVariant,
                  size: 28,
                ),
                child: isSelected 
                    ? (item.activeIcon ?? item.icon) 
                    : item.icon,
              ),
            ),
            
            const SizedBox(height: 4),
            
            // Label
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? MaterialYouTokens.primaryVibrant
                    : colorScheme.onSurfaceVariant,
              ),
              child: Text(
                item.label ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
