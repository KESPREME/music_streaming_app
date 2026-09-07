import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Row of stat chips for artist header matching BitChord ArtistStatsRow
class ArtistStatsRow extends StatelessWidget {
  final String? subscriberCountText;
  final String? monthlyListenerCount;

  const ArtistStatsRow({
    super.key,
    this.subscriberCountText,
    this.monthlyListenerCount,
  });

  @override
  Widget build(BuildContext context) {
    if (subscriberCountText == null && monthlyListenerCount == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (subscriberCountText != null && subscriberCountText!.isNotEmpty)
            _buildStatChip(
              icon: Icons.person_rounded,
              text: subscriberCountText!,
            ),
          if (subscriberCountText != null &&
              subscriberCountText!.isNotEmpty &&
              monthlyListenerCount != null &&
              monthlyListenerCount!.isNotEmpty)
            const SizedBox(width: 8),
          if (monthlyListenerCount != null && monthlyListenerCount!.isNotEmpty)
            _buildStatChip(
              icon: Icons.graphic_eq_rounded,
              text: monthlyListenerCount!,
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: Colors.white.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
