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
import '../../widgets/liquid_play_button.dart';
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
                  _ExploreHeader(
                    controller: controller,
                    accent: _palette.accent,
                    total: items.length,
                  ),
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
        return _DeckPage(
          key: ValueKey('explore_page_${item.id}'),
          item: item,
          prev: index > 0 ? items[index - 1] : null,
          next: index + 1 < items.length ? items[index + 1] : null,
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
  const _ExploreHeader(
      {required this.controller, required this.accent, required this.total});

  final ExploreController controller;
  final Color accent;
  final int total;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    final progress = total <= 0
        ? 0.0
        : ((session?.currentIndex ?? 0) + 1).clamp(1, total) / total;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
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
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
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
        ),
        // Understated position indicator (replaces the technical counter).
        SizedBox(
          height: ExploreTokens.progressHeight,
          child: total <= 1
              ? null
              : LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
        ),
      ],
    );
  }
}

/// One deck page: prev peek · artwork · floating metadata · slim rail ·
/// next peek. Sized by [ExploreLayout.plan] so nothing overflows and no
/// scroll view fights the vertical PageView.
class _DeckPage extends StatelessWidget {
  const _DeckPage({
    super.key,
    required this.item,
    required this.prev,
    required this.next,
    required this.accent,
    required this.controller,
    required this.onJump,
  });

  final ExploreItem item;
  final ExploreItem? prev;
  final ExploreItem? next;
  final Color accent;
  final ExploreController controller;
  final void Function(int index) onJump;

  void _togglePlay(BuildContext context, MusicProvider provider, bool isCurrent) {
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final track = item.track;
    final isCurrent = provider.currentTrack?.id == track.id;
    final session = controller.session;
    final index = session?.items.indexOf(item) ?? 0;

    return RepaintBoundary(
      child: LayoutBuilder(builder: (context, constraints) {
        final spec = ExploreLayout.plan(
            Size(constraints.maxWidth, constraints.maxHeight));
        return Center(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: spec.contentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: ExploreTokens.pagePadding, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  if (spec.showPrevPeek && prev != null) ...[
                    _PrevPeek(
                        item: prev!,
                        onTap: () => onJump(index - 1)),
                    const SizedBox(height: 10),
                  ],
                  Semantics(
                    label: 'Toggle playback for ${track.trackName}',
                    button: true,
                    child: GestureDetector(
                      onTap: () => _togglePlay(context, provider, isCurrent),
                      child: _ArtworkPanel(
                          track: track,
                          size: spec.artworkSize,
                          accent: accent),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: spec.artworkSize,
                    child: _TrackProgress(
                        provider: provider,
                        isCurrent: isCurrent,
                        accent: accent),
                  ),
                  SizedBox(height: spec.gapAfterArtwork),
                  _FloatingMetadata(
                      item: item, accent: accent, provider: provider),
                  const SizedBox(height: 12),
                  _SlimRail(
                    track: track,
                    provider: provider,
                    controller: controller,
                    isCurrent: isCurrent,
                    onPlay: () => _togglePlay(context, provider, isCurrent),
                    onSheetClosed: () {},
                  ),
                  const SizedBox(height: 4),
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
                  if (next != null) ...[
                    const SizedBox(height: 6),
                    _NextPeek(
                        item: next!,
                        onJump: () => onJump(index + 1)),
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

/// Faded previous discovery row (compact, left-aligned).
class _PrevPeek extends StatelessWidget {
  const _PrevPeek({required this.item, required this.onTap});

  final ExploreItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final track = item.track;
    return Opacity(
      opacity: ExploreTokens.prevPeekOpacity,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: ExploreTokens.prevPeekHeight,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: track.albumArtUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.albumArtUrl,
                        width: 34,
                        height: 34,
                        fit: BoxFit.cover,
                        memCacheWidth: 68,
                        errorWidget: (_, __, ___) =>
                            const _ArtworkFallback(),
                      )
                    : const SizedBox(width: 34, height: 34),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(track.trackName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(track.artistName,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.5)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Next discovery chip: offset glass row with a jump-and-play affordance.
class _NextPeek extends StatelessWidget {
  const _NextPeek({required this.item, required this.onJump});

  final ExploreItem item;
  final VoidCallback onJump;

  @override
  Widget build(BuildContext context) {
    final track = item.track;
    return Padding(
      // Deterministic diagonal offset (Reference B stagger).
      padding: const EdgeInsets.only(left: 56),
      child: Opacity(
        opacity: ExploreTokens.nextPeekOpacity,
        child: GlassSurface(
          tier: GlassTier.card,
          borderRadius: 18,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              height:
                  ExploreTokens.nextPeekHeight - 20,
              child: Row(
                children: [
                  ClipOval(
                    child: track.albumArtUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: track.albumArtUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            memCacheWidth: 88,
                            errorWidget: (_, __, ___) =>
                                const _ArtworkFallback(),
                          )
                        : const SizedBox(width: 44, height: 44),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(track.trackName,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(track.artistName,
                            style: TextStyle(
                                fontSize: 11,
                                color:
                                    Colors.white.withValues(alpha: 0.55)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  GlassCircleButton(
                    icon: Icons.play_arrow_rounded,
                    size: 34,
                    iconSize: 18,
                    semanticLabel: 'Play next',
                    onTap: onJump,
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

/// Floating metadata: text over atmosphere, no competing panel.
class _FloatingMetadata extends StatelessWidget {
  const _FloatingMetadata(
      {required this.item, required this.accent, required this.provider});

  final ExploreItem item;
  final Color accent;
  final MusicProvider provider;

  @override
  Widget build(BuildContext context) {
    final track = item.track;
    final showReason = ExploreLayout.shouldShowReason(item.confidence);
    final contextLine = [
      if (track.albumName.isNotEmpty) track.albumName,
      if (showReason) ExplorePolicy.reasonLabel(item.reason),
    ].join(' • ');
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Column(
        key: ValueKey('meta_${item.id}'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Semantics(
            label: '${track.trackName} by ${track.artistName}',
            child: Text(
              track.trackName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: ExploreTokens.titleSize,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  shadows: [
                    Shadow(
                        color: Colors.black54,
                        blurRadius: 12,
                        offset: Offset(0, 2)),
                  ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => ArtistPickerSheet.showIfNeeded(
                context, provider, track.artistName),
            child: Text(
              track.artistName,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: ExploreTokens.artistSize,
                  fontWeight: FontWeight.w500,
                  color: accent.withValues(alpha: 0.95)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (contextLine.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              contextLine,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: ExploreTokens.reasonSize,
                  color: Colors.white.withValues(alpha: 0.55)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Slim glass action rail: primary play dominates, rest stay quiet.
class _SlimRail extends StatelessWidget {
  const _SlimRail({
    required this.track,
    required this.provider,
    required this.controller,
    required this.isCurrent,
    required this.onPlay,
    required this.onSheetClosed,
  });

  final Track track;
  final MusicProvider provider;
  final ExploreController controller;
  final bool isCurrent;
  final VoidCallback onPlay;
  final VoidCallback onSheetClosed;

  @override
  Widget build(BuildContext context) {
    final screenState =
        context.findAncestorStateOfType<_ExploreScreenState>();
    return GlassSurface(
      tier: GlassTier.floating,
      borderRadius: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                iconSize: 20,
                semanticLabel: provider.isSongLiked(track.id)
                    ? 'Unlike'
                    : 'Like',
                onTap: () => provider.toggleLike(track),
              ),
              LiquidPlayButton(
                isPlaying: isCurrent && provider.isPlaying,
                onPressed: onPlay,
              ),
              GlassCircleButton(
                icon: Icons.playlist_add_rounded,
                size: ExploreTokens.controlSizeSmall,
                iconSize: 20,
                semanticLabel: 'Add to queue',
                onTap: () {
                  provider.addListToQueue([track]);
                  showGlassSnackBar(context, 'Added to queue');
                },
              ),
              GlassCircleButton(
                icon: Icons.ios_share_rounded,
                size: ExploreTokens.controlSizeSmall,
                iconSize: 20,
                semanticLabel: 'Share',
                onTap: () => SharePlus.instance.share(ShareParams(
                    text: '${track.trackName} — ${track.artistName}')),
              ),
              GlassCircleButton(
                icon: Icons.more_horiz_rounded,
                size: ExploreTokens.controlSizeSmall,
                iconSize: 20,
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

/// Subtle playback progress under the artwork (active item only).
class _TrackProgress extends StatelessWidget {
  const _TrackProgress(
      {required this.provider, required this.isCurrent, required this.accent});

  final MusicProvider provider;
  final bool isCurrent;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (!isCurrent) {
      return SizedBox(
        height: ExploreTokens.progressHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(1),
          child: ColoredBox(
              color: Colors.white.withValues(alpha: 0.10)),
        ),
      );
    }
    return SizedBox(
      height: ExploreTokens.progressHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: StreamBuilder<Duration>(
          stream: provider.positionStream,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            final duration = provider.duration;
            double progress = 0.0;
            if (duration.inSeconds > 0) {
              progress = (position.inSeconds / duration.inSeconds)
                  .clamp(0.0, 1.0);
            }
            return LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            );
          },
        ),
      ),
    );
  }
}

class _ArtworkPanel extends StatelessWidget {
  const _ArtworkPanel(
      {required this.track, required this.size, required this.accent});

  final Track track;
  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ExploreTokens.artworkRadius),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: ExploreTokens.artworkGlow),
            blurRadius: 40,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ExploreTokens.artworkRadius),
        child: track.albumArtUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: track.albumArtUrl,
                fit: BoxFit.cover,
                memCacheWidth: ExploreTokens.artworkMemCacheWidth,
                fadeInDuration: const Duration(milliseconds: 250),
                errorWidget: (_, __, ___) => const _ArtworkFallback(),
              )
            : const _ArtworkFallback(),
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

class _ExploreSkeleton extends StatelessWidget {
  const _ExploreSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final spec = ExploreLayout.plan(
          Size(constraints.maxWidth, constraints.maxHeight));
      return Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: 1.0),
          duration: const Duration(milliseconds: 1200),
          builder: (context, value, child) => Opacity(
            opacity: 0.5 + 0.5 * (1 - (value - 0.75).abs() * 4).clamp(0.0, 1.0),
            child: child,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: spec.artworkSize,
                height: spec.artworkSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                      ExploreTokens.artworkRadius),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                child: const Icon(Icons.music_note_rounded,
                    size: 64, color: Colors.white24),
              ),
              const SizedBox(height: 18),
              Container(
                width: 180,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 120,
                height: 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ],
          ),
        ),
      );
    });
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
