import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/explore/explore_engine.dart';
import 'explore_layout.dart';
import '../../widgets/glass_circle_button.dart';
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
            final item = items[index];
            return Transform.translate(
              offset: Offset(dx, 0),
              child: Transform.scale(
                scale: ExploreWheelMath.scaleFor(c),
                child: Opacity(
                  opacity: ExploreWheelMath.opacityFor(c),
                  child: RepaintBoundary(
                    child: _WheelRow(
                      key: ValueKey('explore_row_${item.id}'),
                      item: item,
                      centrality: c,
                      isSettled: index == settledIndex,
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
    // Inactive rows: bare vinyl + floating type. No containers, no
    // borders, no shadows — the wheel is the composition.
    final track = item.track;
    final textOpacity = ExploreWheelMath.textOpacityFor(centrality);
    return GestureDetector(
      onTap: onTapRow,
      behavior: HitTestBehavior.translucent,
      child: ConstrainedBox(
        constraints: const BoxConstraints.expand(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
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
              const SizedBox(width: 12),
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
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                  color: Color.fromRGBO(0, 0, 0, 0.3),
                                  blurRadius: 4,
                                  offset: Offset(0, 1)),
                            ]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artistName,
                        style: TextStyle(
                            fontSize: ExploreTokens.artistSize,
                            color: accent.withValues(alpha: 0.9)),
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

/// Authentic liquid-glass capsule — active row only. Gradient light
/// border via nested containers (no custom painter); bevel via top
/// highlight overlay; elevation via drop shadow. Disc hangs over the
/// left edge; long-press opens track options.
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
              horizontal: ExploreTokens.pillMarginH),
          child: SizedBox(
            height: ExploreTokens.pillHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Glass body: blur + gradient light border + bevel + lift.
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                        ExploreTokens.pillRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                          sigmaX: ExploreTokens.pillBlurSigma,
                          sigmaY: ExploreTokens.pillBlurSigma),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                              ExploreTokens.pillRadius),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(
                                  alpha: ExploreTokens.pillBorderTop),
                              Colors.white.withValues(
                                  alpha: ExploreTokens.pillBorderBottom),
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.all(1),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                ExploreTokens.pillRadius - 1),
                            color: Colors.white.withValues(
                                alpha: ExploreTokens.pillFillAlpha),
                            boxShadow: const [
                              BoxShadow(
                                color: Color.fromRGBO(0, 0, 0, 0.45),
                                blurRadius: 40,
                                spreadRadius: -8,
                                offset: Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                  ExploreTokens.pillRadius - 1),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.center,
                                colors: [
                                  Colors.white.withValues(alpha: 0.25),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                                stops: const [0.0, 0.35],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Disc hanging over the left edge.
                Positioned(
                  left: -ExploreTokens.pillDiscOverlap,
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
                // Text + heart + eq/play.
                Positioned(
                  left: ExploreTokens.pillDiscSize -
                      ExploreTokens.pillDiscOverlap +
                      10,
                  right: 10,
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
                                    fontSize: ExploreTokens.titleSize,
                                    fontWeight: FontWeight.w600,
                                    height: 1.15,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                          color:
                                              Color.fromRGBO(0, 0, 0, 0.3),
                                          blurRadius: 4,
                                          offset: Offset(0, 1)),
                                    ]),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: onOpenArtist,
                              child: Text(
                                track.artistName,
                                style: TextStyle(
                                    fontSize: ExploreTokens.artistSize,
                                    color:
                                        accent.withValues(alpha: 0.95)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onLike,
                        iconSize: 20,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                            minWidth: 34, minHeight: 34),
                        tooltip: '',
                        icon: Icon(
                          liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: liked
                              ? accent
                              : Colors.white.withValues(alpha: 0.75),
                          semanticLabel: liked ? 'Unlike' : 'Like',
                        ),
                      ),
                      const SizedBox(width: 2),
                      activePlaying
                          ? GestureDetector(
                              onTap: onTogglePlay,
                              child: MicroEqualizer(color: accent),
                            )
                          : GlassCircleButton(
                              icon: Icons.play_arrow_rounded,
                              size: 44,
                              iconSize: 22,
                              semanticLabel: 'Play',
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
