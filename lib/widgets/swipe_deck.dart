import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/track.dart';
import 'glass_circle_button.dart';
import 'glass_surface.dart';

/// What the user decided about a card.
enum SwipeAction { like, skip, queue }

/// Tinder-style discovery deck with liquid-glass cards.
///
/// Top card drags horizontally (rotate ∝ dx, spring return on cancel); the
/// next card peeks behind. Horizontal-only drags so vertical scrolling of
/// the surrounding list is never hijacked. Buttons mirror gestures.
class SwipeDeck extends StatefulWidget {
  const SwipeDeck({
    super.key,
    required this.tracks,
    required this.onAction,
    this.height = 440,
  });

  final List<Track> tracks;
  final void Function(Track track, SwipeAction action) onAction;
  final double height;

  @override
  State<SwipeDeck> createState() => _SwipeDeckState();
}

class _SwipeDeckState extends State<SwipeDeck> {
  static const _threshold = 110.0;
  static const _flyDuration = Duration(milliseconds: 260);

  double _dx = 0;
  bool _flying = false;
  SwipeAction? _flyDirection;
  int _top = 0;

  bool get _hasCurrent => _top < widget.tracks.length;
  bool get _hasNext => _top + 1 < widget.tracks.length;

  void _onDragUpdate(DragUpdateDetails d) {
    if (_flying || !_hasCurrent) return;
    setState(() => _dx += d.delta.dx);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_flying || !_hasCurrent) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    SwipeAction? action;
    if (_dx > _threshold || vx > 700) {
      action = SwipeAction.like;
    } else if (_dx < -_threshold || vx < -700) {
      action = SwipeAction.skip;
    }
    if (action != null) {
      _flyOut(action);
    } else {
      setState(() => _dx = 0);
    }
  }

  void _flyOut(SwipeAction action) {
    if (_flying || !_hasCurrent) return;
    setState(() {
      _flying = true;
      _flyDirection = action;
    });
    widget.onAction(widget.tracks[_top], action);
    Future.delayed(_flyDuration, () {
      if (!mounted) return;
      setState(() {
        _top++;
        _dx = 0;
        _flying = false;
        _flyDirection = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCurrent) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.style_outlined,
                  size: 44, color: Colors.white.withValues(alpha: 0.15)),
              const SizedBox(height: 12),
              Text(
                'Deck exhausted — pull down to refresh',
                style: GoogleFonts.outfit(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }

    final current = widget.tracks[_top];
    final progress = (_dx.abs() / _threshold).clamp(0.0, 1.0);
    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Peek card
              if (_hasNext)
                Transform.translate(
                  offset: const Offset(0, 14),
                  child: Transform.scale(
                    scale: 0.94,
                    child: IgnorePointer(
                        child: _CardFace(track: widget.tracks[_top + 1])),
                  ),
                ),
              // Top card
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Transform.translate(
                  key: ValueKey(current.id),
                  offset: _flying ? _flyOffset() : Offset(_dx, 0),
                  child: Transform.rotate(
                    angle: _flying
                        ? (_flyDirection == SwipeAction.like ? 0.35 : -0.35)
                        : _dx / 20 * 3.14159 / 12,
                    child: Opacity(
                      opacity: _flying ? 0.0 : (1 - progress * 0.25),
                      child: GestureDetector(
                        onHorizontalDragUpdate: _onDragUpdate,
                        onHorizontalDragEnd: _onDragEnd,
                        child: _CardFace(track: current),
                      ),
                    ),
                  ),
                ),
              ),
              // Decision stamps
              if (!_flying && _dx.abs() > 20) ...[
                _Stamp(
                  label: 'LIKE',
                  color: accent,
                  opacity: _dx > 0 ? progress : 0,
                  alignment: Alignment.topLeft,
                ),
                _Stamp(
                  label: 'SKIP',
                  color: Colors.white70,
                  opacity: _dx < 0 ? progress : 0,
                  alignment: Alignment.topRight,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _ActionBar(
          onSkip: () => _flyOut(SwipeAction.skip),
          onPlay: () => widget.onAction(current, SwipeAction.queue),
          onLike: () => _flyOut(SwipeAction.like),
        ),
      ],
    );
  }

  Offset _flyOffset() {
    switch (_flyDirection) {
      case SwipeAction.like:
        return const Offset(500, -60);
      case SwipeAction.skip:
        return const Offset(-500, -60);
      case SwipeAction.queue:
        return const Offset(0, -600);
      default:
        return Offset.zero;
    }
  }
}

/// Liquid-glass card face: glass panel, art inset, glass info strip.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassSurface(
        tier: GlassTier.card,
        borderRadius: 30,
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: track.albumArtUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 200),
                      errorWidget: (_, __, ___) =>
                          Container(color: Colors.grey[900]),
                    ),
                  ],
                ),
              ),
            ),
            // Glass info strip.
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.trackName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.splineSans(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          track.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                              color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.graphic_eq_rounded,
                    color:
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                    size: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.label,
    required this.color,
    required this.opacity,
    required this.alignment,
  });

  final String label;
  final Color color;
  final double opacity;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Transform.rotate(
          angle: alignment == Alignment.topLeft ? -0.4 : 0.4,
          child: Container(
            margin: const EdgeInsets.all(30),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: 0.9), width: 3),
              borderRadius: BorderRadius.circular(10),
              color: Colors.black.withValues(alpha: 0.25),
            ),
            child: Opacity(
              opacity: opacity,
              child: Text(
                label,
                style: GoogleFonts.splineSans(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onSkip,
    required this.onPlay,
    required this.onLike,
  });

  final VoidCallback onSkip;
  final VoidCallback onPlay;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GlassCircleButton(
          icon: Icons.close_rounded,
          size: 52,
          iconSize: 26,
          onTap: onSkip,
          semanticLabel: 'Skip',
        ),
        const SizedBox(width: 22),
        GlassCircleButton(
          icon: Icons.play_arrow_rounded,
          size: 66,
          iconSize: 34,
          glow: true,
          onTap: onPlay,
          semanticLabel: 'Queue and play',
        ),
        const SizedBox(width: 22),
        GlassCircleButton(
          icon: Icons.favorite_outline_rounded,
          size: 52,
          iconSize: 24,
          onTap: onLike,
          semanticLabel: 'Like',
        ),
      ],
    );
  }
}
