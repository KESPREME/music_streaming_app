import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../screens/themed_now_playing_screen.dart';
import '../utils/color_utils.dart';
import '../utils/app_image_cache.dart';
import 'covered_gate.dart';
import 'seek_zone.dart';
import 'track_swap.dart';

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

/// The pill's hairline progress bar.
///
/// Its own widget so the cover flag (see [CoveredScope]) rebuilds this and
/// nothing else. While the open player sits on top, the pill is not drawn, and
/// listening to the position would rebuild a bar nobody can see five times a
/// second; unsubscribing keeps the last value, and it catches up on the first
/// reading after the pill is uncovered.
class _PillProgress extends StatelessWidget {
  const _PillProgress({
    required this.musicProvider,
    required this.accent,
    required this.radius,
  });

  final MusicProvider musicProvider;
  final Color accent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final covered = CoveredScope.of(context);
    return StreamBuilder<Duration>(
      stream: covered ? null : musicProvider.positionStream,
      initialData: musicProvider.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = musicProvider.duration;
        double progress = 0.0;
        if (duration.inSeconds > 0) {
          progress = (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0);
        }

        // The same transition zone as the player's scrubber: the last stretch
        // is tinted, and the fill is dyed as it passes through.
        return SeekZoneHost(
          upcoming: musicProvider.upcomingMix,
          ui: musicProvider.transitionState,
          totalMs: duration.inMilliseconds,
          mixColor: accent,
          builder: (context, zone) => SizedBox(
            height: 2,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(radius),
              ),
              child: CustomPaint(
                painter: _HairlinePainter(
                  progress: progress,
                  fill: Color.lerp(Colors.white, accent, 0.75)!,
                  zone: zone,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The pill's 2 px progress line: an empty track, the transition's stretch of
/// it, and the played fill (dyed across that stretch).
class _HairlinePainter extends CustomPainter {
  _HairlinePainter({
    required this.progress,
    required this.fill,
    required this.zone,
  }) : super(repaint: zone.repaint);

  final double progress;
  final Color fill;
  final SeekZoneFrame zone;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Offset.zero & size;
    canvas.drawRect(track, Paint()..color = Colors.white.withValues(alpha: 0.07));
    SeekZonePaint.under(canvas, track, zone);
    if (progress > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * progress, size.height),
        SeekZonePaint.fillPaint(track, zone, fill),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HairlinePainter old) =>
      old.progress != progress || old.fill != fill || old.zone != zone;
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
    try {
      Provider.of<MusicProvider>(context, listen: false).setPlayerExpanded(true);
      return;
    } catch (_) {}
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

    final placement = lgw.GlassTabBarAccessoryPlacementScope.of(context);
    final isInline = placement == lgw.GlassTabBarAccessoryPlacement.inline;
    final isHostedInTabBar = placement != null;

    final outerPadding = isHostedInTabBar
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(horizontal: 16.0);
    const double pillRadius = 26.0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: isHostedInTabBar ? 1.0 : 0.0, end: 1.0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child),
      ),
      child: Padding(
        padding: outerPadding,
        child: _PressSquish(
          onTap: () => _openFullPlayer(context),
          onHorizontalDragEnd: (details) {
            final vel = details.primaryVelocity;
            if (vel != null) {
              if (vel < -200) {
                musicProvider.skipToNext();
              } else if (vel > 200) {
                musicProvider.skipToPrevious();
              }
            }
          },
          onVerticalDragEnd: (details) {
            final vel = details.primaryVelocity;
            if (vel != null && vel < -200) {
              _openFullPlayer(context);
            }
          },
          child: SizedBox(
            height: 52.0, // Aligns with 52dp tab and search circle height
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
                  key: const ValueKey('mini_player_lens'),
                  style: LiquidGlassStyle(
                    shape: LiquidGlassShape.continuousRoundedRectangle(
                      cornerRadius: pillRadius,
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
                      borderRadius: BorderRadius.circular(pillRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(pillRadius),
                      child: Stack(
                        children: [
                          // ── Soft Color Flowing & Leaking ──
                          // 1. Soft radial bloom leaking from album art on the left
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(pillRadius),
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
                                borderRadius: BorderRadius.circular(pillRadius),
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
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                  child: isInline
                                      ? _buildInlineContent(
                                          currentTrack, musicProvider)
                                      : _buildExpandedContent(
                                          currentTrack, musicProvider),
                                ),
                              ),

                              // Thin bottom progress bar (only in expanded mode)
                              if (!isInline)
                                RepaintBoundary(
                                  child: _PillProgress(
                                    musicProvider: musicProvider,
                                    accent: activeVibrant,
                                    radius: pillRadius,
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

  Widget _buildInlineContent(Track currentTrack, MusicProvider musicProvider) {
    return Padding(
      key: const ValueKey('mini_inline_content'),
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          // Compact 32x32 rounded album art thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: currentTrack.albumArtUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: currentTrack.albumArtUrl,
                    width: 32,
                    height: 32,
                    memCacheWidth: AppImageCache.thumbnailMemCache,
                    memCacheHeight: AppImageCache.thumbnailMemCache,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    errorWidget: (_, __, ___) => Container(
                      width: 32,
                      height: 32,
                      color: Colors.grey[900],
                    ),
                  )
                : Container(
                    width: 32,
                    height: 32,
                    color: Colors.grey[900],
                  ),
          ),
          const SizedBox(width: 8),

          // Track title only (bold, Plus Jakarta Sans, single line with ellipsis)
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TrackTextSwap(
                identity: currentTrack.id,
                child: Text(
                  currentTrack.trackName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.0,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Play / Pause button
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
                size: 28,
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
        ],
      ),
    );
  }

  Widget _buildExpandedContent(Track currentTrack, MusicProvider musicProvider) {
    return Padding(
      key: const ValueKey('mini_expanded_content'),
      padding: const EdgeInsets.only(
        left: 10.0,
        right: 8.0,
      ),
      child: Row(
        children: [
          // Rounded album art thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10.0),
            child: currentTrack.albumArtUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: currentTrack.albumArtUrl,
                    width: 36,
                    height: 36,
                    memCacheWidth: AppImageCache.thumbnailMemCache,
                    memCacheHeight: AppImageCache.thumbnailMemCache,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    errorWidget: (_, __, ___) => Container(
                      width: 36,
                      height: 36,
                      color: Colors.grey[900],
                    ),
                  )
                : Container(
                    width: 36,
                    height: 36,
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
                TrackTextSwap(
                  identity: currentTrack.id,
                  child: Text(
                    currentTrack.trackName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 1),
                TrackTextSwap(
                  identity: currentTrack.id,
                  lag: 0.18,
                  child: Text(
                    currentTrack.artistName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Inline Controls: Previous, Play/Pause, Next
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: 'Previous track',
                button: true,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(
                    Icons.skip_previous_rounded,
                    color: Colors.white,
                    size: 22,
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
                    size: 28,
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
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(
                    Icons.skip_next_rounded,
                    color: Colors.white,
                    size: 22,
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
    );
  }
}

/// Scale-to-0.97 while pressed; springs back on release.
class _PressSquish extends StatefulWidget {
  const _PressSquish({
    required this.onTap,
    required this.onHorizontalDragEnd,
    this.onVerticalDragEnd,
    required this.child,
  });

  final VoidCallback onTap;
  final GestureDragEndCallback onHorizontalDragEnd;
  final GestureDragEndCallback? onVerticalDragEnd;
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
      onVerticalDragEnd: widget.onVerticalDragEnd,
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

