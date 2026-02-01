import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'glass_nav_bar.dart';
import 'material_you_nav_bar.dart';

/// Theme-aware navigation bar wrapper
/// Conditionally renders GlassNavBar or MaterialYouNavBar based on theme
class ThemedNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavigationBarItem> items;

  const ThemedNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        if (themeProvider.isGlassmorphism) {
          return GlassNavBar(
            currentIndex: currentIndex,
            onTap: onTap,
            items: items,
          );
        } else {
          return MaterialYouNavBar(
            currentIndex: currentIndex,
            onTap: onTap,
            items: items,
          );
        }
      },
    );
  }
}
