import 'dart:ui';
import 'package:flutter/material.dart';

class GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavigationBarItem> items;

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    // We want a floating "pill" look, so we wrap in a Container with margin
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 25), // Float higher
      height: 65, // Slightly slimmer
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1E1E).withOpacity(0.60) // More transparent/liquid
            : Colors.white.withOpacity(0.70), 
        borderRadius: BorderRadius.circular(40), // More rounded pill
        // Removed border as requested
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 30, // Softer shadow
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0), // Reduced blur for liquid feel
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isSelected = index == currentIndex;
              
              // Custom Red Accent
              final accentColor = const Color(0xFFFF1744); 

              return InkWell(
                onTap: () => onTap(index),
                borderRadius: BorderRadius.circular(30),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  // No background decoration for selection, just icon color
                  child: IconTheme(
                    data: IconThemeData(
                      color: isSelected
                          ? accentColor
                          : Colors.white.withOpacity(0.6), // Subtle unselected
                      size: 28, // Slightly larger icons
                    ),
                    child: isSelected ? (item.activeIcon ?? item.icon) : item.icon,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
