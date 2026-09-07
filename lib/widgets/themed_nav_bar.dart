import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'liquid_glass_nav_bar.dart';
import 'material_you_nav_bar.dart';

/// Theme-aware navigation bar wrapper.
/// Glass mode = continuous liquid-glass platter with minimizable dock on scroll
/// and morphing search pill. Material You keeps the classic bar.
class ThemedNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavigationBarItem> items;

  final bool searchMode;
  final ValueChanged<bool>? onSearchToggle;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onSearchCancel;

  final lgw.GlassTabBarMinimizeController? minimizeController;
  final VoidCallback? onMinimizedTabTap;
  final VoidCallback? onExpandPlayer;

  const ThemedNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.searchMode = false,
    this.onSearchToggle,
    this.searchController,
    this.searchFocusNode,
    this.onSearchSubmitted,
    this.onSearchCancel,
    this.minimizeController,
    this.onMinimizedTabTap,
    this.onExpandPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        if (themeProvider.isGlassmorphism) {
          return LiquidGlassNavBar(
            currentIndex: currentIndex,
            onTap: onTap,
            items: items,
            searchMode: searchMode,
            minimizeController: minimizeController,
            onMinimizedTabTap: onMinimizedTabTap,
            onExpandPlayer: onExpandPlayer,
            onSearchToggle: onSearchToggle,
            searchController: searchController,
            searchFocusNode: searchFocusNode,
            onSearchSubmitted: onSearchSubmitted,
            onSearchCancel: onSearchCancel,
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

