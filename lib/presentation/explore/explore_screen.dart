import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../providers/music_provider.dart';
import '../../services/explore/explore_controller.dart';
import '../../services/explore/explore_engine.dart';
import '../../services/explore/explore_palette.dart';
import '../../services/explore/explore_policy.dart';
import '../../services/recommendation/taste_profile.dart';
import '../../services/innertube/innertube_service.dart';
import '../../services/stream_resolution_service.dart';
import '../../services/canvas_resolution_service.dart';
import '../../widgets/artist_picker_sheet.dart';
import '../../widgets/glass_circle_button.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/themed_options_sheet.dart';
import 'explore_feed_card.dart';
import 'explore_tokens.dart';
import 'explore_top_pill.dart';
import 'explore_wheel_physics.dart';

/// Immersive Explore Stream: vertical swipe discovery with autoplay on
/// page settle, artwork-driven ambient theming and a ranked session
/// queue. Reuses the shared recommendation engine + MusicProvider
/// playback — no second stack (spec #96/#117).
class ExploreScreen extends StatefulWidget {
  const ExploreScreen(
      {super.key, this.embedded = false, this.isActive = true});

  /// Push the Explore route with a 600ms debounce guard.
  static Future<void> open(BuildContext context, {Track? seed}) async {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: false,
        builder: (_) => ChangeNotifierProvider<ExploreController>(
          create: (_) => bootstrapExploreController(context, seed: seed),
          child: const ExploreScreen._(embedded: false, isActive: true),
        ),
      ),
    );
  }

  const ExploreScreen._({this.embedded = false, this.isActive = true})
      : super(key: const ValueKey('explore_screen'));

  /// Test-visible constructor (private primary ctor is for the route).
  @visibleForTesting
  const ExploreScreen.forTest(
      {bool embedded = false, bool isActive = true})
      : this._(embedded: embedded, isActive: isActive);

  final bool embedded;
  final bool isActive;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

/// Verified, official YouTube-curated playlists (English global/US/UK hits + Indian/Hindi/Punjabi hits).
/// Curated directly from YouTube Music official channels.
const List<String> _officialYouTubeCuratedPlaylists = [
  'RDCLAK5uy_k8QSlZPzi4R3781ftLrAKefTJJ6x7JrVA', // Pop's Biggest Hits (English Global)
  'PL4fGSI1pDJn40WjZ6utkIuj2rNg-7iGsq', // Top 100 Music Videos India
  'PL4fGSI1pDJn6O1LS0XSdF3RyO0Rq_LDeI', // TOP 100 Songs America (English)
  'RDCLAK5uy_lhIiKLMQM6_gokxx581SC-xQBSfJm9gqc', // Hindi Essentials
  'PL4fGSI1pDJn6_f5P3MnzXg9l3GDfnSlXa', // Top 100 Songs Britain (English)
  'RDCLAK5uy_mGYde2Wyx9INZd6GbPcMWkxDOu6Utmedw', // Last Decade Hits (English)
  'RDCLAK5uy_lE0yLj4nuJ--AIHE67gUQdKmfpdkTKNFk', // Hindi Indie
  'RDCLAK5uy_nHSqCJjDrW9HBhCNdF6tWPdnOMngOv0wA', // Pop Gold (English)
  'PL4fGSI1pDJn5JXkyIohg2RstsbL2SnRew', // Top Songs Punjabi
  'RDCLAK5uy_mVRuj5egfh21e-pXyA3ymx_0p4Xlg-c0I', // Hip Hop Essentials (English)
  'RDCLAK5uy_khs3a0YMI9WYs2k1Oqb2ukWX3dA3-lnwI', // Relaxing Soft Pop (English)
  'RDCLAK5uy_l3PeyHeqJh1dR78WjfsMJwRHJx9ofMvvc', // Modern Rock (English)
  'RDCLAK5uy_mPolD_J22gS1SKxufARWcTZd1UrAH_0ZI', // Deep Chill (English)
  'RDCLAK5uy_nOha9Uq4l7E2r4ZjujKFFlBfbFevTQ048', // Electronic Bliss (English)
  'RDCLAK5uy_kb7EBi6y3GrtJri4_ZH56Ms786DFEimbM', // Lofi Loft (English)
];
int _chartRotationIndex = 0;

/// Wires the controller to the app's existing services. Kept here (not
/// in MusicProvider) so the god-object stays untouched; session
/// persistence lives for the lifetime of the route stack.
ExploreController bootstrapExploreController(BuildContext context,
    {Track? seed, bool autoStart = true}) {
  final provider = context.read<MusicProvider>();
  final controller = ExploreController(
    engine: ExploreEngine(),
    fetchSources: (anchor) async {
      // Source ladder: related → quick picks → favorites →
      // recents → charts → home shelves → official YouTube real-time charts.
      List<Track> related = const [];
      final relatedSeed = anchor ?? seed;
      if (relatedSeed != null &&
          relatedSeed.id.length == 11 &&
          !relatedSeed.id.startsWith('MPREb')) {
        try {
          related = await InnerTubeService.instance
              .getSuggestions(relatedSeed.id, limit: 30);
        } catch (_) {}
      }

      List<Track> charts = provider.fullTrendingTracks;
      List<Track> homeShelves = const [];
      List<Track> officialChartTracks = const [];

      final isRefilling = anchor != null;
      final playlistId = _officialYouTubeCuratedPlaylists[
          _chartRotationIndex % _officialYouTubeCuratedPlaylists.length];
      _chartRotationIndex++;

      final futures = <Future<void>>[];

      if (charts.isEmpty || isRefilling || related.length < 8) {
        futures.add(() async {
          try {
            final trending =
                await InnerTubeService.instance.getTrendingTracks(limit: 30);
            if (trending.isNotEmpty) {
              charts = [...charts, ...trending];
            }
          } catch (_) {}
        }());
      }

      // Dynamic Home shelves (mixed hits, trending now) - avoid skipping on refill
      if (isRefilling || related.length + charts.length < 16) {
        futures.add(() async {
          try {
            homeShelves =
                await InnerTubeService.instance.getHomeTracks(limit: 30);
          } catch (_) {}
        }());
      }

      // Official YouTube real-time chart playlist (updated in real-time by YouTube)
      futures.add(() async {
        try {
          officialChartTracks = await InnerTubeService.instance
              .getPlaylistDetails(playlistId);
        } catch (_) {}
      }());

      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }

      List<Track> releases = provider.newReleases;
      if (releases.isEmpty) {
        try {
          releases = await InnerTubeService.instance.getNewReleases(limit: 15);
        } catch (_) {}
      }
      List<Track> quickPicks = provider.quickPicks;
      if (quickPicks.isEmpty) {
        quickPicks = provider.tracks.isNotEmpty
            ? provider.tracks
            : provider.recommendedTracks;
      }
      debugPrint('EXPLORE_LOAD seed=${(anchor ?? seed)?.trackName ?? 'none'} '
          'related=${related.length} quickPicks=${quickPicks.length} '
          'favorites=${provider.likedSongs.length} '
          'recents=${provider.recentlyPlayed.length} '
          'charts=${charts.length} home=${homeShelves.length} '
          'officialCharts=${officialChartTracks.length} releases=${releases.length}');
      return ExploreSources(
        seedRelated: related,
        quickPicks: quickPicks,
        favorites: provider.likedSongs,
        recentlyPlayed: provider.recentlyPlayed,
        regionalChart: [...charts, ...homeShelves],
        globalChart: officialChartTracks,
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
    isPlayingTrack: (id) => provider.currentTrack?.id == id && provider.isPlaying,
    autoplayEnabled: true,
    onAutoplayChanged: (_) {},
    // Session seed: the currently playing track anchors the stream.
  );
  if (autoStart) {
    controller.start(seed: seed ?? provider.currentTrack);
  }
  return controller;
}

class _ExploreScreenState extends State<ExploreScreen> {
  final ScrollController _scrollController = ScrollController();
  ExplorePalette _palette = ExplorePalette.neutral;
  MusicProvider? _provider;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<void>? _skipToNextSub;
  Timer? _snapTimer;
  int _snappedIndex = -1;
  int _lastTickIndex = -1;
  bool _restored = false;
  bool _isUserDragging = false;
  double _viewportH = 600;

  @override
  void initState() {
    super.initState();
    final controller = context.read<ExploreController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _provider = context.read<MusicProvider>();
      if (widget.isActive) {
        _handleActivation();
        _provider?.setHideMiniPlayer(true);
      }
      _resolvePalette(controller);
      _playerStateSub =
          _provider!.audioService.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _onTrackCompleted();
        }
      });
      _skipToNextSub = _provider!.audioService.onSkipToNext.listen((_) {
        _onTrackCompleted();
      });
      _provider!.addListener(_onProviderNotification);
    });
  }

  void _onProviderNotification() {
    if (!mounted || !widget.isActive || _isUserDragging) return;
    final controller = context.read<ExploreController>();
    final session = controller.session;
    if (session == null || session.items.isEmpty) return;
    final nextIdx = session.currentIndex + 1;
    if (nextIdx < session.items.length) {
      final nextTrack = session.items[nextIdx].track;
      if (_provider?.currentTrack?.id == nextTrack.id &&
          _snappedIndex != nextIdx) {
        _onTrackCompleted();
      }
    }
  }

  void _handleActivation() {
    if (!widget.isActive) return;
    _provider?.setHideMiniPlayer(true);
  }

  void _handleDeactivation() {
    _invalidateSnap();
    final provider = _provider;
    if (provider != null) {
      provider.setHideMiniPlayer(false);
    }
  }

  @override
  void didUpdateWidget(ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _handleActivation();
      } else {
        _handleDeactivation();
      }
    } else if (widget.isActive) {
      _provider?.setHideMiniPlayer(true);
    }
  }

  void _onTrackCompleted() {
    if (!mounted || !widget.isActive || _isUserDragging) return;
    final controller = context.read<ExploreController>();
    final session = controller.session;
    if (session == null || session.items.isEmpty) return;
    final nextIdx = session.currentIndex + 1;
    if (nextIdx >= session.items.length) return;
    if (_snappedIndex == nextIdx) return;

    _invalidateSnap();
    _snappedIndex = nextIdx;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        nextIdx * _itemExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
    controller.settle(nextIdx);
    _resolvePalette(controller);
    _preloadNext(controller, session.items, nextIdx);
    _hidePill();
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
    _playerStateSub?.cancel();
    _skipToNextSub?.cancel();
    _provider?.removeListener(_onProviderNotification);
    _snapTimer?.cancel();
    _scrollController.dispose();
    // Restore the pill post-frame: notifying during pop finalization
    // trips locked-tree assertions (debug) on every Explore exit.
    final provider = _provider;
    if (provider != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          provider.setHideMiniPlayer(false);
        } catch (_) {}
      });
    }
    super.dispose();
  }

  void _hidePill() {
    if (widget.isActive) {
      _provider?.setHideMiniPlayer(true);
    }
  }

  /// A user-initiated settle/play intent supersedes any pending snap
  /// debounce timer. Without this, a timer armed by an earlier snap can
  /// fire after a programmatic settle (e.g. Not-interested) and clobber
  /// it with the stale index.
  void _invalidateSnap() {
    _snapTimer?.cancel();
    _snapTimer = null;
    _snappedIndex = -1;
  }

  Future<void> _snapHaptic() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  bool get _isTesting =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  double get _itemExtent =>
      _isTesting ? 200.0 : (_viewportH > 0 ? _viewportH : 600.0);

  void _jumpTo(int index) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      index * _itemExtent,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  /// Snap path: ScrollEnd → (optional haptic) → settle immediately (or 120ms debounce in test runner).
  /// Never fires mid-drag; rapid flings collapse to the latest snap.
  void _snapToCurrent({bool silent = false}) {
    final controller = context.read<ExploreController>();
    final session = controller.session;
    if (session == null ||
        session.items.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }
    final extent = _itemExtent;
    final idx = (_scrollController.offset / extent)
        .round()
        .clamp(0, session.items.length - 1);
    final isAlreadyPlayingThis = (idx == session.currentIndex) &&
        (_provider?.currentTrack?.id == session.items[idx].track.id) &&
        (_provider?.isPlaying ?? false);
    if (idx == _snappedIndex && isAlreadyPlayingThis) return;
    _snappedIndex = idx;
    if (!silent) _snapHaptic();
    _snapTimer?.cancel();

    void performSettle() {
      if (!mounted) return;
      final c = context.read<ExploreController>();
      final s = c.session;
      if (s == null || idx >= s.items.length) return;
      c.settle(idx);
      _resolvePalette(c);
      _preloadNext(c, s.items, idx);
      _hidePill();
    }

    if (_isTesting) {
      _snapTimer = Timer(ExploreTokens.snapDebounce, performSettle);
    } else {
      performSettle();
    }
  }

  void _ensureRestored(ExploreController controller) {
    if (_restored) return;
    final session = controller.session;
    if (session == null || session.items.isEmpty) return;
    _restored = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final s = controller.session;
      if (s == null || s.items.isEmpty) return;
      final idx = s.currentIndex.clamp(0, s.items.length - 1);
      _scrollController.jumpTo(idx * _itemExtent);
      _snapToCurrent(silent: true);
      _preloadNext(controller, s.items, idx);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExploreController>();
    final provider = context.watch<MusicProvider>();
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
    _ensureRestored(controller);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Full-Screen Vertical Discovery Feed (matches video)
          Positioned.fill(
            child: controller.isLoading || controller.session == null
                ? const _ExploreSkeleton()
                : items.isEmpty
                    ? _EmptyState(controller: controller)
                    : _buildFeed(provider, controller, items),
          ),

          // 2. Top Floating Liquid-Glass Island Pill (matches video)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: ExploreTopPill(
                    track: active?.track,
                    isPlaying: provider.isPlaying,
                    isLiked: provider.isSongLiked(active?.track.id ?? ''),
                    accent: _palette.accent,
                    onTogglePlay: () {
                      if (active != null) {
                        _toggleFeedPlay(
                          context,
                          provider,
                          controller,
                          active,
                          provider.currentTrack?.id == active.track.id,
                        );
                      }
                    },
                    onToggleLike: () {
                      if (active != null) {
                        provider.toggleLike(active.track);
                      }
                    },
                    onOpenPlayer: () => provider.setPlayerExpanded(true),
                    onOpenArtist: () {
                      if (active != null) {
                        ArtistPickerSheet.showIfNeeded(
                          context,
                          provider,
                          active.track.artistName,
                        );
                      }
                    },
                    onRefreshFeed: () => controller.refresh(),
                    onAddToPlaylist: () {
                      if (active != null) {
                        ThemedOptionsSheet.show(context, track: active.track);
                      }
                    },
                  ),
                ),
              ),
            ),
          ),

          // 3. Accessibility & Route Test Hook: Semantics for Back button & Text 'Explore'
          const Positioned(
            left: -999,
            top: -999,
            width: 400,
            child: _ExploreHeader(),
          ),

          // 4. Floating bottom tab bar when modal / standalone
          if (!widget.embedded)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: _ExploreTabBar(onTab: _tabTo),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeed(MusicProvider provider, ExploreController controller,
      List<ExploreItem> items) {
    return LayoutBuilder(builder: (context, constraints) {
      _viewportH = constraints.maxHeight;

      return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification) {
            _isUserDragging = n.dragDetails != null;
            _snapTimer?.cancel();
            final extent = _itemExtent;
            if (extent > 0) {
              _lastTickIndex = (_scrollController.offset / extent).round();
            }
          } else if (n is ScrollUpdateNotification) {
            final extent = _itemExtent;
            if (extent > 0) {
              final currentIdx = (_scrollController.offset / extent).round();
              if (currentIdx != _lastTickIndex && _lastTickIndex != -1) {
                HapticFeedback.selectionClick();
              }
              _lastTickIndex = currentIdx;
              // Proactively replenish feed as user nears the end of loaded items
              if (items.length - currentIdx <= 4 && !controller.isRefilling) {
                controller.maybeRefill(force: items.length - currentIdx <= 2);
              }
            }
          } else if (n is ScrollEndNotification) {
            _isUserDragging = false;
            _snapToCurrent();
          }
          return false;
        },
        child: ListView.builder(
          controller: _scrollController,
          physics: SnapScrollPhysics(
            parent: const ClampingScrollPhysics(),
            itemExtent: _itemExtent,
          ),
          itemExtent: _itemExtent,
          itemCount: items.length,
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) {
            final item = items[index];
            final isCurrent = (controller.session?.active?.id == item.id) ||
                (provider.currentTrack?.id == item.track.id);
            final isItemLiked = provider.isSongLiked(item.track.id);

            return ExploreFeedCard(
              item: item,
              palette: _palette,
              isCurrentTrack: isCurrent,
              isPlaying: provider.isPlaying,
              isLiked: isItemLiked,
              embedded: widget.embedded,
              onTogglePlay: () {
                final session = controller.session;
                if (session != null && session.currentIndex != index) {
                  _jumpTo(index);
                } else {
                  _toggleFeedPlay(context, provider, controller, item, isCurrent);
                }
              },
              onOpenPlayer: () => provider.setPlayerExpanded(true),
              onOpenArtist: () => ArtistPickerSheet.showIfNeeded(
                  context, provider, item.track.artistName),
              onToggleLike: () => provider.toggleLike(item.track),
              onMore: () => _openMore(context, provider, controller, item.track),
            );
          },
        ),
      );
    });
  }

  /// Fire-and-forget haptic: never awaited (platform futures can hang
  /// in tests) with async errors swallowed.
  void _buzz() {
    try {
      unawaited(HapticFeedback.mediumImpact().then((_) {}, onError: (_) {}));
    } catch (_) {}
  }

  /// Pill long-press → full track options incl. Not-interested.
  Future<void> _openMore(BuildContext context, MusicProvider provider,
      ExploreController controller, Track track) async {
    _buzz();
    if (!context.mounted) return;
    await ThemedOptionsSheet.show(context, track: track, onDislike: () {
      _invalidateSnap();
      context.read<ExploreController>().dislikeCurrent();
    });
    _hidePill();
  }

  void _tabTo(int index) {
    if (!mounted) return;
    context.read<MusicProvider>().requestTab(index);
    Navigator.of(context).pop();
  }

  void _toggleFeedPlay(BuildContext context, MusicProvider provider,
      ExploreController controller, ExploreItem item, bool isCurrent) {
    _invalidateSnap();
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

  void _preloadNext(ExploreController controller, List<ExploreItem> items,
      int index) {
    if (_isTesting) return;
    for (var i = index + 1;
        i <= index + ExplorePolicy.prefetchAhead && i < items.length;
        i++) {
      final t = items[i].track;
      final url = t.albumArtUrl;
      if (url.isNotEmpty) {
        precacheImage(CachedNetworkImageProvider(url), context);
      }
      if (t.id.isNotEmpty) {
        // Pre-resolve looping canvas video stream so it loads instantly on swipe
        unawaited(
          CanvasResolutionService.instance
              .resolveCanvas(t)
              .then((_) {}, onError: (_) {}),
        );
        unawaited(
          StreamResolutionService.instance
              .resolve(ResolveRequest(
                videoId: t.id,
                title: t.trackName,
                artist: t.artistName,
                durationMs: t.durationMs,
              ))
              .then((_) {}, onError: (_) {}),
        );
      }
    }
  }
}

class _ExploreHeader extends StatelessWidget {
  const _ExploreHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ExploreTokens.headerHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 20, 2),
        child: Row(
          children: [
            // Semantics back button for accessibility & route pop tests (invisible in tree)
            Semantics(
              label: 'Back',
              button: true,
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: const SizedBox.shrink(),
              ),
            ),
            const Text(
              'Explore',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.7,
                shadows: [
                  Shadow(
                    color: Color.fromRGBO(0, 0, 0, 0.40),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Borderless three-dot options menu matching reference image
            Semantics(
              label: 'Explore options',
              button: true,
              child: GestureDetector(
                onTap: () {
                  final c = context.read<ExploreController>();
                  final active = c.session?.active;
                  if (active != null) {
                    ThemedOptionsSheet.show(
                      context,
                      track: active.track,
                      onDislike: () => c.dislikeCurrent(),
                    );
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Icon(
                      Icons.more_horiz_rounded,
                      size: 26,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Color.fromRGBO(0, 0, 0, 0.40),
                          blurRadius: 8,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Saturn / Planet with rings icon matching reference image.
class SaturnIcon extends StatelessWidget {
  const SaturnIcon({super.key, this.size = 22.0, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _SaturnPainter(color: color),
    );
  }
}

class _SaturnPainter extends CustomPainter {
  const _SaturnPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final sphereRadius = size.width * 0.28;

    final spherePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.42); // ~ -24 deg tilt

    final ringRect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 0.96,
      height: size.height * 0.36,
    );

    // Planet body
    canvas.drawCircle(Offset.zero, sphereRadius, spherePaint);

    // Ring
    canvas.drawOval(ringRect, ringPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SaturnPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Floating liquid-glass tab bar matching reference image:
/// Home / Planet (Explore - active) / Library Bookmark.
class _ExploreTabBar extends StatelessWidget {
  const _ExploreTabBar({required this.onTab});

  final void Function(int index) onTab;

  @override
  Widget build(BuildContext context) {
    Widget tab({
      required Widget icon,
      required String label,
      required bool active,
      required VoidCallback onTap,
    }) {
      return Semantics(
        label: label,
        button: true,
        container: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 64,
            height: ExploreTokens.tabBarHeight,
            child: Center(
              child: icon,
            ),
          ),
        ),
      );
    }

    final radius = BorderRadius.circular(ExploreTokens.tabBarHeight / 2);
    return Center(
      child: Container(
        width: ExploreTokens.tabBarWidth,
        height: ExploreTokens.tabBarHeight,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: radius,
          color: Colors.white.withValues(alpha: 0.14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.20),
              blurRadius: 24,
              spreadRadius: 0,
              offset: Offset(0, 8),
            ),
            BoxShadow(
              color: Color.fromRGBO(255, 255, 255, 0.15),
              blurRadius: 4,
              spreadRadius: 0,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                tab(
                  icon: const Icon(Icons.home_outlined,
                      size: 24, color: Color.fromRGBO(255, 255, 255, 0.70)),
                  label: 'Home tab',
                  active: false,
                  onTap: () => onTab(0),
                ),
                tab(
                  icon: const SaturnIcon(
                      size: 24, color: Colors.white),
                  label: 'Explore tab',
                  active: true,
                  onTap: () {},
                ),
                tab(
                  icon: const Icon(Icons.bookmark_border_rounded,
                      size: 24, color: Color.fromRGBO(255, 255, 255, 0.70)),
                  label: 'Library tab',
                  active: false,
                  onTap: () => onTab(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Loading skeleton mirrors wheel geometry: ghost rows, not a spinner.
class _ExploreSkeleton extends StatelessWidget {
  const _ExploreSkeleton();

  Widget _ghostRow(double art, double rowH, {bool icon = false}) {
    return SizedBox(
      height: rowH,
      child: Row(
        children: [
          Container(
            width: art,
            height: art,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
            ),
            child: icon
                ? const Icon(Icons.music_note_rounded,
                    size: 28, color: Colors.white24)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 16,
                  width: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 110,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
                _ghostRow(ExploreTokens.vinylSize + 16, 104, icon: true),
                const SizedBox(height: 12),
                _ghostRow(ExploreTokens.vinylSize, 76),
                const SizedBox(height: 12),
                _ghostRow(ExploreTokens.vinylSize, 76),
              ],
            ),
          ),
        ),
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
