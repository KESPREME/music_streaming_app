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
    final itemCount = items.length;
    
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 25),
      height: 65,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1E1E).withOpacity(0.60)
            : Colors.white.withOpacity(0.70), 
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / itemCount;
              const accentColor = Color(0xFFFF1744);
              
              return Stack(
                children: [
                  // Animated Pill Indicator
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    left: currentIndex * itemWidth + (itemWidth - 56) / 2,
                    top: (65 - 44) / 2,
                    child: Container(
                      width: 56,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: accentColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                  // Icons Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: items.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final isSelected = index == currentIndex;
                      
                      return InkWell(
                        onTap: () => onTap(index),
                        borderRadius: BorderRadius.circular(30),
                        child: SizedBox(
                          width: itemWidth,
                          height: 65,
                          child: Center(
                            child: AnimatedScale(
                              scale: isSelected ? 1.1 : 1.0,
                              duration: const Duration(milliseconds: 200),
                              child: IconTheme(
                                data: IconThemeData(
                                  color: isSelected
                                      ? accentColor
                                      : Colors.white.withOpacity(0.5),
                                  size: 26,
                                ),
                                child: isSelected 
                                    ? (item.activeIcon ?? item.icon) 
                                    : item.icon,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
