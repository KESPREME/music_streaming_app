// lib/widgets/bitchord_detail/release_header.dart
//
// Album and artist page headers after BitChord's release / artist pages
// (behaviour and numbers only; BitChord is GPLv3 and no code is copied):
//   * a framed square sleeve on the flat palette colour, not a full-bleed hero;
//   * one meta line, "Album · 2008 · 14 tracks · 59 min", built only from what
//     the page knows (no invented year);
//   * a shuffle circle, a white Play pill that takes the width, and one
//     trailing circle;
//   * the artist page's latest-release card.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_font.dart';

import '../../utils/app_image_cache.dart';

export '../../models/bitchord_page_models.dart' show releaseKindFrom;
import '../../utils/artwork_palette_resolver.dart';
import '../../utils/image_quality_utils.dart';

/// "Album · 2008 · 14 tracks · 59 min". Unknown parts are left out rather
/// than guessed; [totalSeconds] of 0 means the durations are unknown.
String releaseMetaLine({
  String? kind,
  String? year,
  required int trackCount,
  int totalSeconds = 0,
}) {
  final parts = <String>[
    if (kind != null && kind.trim().isNotEmpty) kind.trim(),
    if (year != null && year.trim().isNotEmpty) year.trim(),
    if (trackCount > 0) '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
    if (totalSeconds > 0) releaseDurationText(totalSeconds),
  ];
  return parts.join(' · ');
}

/// "59 min", "1 hr 12 min", "2 hr".
String releaseDurationText(int totalSeconds) {
  final mins = (totalSeconds / 60).round();
  if (mins < 60) return '${mins < 1 ? 1 : mins} min';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '$h hr' : '$h hr $m min';
}

/// Edge of the framed sleeve: 76% of the width, never more than half the
/// height (a landscape phone or a split screen keeps the title in view).
double releaseSleeveSize(Size screen) {
  final byWidth = screen.width * 0.76;
  final byHeight = screen.height * 0.5;
  return byWidth < byHeight ? byWidth : byHeight;
}

/// The album cover, framed: rounded 12, a soft drop shadow, [overlay] (a
/// motion cover) drawn inside the same clip.
class FramedSleeve extends StatelessWidget {
  const FramedSleeve({
    super.key,
    required this.imageUrl,
    required this.size,
    this.overlay,
  });

  final String? imageUrl;
  final double size;
  final Widget? overlay;

  static const double radius = 12;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl ?? '';
    final placeholder = ColoredBox(
      color: Colors.white.withValues(alpha: 0.06),
      child: Icon(Icons.album_rounded, size: size * 0.3, color: Colors.white24),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url.isEmpty)
              placeholder
            else
              CachedNetworkImage(
                imageUrl: ImageQualityUtils.getHighQualityUrl(url),
                fit: BoxFit.cover,
                memCacheWidth: AppImageCache.heroMemCache,
                memCacheHeight: AppImageCache.heroMemCache,
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
              ),
            if (overlay != null) overlay!,
          ],
        ),
      ),
    );
  }
}

class _Press extends StatefulWidget {
  const _Press({required this.onTap, required this.child, this.semanticLabel});

  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A translucent outlined circle, as BitChord's shuffle / add buttons.
class GhostCircleButton extends StatelessWidget {
  const GhostCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.size = 56,
    this.iconColor = Colors.white,
    this.child,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final double size;
  final Color iconColor;

  /// Replaces the icon (a progress ring while downloading).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return _Press(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1),
        ),
        child: Center(child: child ?? Icon(icon, color: iconColor, size: size * 0.42)),
      ),
    );
  }
}

/// Download state of a release, for the trailing circle.
enum ReleaseDownloadState { none, partial, downloading, done }

/// [ shuffle ]  [ ▶ Play ──────── ]  [ trailing ]
class ReleaseActionRow extends StatelessWidget {
  const ReleaseActionRow({
    super.key,
    required this.onPlay,
    required this.onShuffle,
    required this.trailing,
  });

  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          GhostCircleButton(
            icon: Icons.shuffle_rounded,
            semanticLabel: 'Shuffle',
            onTap: onShuffle,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: _Press(
              onTap: onPlay,
              semanticLabel: 'Play',
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 28),
                    const SizedBox(width: 6),
                    Text(
                      'Play',
                      style: AppFont.style(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          trailing,
        ],
      ),
    );
  }
}

/// The trailing download circle of an album page.
class ReleaseDownloadButton extends StatelessWidget {
  const ReleaseDownloadButton({
    super.key,
    required this.state,
    required this.onTap,
    this.accent = Colors.white,
  });

  final ReleaseDownloadState state;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case ReleaseDownloadState.downloading:
        return GhostCircleButton(
          icon: Icons.downloading_rounded,
          semanticLabel: 'Downloading',
          onTap: onTap,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: accent),
          ),
        );
      case ReleaseDownloadState.done:
        return GhostCircleButton(
          icon: Icons.download_done_rounded,
          semanticLabel: 'Downloaded',
          iconColor: accent,
          onTap: onTap,
        );
      case ReleaseDownloadState.partial:
      case ReleaseDownloadState.none:
        return GhostCircleButton(
          icon: Icons.download_rounded,
          semanticLabel: 'Download',
          onTap: onTap,
        );
    }
  }
}

/// [ shuffle ]  ( ▶ )  [ trailing ] - the artist page's row, Play a 70dp disc.
class ArtistActionRow extends StatelessWidget {
  const ArtistActionRow({
    super.key,
    required this.onPlay,
    required this.onShuffle,
    required this.trailing,
  });

  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GhostCircleButton(icon: Icons.shuffle_rounded, semanticLabel: 'Shuffle', onTap: onShuffle),
        const SizedBox(width: 32),
        _Press(
          onTap: onPlay,
          semanticLabel: 'Play',
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 40),
          ),
        ),
        const SizedBox(width: 32),
        trailing,
      ],
    );
  }
}

/// The artist's newest release, as a card under the action row.
class LatestReleaseCard extends StatelessWidget {
  const LatestReleaseCard({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.eyebrow,
    required this.caption,
    required this.palette,
    required this.onTap,
  });

  final String title;
  final String imageUrl;

  /// "Single · 2023".
  final String eyebrow;

  /// "Latest release".
  final String caption;
  final ArtworkPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _Press(
        onTap: onTap,
        semanticLabel: '$caption: $title',
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: Color.alphaBlend(
              Colors.white.withValues(alpha: 0.07),
              palette.elevated.withValues(alpha: 0.35),
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: imageUrl.isEmpty
                      ? ColoredBox(color: Colors.white.withValues(alpha: 0.06))
                      : CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 300,
                          errorWidget: (_, __, ___) =>
                              ColoredBox(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (eyebrow.isNotEmpty)
                      Text(
                        eyebrow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.style(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.style(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
