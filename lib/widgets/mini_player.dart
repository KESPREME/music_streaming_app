// import 'package:cached_network_image/cached_network_image.dart'; // Commented out
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../now_playing_screen.dart'; // Ensure this is the updated NowPlayingScreen

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final currentTrack = musicProvider.currentTrack;

        if (currentTrack == null) {
          return const SizedBox.shrink(); // Don't show if no track is playing
        }

        return GestureDetector(
          onTap: () {
            // Navigate to the full NowPlayingScreen
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => NowPlayingScreen(track: currentTrack),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  const begin = Offset(0.0, 1.0);
                  const end = Offset.zero;
                  const curve = Curves.easeOutQuad; // Smoother curve
                  var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                  return SlideTransition(
                    position: animation.drive(tween),
                    child: child,
                  );
                },
                transitionDuration: const Duration(milliseconds: 300), // Faster transition
              ),
            ).then((_) {
              // Optional: Force rebuild if needed, though Provider should handle state updates
              // (context as Element).markNeedsBuild();
            });
          },
          child: Container(
            height: 65, // Slightly reduced height
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.95), // Use a slightly transparent surface color
              // No separate shadow needed if BottomNavigationBar below has elevation
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end, // Align progress bar to bottom of its space
              children: [
                // Player content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      children: [
                        // Album Art
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4.0),
                          child: currentTrack.albumArtUrl.isNotEmpty
                              ? Image.network( // Replaced CachedNetworkImage
                                  currentTrack.albumArtUrl,
                                  width: 48, // Standard size
                                  height: 48,
                                  cacheWidth: (48 * MediaQuery.of(context).devicePixelRatio).round(),
                                  cacheHeight: (48 * MediaQuery.of(context).devicePixelRatio).round(),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(width: 48, height: 48, color: theme.colorScheme.surface, child: Icon(Icons.broken_image, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(width: 48, height: 48, color: theme.colorScheme.surface, child: Center(child: CircularProgressIndicator(value: loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : null)));
                                  },
                                )
                              : Container(width: 48, height: 48, color: theme.colorScheme.surface, child: Icon(Icons.music_note, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                        ),
                        const SizedBox(width: 12),
                        // Track Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                currentTrack.trackName,
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currentTrack.artistName,
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Controls
                        IconButton(
                          icon: Icon(
                            musicProvider.isSongLiked(currentTrack.id) ? Icons.favorite : Icons.favorite_border,
                            color: musicProvider.isSongLiked(currentTrack.id) ? theme.colorScheme.primary : theme.iconTheme.color?.withOpacity(0.8),
                            size: 26,
                          ),
                          tooltip: musicProvider.isSongLiked(currentTrack.id) ? "Unlike" : "Like",
                          onPressed: () {
                            musicProvider.toggleLike(currentTrack);
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            musicProvider.isPlaying ? Icons.pause_circle_filled_outlined : Icons.play_circle_filled_outlined,
                            color: theme.iconTheme.color, // Uses primary color by default from IconTheme
                            size: 32, // Slightly larger main control
                          ),
                          tooltip: musicProvider.isPlaying ? "Pause" : "Play",
                          onPressed: () {
                            if (musicProvider.isPlaying) {
                              musicProvider.pauseTrack();
                            } else {
                              musicProvider.resumeTrack();
                            }
                          },
                        ),
                        // Removed Next button for a cleaner look, common in some modern UIs (Spotify mini player)
                        // If needed, it can be added back:
                        // IconButton(
                        //   icon: Icon(Icons.skip_next_outlined, color: theme.iconTheme.color?.withOpacity(0.8), size: 28),
                        //   onPressed: musicProvider.skipToNext,
                        //   tooltip: "Next",
                        // ),
                      ],
                    ),
                  ),
                ),
                // Progress bar at the very bottom of the MiniPlayer
                StreamBuilder<Duration>(
                  stream: musicProvider.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final duration = musicProvider.duration;
                    double progress = 0.0;
                    if (duration.inSeconds > 0) {
                      progress = (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0);
                    }
                    return SizedBox(
                      height: 2.5, // Thinner progress bar
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: theme.colorScheme.surfaceVariant, // Barely visible background
                        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
