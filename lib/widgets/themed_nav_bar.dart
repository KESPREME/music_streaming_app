import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'glass_nav_bar.dart';
import 'material_you_nav_bar.dart';

/// Theme-aware navigation bar wrapper.
/// Glass mode supports the in-pill search morph (Muzo-style); Material You
/// keeps the classic bar and ignores search params.
class ThemedNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavigationBarItem> items;

  final bool searchMode;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String>? onSearchSubmitted;

  const ThemedNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.searchMode = false,
    this.searchController,
    this.searchFocusNode,
    this.onSearchSubmitted,
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
            searchMode: searchMode,
            searchController: searchController,
            searchFocusNode: searchFocusNode,
            onSearchSubmitted: onSearchSubmitted,
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
