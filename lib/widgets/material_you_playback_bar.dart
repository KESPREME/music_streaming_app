import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../theme/material_you_tokens.dart';
import 'material_you_progress_bar.dart';

/// Material You playback bar (mini player) - REDESIGNED
/// Features:
/// - Elevated surface above navigation
/// - Larger play button (56dp)
/// - Progress bar visible at top
/// - Swipe up gesture to expand
/// - NO blur, NO gradients - solid colors only
class MaterialYouPlaybackBar extends StatelessWidget {
  final Track track;
  final MusicProvider provider;
  final Color accentColor;

  const MaterialYouPlaybackBar({
    super.key,
    required this.track,
    required this.provider,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // Extract dynamic color from provider
    final palette = provider.paletteGenerator;
    final vibrantColor = palette?.vibrantColor?.color ?? MaterialYouTokens.primaryVibrant;

    if (!provider.isMiniPlayerVisible) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12), // Floating pill
      height: 72, // Fixed height for pill
      decoration: BoxDecoration(
        color: MaterialYouTokens.surfaceContainerDark, // Solid background
        borderRadius: BorderRadius.circular(36), // Fully rounded pill
        boxShadow: const [
           BoxShadow(
             color: Colors.black38, 
             blurRadius: 12, 
             offset: Offset(0, 4)
           ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(36),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity! < -200) { // Swipe Up
               provider.setPlayerExpanded(true);
            }
          },
          // Added Horizontal Swipe for Next/Prev
          onHorizontalDragEnd: (details) {
             if (details.primaryVelocity! < -200) { // Swipe Left -> Next
               provider.skipToNext();
             } else if (details.primaryVelocity! > 200) { // Swipe Right -> Prev
               provider.skipToPrevious();
             }
          },
          onTap: () {
            provider.setPlayerExpanded(true);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12), // Inner padding
            child: Row(
              children: [
                // Album Art (Circle or rounded rect inside pill)
                ClipRRect(
                  borderRadius: BorderRadius.circular(28), // Matches container curve radius roughly or circular
                  child: track.albumArtUrl.isNotEmpty
                      ? Image.network(
                          track.albumArtUrl,
                          width: 56, // Slightly larger art
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholderArt(colorScheme, vibrantColor),
                        )
                      : _buildPlaceholderArt(colorScheme, vibrantColor),
                ),
                
                const SizedBox(width: 16),
                
                // Track Info (Expanded to fix truncation)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.trackName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        track.artistName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: vibrantColor, // Dynamic color
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                       // Mini Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                           // Robust Duration Check: Use provider.duration if track.durationMs is missing
                           value: (provider.position.inMilliseconds / 
                                  ((track.durationMs != null && track.durationMs! > 0) 
                                      ? track.durationMs! 
                                      : (provider.duration.inMilliseconds > 0 ? provider.duration.inMilliseconds : 1)
                                  )).clamp(0.0, 1.0),
                           backgroundColor: colorScheme.onSurfaceVariant.withOpacity(0.1),
                           valueColor: AlwaysStoppedAnimation<Color>(vibrantColor),
                           minHeight: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // Play/Pause Button (Only one button)
                IconButton(
                  onPressed: () {
                    if (provider.isPlaying) {
                      provider.pauseTrack();
                    } else {
                      provider.resumeTrack();
                    }
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: vibrantColor, // Dynamic accent background
                    foregroundColor: Colors.white, // Icon color
                    fixedSize: const Size(56, 56), // Large circle
                    elevation: 0,
                  ),
                  icon: Icon(
                    provider.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 32,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderArt(ColorScheme colorScheme, Color vibrantColor) {
    return Container(
      width: 56, // Updated to match new Art size
      height: 56,
      decoration: BoxDecoration(
        color: vibrantColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: vibrantColor,
        size: 24,
      ),
    );
  }
}
