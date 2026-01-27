// import 'package:cached_network_image/cached_network_image.dart'; // Commented out
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui'; // For ImageFilter
import 'package:google_fonts/google_fonts.dart'; // For GoogleFonts
import '../providers/music_provider.dart';
import '../now_playing_screen.dart'; // Ensure this is the updated NowPlayingScreen

class MiniPlayer extends StatelessWidget {
  final VoidCallback? onExpand;
  const MiniPlayer({this.onExpand, super.key});

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
             if (onExpand != null) {
               onExpand!();
             } else {
                // Fallback (though MainScreen should always provide callback)
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => NowPlayingScreen(track: currentTrack),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      const begin = Offset(0.0, 1.0);
                      const end = Offset.zero;
                      const curve = Curves.easeOutQuad;
                      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                      return SlideTransition(
                        position: animation.drive(tween),
                        child: child,
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 300),
                  ),
                );
             }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 8.0), // Floating pill - narrower
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withOpacity(0.85), // Liquid dark glass
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                 BoxShadow(
                   color: Colors.black.withOpacity(0.4),
                   blurRadius: 15,
                   offset: const Offset(0, 5),
                 )
              ],
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), // Liquid blur effect
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end, 
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0), // Increased inner padding
                        child: Row(
                          children: [
                            // Album Art
                            Hero(
                              tag: 'currentArtwork',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8), // Less rounded for compact look
                                child: currentTrack.albumArtUrl.isNotEmpty
                                    ? Image.network( 
                                        currentTrack.albumArtUrl,
                                        width: 40, 
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_,__,___) => Container(width: 40, height: 40, color: Colors.grey[900]),
                                      )
                                    : Container(width: 40, height: 40, color: Colors.grey[900]),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    currentTrack.trackName,
                                    style: GoogleFonts.splineSans(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    currentTrack.artistName,
                                    style: GoogleFonts.splineSans(color: Colors.white.withOpacity(0.6), fontSize: 11),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Play/Pause
                            IconButton(
                              icon: Icon(
                                musicProvider.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 30, // Restored size
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                if (musicProvider.isPlaying) {
                                  musicProvider.pauseTrack();
                                } else {
                                  musicProvider.resumeTrack();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Progress Bar (Dynamic Color)
                    StreamBuilder<Duration>(
                      stream: musicProvider.positionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? Duration.zero;
                        final duration = musicProvider.duration;
                        double progress = 0.0;
                        if (duration.inSeconds > 0) {
                          progress = (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0);
                        }
                        // Dynamic Color
                        final dynamicColor = musicProvider.paletteGenerator?.dominantColor?.color ?? const Color(0xFFFF1744);
                        
                        return SizedBox(
                          height: 3, 
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.transparent, 
                            valueColor: AlwaysStoppedAnimation<Color>(dynamicColor),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
