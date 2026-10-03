import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'package:provider/provider.dart';

import '../design/tokens/type.dart' as type_tokens;
import '../providers/music_provider.dart';
import '../utils/color_utils.dart';
import 'mini_player.dart';

/// Continuous liquid-glass navigation platter (liquid_glass_widgets
/// [lgw.GlassTabBar.minimizable] / [lgw.GlassTabBar.searchable]).
///
/// One glass surface hosts all tabs; the selected item is a physical
/// magic-lens indicator that springs between tabs. On scroll down, the bar
/// minimizes into a single active tab circle on the left and standalone search
/// button on the right, while the [MiniPlayer] accessory smoothly animates down
/// and docks into the baseline gap between them.
class LiquidGlassNavBar extends StatelessWidget {
  const LiquidGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.searchMode,
    this.minimizeController,
    this.onMinimizedTabTap,
    this.onExpandPlayer,
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
  final lgw.GlassTabBarMinimizeController? minimizeController;
  final VoidCallback? onMinimizedTabTap;
  final VoidCallback? onExpandPlayer;
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
    final hasTrack = musicProvider?.currentTrack != null;
    final hideMiniPlayer = musicProvider?.hideMiniPlayer ?? false;
    // Deliberately NOT gated on isPlayerExpanded, even though the accessory is
    // fully covered once the player is open.
    //
    // Tempting, and wrong: the flag flips at the halfway point of the opening
    // flight, so gating on it reconfigures the glass bar - re-measuring it,
    // re-laying the tabs out and re-running its blur - in the middle of the
    // transition. Trading a permanently-visible widget for a relayout of the
    // most expensive widget in the app at the worst possible moment is a bad
    // bargain. Left alone.
    final bottomAccessoryEnabled = hasTrack && !hideMiniPlayer;

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(begin: targetAccent, end: targetAccent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, animatedAccent, child) {
        final albumAccent = animatedAccent ?? targetAccent;

        final tabs = [
          for (final item in items)
            lgw.GlassTab(
              icon: item.icon,
              activeIcon: item.activeIcon,
              label: item.label,
            ),
        ];

        final glassSettings = lgw.LiquidGlassSettings(
          thickness: 24,
          blur: 24,
          chromaticAberration: 0.04,
          lightIntensity: 0.85,
          refractiveIndex: 1.18,
          saturation: 1.15,
          ambientStrength: 0.9,
          glassColor: Color.lerp(const Color(0x0EFFFFFF), albumAccent.withValues(alpha: 0.08), 0.35) ?? const Color(0x0EFFFFFF),
        );

        final indicatorSettings = lgw.LiquidGlassSettings(
          thickness: 22,
          blur: 0,
          chromaticAberration: 0.05,
          lightIntensity: 1.0,
          refractiveIndex: 1.12,
          ambientStrength: 1.0,
          ambientRim: 0.25,
          glassColor: albumAccent.withValues(alpha: 0.16),
        );

        final accessory = MiniPlayer(onExpand: onExpandPlayer);

        if (searchMode) {
          return lgw.GlassTabBar.searchable(
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
            settings: glassSettings,
            indicatorSettings: indicatorSettings,
            tabs: tabs,
            selectedIndex: currentIndex,
            onTabSelected: onTap,
            isSearchActive: true,
            bottomAccessory: bottomAccessoryEnabled ? accessory : null,
            bottomAccessoryHeight: 52.0,
            bottomAccessorySpacing: 8.0,
            bottomAccessoryEnabled: bottomAccessoryEnabled,
            searchConfig: lgw.GlassSearchBarConfig(
              hintText: 'Search songs, artists...',
              hintStyle: type_tokens.Type.searchHint(context),
              controller: searchController,
              focusNode: searchFocusNode,
              searchIcon: const Icon(Icons.search_rounded, size: 22),
              cancelIcon: const Icon(Icons.search_rounded, size: 22, color: Colors.white),
              cancelIconSize: 22,
              onSearchToggle: (active) => onSearchToggle?.call(active),
              onSubmitted: (query) {
                searchFocusNode?.unfocus();
                onSearchSubmitted?.call(query);
              },
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
        }

        return lgw.GlassTabBar.minimizable(
          enableBlend: true,
          blendAmount: 12.0,
          spacing: 8.0,
          horizontalPadding: 16.0,
          verticalPadding: 9.0,
          barHeight: 62.0,
          minimizedBarHeight: 52.0,
          whitenAtBottom: false,
          indicatorExpansion: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          indicatorPinchStrength: 0.45,
          indicatorColor: albumAccent.withValues(alpha: 0.24),
          selectedIconColor: albumAccent,
          selectedLabelColor: albumAccent,
          unselectedIconColor: Colors.white.withValues(alpha: 0.65),
          unselectedLabelColor: Colors.white.withValues(alpha: 0.65),
          interactionGlowColor: albumAccent.withValues(alpha: 0.38),
          settings: glassSettings,
          indicatorSettings: indicatorSettings,
          tabs: tabs,
          selectedIndex: currentIndex,
          onTabSelected: onTap,
          minimizeController: bottomAccessoryEnabled ? minimizeController : null,
          onMinimizedTabTap: onMinimizedTabTap ?? () => minimizeController?.expand(),
          trailingButton: lgw.GlassTabBarTrailingButton(
            icon: const Icon(Icons.search_rounded, size: 22),
            onTap: () => onSearchToggle?.call(true),
          ),
          bottomAccessory: bottomAccessoryEnabled ? accessory : null,
          bottomAccessoryHeight: 52.0,
          bottomAccessorySpacing: 8.0,
          bottomAccessoryEnabled: bottomAccessoryEnabled,
        );
      },
    );
  }
}

