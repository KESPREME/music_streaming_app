import 'package:flutter/material.dart';
import '../../theme/app_font.dart';
import '../../utils/artwork_palette_resolver.dart';

/// Row of stat chips for artist header matching BitChord ArtistStatsRow.
/// Formats counts using 'it.substringBefore(' ')' to prevent 'monthly audience' overflow.
class ArtistStatsRow extends StatelessWidget {
  final String? subscriberCountText;
  final String? monthlyListenerCount;
  final ArtworkPalette? palette;

  const ArtistStatsRow({
    super.key,
    this.subscriberCountText,
    this.monthlyListenerCount,
    this.palette,
  });

  @override
  Widget build(BuildContext context) {
    if (subscriberCountText == null && monthlyListenerCount == null) {
      return const SizedBox.shrink();
    }

    final formattedSubs = _formatSubscribers(subscriberCountText);
    final formattedListeners = _formatMonthlyListeners(monthlyListenerCount);

    if (formattedSubs == null && formattedListeners == null) {
      return const SizedBox.shrink();
    }

    final onVariant = palette?.onBackgroundVariant ?? Colors.white.withValues(alpha: 0.80);
    final chipBg = palette != null
        ? Color.alphaBlend(palette!.elevated.withValues(alpha: 0.32), const Color(0xFF23201E))
        : const Color(0xFF23201E);
    final chipBorder = Colors.white.withValues(alpha: 0.08);

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16.0, end: 16.0, bottom: 14.0),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (formattedSubs != null)
                _buildStatChip(
                  icon: Icons.person_rounded,
                  text: formattedSubs,
                  bgColor: chipBg,
                  borderColor: chipBorder,
                  textColor: onVariant,
                ),
              if (formattedSubs != null && formattedListeners != null)
                const SizedBox(width: 8),
              if (formattedListeners != null)
                _buildStatChip(
                  icon: Icons.graphic_eq_rounded,
                  text: formattedListeners,
                  bgColor: chipBg,
                  borderColor: chipBorder,
                  textColor: onVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _formatSubscribers(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final count = raw.trim().split(' ').first;
    return '$count subscribers';
  }

  String? _formatMonthlyListeners(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final count = raw.trim().split(' ').first;
    return '$count monthly listeners';
  }

  Widget _buildStatChip({
    required IconData icon,
    required String text,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: bgColor,
        border: Border.all(
          color: borderColor,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: textColor,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppFont.style(
              color: textColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
