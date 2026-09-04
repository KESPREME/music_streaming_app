import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../providers/music_provider.dart';
import '../../services/explore/explore_controller.dart';
import '../../services/explore/explore_engine.dart';
import 'explore_layout.dart';
import '../../services/explore/explore_palette.dart';
import '../../services/explore/explore_policy.dart';
import '../../services/recommendation/taste_profile.dart';
import '../../services/innertube/innertube_service.dart';
import '../../widgets/artist_picker_sheet.dart';
import '../../widgets/glass_circle_button.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/themed_options_sheet.dart';
import 'explore_mesh.dart';
import 'explore_tokens.dart';
import 'explore_wheel.dart';

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
  final ScrollController _scrollController = ScrollController();
  ExplorePalette _palette = ExplorePalette.neutral;
  MusicProvider? _provider;
  Timer? _snapTimer;
  int _snappedIndex = -1;
  bool _restored = false;
  double _viewportH = 600;

  @override
  void initState() {
    super.initState();
    final controller = context.read<ExploreController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolvePalette(controller);
      // Immersive route: the pill would duplicate the wheel's own
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

  void _hidePill() => _provider?.setHideMiniPlayer(true);

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

  void _jumpTo(int index) {
    if (!_scrollController.hasClients) return;
    final extent =
        ExploreWheelMath.itemExtentFor(_viewportH);
    _scrollController.animateTo(
      index * extent,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  /// Snap path: ScrollEnd → (optional haptic) → 180ms debounce → settle.
  /// Never fires mid-drag; rapid flings collapse to the latest snap.
  void _snapToCurrent({bool silent = false}) {
    final controller = context.read<ExploreController>();
    final session = controller.session;
    if (session == null ||
        session.items.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }
    final extent = ExploreWheelMath.itemExtentFor(_viewportH);
    final idx = SnapScrollPhysics.indexFor(_scrollController.offset, extent)
        .clamp(0, session.items.length - 1);
    if (idx == _snappedIndex) return;
    _snappedIndex = idx;
    if (!silent) _snapHaptic();
    _snapTimer?.cancel();
    _snapTimer = Timer(ExploreTokens.snapDebounce, () {
      if (!mounted) return;
      final c = context.read<ExploreController>();
      final s = c.session;
      if (s == null || idx >= s.items.length) return;
      c.settle(idx);
      _resolvePalette(c);
      _preloadNext(c, s.items, idx);
      _hidePill();
    });
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
      _scrollController.jumpTo(
          idx * ExploreWheelMath.itemExtentFor(_viewportH));
      _snapToCurrent(silent: true);
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
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Palette-driven liquid atmosphere (tweens itself on seed change).
          Positioned.fill(
            child: LiquidMeshBackground(
              palette: _palette,
              seed: active?.id ?? 'none',
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const _ExploreHeader(),
                Expanded(
                  child: controller.isLoading || controller.session == null
                      ? const _ExploreSkeleton()
                      : items.isEmpty
                          ? _EmptyState(controller: controller)
                          : _buildWheel(provider, controller, items),
                ),
                _ExploreTabBar(onTab: _tabTo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWheel(MusicProvider provider, ExploreController controller,
      List<ExploreItem> items) {
    return LayoutBuilder(builder: (context, constraints) {
      _viewportH = constraints.maxHeight;
      final extent = ExploreWheelMath.itemExtentFor(_viewportH);
      final spec = ExploreWheelMath.plan(
          Size(constraints.maxWidth, constraints.maxHeight));
      final session = controller.session;
      return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification) {
            _snapTimer?.cancel();
          } else if (n is ScrollEndNotification) {
            _snapToCurrent();
          }
          return false;
        },
        child: ExploreWheel(
          items: items,
          scrollController: _scrollController,
          physics: SnapScrollPhysics(
              parent: const ClampingScrollPhysics(), itemExtent: extent),
          viewportH: _viewportH,
          extent: extent,
          spec: spec,
          settledIndex: session?.currentIndex ?? -1,
          currentTrackId: provider.currentTrack?.id,
          isPlaying: provider.isPlaying,
          accent: _palette.accent,
          onTapRow: _jumpTo,
          onTogglePlay: (item, isCurrent) => _toggleWheelPlay(
              context, provider, controller, item, isCurrent),
          onOpenPlayer: () => provider.setPlayerExpanded(true),
          onOpenArtist: (track) => ArtistPickerSheet.showIfNeeded(
              context, provider, track.artistName),
          isLiked: provider.isSongLiked,
          onLike: (track) => provider.toggleLike(track),
          onMore: (track) => _openMore(context, provider, controller, track),
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

  void _toggleWheelPlay(BuildContext context, MusicProvider provider,
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
    for (var i = index + 1;
        i <= index + ExplorePolicy.prefetchAhead && i < items.length;
        i++) {
      final url = items[i].track.albumArtUrl;
      if (url.isEmpty) continue;
      precacheImage(CachedNetworkImageProvider(url), context);
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
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Slim floating glass tab bar: Home / Explore-Orbit (active) / Library.
/// Tabs pop back to the shell and request the destination tab via the
/// provider (consumed post-frame by MainScreen) — no shell redesign.
class _ExploreTabBar extends StatelessWidget {
  const _ExploreTabBar({required this.onTab});

  final void Function(int index) onTab;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Widget tab({
      required IconData icon,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 22,
                    color: active
                        ? accent
                        : Colors.white.withValues(alpha: 0.55)),
                const SizedBox(height: 3),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? accent : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: GlassSurface(
        tier: GlassTier.floating,
        borderRadius: 28,
        child: SizedBox(
          width: ExploreTokens.tabBarWidth,
          height: ExploreTokens.tabBarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              tab(
                  icon: Icons.home_rounded,
                  label: 'Home tab',
                  active: false,
                  onTap: () => onTab(0)),
              tab(
                  icon: Icons.explore_rounded,
                  label: 'Explore tab',
                  active: true,
                  onTap: () {}),
              tab(
                  icon: Icons.library_music_rounded,
                  label: 'Library tab',
                  active: false,
                  onTap: () => onTab(2)),
            ],
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
