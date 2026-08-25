import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/track.dart';

/// What the user decided about a card.
enum SwipeAction { like, skip, queue }

/// Tinder-style discovery deck. Top card is draggable (rotate ∝ dx, spring
/// return on cancel); the next card peeks behind. Buttons mirror gestures.
class SwipeDeck extends StatefulWidget {
  const SwipeDeck({
    super.key,
    required this.tracks,
    required this.onAction,
    this.height = 420,
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

  Offset _drag = Offset.zero;
  bool _flying = false;
  SwipeAction? _flyDirection;
  int _top = 0;

  bool get _hasCurrent => _top < widget.tracks.length;
  bool get _hasNext => _top + 1 < widget.tracks.length;

  void _onPanUpdate(DragUpdateDetails d) {
    if (_flying || !_hasCurrent) return;
    setState(() => _drag += d.delta);
  }

  void _onPanEnd(DragEndDetails d) {
    if (_flying || !_hasCurrent) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    final vy = d.velocity.pixelsPerSecond.dy;
    SwipeAction? action;
    if (_drag.dx > _threshold || vx > 700) {
      action = SwipeAction.like;
    } else if (_drag.dx < -_threshold || vx < -700) {
      action = SwipeAction.skip;
    } else if (_drag.dy < -_threshold || vy < -700) {
      action = SwipeAction.queue;
    }
    if (action != null) {
      _flyOut(action);
    } else {
      setState(() => _drag = Offset.zero);
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
        _drag = Offset.zero;
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
          child: Text(
            'Deck exhausted — pull to refresh',
            style: GoogleFonts.outfit(color: Colors.white54),
          ),
        ),
      );
    }

    final current = widget.tracks[_top];
    final progress = (_drag.dx.abs() / _threshold).clamp(0.0, 1.0);
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
                  offset: _flying ? _flyOffset() : _drag,
                  child: Transform.rotate(
                    angle: _flying
                        ? (_flyDirection == SwipeAction.like ? 0.35 : -0.35)
                        : _drag.dx / 20 * 3.14159 / 12,
                    child: Opacity(
                      opacity: _flying ? 0.0 : (1 - progress * 0.25),
                      child: GestureDetector(
                        onPanUpdate: _onPanUpdate,
                        onPanEnd: _onPanEnd,
                        child: _CardFace(track: current),
                      ),
                    ),
                  ),
                ),
              ),
              // Decision stamps
              if (!_flying && _drag.dx.abs() > 20) ...[
                _Stamp(
                  label: 'LIKE',
                  color: accent,
                  opacity: _drag.dx > 0 ? progress : 0,
                  alignment: Alignment.topLeft,
                ),
                _Stamp(
                  label: 'SKIP',
                  color: Colors.white70,
                  opacity: _drag.dx < 0 ? progress : 0,
                  alignment: Alignment.topRight,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ActionBar(
          accent: accent,
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

class _CardFace extends StatelessWidget {
  const _CardFace({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
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
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.4, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.9),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.trackName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.splineSans(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    track.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                        color: Colors.white70, fontSize: 15),
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
            margin: const EdgeInsets.all(28),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 3),
              borderRadius: BorderRadius.circular(10),
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
    required this.accent,
    required this.onSkip,
    required this.onPlay,
    required this.onLike,
  });

  final Color accent;
  final VoidCallback onSkip;
  final VoidCallback onPlay;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ActionButton(
          icon: Icons.close_rounded,
          color: Colors.white70,
          size: 52,
          onTap: onSkip,
        ),
        const SizedBox(width: 22),
        _ActionButton(
          icon: Icons.play_arrow_rounded,
          color: accent,
          size: 68,
          onTap: onPlay,
          glow: true,
        ),
        const SizedBox(width: 22),
        _ActionButton(
          icon: Icons.favorite_rounded,
          color: accent,
          size: 52,
          onTap: onLike,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
    this.glow = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final filled = glow;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? color : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: color.withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: glow
              ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 22)]
              : null,
        ),
        child: Icon(
          icon,
          color: filled ? Colors.black : color,
          size: size * 0.5,
        ),
      ),
    );
  }
}
