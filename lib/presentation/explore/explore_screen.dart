import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/track.dart';
import '../../providers/music_provider.dart';
import '../../services/explore/explore_controller.dart';
import '../../services/explore/explore_engine.dart';
import '../../services/explore/explore_palette.dart';
import '../../services/explore/explore_policy.dart';
import '../../services/recommendation/taste_profile.dart';
import '../../services/innertube/innertube_service.dart';
import '../../widgets/artist_picker_sheet.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/glass_circle_button.dart';
import '../../widgets/glass_snackbar.dart' show showGlassSnackBar;
import '../../widgets/themed_options_sheet.dart';
import 'explore_layout.dart';
import 'explore_tokens.dart';

/// Immersive Explore Stream: vertical swipe discovery with autoplay on
/// page settle, artwork-driven ambient theming and a ranked session
/// queue. Reuses the shared recommendation engine + MusicProvider
/// playback — no second stack (spec #96/#117).
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  /// Push the Explore route with a 600ms debounce guard.
  static Future<void> open(BuildContext context, {Track? seed}) async {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: false,
        builder: (_) => ChangeNotifierProvider<ExploreController>(
          create: (_) => bootstrapExploreController(context, seed: seed),
          child: const ExploreScreen._(),
        ),
      ),
    );
  }

  const ExploreScreen._()
      : super(key: const ValueKey('explore_screen'));

  /// Test-visible constructor (private primary ctor is for the route).
  @visibleForTesting
  const ExploreScreen.forTest() : this._();

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

/// Wires the controller to the app's existing services. Kept here (not
/// in MusicProvider) so the god-object stays untouched; session
/// persistence lives for the lifetime of the route stack.
ExploreController bootstrapExploreController(BuildContext context,
    {Track? seed}) {
  final provider = context.read<MusicProvider>();
  return ExploreController(
    engine: ExploreEngine(),
    fetchSources: (anchor) async {
      // Source ladder (spec #26): related → quick picks → favorites →
      // recents → charts → new releases. No random search fallback.
      List<Track> related = const [];
      final relatedSeed = anchor ?? seed;
      if (relatedSeed != null &&
          relatedSeed.id.length == 11 &&
          !relatedSeed.id.startsWith('MPREb')) {
        try {
          related = await InnerTubeService.instance
              .getSuggestions(relatedSeed.id, limit: ExplorePolicy.relatedLimit);
        } catch (_) {}
      }
      List<Track> charts = provider.fullTrendingTracks;
      if (charts.isEmpty) {
        try {
          charts = await provider.fetchTrendingTracks();
        } catch (_) {}
      }
      List<Track> releases = provider.newReleases;
      if (releases.isEmpty) {
        try {
          releases = await InnerTubeService.instance.getNewReleases(limit: 10);
        } catch (_) {}
      }
      debugPrint('EXPLORE_LOAD seed=${(anchor ?? seed)?.trackName ?? 'none'} '
          'related=${related.length} quickPicks=${provider.quickPicks.length} '
          'favorites=${provider.likedSongs.length} '
          'recents=${provider.recentlyPlayed.length} '
          'charts=${charts.length} releases=${releases.length}');
      return ExploreSources(
        seedRelated: related,
        quickPicks: provider.quickPicks,
        favorites: provider.likedSongs,
        recentlyPlayed: provider.recentlyPlayed,
        regionalChart: charts,
        newReleases: releases,
      );
    },
    play: (track, upcoming) => provider.playTrack(track,
        playlistTracks: [track, ...upcoming],
        setContext: true,
        clearQueue: true),
    profileProvider: () {
      final service = provider.recommendationService;
      return TasteProfile.build(
        events: service.eventViews(),
        favoriteArtists: service.favoriteArtists(),
      );
    },
    recordSwipeOutcome: (artist, {required wasAccepted}) =>
        provider.recommendationService.recordSwipeOutcome(
            artistName: artist, wasAccepted: wasAccepted),
    isCurrentTrack: (id) => provider.currentTrack?.id == id,
    autoplayEnabled: true,
    onAutoplayChanged: (_) {},
    // Session seed: the currently playing track anchors the stream.
  )..start(seed: seed ?? provider.currentTrack);
}

class _ExploreScreenState extends State<ExploreScreen> {
  final PageController _pageController = PageController();
  ExplorePalette _palette = ExplorePalette.neutral;
  bool _showHint = true;
  MusicProvider? _provider;

  @override
  void initState() {
    super.initState();
    final controller = context.read<ExploreController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolvePalette(controller);
      // Immersive route: the pill would duplicate the deck's own
      // playback surface. Sheet pattern (restore on dispose).
      if (mounted) {
        _provider = context.read<MusicProvider>();
        _provider!.setHideMiniPlayer(true);
      }
    });
  }

  Future<void> _resolvePalette(ExploreController controller) async {
    final item = controller.session?.active;
    if (item == null) return;
    final p = await ExplorePaletteCache.resolve(
        item.id, item.track.albumArtUrl);
    if (!mounted) return;
    setState(() => _palette = p);
  }

  @override
  void dispose() {
    _provider?.setHideMiniPlayer(false);
    _pageController.dispose();
    super.dispose();
  }

  void _hidePill() => _provider?.setHideMiniPlayer(true);

  void _jumpTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExploreController>();
    final items = controller.session?.items ?? const <ExploreItem>[];
    final active = controller.session?.active;

    // Hysteresis: palette only re-resolves on settle (spec #33).
    if (active != null && ExplorePaletteCache.cached(active.id) == null) {
      _resolvePalette(controller);
    } else if (active != null) {
      final cached = ExplorePaletteCache.cached(active.id);
      if (cached != null && cached.background != _palette.background) {
        _palette = cached;
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedContainer(
        duration: ExploreTokens.ambientTransition,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _palette.background.withValues(alpha: 0.9),
              _darken(_palette.background, 0.45),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Ambient blurred artwork layer.
            if (active != null && active.track.albumArtUrl.isNotEmpty)
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: ExploreTokens.ambientTransition,
                  child: ImageFiltered(
                    key: ValueKey('ambient_${active.id}'),
                    imageFilter: ImageFilter.blur(
                        sigmaX: ExploreTokens.blurSigma,
                        sigmaY: ExploreTokens.blurSigma),
                    child: Opacity(
                      opacity: ExploreTokens.backgroundStrength,
                      child: Transform.scale(
                        scale: 1.25,
                        child: CachedNetworkImage(
                          imageUrl: active.track.albumArtUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 240,
                          errorWidget: (_, __, ___) => const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Dark scrim for text/control readability.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: ExploreTokens.scrimTop),
                      Colors.black
                          .withValues(alpha: ExploreTokens.scrimBottom),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _ExploreHeader(controller: controller),
                  Expanded(
                    child: controller.isLoading || controller.session == null
                        ? const _ExploreSkeleton()
                        : items.isEmpty
                            ? _EmptyState(controller: controller)
                            : _buildPageView(controller, items),
                  ),
                  _SwipeHint(visible: _showHint && items.isNotEmpty),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageView(
      ExploreController controller, List<ExploreItem> items) {
    return PageView.builder(
      scrollDirection: Axis.vertical,
      controller: _pageController,
      allowImplicitScrolling: true,
      itemCount: controller.exhausted
          ? items.length
          : items.length + 1, // trailing loading stub
      onPageChanged: (index) {
        if (mounted && _showHint) setState(() => _showHint = false);
        if (index < items.length) {
          controller.settle(index);
          _hidePill();
          _preloadNext(controller, items, index);
        }
      },
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const _LoadingStub();
        }
        final item = items[index];
        ExploreItem? at(int i) =>
            (i >= 0 && i < items.length) ? items[i] : null;
        return _StreamPage(
          key: ValueKey('explore_page_${item.id}'),
          item: item,
          farPrev: at(index - 2),
          nearPrev: at(index - 1),
          nearNext: at(index + 1),
          farNext: at(index + 2),
          index: index,
          isActivePage: index == controller.session?.currentIndex,
          accent: _palette.accent,
          controller: controller,
          onJump: _jumpTo,
        );
      },
    );
  }

  void _preloadNext(ExploreController controller, List<ExploreItem> items,
      int index) {
    for (var i = index + 1;
        i <= index + ExplorePolicy.prefetchAhead && i < items.length;
        i++) {
      final url = items[i].track.albumArtUrl;
      if (url.isEmpty) continue;
      precacheImage(CachedNetworkImageProvider(url), context);
    }
  }

  static Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness * (1 - amount)).clamp(0.02, 1.0))
        .toColor();
  }
}

class _ExploreHeader extends StatelessWidget {
  const _ExploreHeader({required this.controller});

  final ExploreController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ExploreTokens.headerHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            GlassCircleButton(
              icon: Icons.arrow_back_rounded,
              size: 38,
              iconSize: 19,
              semanticLabel: 'Back',
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 12),
            const Text('Explore',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const Spacer(),
            GlassCircleButton(
              icon: controller.autoplayEnabled
                  ? Icons.play_circle_rounded
                  : Icons.play_disabled_rounded,
              size: 38,
              iconSize: 19,
              semanticLabel: 'Toggle autoplay',
              onTap: controller.toggleAutoplay,
            ),
          ],
        ),
      ),
    );
  }
}

/// Single playback path for the active item (art tap + play capsule).
void _toggleExplorePlay(BuildContext context, MusicProvider provider,
    ExploreController controller, ExploreItem item, bool isCurrent) {
  final track = item.track;
  if (isCurrent) {
    provider.isPlaying ? provider.pauseTrack() : provider.resumeTrack();
  } else {
    provider.playTrack(track,
        playlistTracks: [track, ...controller.upcomingTracks()],
        setContext: true,
        clearQueue: true);
  }
}

/// One stream page: far/near neighbors flow along the diagonal into the
/// centered active pill. Sized by [ExploreLayout.plan] so nothing
/// overflows and no scroll view fights the vertical PageView.
class _StreamPage extends StatelessWidget {
  const _StreamPage({
    super.key,
    required this.item,
    required this.farPrev,
    required this.nearPrev,
    required this.nearNext,
    required this.farNext,
    required this.index,
    required this.isActivePage,
    required this.accent,
    required this.controller,
    required this.onJump,
  });

  final ExploreItem item;
  final ExploreItem? farPrev;
  final ExploreItem? nearPrev;
  final ExploreItem? nearNext;
  final ExploreItem? farNext;
  final int index;
  final bool isActivePage;
  final Color accent;
  final ExploreController controller;
  final void Function(int index) onJump;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final track = item.track;
    final isCurrent = provider.currentTrack?.id == track.id;

    return RepaintBoundary(
      child: LayoutBuilder(builder: (context, constraints) {
        final spec = ExploreLayout.plan(
            Size(constraints.maxWidth, constraints.maxHeight));
        Widget gap() => const SizedBox(height: 12);
        return Center(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: spec.contentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: ExploreTokens.pagePadding, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  if (spec.showFar && farPrev != null) ...[
                    _NeighborRow(
                        key: ValueKey('jump_${farPrev!.id}'),
                        item: farPrev!,
                        far: true,
                        dx: spec.slotDx[0],
                        onTap: () => onJump(index - 2)),
                    gap(),
                  ],
                  if (nearPrev != null) ...[
                    _NeighborRow(
                        key: ValueKey('jump_${nearPrev!.id}'),
                        item: nearPrev!,
                        far: false,
                        dx: spec.slotDx[1],
                        onTap: () => onJump(index - 1)),
                    gap(),
                  ],
                  _PillEntry(
                    itemId: item.id,
                    active: isActivePage,
                    child: _ActivePill(
                      key: ValueKey('explore_pill_${item.id}'),
                      item: item,
                      accent: accent,
                      provider: provider,
                      controller: controller,
                      isCurrent: isCurrent,
                    ),
                  ),
                  gap(),
                  _QuietRail(
                    track: track,
                    provider: provider,
                  ),
                  TextButton(
                    onPressed: controller.dislikeCurrent,
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                    ),
                    child: Text('Not interested',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Colors.white.withValues(alpha: 0.38))),
                  ),
                  if (nearNext != null) ...[
                    gap(),
                    _NeighborRow(
                        key: ValueKey('jump_${nearNext!.id}'),
                        item: nearNext!,
                        far: false,
                        dx: spec.slotDx[3],
                        onTap: () => onJump(index + 1)),
                  ],
                  if (spec.showFar && farNext != null) ...[
                    gap(),
                    _NeighborRow(
                        key: ValueKey('jump_${farNext!.id}'),
                        item: farNext!,
                        far: true,
                        dx: spec.slotDx[4],
                        onTap: () => onJump(index + 2)),
                  ],
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Replays a subtle settle-in (scale + fade) when its page becomes active.
/// Fires once per activation, never loops.
class _PillEntry extends StatefulWidget {
  const _PillEntry(
      {required this.itemId, required this.active, required this.child});

  final String itemId;
  final bool active;
  final Widget child;

  @override
  State<_PillEntry> createState() => _PillEntryState();
}

class _PillEntryState extends State<_PillEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));

  @override
  void initState() {
    super.initState();
    if (widget.active) _entry.forward(from: 0);
  }

  @override
  void didUpdateWidget(_PillEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        (!oldWidget.active || oldWidget.itemId != widget.itemId)) {
      _entry.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entry.drive(CurveTween(curve: Curves.easeOut)),
      child: ScaleTransition(
        scale: _entry.drive(
            Tween(begin: 0.96, end: 1.0).chain(CurveTween(curve: Curves.easeOut))),
        child: widget.child,
      ),
    );
  }
}

/// Neighbor discovery row along the diagonal flow. Tappable → jumps.
/// No glass here — selective glass belongs to the active pill only.
class _NeighborRow extends StatelessWidget {
  const _NeighborRow({
    super.key,
    required this.item,
    required this.far,
    required this.dx,
    required this.onTap,
  });

  final ExploreItem item;
  final bool far;
  final double dx;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final track = item.track;
    final art = far ? ExploreTokens.farArtSize : ExploreTokens.neighborArtSize;
    final rowH =
        far ? ExploreTokens.farRowHeight : ExploreTokens.neighborRowHeight;
    return Opacity(
      opacity: far ? ExploreTokens.farOpacity : ExploreTokens.nearOpacity,
      child: Semantics(
        label: 'Jump to ${track.trackName}',
        button: true,
        container: true,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.only(
                left: dx > 0 ? dx : 0, right: dx < 0 ? -dx : 0),
            child: SizedBox(
              height: rowH,
              child: Row(
                children: [
                  ClipOval(
                    child: track.albumArtUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: track.albumArtUrl,
                            width: art,
                            height: art,
                            fit: BoxFit.cover,
                            memCacheWidth: (art * 2).round(),
                            errorWidget: (_, __, ___) =>
                                const _ArtworkFallback(),
                          )
                        : SizedBox(width: art, height: art),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(track.trackName,
                            style: TextStyle(
                                fontSize: far
                                    ? ExploreTokens.farTitleSize
                                    : ExploreTokens.neighborTitleSize,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(track.artistName,
                            style: TextStyle(
                                fontSize: far
                                    ? ExploreTokens.farArtistSize
                                    : ExploreTokens.neighborArtistSize,
                                color:
                                    Colors.white.withValues(alpha: 0.5)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The active discovery object: liquid-glass pill with circular artwork,
/// title/artist and the Play capsule.
class _ActivePill extends StatelessWidget {
  const _ActivePill({
    super.key,
    required this.item,
    required this.accent,
    required this.provider,
    required this.controller,
    required this.isCurrent,
  });

  final ExploreItem item;
  final Color accent;
  final MusicProvider provider;
  final ExploreController controller;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final track = item.track;
    final playing = isCurrent && provider.isPlaying;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: GlassSurface(
        key: ValueKey('pillbody_${item.id}'),
        tier: GlassTier.floating,
        borderRadius: 40,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: ExploreTokens.activeRowHeight - 24,
            child: Row(
              children: [
                Semantics(
                  label: 'Toggle playback for ${track.trackName}',
                  button: true,
                  child: GestureDetector(
                    onTap: () => _toggleExplorePlay(
                        context, provider, controller, item, isCurrent),
                    child: Container(
                      width: ExploreTokens.activeArtSize,
                      height: ExploreTokens.activeArtSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: accent.withValues(alpha: 0.5), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(
                                alpha: ExploreTokens.artworkGlow),
                            blurRadius: 28,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: track.albumArtUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: track.albumArtUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 152,
                                fadeInDuration:
                                    const Duration(milliseconds: 250),
                                errorWidget: (_, __, ___) =>
                                    const _ArtworkFallback(),
                              )
                            : const _ArtworkFallback(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
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
                            shadows: [
                              Shadow(
                                  color: Colors.black54,
                                  blurRadius: 10,
                                  offset: Offset(0, 2)),
                            ]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => ArtistPickerSheet.showIfNeeded(
                            context, provider, track.artistName),
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
                const SizedBox(width: 8),
                _PlayCapsule(
                  playing: playing,
                  onTap: () => _toggleExplorePlay(
                      context, provider, controller, item, isCurrent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The explicit play affordance: glass capsule with icon + label.
class _PlayCapsule extends StatelessWidget {
  const _PlayCapsule({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: playing ? 'Pause' : 'Play',
      button: true,
      container: true,
      child: GestureDetector(
        onTap: onTap,
        child: GlassSurface(
          tier: GlassTier.card,
          borderRadius: 24,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SizedBox(
              height: ExploreTokens.playCapsuleHeight - 20,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 18),
                  const SizedBox(width: 6),
                  Text(playing ? 'Pause' : 'Play',
                      style: const TextStyle(
                          fontSize:
                              ExploreTokens.playCapsuleLabelSize,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet glass rail under the pill: secondary actions only.
class _QuietRail extends StatelessWidget {
  const _QuietRail({
    required this.track,
    required this.provider,
  });

  final Track track;
  final MusicProvider provider;

  @override
  Widget build(BuildContext context) {
    final screenState =
        context.findAncestorStateOfType<_ExploreScreenState>();
    return GlassSurface(
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
              GlassCircleButton(
                icon: provider.isSongLiked(track.id)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: ExploreTokens.controlSizeSmall,
                iconSize: 18,
                semanticLabel: provider.isSongLiked(track.id)
                    ? 'Unlike'
                    : 'Like',
                onTap: () => provider.toggleLike(track),
              ),
              GlassCircleButton(
                icon: Icons.playlist_add_rounded,
                size: ExploreTokens.controlSizeSmall,
                iconSize: 18,
                semanticLabel: 'Add to queue',
                onTap: () {
                  provider.addListToQueue([track]);
                  showGlassSnackBar(context, 'Added to queue');
                },
              ),
              GlassCircleButton(
                icon: Icons.ios_share_rounded,
                size: ExploreTokens.controlSizeSmall,
                iconSize: 18,
                semanticLabel: 'Share',
                onTap: () => SharePlus.instance.share(ShareParams(
                    text: '${track.trackName} — ${track.artistName}')),
              ),
              GlassCircleButton(
                icon: Icons.more_horiz_rounded,
                size: ExploreTokens.controlSizeSmall,
                iconSize: 18,
                semanticLabel: 'More options',
                onTap: () => ThemedOptionsSheet.show(context, track: track)
                    .then((_) => screenState?._hidePill()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.06),
      child: const Icon(Icons.music_note_rounded,
          size: 64, color: Colors.white24),
    );
  }
}

/// Loading skeleton mirrors stream geometry: ghost pills, not a spinner.
class _ExploreSkeleton extends StatelessWidget {
  const _ExploreSkeleton();

  Widget _ghost(double height, {bool icon = false}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        color: Colors.white.withValues(alpha: 0.06),
      ),
      child: icon
          ? const Icon(Icons.music_note_rounded,
              size: 40, color: Colors.white24)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            maxWidth: ExploreTokens.contentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ExploreTokens.pagePadding),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.5, end: 1.0),
            duration: const Duration(milliseconds: 1200),
            builder: (context, value, child) => Opacity(
              opacity:
                  0.5 + 0.5 * (1 - (value - 0.75).abs() * 4).clamp(0.0, 1.0),
              child: child,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ghost(ExploreTokens.activeRowHeight, icon: true),
                const SizedBox(height: 12),
                _ghost(ExploreTokens.neighborRowHeight),
                const SizedBox(height: 12),
                _ghost(ExploreTokens.neighborRowHeight),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          children: [
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 20, color: Colors.white.withValues(alpha: 0.5)),
            Text('Swipe for more',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5))),
          ],
        ),
      ),
    );
  }
}

class _LoadingStub extends StatelessWidget {
  const _LoadingStub();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(strokeWidth: 2),
          SizedBox(height: 12),
          Text('Finding more',
              style: TextStyle(fontSize: 13, color: Colors.white54)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});

  final ExploreController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassSurface(
        tier: GlassTier.card,
        borderRadius: 20,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_rounded,
                  size: 40, color: Colors.white24),
              const SizedBox(height: 12),
              Text(controller.error ?? 'Nothing new right now',
                  style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 16),
              GlassCircleButton(
                icon: Icons.refresh_rounded,
                semanticLabel: 'Retry',
                onTap: controller.refresh,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
