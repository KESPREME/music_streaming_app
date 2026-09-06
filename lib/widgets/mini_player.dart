import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../providers/music_provider.dart';
import '../screens/themed_now_playing_screen.dart';
import '../utils/color_utils.dart';

/// Floating liquid-glass mini player matching Muzo sizing (Image 2)
/// with Previous, Play/Pause, Next inline controls and soft dynamic
/// album-art color leakage (Image 3).
class MiniPlayer extends StatelessWidget {
  final VoidCallback? onExpand;
  const MiniPlayer({this.onExpand, super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final currentTrack = musicProvider.currentTrack;

        if (currentTrack == null) {
          return const SizedBox.shrink();
        }

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
    final theme = Theme.of(context);
    final palette = musicProvider.paletteGenerator;
    final vibrantColor = ColorUtils.getVibrantAccent(palette, theme.colorScheme.primary);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: _PressSquish(
          onTap: () => _openFullPlayer(context),
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity! < -200) {
              musicProvider.skipToNext();
            } else if (details.primaryVelocity! > 200) {
              musicProvider.skipToPrevious();
            }
          },
          child: SizedBox(
            height: 56.0, // Muzo sizing: sleek compact 56dp pill height (Image 2)
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                begin: vibrantColor,
                end: vibrantColor,
              ),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              builder: (context, animColor, _) {
                final activeVibrant = animColor ?? vibrantColor;
                return LiquidGlassLens(
                  style: LiquidGlassStyle(
                    shape: LiquidGlassShape.continuousRoundedRectangle(
                      cornerRadius: 28.0,
                      borderWidth: 0.85,
                      borderColor: Color.lerp(
                        Colors.white.withValues(alpha: 0.18),
                        activeVibrant,
                        0.22,
                      ),
                      lightDirection: 135.0,
                      lightIntensity: 1.15,
                    ),
                    appearance: const LiquidGlassAppearance(
                      // Transparent smoked glass tint so background content is visible
                      color: Color(0x14FFFFFF),
                      blur: LiquidGlassBlur(sigmaX: 16, sigmaY: 16),
                      saturation: 1.15,
                    ),
                    refraction: const LiquidGlassRefraction(
                      distortion: 0.08,
                      distortionWidth: 24,
                      magnification: 1.02,
                      chromaticAberration: 0.002,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28.0),
                      child: Stack(
                        children: [
                          // ── Soft Color Flowing & Leaking (Image 3) ──
                          // 1. Soft radial bloom leaking from album art on the left
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                gradient: RadialGradient(
                                  center: const Alignment(-0.85, -0.2),
                                  radius: 1.45,
                                  colors: [
                                    activeVibrant.withValues(alpha: 0.28),
                                    activeVibrant.withValues(alpha: 0.14),
                                    activeVibrant.withValues(alpha: 0.04),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.32, 0.68, 1.0],
                                ),
                              ),
                            ),
                          ),

                          // 2. Soft horizontal ambient wash bleeding across pill
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    activeVibrant.withValues(alpha: 0.12),
                                    activeVibrant.withValues(alpha: 0.03),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.40, 0.85],
                                ),
                              ),
                            ),
                          ),

                          // ── Pill Content (Artwork + Metadata + Controls) ──
                              Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 10.0,
                                        right: 8.0,
                                      ),
                                      child: Row(
                                        children: [
                                          // Compact rounded album art thumbnail (Image 2)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(10.0),
                                            child: currentTrack.albumArtUrl.isNotEmpty
                                                ? CachedNetworkImage(
                                                    imageUrl: currentTrack.albumArtUrl,
                                                    width: 38,
                                                    height: 38,
                                                    fit: BoxFit.cover,
                                                    fadeInDuration: const Duration(milliseconds: 150),
                                                    errorWidget: (_, __, ___) => Container(
                                                      width: 38,
                                                      height: 38,
                                                      color: Colors.grey[900],
                                                    ),
                                                  )
                                                : Container(
                                                    width: 38,
                                                    height: 38,
                                                    color: Colors.grey[900],
                                                  ),
                                          ),
                                          const SizedBox(width: 10),

                                          // Track title & artist in Plus Jakarta Sans
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  currentTrack.trackName,
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 14.0,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                    letterSpacing: -0.2,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  currentTrack.artistName,
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 12.0,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.white.withValues(alpha: 0.65),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Inline Controls: Previous, Play/Pause, Next (Image 2)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Semantics(
                                                label: 'Previous track',
                                                button: true,
                                                child: IconButton(
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(
                                                    minWidth: 34,
                                                    minHeight: 34,
                                                  ),
                                                  icon: const Icon(
                                                    Icons.skip_previous_rounded,
                                                    color: Colors.white,
                                                    size: 24,
                                                  ),
                                                  onPressed: () {
                                                    HapticFeedback.selectionClick();
                                                    musicProvider.skipToPrevious();
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 2),
                                              Semantics(
                                                label: musicProvider.isPlaying ? 'Pause' : 'Play',
                                                button: true,
                                                child: IconButton(
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(
                                                    minWidth: 36,
                                                    minHeight: 36,
                                                  ),
                                                  icon: Icon(
                                                    musicProvider.isPlaying
                                                        ? Icons.pause_rounded
                                                        : Icons.play_arrow_rounded,
                                                    color: Colors.white,
                                                    size: 30,
                                                  ),
                                                  onPressed: () {
                                                    HapticFeedback.selectionClick();
                                                    if (musicProvider.isPlaying) {
                                                      musicProvider.pauseTrack();
                                                    } else {
                                                      musicProvider.resumeTrack();
                                                    }
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 2),
                                              Semantics(
                                                label: 'Next track',
                                                button: true,
                                                child: IconButton(
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(
                                                    minWidth: 34,
                                                    minHeight: 34,
                                                  ),
                                                  icon: const Icon(
                                                    Icons.skip_next_rounded,
                                                    color: Colors.white,
                                                    size: 24,
                                                  ),
                                                  onPressed: () {
                                                    HapticFeedback.selectionClick();
                                                    musicProvider.skipToNext();
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Thin bottom progress bar tinted with album vibrant color
                                  RepaintBoundary(
                                    child: StreamBuilder<Duration>(
                                      stream: musicProvider.positionStream,
                                      builder: (context, snapshot) {
                                        final position = snapshot.data ?? Duration.zero;
                                        final duration = musicProvider.duration;
                                        double progress = 0.0;
                                        if (duration.inSeconds > 0) {
                                          progress = (position.inSeconds / duration.inSeconds)
                                              .clamp(0.0, 1.0);
                                        }

                                        return SizedBox(
                                          height: 2,
                                          child: ClipRRect(
                                            borderRadius: const BorderRadius.vertical(
                                              bottom: Radius.circular(28),
                                            ),
                                            child: LinearProgressIndicator(
                                              value: progress,
                                              backgroundColor: Colors.white.withValues(alpha: 0.07),
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                Color.lerp(
                                                  Colors.white,
                                                  activeVibrant,
                                                  0.75,
                                                )!,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
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
