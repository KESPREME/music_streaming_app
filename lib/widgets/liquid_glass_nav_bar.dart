import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import '../design/tokens/type.dart' as type_tokens;

/// Continuous liquid-glass navigation platter (liquid_glass_widgets
/// [lgw.GlassTabBar.searchable]).
///
/// One glass surface hosts all tabs; the selected item is a physical
/// magic-lens indicator that springs between tabs (jelly physics,
/// deformation on travel, settle overshoot). The companion search pill
/// morphs into a live text field — replacing the old hand-rolled
/// GlassNavBar droplet/morph implementation.
class LiquidGlassNavBar extends StatelessWidget {
  const LiquidGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.searchMode,
    this.onSearchToggle,
    this.searchController,
    this.searchFocusNode,
    this.onSearchSubmitted,
    this.onSearchCancel,
  });

  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavigationBarItem> items;

  final bool searchMode;
  final ValueChanged<bool>? onSearchToggle;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onSearchCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return lgw.GlassTabBar.searchable(
      // The bar is the single glass platter; no nested glass children.
      enableBlend: false,
      spacing: 0,
      horizontalPadding: 16,
      verticalPadding: 12,
      barHeight: 64,
      tabs: [
        for (final item in items)
          lgw.GlassTab(
            icon: item.icon,
            activeIcon: item.activeIcon,
            label: item.label,
          ),
      ],
      selectedIndex: currentIndex,
      onTabSelected: onTap,
      isSearchActive: searchMode,
      searchConfig: lgw.GlassSearchBarConfig(
        hintText: 'Search songs, artists...',
        hintStyle: type_tokens.Type.searchHint(context),
        controller: searchController,
        focusNode: searchFocusNode,
        // cupertino_icons isn't a dependency, so the library's default
        // CupertinoIcons.search renders as a missing-glyph box. Supply
        // Material icons explicitly for both the collapsed pill and the
        // expanded field prefix.
        searchIcon: const Icon(Icons.search_rounded, size: 22),
        onSearchToggle: (active) => onSearchToggle?.call(active),
        onSubmitted: (query) {
          searchFocusNode?.unfocus();
          onSearchSubmitted?.call(query);
        },
        // Clear (x) chip inside the expanded search pill while typing.
        trailingBuilder: (ctx) => ValueListenableBuilder<TextEditingValue>(
          valueListenable: searchController ?? TextEditingController(),
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () {
                searchController?.clear();
                searchFocusNode?.requestFocus();
              },
              child: Icon(Icons.cancel_rounded,
                  size: 18,
                  color: scheme.onSurface.withValues(alpha: 0.4)),
            );
          },
        ),
        onCancelTap: onSearchCancel,
        textColor: scheme.onSurface,
        cursorColor: scheme.primary,
        autoFocusOnExpand: false,
      ),
    );
  }
}
