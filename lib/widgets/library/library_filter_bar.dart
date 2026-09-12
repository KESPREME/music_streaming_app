import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../glass_circle_button.dart';
import '../glass_surface.dart';

enum LibrarySortOption {
  recentlyAdded('Recently Added', Icons.access_time_rounded),
  alphabetical('Alphabetical (A-Z)', Icons.sort_by_alpha_rounded),
  trackCount('Most Tracks', Icons.format_list_numbered_rounded);

  const LibrarySortOption(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Filter control & companion sort button for LibraryScreen.
///
/// Refined iOS-grade liquid glass material behavior:
/// - Dark, translucent outer capsule with hairline border.
/// - Restrained active glass indicator (quiet, tactile frosted pill without
///   bright silver sheen or neon glow).
/// - Quiet inactive labels and companion sort button sharing one material system.
class LibraryFilterBar extends StatelessWidget {
  const LibraryFilterBar({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.currentSort,
    required this.onSortChanged,
  });

  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final LibrarySortOption currentSort;
  final ValueChanged<LibrarySortOption> onSortChanged;

  static const List<String> categories = [
    'All',
    'Playlists',
    'Artists',
    'Albums',
  ];

  void _showSortSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => GlassSurface(
        tier: GlassTier.chrome,
        borderRadius: 24,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Sort by',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                for (final option in LibrarySortOption.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      option.icon,
                      color: currentSort == option
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.55),
                      size: 22,
                    ),
                    title: Text(
                      option.label,
                      style: GoogleFonts.plusJakartaSans(
                        color: currentSort == option
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.75),
                        fontWeight: currentSort == option
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 14.5,
                      ),
                    ),
                    trailing: currentSort == option
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 20,
                          )
                        : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(sheetContext);
                      onSortChanged(option);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        children: [
          // Segmented Liquid Glass Capsule
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(3.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04), // Darker, translucent
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07), // Thin hairline
                  width: 0.6,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final segmentWidth = constraints.maxWidth / categories.length;
                  final selectedIndex =
                      categories.indexOf(selectedCategory).clamp(0, categories.length - 1);

                  return Stack(
                    children: [
                      // Smooth sliding active glass indicator (Restrained frosted pill)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        left: segmentWidth * selectedIndex,
                        top: 0,
                        width: segmentWidth,
                        height: constraints.maxHeight,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.18),
                                Colors.white.withValues(alpha: 0.07),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.20),
                              width: 0.6,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.28),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Text Segments Row
                      Row(
                        children: [
                          for (int i = 0; i < categories.length; i++)
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  onCategorySelected(categories[i]);
                                },
                                child: Center(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 160),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: selectedCategory == categories[i]
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: selectedCategory == categories[i]
                                          ? Colors.white
                                          : const Color(0xFF7E8492),
                                    ),
                                    child: Text(
                                      categories[i],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Companion Sort Button (Integrated material)
          GlassCircleButton(
            icon: Icons.swap_vert_rounded,
            size: 44,
            iconSize: 20,
            onTap: () => _showSortSheet(context),
            semanticLabel: 'Sort library items',
          ),
        ],
      ),
    );
  }
}
