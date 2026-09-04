import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/track.dart';
import '../../providers/music_provider.dart';
import '../../services/explore/explore_engine.dart';
import 'explore_layout.dart';
import '../../widgets/artist_picker_sheet.dart';
import '../../widgets/glass_circle_button.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/themed_options_sheet.dart';
import 'explore_tokens.dart';
import 'explore_vinyl.dart';
import 'explore_wheel_physics.dart';

export 'explore_wheel_physics.dart';

/// Rotary discovery wheel: uniform rows flow along the arc
/// Δx = k·(1−cos(|t|·θmax)) with scale/opacity driven by centrality.
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
    required this.onTapRow,
    required this.onTogglePlay,
    required this.onOpenPlayer,
    required this.onOpenArtist,
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
  final void Function(int index) onTapRow;
  final void Function(ExploreItem item, bool isCurrent) onTogglePlay;
  final VoidCallback onOpenPlayer;
  final void Function(Track track) onOpenArtist;

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
            final dx = ExploreWheelMath.arcDx(t, spec.arcK, spec.maxTheta);
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
                      onTapRow: () => onTapRow(index),
                      onTogglePlay: () =>
                          onTogglePlay(item, currentTrackId == item.id),
                      onOpenPlayer: onOpenPlayer,
                      onOpenArtist: () => onOpenArtist(item.track),
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
    required this.onTapRow,
    required this.onTogglePlay,
    required this.onOpenPlayer,
    required this.onOpenArtist,
  });

  final ExploreItem item;
  final double centrality;
  final bool isSettled;
  final bool isCurrent;
  final bool playing;
  final Color accent;
  final VoidCallback onTapRow;
  final VoidCallback onTogglePlay;
  final VoidCallback onOpenPlayer;
  final VoidCallback onOpenArtist;

  @override
  Widget build(BuildContext context) {
    final track = item.track;
    final glass = ExploreWheelMath.glassFor(centrality);
    final textOpacity = ExploreWheelMath.textOpacityFor(centrality);
    final activePlaying = isSettled && isCurrent && playing;
    return GestureDetector(
      onTap: onTapRow,
      behavior: HitTestBehavior.translucent,
      child: ConstrainedBox(
        constraints: const BoxConstraints.expand(),
        child: Stack(
          children: [
            // Pill chrome fades in only near the focal point.
            Opacity(
              opacity: glass,
              child: const GlassSurface(
                tier: GlassTier.card,
                borderRadius: 24,
                child: SizedBox.expand(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Semantics(
                    label: 'Toggle playback for ${track.trackName}',
                    button: true,
                    child: GestureDetector(
                      onTap: onTogglePlay,
                      child: VinylDisc(
                        imageUrl: track.albumArtUrl,
                        size: ExploreTokens.vinylSize,
                        spinning: activePlaying,
                        accent: accent,
                      ),
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
                          GestureDetector(
                            onTap: onOpenPlayer,
                            child: Text(
                              track.trackName,
                              style: const TextStyle(
                                  fontSize: ExploreTokens.titleSize,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                  shadows: [
                                    Shadow(
                                        color: Colors.black54,
                                        blurRadius: 10,
                                        offset: Offset(0, 2)),
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
                                  fontWeight: FontWeight.w500,
                                  color: accent.withValues(alpha: 0.95)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (centrality > 0.6)
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
    );
  }
}

/// Fixed action cluster under the wheel: secondary actions for the
/// ACTIVE track live here so rows stay calm (spec: 5 focused controls).
class WheelActions extends StatelessWidget {
  const WheelActions({
    super.key,
    required this.track,
    required this.liked,
    required this.onLike,
    required this.onQueue,
    required this.onExpand,
    required this.onShare,
    required this.onMore,
    required this.onDislike,
  });

  final Track? track;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onQueue;
  final VoidCallback onExpand;
  final VoidCallback onShare;
  final VoidCallback onMore;
  final VoidCallback onDislike;

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) return const SizedBox.shrink();
    Widget btn({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) =>
        GlassCircleButton(
          icon: icon,
          size: ExploreTokens.controlSizeSmall,
          iconSize: 18,
          semanticLabel: label,
          onTap: onTap,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassSurface(
          tier: GlassTier.card,
          borderRadius: 24,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: SizedBox(
              height: ExploreTokens.railHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  btn(
                      icon: liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: liked ? 'Unlike' : 'Like',
                      onTap: onLike),
                  btn(
                      icon: Icons.playlist_add_rounded,
                      label: 'Add to queue',
                      onTap: onQueue),
                  btn(
                      icon: Icons.open_in_full_rounded,
                      label: 'Open player',
                      onTap: onExpand),
                  btn(
                      icon: Icons.ios_share_rounded,
                      label: 'Share',
                      onTap: onShare),
                  btn(
                      icon: Icons.more_horiz_rounded,
                      label: 'More options',
                      onTap: onMore),
                ],
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: onDislike,
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: Text('Not interested',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.38))),
        ),
      ],
    );
  }
}

/// Shared row actions wired to the existing provider/sheet systems.
/// Kept as a free function so the screen stays a thin composer.
class WheelActionWiring {
  WheelActionWiring._();

  static void openArtist(
      BuildContext context, MusicProvider provider, Track track) {
    ArtistPickerSheet.showIfNeeded(context, provider, track.artistName);
  }

  static Future<void> openMore(BuildContext context, Track track,
      {required VoidCallback onClosed}) {
    return ThemedOptionsSheet.show(context, track: track)
        .then((_) => onClosed());
  }

  static void share(Track track) {
    SharePlus.instance
        .share(ShareParams(text: '${track.trackName} — ${track.artistName}'));
  }
}
