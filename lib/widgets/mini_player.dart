import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/music_provider.dart';
import '../screens/themed_now_playing_screen.dart'; // Use themed wrapper
import '../utils/color_utils.dart';
import 'glass_surface.dart';

/// Floating liquid-glass mini player.
///
/// Motion contract (transform/opacity only):
/// - Entrance: slide-up + fade, plays once when a track starts.
/// - Press: 0.97 squish while the finger is down.
class MiniPlayer extends StatelessWidget {
  final VoidCallback? onExpand;
  const MiniPlayer({this.onExpand, super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final currentTrack = musicProvider.currentTrack;

        if (currentTrack == null) {
          return const SizedBox.shrink(); // Don't show if no track is playing
        }

        // FIX: RepaintBoundary for smoother 120Hz performance
        return RepaintBoundary(
          child: _PillBody(musicProvider: musicProvider, onExpand: onExpand),
        );
      },
    );
  }
}

class _PillBody extends StatelessWidget {
  const _PillBody({required this.musicProvider, this.onExpand});

  final MusicProvider musicProvider;
  final VoidCallback? onExpand;

  void _openFullPlayer(BuildContext context) {
    final currentTrack = musicProvider.currentTrack;
    if (currentTrack == null) return;
    if (onExpand != null) {
      onExpand!();
      return;
    }
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ThemedNowPlayingScreen(track: currentTrack),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 280),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = musicProvider.currentTrack!;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child),
      ),
      child: _PressSquish(
        onTap: () => _openFullPlayer(context),
        onHorizontalDragEnd: (details) {
          // Sensitivity adjustment
          if (details.primaryVelocity! < -200) {
            // Swipe Left -> Next
            musicProvider.skipToNext();
          } else if (details.primaryVelocity! > 200) {
            // Swipe Right -> Prev
            musicProvider.skipToPrevious();
          }
        },
        child: GlassSurface(
          tier: GlassTier.chrome,
          borderRadius: 30,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0),
                  child: Row(
                    children: [
                      // Album Art
                      Hero(
                        tag: 'albumArt_${currentTrack.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: currentTrack.albumArtUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: currentTrack.albumArtUrl,
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                  fadeInDuration:
                                      const Duration(milliseconds: 200),
                                  errorWidget: (_, __, ___) => Container(
                                      width: 42,
                                      height: 42,
                                      color: Colors.grey[900]),
                                )
                              : Container(
                                  width: 42,
                                  height: 42,
                                  color: Colors.grey[900]),
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
                              style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              currentTrack.artistName,
                              style: GoogleFonts.outfit(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Play/Pause
                      IconButton(
                        icon: Icon(
                          musicProvider.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
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
              // Progress Bar - FIX: RepaintBoundary for independent repaints
              RepaintBoundary(
                child: StreamBuilder<Duration>(
                  stream: musicProvider.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final duration = musicProvider.duration;
                    double progress = 0.0;
                    if (duration.inSeconds > 0) {
                      progress =
                          (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0);
                    }
                    // Dynamic Color: album palette wins, falls back to live accent
                    final palette = musicProvider.paletteGenerator;
                    final dynamicColor = ColorUtils.getVibrantAccent(
                        palette, Theme.of(context).colorScheme.primary);

                    return SizedBox(
                      height: 2,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(dynamicColor),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scale-to-0.97 while pressed; springs back on release.
class _PressSquish extends StatefulWidget {
  const _PressSquish({
    required this.onTap,
    required this.onHorizontalDragEnd,
    required this.child,
  });

  final VoidCallback onTap;
  final GestureDragEndCallback onHorizontalDragEnd;
  final Widget child;

  @override
  State<_PressSquish> createState() => _PressSquishState();
}

class _PressSquishState extends State<_PressSquish> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onHorizontalDragEnd: widget.onHorizontalDragEnd,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
