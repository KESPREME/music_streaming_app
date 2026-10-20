import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_font.dart';

import '../models/track.dart';

/// Muzo-parity media card for 2-column grids (Albums & Playlists).
///
/// Features 1:1 square artwork with 16px continuous rounded corners, bold 1-line
/// title, muted subtitle, organic spring scale-down on press (0.95), and staggered entrance.
class SearchMediaGridCard extends StatefulWidget {
  final Track track;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final int index;

  const SearchMediaGridCard({
    super.key,
    required this.track,
    this.subtitle,
    this.onTap,
    this.onLongPress,
    this.index = 0,
  });

  @override
  State<SearchMediaGridCard> createState() => _SearchMediaGridCardState();
}

class _SearchMediaGridCardState extends State<SearchMediaGridCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        widget.onLongPress?.call();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _GridArtwork(
                  imageUrl: widget.track.albumArtUrl,
                  fallbackIcon: Icons.album_rounded,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.track.trackName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFont.style(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.subtitle ?? 'Playlist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFont.style(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.index >= 12) return card;
    return _StaggeredEntrance(
      delay: Duration(milliseconds: (widget.index * 30).clamp(0, 360)),
      child: card,
    );
  }
}

/// Muzo-parity artist card for 2-column grids.
///
/// Features large 1:1 circular portrait, centered bold artist name, centered
/// "Artist" subtitle, organic spring scale-down on press (0.95), and staggered entrance.
class SearchArtistGridCard extends StatefulWidget {
  final String artistName;
  final String? artistImageUrl;
  final String? subtitle;
  final VoidCallback? onTap;
  final int index;

  const SearchArtistGridCard({
    super.key,
    required this.artistName,
    this.artistImageUrl,
    this.subtitle,
    this.onTap,
    this.index = 0,
  });

  @override
  State<SearchArtistGridCard> createState() => _SearchArtistGridCardState();
}

class _SearchArtistGridCardState extends State<SearchArtistGridCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _GridArtwork(
                    imageUrl: widget.artistImageUrl,
                    fallbackIcon: Icons.person_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.artistName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFont.style(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.subtitle ?? 'Artist',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFont.style(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.index >= 12) return card;
    return _StaggeredEntrance(
      delay: Duration(milliseconds: (widget.index * 30).clamp(0, 360)),
      child: card,
    );
  }
}

class _GridArtwork extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;

  const _GridArtwork({
    required this.imageUrl,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _fallback(loading: true),
      );
    }
    return _fallback();
  }

  Widget _fallback({bool loading = false}) {
    return Container(
      color: const Color(0xFF1E1C22),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                fallbackIcon,
                color: Colors.white24,
                size: 38,
              ),
      ),
    );
  }
}

class _StaggeredEntrance extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const _StaggeredEntrance({required this.delay, required this.child});

  @override
  State<_StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<_StaggeredEntrance> {
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
    return AnimatedOpacity(
      opacity: _show ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _show ? Offset.zero : const Offset(0, 0.04),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
