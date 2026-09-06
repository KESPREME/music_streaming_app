import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'package:provider/provider.dart';

import '../design/tokens/type.dart' as type_tokens;
import '../providers/music_provider.dart';
import '../utils/color_utils.dart';

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

    MusicProvider? musicProvider;
    try {
      musicProvider = Provider.of<MusicProvider>(context, listen: true);
    } catch (_) {
      // In isolated tests without MusicProvider in context
    }
    final palette = musicProvider?.paletteGenerator;
    final targetAccent = ColorUtils.getVibrantAccent(palette, scheme.primary);

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(begin: targetAccent, end: targetAccent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, animatedAccent, child) {
        final albumAccent = animatedAccent ?? targetAccent;

        return lgw.GlassTabBar.searchable(
          // The bar is the single glass platter with liquid metaball blending to the search button.
          enableBlend: true,
          blendAmount: 12.0,
          spacing: 8.0,
          horizontalPadding: 16.0,
          verticalPadding: 9.0,
          barHeight: 62.0,
          searchBarHeight: 52.0,
          whitenAtBottom: false,
          indicatorExpansion: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          indicatorPinchStrength: 0.45,
          indicatorColor: albumAccent.withValues(alpha: 0.24),
          selectedIconColor: albumAccent,
          selectedLabelColor: albumAccent,
          unselectedIconColor: Colors.white.withValues(alpha: 0.65),
          unselectedLabelColor: Colors.white.withValues(alpha: 0.65),
          interactionGlowColor: albumAccent.withValues(alpha: 0.38),
          settings: lgw.LiquidGlassSettings(
            thickness: 24,
            blur: 24,
            chromaticAberration: 0.04,
            lightIntensity: 0.85,
            refractiveIndex: 1.18,
            saturation: 1.15,
            ambientStrength: 0.9,
            glassColor: Color.lerp(const Color(0x0EFFFFFF), albumAccent.withValues(alpha: 0.08), 0.35) ?? const Color(0x0EFFFFFF),
          ),
          indicatorSettings: lgw.LiquidGlassSettings(
            thickness: 22,
            blur: 0,
            chromaticAberration: 0.05,
            lightIntensity: 1.0,
            refractiveIndex: 1.12,
            ambientStrength: 1.0,
            ambientRim: 0.25,
            glassColor: albumAccent.withValues(alpha: 0.16),
          ),
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
            cursorColor: albumAccent,
            autoFocusOnExpand: false,
          ),
        );
      },
    );
  }
}
