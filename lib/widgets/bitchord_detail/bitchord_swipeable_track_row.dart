import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../providers/music_provider.dart';
import '../../utils/artwork_palette_resolver.dart';

/// Swipeable track row matching BitChord DetailScreen onSwipeToQueue.
///
/// Swiping right reveals a liquid pill for "Play Next".
/// Swiping left reveals a liquid pill for "Add to Queue".
/// Crossing the threshold fires haptic feedback and executes the queue action,
/// springing smoothly back into place without dismissing the row.
class BitchordSwipeableTrackRow extends StatelessWidget {
  final Track track;
  final Widget child;
  final ArtworkPalette? palette;

  const BitchordSwipeableTrackRow({
    super.key,
    required this.track,
    required this.child,
    this.palette,
  });

  void _showFeedback(BuildContext context, String message, IconData icon, Color accent) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1400),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 90, left: 24, right: 24),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1C28).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.40),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectivePalette = palette ?? ArtworkPalette.defaultDark;
    final accent = effectivePalette.accent;

    return Dismissible(
      key: ValueKey('swipe_${track.id}_${track.trackName}_${track.artistName}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.35,
        DismissDirection.endToStart: 0.35,
      },
      confirmDismiss: (direction) async {
        HapticFeedback.lightImpact();
        final provider = context.read<MusicProvider>();

        if (direction == DismissDirection.startToEnd) {
          // Swipe Right: Play Next
          provider.playNext(track);
          if (context.mounted) {
            _showFeedback(
              context,
              'Playing next: ${track.trackName}',
              Icons.playlist_play_rounded,
              accent,
            );
          }
        } else {
          // Swipe Left: Add to Queue
          provider.addToQueue(track);
          if (context.mounted) {
            _showFeedback(
              context,
              'Added to queue: ${track.trackName}',
              Icons.queue_music_rounded,
              accent,
            );
          }
        }
        // Always return false so the row smoothly springs back
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        color: const Color(0xFF4A3E37), // Solid dark taupe block matching Screenshot 4
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.playlist_add_rounded,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              'Queue',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        color: const Color(0xFF4A3E37),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Queue',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.playlist_add_rounded,
              color: Colors.white,
              size: 24,
            ),
          ],
        ),
      ),
      child: child,
    );
  }
}
