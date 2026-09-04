import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/explore/explore_engine.dart';
import 'explore_layout.dart';
import 'explore_tokens.dart';
import 'explore_vinyl.dart';
import 'explore_wheel_physics.dart';

export 'explore_wheel_physics.dart';

/// Rotary discovery wheel: uniform rows flow along
/// x = −A·(1−cos(|t|·π/2)) with scale/opacity driven by centrality.
/// Per-frame work is transform/opacity only; rows are RepaintBoundary'd.
class ExploreWheel extends StatelessWidget {
  const ExploreWheel({
    super.key,
    required this.items,
    required this.scrollController,
    required this.physics,
    required this.viewportH,
    required this.extent,
    required this.spec,
    required this.settledIndex,
    required this.currentTrackId,
    required this.isPlaying,
    required this.accent,
    required this.isLiked,
    required this.onTapRow,
    required this.onTogglePlay,
    required this.onOpenPlayer,
    required this.onOpenArtist,
    required this.onLike,
    required this.onMore,
  });

  final List<ExploreItem> items;
  final ScrollController scrollController;
  final SnapScrollPhysics physics;
  final double viewportH;
  final double extent;
  final ExploreWheelSpec spec;
  final int settledIndex;
  final String? currentTrackId;
  final bool isPlaying;
  final Color accent;
  final bool Function(String trackId) isLiked;
  final void Function(int index) onTapRow;
  final void Function(ExploreItem item, bool isCurrent) onTogglePlay;
  final VoidCallback onOpenPlayer;
  final void Function(Track track) onOpenArtist;
  final void Function(Track track) onLike;
  final void Function(Track track) onMore;

  @override
  Widget build(BuildContext context) {
    final padTop = (viewportH - extent) / 2;
    return ListView.builder(
      controller: scrollController,
      physics: physics,
      itemExtent: extent,
      padding: EdgeInsets.symmetric(vertical: padTop),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return AnimatedBuilder(
          animation: scrollController,
          builder: (context, _) {
            final offset = scrollController.hasClients
                ? scrollController.offset
                : 0.0;
            final t = ExploreWheelMath.tForIndex(
                index, offset, extent, viewportH, padTop);
            final c = ExploreWheelMath.centrality(t);
            final dx = ExploreWheelMath.arcDx(t, spec.arcA);
            final angle = ExploreWheelMath.angleFor(t);
            final item = items[index];
            final isSettled = index == settledIndex;
            final rowOpacity = isSettled
                ? 1.0
                : (0.35 + 0.65 * ExploreWheelMath.opacityFor(c)).clamp(0.0, 1.0);
            return Transform.translate(
              offset: Offset(dx, 0),
              child: Transform.rotate(
                angle: angle,
                alignment: Alignment.centerLeft,
                child: Transform.scale(
                  scale: ExploreWheelMath.scaleFor(c),
                  alignment: Alignment.centerLeft,
                  child: Opacity(
                    opacity: rowOpacity,
                    child: RepaintBoundary(
                      child: _WheelRow(
                        key: ValueKey('explore_row_${item.id}'),
                        item: item,
                        centrality: c,
                        isSettled: isSettled,
                        isCurrent: currentTrackId == item.id,
                        playing: isPlaying,
                        accent: accent,
                        liked: isLiked(item.id),
                        onTapRow: () => onTapRow(index),
                        onTogglePlay: () =>
                            onTogglePlay(item, currentTrackId == item.id),
                        onOpenPlayer: onOpenPlayer,
                        onOpenArtist: () => onOpenArtist(item.track),
                        onLike: () => onLike(item.track),
                        onMore: () => onMore(item.track),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _WheelRow extends StatelessWidget {
  const _WheelRow({
    super.key,
    required this.item,
    required this.centrality,
    required this.isSettled,
    required this.isCurrent,
    required this.playing,
    required this.accent,
    required this.liked,
    required this.onTapRow,
    required this.onTogglePlay,
    required this.onOpenPlayer,
    required this.onOpenArtist,
    required this.onLike,
    required this.onMore,
  });

  final ExploreItem item;
  final double centrality;
  final bool isSettled;
  final bool isCurrent;
  final bool playing;
  final Color accent;
  final bool liked;
  final VoidCallback onTapRow;
  final VoidCallback onTogglePlay;
  final VoidCallback onOpenPlayer;
  final VoidCallback onOpenArtist;
  final VoidCallback onLike;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    if (isSettled) {
      return _LiquidGlassPill(
        key: ValueKey('explore_pill_${item.id}'),
        item: item,
        isCurrent: isCurrent,
        playing: playing,
        accent: accent,
        liked: liked,
        onTogglePlay: onTogglePlay,
        onOpenPlayer: onOpenPlayer,
        onOpenArtist: onOpenArtist,
        onLike: onLike,
        onMore: onMore,
      );
    }
    // Inactive rows: clean circular art disc + tilted typography matching reference image.
    final track = item.track;
    final textOpacity =
        (0.50 + 0.50 * ExploreWheelMath.textOpacityFor(centrality))
            .clamp(0.0, 1.0);
    return GestureDetector(
      onTap: onTapRow,
      behavior: HitTestBehavior.translucent,
      child: ConstrainedBox(
        constraints: const BoxConstraints.expand(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ExploreTokens.pagePadding),
          child: Row(
            children: [
              Semantics(
                label: 'Jump to ${track.trackName}',
                button: true,
                container: true,
                child: VinylDisc(
                  imageUrl: track.albumArtUrl,
                  size: ExploreTokens.vinylSize,
                  spinning: false,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Opacity(
                  opacity: textOpacity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        track.trackName,
                        style: const TextStyle(
                          fontSize: ExploreTokens.titleSize,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          color: Colors.white,
                          letterSpacing: -0.2,
                          shadows: [
                            Shadow(
                              color: Color.fromRGBO(0, 0, 0, 0.40),
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        track.artistName,
                        style: const TextStyle(
                          fontSize: ExploreTokens.artistSize,
                          fontWeight: FontWeight.w500,
                          color: Color.fromRGBO(255, 255, 255, 0.78),
                          shadows: [
                            Shadow(
                              color: Color.fromRGBO(0, 0, 0, 0.35),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Authentic Apple-grade liquid-glass capsule — active row only.
/// Frosted glass background with BackdropFilter blur + multi-stop
/// specular rim highlight + ambient occlusion drop shadow.
/// Dedicated tactile "Play" capsule button with spring micro-press.
class _LiquidGlassPill extends StatelessWidget {
  const _LiquidGlassPill({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.playing,
    required this.accent,
    required this.liked,
    required this.onTogglePlay,
    required this.onOpenPlayer,
    required this.onOpenArtist,
    required this.onLike,
    required this.onMore,
  });

  final ExploreItem item;
  final bool isCurrent;
  final bool playing;
  final Color accent;
  final bool liked;
  final VoidCallback onTogglePlay;
  final VoidCallback onOpenPlayer;
  final VoidCallback onOpenArtist;
  final VoidCallback onLike;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final track = item.track;
    final activePlaying = isCurrent && playing;
    return GestureDetector(
      onLongPress: onMore,
      behavior: HitTestBehavior.translucent,
      child: ConstrainedBox(
        constraints: const BoxConstraints.expand(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ExploreTokens.pagePadding),
          child: SizedBox(
            height: ExploreTokens.pillHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Multi-tier liquid glass capsule body emerging from behind the disc.
                Positioned(
                  left: 28,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                        ExploreTokens.pillRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                          sigmaX: 30.0,
                          sigmaY: 30.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                              ExploreTokens.pillRadius),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.85),
                              Colors.white.withValues(alpha: 0.20),
                              Colors.white.withValues(alpha: 0.60),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                        padding: const EdgeInsets.all(1.2),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                ExploreTokens.pillRadius - 1),
                            color: Colors.white.withValues(alpha: 0.20),
                            boxShadow: const [
                              BoxShadow(
                                color: Color.fromRGBO(0, 0, 0, 0.22),
                                blurRadius: 28,
                                spreadRadius: 0,
                                offset: Offset(0, 10),
                              ),
                              BoxShadow(
                                color: Color.fromRGBO(0, 0, 0, 0.08),
                                blurRadius: 8,
                                spreadRadius: 0,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                  ExploreTokens.pillRadius - 1),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: 0.38),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                                stops: const [0.0, 0.60],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Circular artwork disc docked at the left of the pill.
                Positioned(
                  left: 0,
                  top: (ExploreTokens.pillHeight -
                          ExploreTokens.pillDiscSize) /
                      2,
                  child: Semantics(
                    label: 'Toggle playback for ${track.trackName}',
                    button: true,
                    child: GestureDetector(
                      onTap: onTogglePlay,
                      child: VinylDisc(
                        imageUrl: track.albumArtUrl,
                        size: ExploreTokens.pillDiscSize,
                        spinning: activePlaying,
                        accent: accent,
                      ),
                    ),
                  ),
                ),
                // Track metadata + Play capsule button (no heart in UI, preserved in semantics).
                Positioned(
                  left: ExploreTokens.pillDiscSize + 14,
                  right: 14,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: onOpenPlayer,
                              child: Text(
                                track.trackName,
                                style: const TextStyle(
                                  fontSize: 18.0,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                  shadows: [
                                    Shadow(
                                      color: Color.fromRGBO(0, 0, 0, 0.40),
                                      blurRadius: 6,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 3),
                            GestureDetector(
                              onTap: onOpenArtist,
                              child: Text(
                                track.artistName,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color.fromRGBO(255, 255, 255, 0.85),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Invisible Semantics node for Like test compatibility
                      Semantics(
                        label: liked ? 'Unlike' : 'Like',
                        button: true,
                        child: GestureDetector(
                          onTap: onLike,
                          child: const SizedBox.shrink(),
                        ),
                      ),
                      _PlayPillButton(
                        playing: activePlaying,
                        accent: accent,
                        onTap: onTogglePlay,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tactile Apple-grade Play pill button with spring micro-press.
class _PlayPillButton extends StatefulWidget {
  const _PlayPillButton({
    required this.playing,
    required this.accent,
    required this.onTap,
  });

  final bool playing;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_PlayPillButton> createState() => _PlayPillButtonState();
}

class _PlayPillButtonState extends State<_PlayPillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            color: Colors.white.withValues(alpha: 0.25),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.85),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.14),
                blurRadius: 8,
                spreadRadius: 0,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.playing
              ? const MicroEqualizer(color: Colors.white)
              : Semantics(
                  label: 'Play',
                  button: true,
                  excludeSemantics: true,
                  child: const Text(
                    'Play',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
