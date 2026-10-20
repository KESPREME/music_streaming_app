import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'package:provider/provider.dart';

import '../theme/app_font.dart';
import '../design/glass/glass_surface.dart';
import '../providers/music_provider.dart';
import '../utils/color_utils.dart';
import 'animated_equalizer_icon.dart';
import 'jelly_press.dart';
import 'glass_circle_button.dart';

/// Muzo-parity glass pills for Search: scope segmented, filter chips, dock.
enum SearchScope { mineMusic, library }

/// Reference mauve-taupe both selected pills are made of.
const Color muzoMauve = Color(0xFF6E5B62);

/// Pill accent following the bottom nav bar's language: vibrant color pulled
/// off the current track's artwork palette, falling back to [muzoMauve]
/// (so top nav and bottom nav always speak the same accent).
Color searchPillAccentOf(BuildContext context) {
  try {
    final p = Provider.of<MusicProvider>(context, listen: true);
    return ColorUtils.getVibrantAccent(p.paletteGenerator, muzoMauve);
  } catch (_) {
    return muzoMauve;
  }
}

/// Press interaction shared by search pills: the house jelly (compress, lean
/// after the finger, wobble on release) + one selection tick.
class SearchPillPressable extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const SearchPillPressable({
    super.key,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) =>
      JellyPress(profile: JellyProfile.pill, onTap: onTap, child: child);
}

/// Mine Music | Library segmented control with authentic liquid glass optics,
/// organic squash/stretch, spring overshoot, and companion equalizer button.
///
/// Mirrors the bottom nav bar's [lgw.GlassTabBar] indicator physics and token
/// layers.
class SearchScopeSegmented extends StatelessWidget {
  final SearchScope scope;
  final ValueChanged<SearchScope> onChanged;

  /// Pill fill; defaults to [muzoMauve], pass the palette accent to speak
  /// the bottom nav's language.
  final Color accent;

  /// Optional tap handler for the companion equalizer button. Defaults
  /// to expanding the mini player if music is active.
  final VoidCallback? onEqualizerTap;

  const SearchScopeSegmented({
    super.key,
    required this.scope,
    required this.onChanged,
    this.accent = muzoMauve,
    this.onEqualizerTap,
  });

  @override
  Widget build(BuildContext context) {
    final glassSettings = lgw.LiquidGlassSettings(
      thickness: 24,
      blur: 24,
      chromaticAberration: 0.04,
      lightIntensity: 0.85,
      refractiveIndex: 1.18,
      saturation: 1.15,
      ambientStrength: 0.9,
      glassColor: Color.lerp(
            const Color(0x0EFFFFFF),
            accent.withValues(alpha: 0.08),
            0.35,
          ) ??
          const Color(0x0EFFFFFF),
    );

    final indicatorSettings = lgw.LiquidGlassSettings(
      thickness: 22,
      blur: 0,
      chromaticAberration: 0.05,
      lightIntensity: 1.0,
      refractiveIndex: 1.12,
      ambientStrength: 1.0,
      ambientRim: 0.25,
      glassColor: accent.withValues(alpha: 0.28),
    );

    MusicProvider? musicProvider;
    try {
      musicProvider = Provider.of<MusicProvider>(context, listen: true);
    } catch (_) {
      // In isolated tests or previews without MusicProvider
    }
    final hasTrack = musicProvider?.currentTrack != null;
    final isPlaying = musicProvider?.isPlaying ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: lgw.GlassSegmentedControl(
              segments: const [
                lgw.GlassSegment(label: 'Mine Music'),
                lgw.GlassSegment(label: 'Library'),
              ],
              selectedIndex: scope == SearchScope.mineMusic ? 0 : 1,
              onSegmentSelected: (index) {
                final newScope = index == 0
                    ? SearchScope.mineMusic
                    : SearchScope.library;
                if (newScope != scope) onChanged(newScope);
              },
              height: 48,
              borderRadius: 9999,
              padding: const EdgeInsets.all(3),
              useOwnLayer: true,
              backgroundColor: const Color(0x18FFFFFF),
              indicatorColor: accent.withValues(alpha: 0.32),
              settings: glassSettings,
              indicatorSettings: indicatorSettings,
              indicatorPinchStrength: 0.45,
              indicatorExpansion:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              selectedTextStyle: AppFont.style(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              unselectedTextStyle: AppFont.style(
                color: Colors.white.withValues(alpha: 0.55),
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GlassCircleButton(
            size: 48,
            onTap: onEqualizerTap ??
                () {
                  if (hasTrack) {
                    musicProvider?.setPlayerExpanded(true);
                  }
                },
            child: AnimatedEqualizerIcon(
              isPlaying: isPlaying,
              color:
                  hasTrack ? accent : Colors.white.withValues(alpha: 0.6),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

/// Muzo filter chips: every chip a sleek liquid glass pill without harsh borders.
///
/// Selected chip is a warm mauve/accent lens with bold white text and soft glow;
/// the rest are sleek translucent dark glass pills (reference parity).
class SearchFilterChips extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelected;

  /// Selected-pill fill; defaults to [muzoMauve], pass the palette accent
  /// to speak the bottom nav's language.
  final Color accent;

  const SearchFilterChips({
    super.key,
    required this.labels,
    required this.index,
    required this.onSelected,
    this.accent = muzoMauve,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ScrollConfiguration(
        behavior: const MaterialScrollBehavior().copyWith(overscroll: false),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          physics: const BouncingScrollPhysics(),
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final selected = i == index;
            return SearchPillPressable(
              onTap: () {
                if (i != index) onSelected(i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9999),
                  gradient: selected
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: 0.42),
                            accent.withValues(alpha: 0.22),
                          ],
                        )
                      : null,
                  color: selected ? null : const Color(0x16FFFFFF),
                  border: Border.all(
                    color: selected
                        ? accent.withValues(alpha: 0.45)
                        : Colors.white.withValues(alpha: 0.12),
                    width: 0.8,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.24),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: AppFont.style(
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.65),
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14.5,
                    ),
                    child: Text(labels[i]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Floating-tier lens shell for the standalone search dock field.
class SearchDockShell extends StatelessWidget {
  final Widget child;

  const SearchDockShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tier: GlassTier.floating,
      borderRadius: 9999,
      child: child,
    );
  }
}
