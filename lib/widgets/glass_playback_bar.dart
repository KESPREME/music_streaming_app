import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import 'glass_options_sheet.dart';
import 'wavy_progress_bar.dart';

class GlassPlaybackBar extends StatelessWidget {
  final Track track;
  final MusicProvider provider;
  final Color accentColor;

  const GlassPlaybackBar({
    super.key,
    required this.track,
    required this.provider,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final position = provider.position;
    final duration = provider.duration;
    
    if (!provider.isMiniPlayerVisible) return const SizedBox.shrink();

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), // Extra bottom padding for safe area
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.15), // Dynamic glass tint
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accentColor.withOpacity(0.05),
                Colors.black.withOpacity(0.6),
              ],
            ),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.1), width: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Wavy Progress Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: WavyProgressBar(
                   provider: provider,
                   accentColor: accentColor,
                ),
              ),
              
              const SizedBox(height: 4),
              
              // 2. Control Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Share
                  IconButton(
                    icon: const Icon(Icons.share_outlined, color: Colors.white70),
                    onPressed: () {
                       Share.share('Listening to ${track.trackName} by ${track.artistName}');
                    },
                  ),
                  
                  // Playback Controls
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildGlassControlButton(
                        icon: Icons.skip_previous_rounded,
                        onPressed: provider.skipToPrevious,
                      ),
                      const SizedBox(width: 20),
                      
                      // Play/Pause Liquid Button
                      Container(
                        height: 64, width: 64, // Slightly larger
                        decoration: BoxDecoration(
                           shape: BoxShape.circle,
                           gradient: LinearGradient(
                             begin: Alignment.topLeft,
                             end: Alignment.bottomRight,
                             colors: [
                               accentColor.withOpacity(0.9),
                               accentColor.withOpacity(0.5),
                             ]
                           ),
                           boxShadow: [
                             BoxShadow(color: accentColor.withOpacity(0.4), blurRadius: 25, spreadRadius: -2)
                           ],
                           border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                        ),
                        child: IconButton(
                          icon: Icon(
                            provider.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white, // White icon on colored button
                            size: 36
                          ),
                          onPressed: () {
                             if (provider.isPlaying) provider.pauseTrack(); else provider.resumeTrack();
                          },
                        ),
                      ),
                      
                      const SizedBox(width: 20),
                      _buildGlassControlButton(
                        icon: Icons.skip_next_rounded,
                        onPressed: provider.skipToNext,
                      ),
                    ],
                  ),
                  
                  // Options
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                    onPressed: () {
                       showModalBottomSheet(
                         context: context,
                         backgroundColor: Colors.transparent,
                         builder: (_) => GlassOptionsSheet(track: track),
                       );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildGlassControlButton({required IconData icon, required VoidCallback onPressed}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 48, width: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 28),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}
