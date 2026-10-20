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
import '../../theme/app_font.dart';
import '../jelly_press.dart';

import '../../models/track.dart';
import '../../providers/music_provider.dart';

export '../../models/bitchord_page_models.dart' show releaseKindFrom;
import '../../utils/artwork_palette_resolver.dart';

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

/// The latest-release card's press: the house jelly, one light tap.
class _Press extends StatelessWidget {
  const _Press({required this.onTap, required this.child, this.semanticLabel});

  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: JellyPress(
        profile: JellyProfile.pill,
        haptic: JellyHaptic.light,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

/// Download state of a release, for the trailing circle.
enum ReleaseDownloadState { none, partial, downloading, done }

/// How much of [tracks] is on the device or on its way. Local files and an empty
/// list read as none: there is nothing to download.
ReleaseDownloadState releaseDownloadStateFor(MusicProvider mp, List<Track> tracks) {
  final ids = [for (final t in tracks) if (t.source != 'local') t.id];
  if (ids.isEmpty) return ReleaseDownloadState.none;
  final active = {
    for (final t in mp.currentlyDownloadingTracks) t.id,
    for (final t in mp.downloadQueue) t.id,
  };
  if (ids.any(active.contains)) return ReleaseDownloadState.downloading;
  final done = ids.where(mp.isTrackDownloadedSync).length;
  if (done == ids.length) return ReleaseDownloadState.done;
  return done > 0 ? ReleaseDownloadState.partial : ReleaseDownloadState.none;
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
