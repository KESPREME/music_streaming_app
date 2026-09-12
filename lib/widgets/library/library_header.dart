import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../glass_circle_button.dart';

/// Top App Bar for the Library screen matching the Mine Music reference design.
///
/// Refined visual hierarchy:
/// - Understated brand lockup (23px mark, 16px text) acting as branding rather
///   than competing with the hero title.
/// - Clear foreground action buttons (+ and search) positioned with comfortable
///   touch targets and clean clearance.
class LibraryHeader extends StatelessWidget {
  const LibraryHeader({
    super.key,
    required this.onCreatePlaylist,
    required this.onSearchTap,
    this.horizontalPadding = 20.0,
  });

  final VoidCallback onCreatePlaylist;
  final VoidCallback onSearchTap;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 4, horizontalPadding, 4),
      child: Row(
        children: [
          // Mine Music Brand Lockup (Restrained optical weight)
          Semantics(
            header: true,
            label: 'Mine Music',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/mine_music_mark.png',
                  height: 23,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 8),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                    children: [
                      TextSpan(
                        text: 'Mine ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const TextSpan(
                        text: 'Music',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Action Buttons: + and Search (Clearly foregrounded, accessible 44px)
          GlassCircleButton(
            icon: Icons.add_rounded,
            size: 44,
            iconSize: 22,
            onTap: () {
              HapticFeedback.lightImpact();
              onCreatePlaylist();
            },
            semanticLabel: 'Create playlist',
          ),
          const SizedBox(width: 8),
          GlassCircleButton(
            icon: Icons.search_rounded,
            size: 44,
            iconSize: 20,
            onTap: () {
              HapticFeedback.lightImpact();
              onSearchTap();
            },
            semanticLabel: 'Search library',
          ),
        ],
      ),
    );
  }
}
