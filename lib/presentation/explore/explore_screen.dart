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
import '../../widgets/glass_surface.dart';
import '../../widgets/glass_circle_button.dart';
import '../../widgets/glass_snackbar.dart' show showGlassSnackBar;
import '../../widgets/liquid_play_button.dart';
import '../../widgets/themed_options_sheet.dart';
import '../../services/recommendation/candidate.dart';
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

  const ExploreScreen._() : super(key: const ValueKey('explore_screen'));

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

  @override
  void initState() {
    super.initState();
    final controller = context.read<ExploreController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolvePalette(controller);
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
    _pageController.dispose();
    super.dispose();
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
                  ),
                  Expanded(
                    child: controller.isLoading
                        ? const Center(child: CircularProgressIndicator())
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
          _preloadNext(controller, items, index);
        }
      },
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const _LoadingStub();
        }
        final item = items[index];
        return _ExplorePage(
          key: ValueKey('explore_page_${item.id}'),
          item: item,
          accent: _palette.accent,
          isBright: _palette.isBright,
          controller: controller,
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
  const _ExploreHeader({required this.controller, required this.accent});

  final ExploreController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          GlassCircleButton(
            icon: Icons.arrow_back_rounded,
            size: 42,
            iconSize: 20,
            semanticLabel: 'Back',
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          const Text('Explore',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (session != null && session.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${session.currentIndex + 1} · ${session.remaining.length} left',
                style: TextStyle(
                    fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
              ),
            ),
          if (!controller.autoplayEnabled)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text('Autoplay off',
                  style: TextStyle(fontSize: 11, color: Colors.white54)),
            ),
          GlassCircleButton(
            icon: controller.autoplayEnabled
                ? Icons.play_circle_rounded
                : Icons.play_disabled_rounded,
            size: 42,
            iconSize: 20,
            semanticLabel: 'Toggle autoplay',
            onTap: controller.toggleAutoplay,
          ),
        ],
      ),
    );
  }
}

class _ExplorePage extends StatelessWidget {
  const _ExplorePage({
    super.key,
    required this.item,
    required this.accent,
    required this.isBright,
    required this.controller,
  });

  final ExploreItem item;
  final Color accent;
  final bool isBright;
  final ExploreController controller;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final track = item.track;
    final isCurrent = provider.currentTrack?.id == track.id;

    return RepaintBoundary(
      child: LayoutBuilder(builder: (context, constraints) {
        final artworkWidth = (constraints.maxWidth - ExploreTokens.pagePadding * 2)
            .clamp(0.0, double.infinity) *
            ExploreTokens.artworkFraction;
        final artwork = artworkWidth.clamp(0.0, ExploreTokens.artworkMaxWidth);

        return Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ExploreTokens.pagePadding, vertical: 8),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ArtworkPanel(
                      track: track, size: artwork, accent: accent),
                  const SizedBox(height: 24),
                  GlassSurface(
                    tier: GlassTier.card,
                    borderRadius: 20,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            label: '${track.trackName} by ${track.artistName}',
                            child: Text(
                              track.trackName,
                              style: const TextStyle(
                                  fontSize: ExploreTokens.titleSize,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            track.artistName,
                            style: TextStyle(
                                fontSize: ExploreTokens.artistSize,
                                fontWeight: FontWeight.w500,
                                color: accent.withValues(alpha: 0.95)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (track.albumName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              track.albumName,
                              style: TextStyle(
                                  fontSize: ExploreTokens.metaSize,
                                  color:
                                      Colors.white.withValues(alpha: 0.55)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 8),
                          _ReasonChip(
                              reason: item.reason,
                              isExploration: item.isExploration),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: ExploreTokens.metadataGap),
                  _Controls(
                    track: track,
                    provider: provider,
                    controller: controller,
                    isCurrent: isCurrent,
                    accent: accent,
                  ),
                ],
              ),
            ),
          ),
        );
      }),
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

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.reason, required this.isExploration});

  final CandidateReason reason;
  final bool isExploration;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.08),
      ),
      child: Text(
        ExplorePolicy.reasonLabel(reason),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.7)),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.track,
    required this.provider,
    required this.controller,
    required this.isCurrent,
    required this.accent,
  });

  final Track track;
  final MusicProvider provider;
  final ExploreController controller;
  final bool isCurrent;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final playing = isCurrent && provider.isPlaying;
    return GlassSurface(
      tier: GlassTier.floating,
      borderRadius: 30,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            GlassCircleButton(
              icon: provider.isSongLiked(track.id)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              size: 48,
              semanticLabel: provider.isSongLiked(track.id)
                  ? 'Unlike'
                  : 'Like',
              onTap: () => provider.toggleLike(track),
            ),
            LiquidPlayButton(
              isPlaying: playing,
              onPressed: () {
                if (isCurrent) {
                  provider.isPlaying
                      ? provider.pauseTrack()
                      : provider.resumeTrack();
                } else {
                  provider.playTrack(track,
                      playlistTracks: [
                        track,
                        ...controller.upcomingTracks()
                      ],
                      setContext: true,
                      clearQueue: true);
                }
              },
            ),
            GlassCircleButton(
              icon: Icons.playlist_add_rounded,
              size: 48,
              semanticLabel: 'Add to queue',
              onTap: () {
                provider.addListToQueue([track]);
                showGlassSnackBar(context, 'Added to queue');
              },
            ),
            GlassCircleButton(
              icon: Icons.ios_share_rounded,
              size: 48,
              semanticLabel: 'Share',
              onTap: () => SharePlus.instance.share(ShareParams(
                  text: '${track.trackName} — ${track.artistName}')),
            ),
            GlassCircleButton(
              icon: Icons.more_horiz_rounded,
              size: 48,
              semanticLabel: 'More options',
              onTap: () =>
                  ThemedOptionsSheet.show(context, track: track),
            ),
          ],
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
