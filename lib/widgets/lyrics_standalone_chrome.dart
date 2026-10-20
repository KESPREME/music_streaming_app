// lib/widgets/lyrics_standalone_chrome.dart
// The chrome the lyrics screen wears when it is NOT inside the player: a blurred
// artwork background, a pull handle, a mini track header and a mini scrubber.
//
// Split out of `lyrics_screen.dart`, where it sat between the scroll logic and
// the list and made a 1700-line file nobody could hold in their head. Inside the
// player none of this is used (the player owns the header and the deck), so the
// embedded path never builds it.

import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_font.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../utils/app_image_cache.dart';
import '../utils/image_quality_utils.dart';
import 'audio_quality_language_sheet.dart';
import 'glass_options_sheet.dart';
import 'jelly_press.dart';
import 'thin_slider.dart';

/// Blurred artwork under a dark scrim.
class LyricsStandaloneBackground extends StatelessWidget {
  const LyricsStandaloneBackground({super.key, required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) {
    final track = this.track;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF08080A)),
        if (track != null && track.albumArtUrl.isNotEmpty)
          RepaintBoundary(
            child: ClipRect(
              child: Transform.scale(
                scale: 1.25,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 65, sigmaY: 65),
                  child: SizedBox.expand(child: _LyricsArt(track: track)),
                ),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.45),
                Colors.black.withValues(alpha: 0.65),
                Colors.black.withValues(alpha: 0.85),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

/// The grabber that minimises the screen.
class LyricsPullHandle extends StatelessWidget {
  const LyricsPullHandle({super.key, this.onMinimize});

  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        HapticFeedback.lightImpact();
        if (onMinimize != null) {
          onMinimize!();
        } else if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: Center(
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 6),
          width: 38,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
  }
}

/// Artwork thumbnail, title and artist, star, pronunciation and options.
class LyricsMiniHeader extends StatelessWidget {
  const LyricsMiniHeader({
    super.key,
    required this.track,
    required this.provider,
    required this.accentColor,
    required this.isEmbedded,
    this.onReturnToAlbum,
    this.onTabTap,
  });

  final Track track;
  final MusicProvider provider;
  final Color accentColor;
  final bool isEmbedded;
  final VoidCallback? onReturnToAlbum;
  final Function(int)? onTabTap;

  void _back() {
    HapticFeedback.lightImpact();
    if (onReturnToAlbum != null) {
      onReturnToAlbum!();
    } else if (onTabTap != null) {
      onTabTap!(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLiked = provider.isSongLiked(track.id);
    final topPadding =
        isEmbedded ? (MediaQuery.of(context).padding.top + 32.0) : 6.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            key: const ValueKey('now_playing_album_art'),
            behavior: HitTestBehavior.opaque,
            onTap: _back,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 46,
                height: 46,
                child: _LyricsArt(track: track),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _back,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.trackName,
                    style: AppFont.style(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artistName,
                    style: AppFont.style(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          _CircleButton(
            semanticLabel: 'Favorite',
            onTap: () {
              HapticFeedback.lightImpact();
              provider.toggleLike(track);
            },
            child: Icon(
              isLiked ? Icons.star_rounded : Icons.star_outline_rounded,
              color: isLiked ? accentColor : Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          _CircleButton(
            semanticLabel: 'Pronunciation',
            onTap: () {
              HapticFeedback.lightImpact();
              AudioQualityLanguageSheet.show(context);
            },
            child: Text(
              'a\u3042',
              style: AppFont.style(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _CircleButton(
            semanticLabel: 'Options',
            onTap: () {
              HapticFeedback.lightImpact();
              GlassOptionsSheet.show(context, track: track);
            },
            child: const Icon(
              Icons.more_vert_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

/// Play/pause, elapsed, scrubber, remaining, and a volume row.
class LyricsMiniScrubber extends StatelessWidget {
  const LyricsMiniScrubber({super.key, required this.provider});

  final MusicProvider provider;

  @override
  Widget build(BuildContext context) {
    final isPlaying = provider.isPlaying;

    return StreamBuilder<Duration>(
      stream: provider.positionStream,
      initialData: provider.position,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? provider.position;
        final dur = provider.duration;
        final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
        final fraction = (pos.inMilliseconds.toDouble() / maxMs).clamp(0.0, 1.0);
        final remaining = dur > pos ? dur - pos : Duration.zero;

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Semantics(
                    label: isPlaying ? 'Pause' : 'Play',
                    button: true,
                    child: JellyPress(
                      profile: JellyProfile.circle,
                      haptic: JellyHaptic.light,
                      onTap: () {
                        if (isPlaying) {
                          provider.pauseTrack();
                        } else {
                          provider.resumeTrack();
                        }
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _formatTime(pos),
                    style: _timeStyle,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ThinSlider(
                      value: fraction,
                      idleHeight: 7.0,
                      activeHeight: 12.0,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white.withValues(alpha: 0.24),
                      onValueChange: (val) {
                        provider.seekTo(
                          Duration(milliseconds: (val * maxMs).toInt()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('-${_formatTime(remaining)}', style: _timeStyle),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.volume_down_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.50),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ThinSlider(
                        value: provider.volume.clamp(0.0, 1.0),
                        idleHeight: 6.0,
                        activeHeight: 10.0,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white.withValues(alpha: 0.24),
                        onValueChange: provider.setVolume,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.volume_up_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.50),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static TextStyle get _timeStyle => AppFont.style(
        color: Colors.white.withValues(alpha: 0.70),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      );

  static String _formatTime(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.child,
    required this.semanticLabel,
    required this.onTap,
  });

  final Widget child;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      excludeSemantics: true,
      // The callers play their own haptic (as before); the jelly adds none.
      child: JellyPress(
        profile: JellyProfile.circle,
        haptic: JellyHaptic.none,
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _LyricsArt extends StatelessWidget {
  const _LyricsArt({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final rawArt = track.albumArtUrl;
    if (rawArt.isEmpty) return const _ArtPlaceholder();
    final art = ImageQualityUtils.getHighResArtwork(rawArt);
    if (!art.contains('://')) {
      final f = File(art);
      if (f.existsSync()) return Image.file(f, fit: BoxFit.cover);
    }
    return CachedNetworkImage(
      imageUrl: art,
      fit: BoxFit.cover,
      memCacheWidth: AppImageCache.cardMemCache,
      memCacheHeight: AppImageCache.cardMemCache,
      errorWidget: (_, __, ___) => const _ArtPlaceholder(),
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Icon(Icons.music_note, color: Colors.white30, size: 24),
      ),
    );
  }
}
