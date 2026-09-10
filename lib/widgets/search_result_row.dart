import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/track.dart';
import 'bitchord_detail/bitchord_explicit_badge.dart';

/// Muzo-parity search result row: 64px rounded artwork, 1-line title with
/// optional explicit badge, grey `artist • duration` subtitle, trailing ⋮.
///
/// Plain (non-glass) by design — rows sit on the opaque screen background, so
/// per-row blur would be pure GPU cost with nothing to refract. Actions are
/// injected ([onTap]/[onMore]) so Muzo online rows, video rows, album rows
/// and local library rows share one visual language.
class SearchResultRow extends StatelessWidget {
  final Track track;

  /// Subtitle override (e.g. album rows: artist • year). Defaults to
  /// `artist • duration` when the track carries a duration.
  final String? subtitle;
  final bool isPlaying;
  final bool circleArt;
  final VoidCallback? onTap;
  final VoidCallback? onMore;

  /// Stagger entrance delay. Pass [Duration.zero] (or >=12th row) to skip.
  final Duration entranceDelay;

  const SearchResultRow({
    super.key,
    required this.track,
    this.subtitle,
    this.isPlaying = false,
    this.circleArt = false,
    this.onTap,
    this.onMore,
    this.entranceDelay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final row = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 9.0),
          child: Row(
            children: [
              _Artwork(track: track, circleArt: circleArt),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (track.isExplicit) ...[
                          const BitchordExplicitBadge(),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            track.trackName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: isPlaying ? accent : Colors.white,
                              fontSize: 16.5,
                              fontWeight: isPlaying
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle ?? _defaultSubtitle(track),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (onMore != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white.withValues(alpha: 0.75),
                    size: 22,
                  ),
                  onPressed: onMore,
                ),
            ],
          ),
        ),
      ),
    );

    if (entranceDelay == Duration.zero) return row;
    // Cheap one-shot entrance: opacity + 12px rise, staggered per index.
    // TweenAnimationBuilder (no controllers to dispose, only visible rows run).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        // Delay by holding at 0 until the delay elapses.
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
      child: row,
    );
  }

  /// Wraps [row] in a delayed starter so [entranceDelay] staggers the list.
  static Widget staged({
    Key? key,
    required Track track,
    String? subtitle,
    bool isPlaying = false,
    bool circleArt = false,
    VoidCallback? onTap,
    VoidCallback? onMore,
    required int index,
  }) {
    if (index >= 12) {
      return SearchResultRow(
        key: key,
        track: track,
        subtitle: subtitle,
        isPlaying: isPlaying,
        circleArt: circleArt,
        onTap: onTap,
        onMore: onMore,
      );
    }
    return _DelayedEntrance(
      key: key,
      delay: Duration(milliseconds: (index * 35).clamp(0, 400)),
      child: SearchResultRow(
        track: track,
        subtitle: subtitle,
        isPlaying: isPlaying,
        circleArt: circleArt,
        onTap: onTap,
        onMore: onMore,
        entranceDelay: const Duration(milliseconds: 1),
      ),
    );
  }

  static String _defaultSubtitle(Track track) {
    final artist = track.artistName.trim();
    final duration = track.durationText.trim();
    if (artist.isEmpty) return duration;
    if (duration.isEmpty) return artist;
    return '$artist • $duration';
  }
}

class _Artwork extends StatelessWidget {
  final Track track;
  final bool circleArt;

  const _Artwork({required this.track, required this.circleArt});

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cache = (size * pixelRatio).round();
    final image = track.albumArtUrl.isNotEmpty
        ? Image.network(
            track.albumArtUrl,
            width: size,
            height: size,
            cacheWidth: cache,
            cacheHeight: cache,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _fallback(loading: true),
          )
        : _fallback();
    if (circleArt) {
      return ClipOval(child: SizedBox(width: size, height: size, child: image));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: size, height: size, child: image),
    );
  }

  Widget _fallback({bool loading = false}) {
    return Container(
      width: 64,
      height: 64,
      color: const Color(0xFF1C1C1E),
      child: loading
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : const Icon(
              Icons.music_note_rounded,
              color: Colors.white24,
              size: 28,
            ),
    );
  }
}

/// Holds a child invisible for [delay], then mounts the entrance animation.
class _DelayedEntrance extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const _DelayedEntrance({super.key, required this.delay, required this.child});

  @override
  State<_DelayedEntrance> createState() => _DelayedEntranceState();
}

class _DelayedEntranceState extends State<_DelayedEntrance> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay).then((_) {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) {
      return const Opacity(
        opacity: 0,
        child: SizedBox(height: 82),
      );
    }
    return widget.child;
  }
}
