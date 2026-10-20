import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';

import '../core/morph_freeze.dart';
import '../core/navigation/root_navigator.dart';
import '../core/perf_trace.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/themed_now_playing_screen.dart';
import '../theme/glass_tokens.dart';
import '../utils/app_image_cache.dart';
import '../utils/color_utils.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/covered_gate.dart';
import '../widgets/material_you_playback_bar.dart';
import '../widgets/mini_player.dart';
import 'player_dock.dart';

/// The mini-pill <-> Now Playing transition.
///
/// ## What this is
///
/// A full-screen player that translates over the page, and - when both ends
/// are on screen - BitChord's dock: the player's artwork flies between its
/// place in the player and the mini player's cover while the rest of the
/// player fades (`player_dock.dart`). Without a cover or an artwork to meet
/// (pill hidden, lyrics or queue open, reduce motion, Material You) it is the
/// plain translate it always was.
///
/// ## Where the two ends come from
///
/// The pill has two hosts (the nav bar's `bottomAccessory` and the floating
/// fallback here) and the nav bar's copy moves when the bar minimizes. So the
/// cover's rect is not assumed: the cover reports its render box and it is read
/// every frame of a flight, from the previous frame's layout, through every
/// transform above it. A stale rect for one frame is a fraction of a pixel at
/// flight speeds; a guessed one was the old "doubled pill".
///
/// ## What that costs per frame
///
/// The plain slide: one matrix on one cached layer and the alpha of one flat
/// scrim (the page sits outside the animated subtree; the player is hoisted
/// into `AnimatedBuilder.child`). The dock adds the player's alpha (one
/// composite of its cached layer) and a small positioned image, laid out per
/// frame. The page and the player are never rebuilt for a tick.
class GlobalMusicOverlay extends StatefulWidget {
  final Widget child;

  const GlobalMusicOverlay({super.key, required this.child});

  @override
  State<GlobalMusicOverlay> createState() => _GlobalMusicOverlayState();
}

class _GlobalMusicOverlayState extends State<GlobalMusicOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _panelController = AnimationController(
    vsync: this,
    lowerBound: 0.0,
    upperBound: 1.0,
    value: 0.0,
  );

  /// Critically damped, stiffness 195: about 0.45 s of response, the pace of
  /// Apple Music's player sheet (BitChord's `SLIDE_STIFFNESS`). It leaves
  /// briskly and spends most of its time settling, which is when the eye is
  /// following the artwork home.
  ///
  /// A spring rather than a tween because a tween has no velocity at its ends:
  /// interrupting one mid-flight restarts from a standstill and reads as a
  /// hitch. A spring carries velocity through a reversal, so an interrupted
  /// gesture just continues. Critically damped (c = 2·sqrt(k·m)) so it never
  /// wobbles from rest.
  static final SpringDescription _kPanelSpring =
      SpringDescription(mass: 1, stiffness: 195, damping: 2 * math.sqrt(195));

  /// A release this fast (dp/s) decides the direction by itself; slower, the
  /// finger's position decides (past halfway opens).
  static const double _kFlingVelocity = 400;

  /// Black at the alpha Material's sheet scrim uses
  /// (`onSurface.copy(alpha = 0.32f)`). The reference dims the page; without
  /// this the player never reads as a layer above it.
  static const double _kScrimPeak = 0.32;

  /// Guards [_onRoutesChanged] so a burst of route changes costs one rebuild
  /// instead of one per notification.
  bool _routeSyncScheduled = false;

  /// True while the open player is sitting still on top of the page, so nothing
  /// under it is worth drawing. See [CoveredGate] and [PanelCover].
  late final PanelCover _cover;

  /// Where the current flight is headed, or null when at rest.
  ///
  /// This is what makes a mid-flight reversal safe. The previous version tracked
  /// the provider's boolean instead, and flipped it *before* the animation ran,
  /// so an interrupted flight was never re-driven and the card could be left
  /// stranded between the two ends with nothing left to move it.
  double? _desiredTarget;

  /// Discriminates concurrent flights, so a superseded flight's completion
  /// callback cannot clear [_desiredTarget] out from under its replacement.
  int _flight = 0;

  /// Latches whether the provider has been told the panel is open, so the
  /// controller's listener only crosses the threshold once per change.
  ///
  /// Instance state, deliberately: as a `static` this leaked across provider
  /// instances and could leave a freshly built provider permanently believing
  /// the panel was already open, never receiving the update at all.
  bool _toldProviderExpanded = false;

  /// Captured in [initState] so [dispose] can detach the intent listener without
  /// reaching for an inherited widget during teardown.
  late final MusicProvider _provider;

  late final _PlayerNavigatorObserver _playerNavObserver =
      _PlayerNavigatorObserver(onRoutesChanged: _onRoutesChanged);

  @override
  void initState() {
    super.initState();

    // Held rather than re-resolved: `Provider.of` depends on an inherited
    // widget, and doing that during teardown is not safe. Every use below is
    // either initState or dispose, so one captured reference covers both.
    final provider = Provider.of<MusicProvider>(context, listen: false);
    _provider = provider;

    _panelController.addListener(() {
      final isExpanded = _panelController.value > 0.5;
      if (_toldProviderExpanded == isExpanded) return;
      _toldProviderExpanded = isExpanded;
      provider.setPlayerExpanded(isExpanded);
      if (isExpanded) return;
      // Collapsing pops the player's own subroutes, so a queue or lyrics page
      // left open above the player is not still there when it comes back.
      final playerNav = provider.playerNavigatorKey.currentState;
      if (playerNav != null && playerNav.canPop()) {
        playerNav.popUntil((r) => r.isFirst);
      }
      if (provider.hideMiniPlayer) provider.setHideMiniPlayer(false);
    });

    // An explicit listener, because the render-time select below deliberately
    // ignores this one field.
    //
    // `isPlayerExpanded` is the *intent* signal - set by the pill's tap, the
    // deep link, the back handler - and it is what actually opens the player.
    // Deriving it from `didChangeDependencies` only worked while the overlay
    // held a broad provider listen, which fired on every notification. Narrowing
    // that listen (which is what removed the per-tick rebuild) also meant the
    // selected value rarely changed, so the dependency never became dirty and
    // the sync silently stopped running: tapping the pill removed the pill and
    // never brought the player up.
    //
    // Listening for the one field that matters costs one notification per
    // open or close, and cannot be lost to a narrowing of the render listen.
    provider.addListener(_onProviderIntentChanged);

    // Cover/uncover follows the card itself rather than the provider's intent
    // (see [PanelCover]); created here so it is listening from the first frame.
    _cover = PanelCover(_panelController, isFrozen: () => MorphFreeze.enabled);

    // The nav-bar-hosted pill reports its pulls here (see player_dock.dart).
    _dock.onPull = _onDockPull;
    _dock.onPullEnd = _onDockPullEnd;

    // The harness parks the flight so a frame can be captured and compared.
    // Applied after the listener so the provider still learns the state.
    final pinned = MorphFreeze.pinned;
    if (pinned != null) {
      _panelController.value = pinned;
    } else if (MorphFreeze.autoOpenMs > 0) {
      // Driven from in here rather than by a tap, so a transition can be
      // measured on a device nobody is touching. See MorphFreeze.autoOpenMs.
      Future<void>.delayed(
        const Duration(milliseconds: MorphFreeze.autoOpenMs),
        () {
          if (mounted) _animatePanelTo(1.0);
        },
      );
    }
  }

  void _onProviderIntentChanged() {
    // A finger on the panel owns it; the provider's intent catches up on
    // release. Without this any unrelated notification mid-drag (a download's
    // progress, a palette) re-ran the sync and pulled the panel out from under
    // the finger.
    if (!mounted || MorphFreeze.enabled || _dragging) return;
    _syncFromProvider(_provider.isPlayerExpanded);
  }

  /// A finger is on the panel (or on the pill pulling it up).
  bool _dragging = false;

  @override
  void dispose() {
    // Removed before the controller: the provider outlives this widget, so a
    // listener left attached would keep this State reachable and fire against a
    // disposed controller.
    _provider.removeListener(_onProviderIntentChanged);
    if (_dock.onPull == _onDockPull) {
      _dock.onPull = null;
      _dock.onPullEnd = null;
    }
    _dock.setDocking(false);
    _cover.dispose();
    _panelController.dispose();
    super.dispose();
  }

  /// Guards [_onRoutesChanged] so a burst of route changes costs one rebuild
  /// instead of one per notification.
  ///
  /// Navigator observers fire inside the navigator's own build/update phase, so
  /// calling `setState` straight from one is "markNeedsBuild during build".
  ///
  /// Beyond the immediate error it corrupted the framework's inactive-element
  /// bookkeeping, which surfaced on a *later*, unrelated rebuild as
  /// `_InactiveElements.remove: _elements.contains(element): is not true` - the
  /// stack pointed at `inflateWidget`, nowhere near the real cause.
  ///
  /// Deferring past the frame is the fix: a route change always animates, so the
  /// callback runs on the very next frame and the overlay is at most one frame
  /// behind, which is imperceptible for a repaint.
  void _onRoutesChanged() {
    if (!mounted || _routeSyncScheduled) return;
    _routeSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeSyncScheduled = false;
      if (!mounted) return;
      setState(() {});
    });
  }

  // --- Gesture ---------------------------------------------------------------

  /// True while the player has a subroute (queue, lyrics) of its own open. The
  /// drag belongs to that subroute then, not to the panel.
  bool get _playerNavHasSubroute {
    final playerNav = Provider.of<MusicProvider>(context, listen: false)
        .playerNavigatorKey
        .currentState;
    return playerNav != null && playerNav.canPop();
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details, double pageHeight) {
    if (_playerNavHasSubroute) return;
    _dragging = true;
    // Clamped: an unclamped flick could drive the controller past either end,
    // putting the card at a position it has no frame for. Assigning `value`
    // stops any running simulation, so a drag always wins over a flight.
    final delta = (details.primaryDelta ?? 0.0) / pageHeight;
    _panelController.value = (_panelController.value - delta).clamp(0.0, 1.0);
  }

  void _handleVerticalDragEnd(DragEndDetails details, double pageHeight) {
    _dragging = false;
    if (_playerNavHasSubroute) return;
    // The drag runs 1:1, so the finger's velocity converts straight into the
    // controller's units - upward finger, increasing value - and seeds the
    // spring, which continues the gesture instead of restarting it.
    final dpPerSecond = details.primaryVelocity ?? 0.0;
    final velocity = -dpPerSecond / pageHeight;
    final open = dpPerSecond.abs() >= _kFlingVelocity
        ? dpPerSecond < 0
        : _panelController.value > 0.5;
    _animatePanelTo(open ? 1.0 : 0.0, velocity: velocity);
  }

  // --- Flight ----------------------------------------------------------------

  /// Idempotent: any disagreement between the provider's intent and where the
  /// card actually is gets corrected, whether that is a fresh request, a
  /// reversal, or the tail of an interrupted flight.
  void _syncFromProvider(bool wantExpanded) {
    final target = wantExpanded ? 1.0 : 0.0;
    final inFlight = _desiredTarget;
    if (inFlight != null) {
      // Reversing mid-flight is legitimate and common - open then immediately
      // close - so retarget from wherever the card is now rather than ignoring
      // the request until the current flight lands.
      if ((inFlight > 0.5) != wantExpanded) _animatePanelTo(target);
      return;
    }
    if (_panelController.value != target) _animatePanelTo(target);
  }

  void _animatePanelTo(double target, {double velocity = 0.0}) {
    if (MorphFreeze.enabled) return;
    if (!_panelController.isAnimating && _panelController.value == target) {
      return;
    }
    final label = target > 0.5 ? 'pill-to-player' : 'player-to-pill';
    PerfTrace.mark(label);

    final generation = ++_flight;
    _desiredTarget = target;

    _panelController
        .animateWith(
          SpringSimulation(
            _kPanelSpring,
            _panelController.value,
            target,
            velocity,
          ),
        )
        .then((_) {
          // A superseded flight lands here too, so anything below belongs only
          // to the flight that is still current.
          if (!mounted || generation != _flight) return;
          // The spring settles a hair short of its target; pin the exact rest
          // value so "at rest" is a fact and not a tolerance.
          _panelController.value = target;
          _desiredTarget = null;
          PerfTrace.summary(label);
        });
    // The flight is live from here: uncover now, not on its first tick.
    _cover.sync();
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Narrow, structural listen.
    //
    // This used to be `Provider.of<MusicProvider>(context)`, which subscribes
    // the overlay to *every* notification the provider makes - including each
    // playback position tick. That rebuilt the page wrapper, the mini player and
    // the whole player card several times a second, during the flight included.
    // Position ticks now cost this widget nothing; only the things that change
    // what is on screen (the track, its extracted palette, and whether a sheet
    // has claimed the pill) rebuild it. The player subtree does its own
    // listening, so nothing inside it lost an update.
    final gate = context.select<MusicProvider, ({Track? track, bool hideMini})>(
      (p) => (track: p.currentTrack, hideMini: p.hideMiniPlayer),
    );
    final isGlassTheme = Provider.of<ThemeProvider>(context).isGlassmorphism;

    _precacheHeroArtwork(gate.track);

    // Page metrics resolved once per build, outside the animation, so a tick
    // costs a matrix and a multiply rather than a layout pass.
    return PlayerAwarePopScope(
      child: LayoutBuilder(
        builder: (context, page) {
          final pageHeight = page.maxHeight;
          final player = _buildPlayerNavigator(gate.track);

          return CoveredScope(
            covered: _cover,
            child: Stack(
            children: [
              // The page in its own repaint boundary. Not an optimisation, a
              // requirement: the scrim's alpha changes every frame, and without
              // this that change dirties everything underneath it, so the whole
              // Home feed - every image on screen - was re-rastered on every
              // frame of the flight. Measured 11.9ms of raster per frame and
              // 41 of 41 frames over budget, against 3.45ms and 4 of 35 with
              // it. The page's own raster is content-driven and almost never
              // needs redoing; this is what lets it prove that.
              //
              // Behind a [CoveredGate]: once the player is open and still, the
              // page under its opaque card is neither painted nor animated.
              // Impeller has no raster cache, so "retained" layers still cost a
              // replay per frame; skipping them is the only way they are free.
              CoveredGate(
                covered: _cover,
                child: RepaintBoundary(child: widget.child),
              ),

              // The mini pill. Deliberately *outside* the animated subtree and
              // carrying no animation of its own.
              //
              // The old version faded it out on `1 - value*2.2`, which put two
              // failure modes on screen: it was fully gone by 45% of the flight,
              // and on the way back it returned at 45% while the card was still
              // visibly mid-air - the source of the doubled pill and the tint
              // left behind after scrolling. No fade is needed now: the card is
              // opaque and travels over the pill, so the pill is simply covered,
              // and uncovered again the instant the card is off-screen. The
              // resting state is the real widget doing its real job.
              if (gate.track != null)
                _buildMiniPlayer(isGlassTheme),

              // Scrim then card, above the pill so the pill dims with the page.
              if (gate.track != null)
                AnimatedBuilder(
                  animation: _panelController,
                  child: player,
                  builder: (context, playerChild) {
                    final t = _panelController.value;
                    // Absent at rest. At `t == 0` the card's own rect is exactly
                    // the resting pill's, so leaving it mounted meant a second
                    // capsule painted over the first - a blurred wash instead of
                    // the pill's glass, plus a duplicate row.
                    if (t <= 0.0) {
                      _dock.setDocking(false);
                      _lastCardOffset = null;
                      return const SizedBox.shrink();
                    }

                    final cardOffset = (1.0 - t) * pageHeight;
                    final frame = t < 1.0 ? _dockFrameFor(t, pageHeight) : null;
                    // Both real artworks stand aside only while the copy flies.
                    _dock.setDocking(frame != null);
                    _lastCardOffset = cardOffset;
                    final sleeve = _dock.sleeve;

                    return Stack(
                      children: [
                        // Flat scrim, own layer. Only its alpha moves.
                        _buildScrim(t),

                        // The card: one translate on a cached layer. The
                        // structure never changes between the plain slide and
                        // the dock (only the alpha does), so the player's
                        // navigator is never remounted mid-flight. Alpha 1 is
                        // free: Opacity paints straight through at 255.
                        //
                        // Square corners on purpose: the reference passes
                        // `RectangleShape` for exactly this surface.
                        Positioned.fill(
                          child: Opacity(
                            opacity: frame?.playerAlpha ?? 1.0,
                            child: Transform.translate(
                              offset: Offset(0, cardOffset),
                              child: RepaintBoundary(child: playerChild),
                            ),
                          ),
                        ),

                        // The artwork flying between the player and the cover,
                        // over the fading player (see player_dock.dart).
                        if (frame != null && sleeve != null) _buildSleeve(frame, sleeve),
                      ],
                    );
                  },
                ),
            ],
            ),
          );
        },
      ),
    );
  }

  /// The dim over the page.
  ///
  /// Full-screen, not clipped to the band above the card. Clipping it was tried
  /// and is not worth the special case: the blend is one quad, and with the
  /// page repaint-isolated the cost is in the page being re-rastered, not in
  /// the area being blended.
  Widget _buildScrim(double t) => Positioned.fill(
    child: RepaintBoundary(
      child: IgnorePointer(
        child: ColoredBox(
          // Nothing at fully open: the player is opaque, and a full-screen
          // blend under it would be paid every frame for nothing.
          color: Colors.black.withValues(alpha: t >= 1.0 ? 0.0 : _kScrimPeak * t),
        ),
      ),
    ),
  );

  // --- Dock ------------------------------------------------------------------

  final PlayerDock _dock = PlayerDock.instance;

  /// The card's offset in the last built frame: the player's artwork was laid
  /// out (and measured) under it, so subtracting it gives the open position.
  double? _lastCardOffset;

  /// This frame of the artwork's trip, or null for the plain slide: reduce
  /// motion, Material You, no cover on screen (pill hidden), no artwork
  /// attached in the player, a player subroute, or the first frame of an open
  /// before the player has been laid out.
  DockFrame? _dockFrameFor(double t, double pageHeight) {
    if (MediaQuery.disableAnimationsOf(context)) return null;
    if (!Provider.of<ThemeProvider>(context, listen: false).isGlassmorphism) return null;
    if (_playerNavHasSubroute) return null;
    final lastOffset = _lastCardOffset;
    if (lastOffset == null) return null;
    final mini = _dock.miniRect();
    final art = _dock.artRect();
    if (mini == null || art == null) return null;
    return dockFrame(
      t: t,
      mini: mini,
      open: art.shift(Offset(0, -lastOffset)),
      travel: pageHeight,
      miniCorner: _dock.miniCorner,
      openCorner: _dock.artCorner,
      softEdge: _dock.artSoftEdge,
    );
  }

  /// The travelling artwork: the player's own image (same cache entry), its
  /// soft bottom edge firming into the cover's hard one as it lands.
  Widget _buildSleeve(DockFrame f, WidgetBuilder sleeve) {
    final fade = f.edgeFade;
    Widget art = SizedBox.expand(child: sleeve(context));
    if (fade > 0.02) {
      art = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.white.withValues(alpha: 1 - fade)],
          stops: const [0.0, 0.58, 1.0],
        ).createShader(bounds),
        child: art,
      );
    }
    return Positioned.fromRect(
      rect: f.rect,
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(f.corner),
          child: art,
        ),
      ),
    );
  }

  /// An upward pull on the nav-bar-hosted pill: the player follows the finger
  /// from the bar, the same as a pull on the floating pill.
  void _onDockPull(double dy) {
    if (!mounted || _playerNavHasSubroute) return;
    final h = screenHeight;
    if (_panelController.value <= 0 && dy >= 0) return; // only upward starts one
    _dragging = true;
    _panelController.value = (_panelController.value - dy / h).clamp(0.0, 1.0);
    _cover.sync();
  }

  void _onDockPullEnd(double velocity) {
    if (!mounted) return;
    if (_panelController.value <= 0 && !_panelController.isAnimating) return;
    _dragging = false;
    // As generous as the old fling-to-open on the pill (200 dp/s up opens);
    // otherwise the same flick-or-halfway rule as the player.
    final open = velocity <= -200
        ? true
        : velocity >= _kFlingVelocity
            ? false
            : _panelController.value > 0.5;
    _animatePanelTo(open ? 1.0 : 0.0, velocity: -velocity / screenHeight);
  }

  /// The player, built once per overlay build and hoisted into
  /// `AnimatedBuilder.child` so a tick never re-runs its build or layout.
  ///
  /// `RepaintBoundary` is deliberately *outside* this, on the transform: the
  /// boundary has to be the animated node's child for its raster to be cached
  /// and then only moved.
  Widget _buildPlayerNavigator(Track? track) {
    if (track == null) return const SizedBox.shrink();
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    return GestureDetector(
      // Dragging anywhere on the open player brings it down; while a subroute
      // (queue, lyrics) is open the drag belongs to that subroute instead.
      onVerticalDragUpdate: (d) => _handleVerticalDragUpdate(d, screenHeight),
      onVerticalDragEnd: (d) => _handleVerticalDragEnd(d, screenHeight),
      child: HeroControllerScope.none(
        child: Navigator(
          key: musicProvider.playerNavigatorKey,
          observers: [_playerNavObserver],
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (context) => Material(
              elevation: 0,
              color: Colors.transparent,
              child: ThemedNowPlayingScreen(
                track: track,
                onMinimize: () => _animatePanelTo(0.0),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniPlayer(bool isGlassTheme) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final track = musicProvider.currentTrack;
    if (track == null) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: CoveredGate(
        covered: _cover,
        child: ValueListenableBuilder<bool>(
        valueListenable: AppRouteObserver.instance.isAtRoot,
        builder: (context, isAtRoot, _) {
          // On MainScreen the nav bar hosts the pill as its bottom accessory; a
          // second copy here would be a duplicate pill directly on top of it.
          // Everywhere else - pushed routes with no nav bar - this is the host.
          if ((isGlassTheme && isAtRoot) || musicProvider.hideMiniPlayer) {
            return const SizedBox.shrink();
          }

          // Painted above the root navigator, so a sheet or dialog could never
          // cover it: it steps aside while one is open.
          return StepAsideForModals(
            child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  // Horizontal gestures are left to the child by not claiming
                  // them here; only the vertical drag for expansion is claimed.
                  onVerticalDragUpdate: (d) =>
                      _handleVerticalDragUpdate(d, screenHeight),
                  onVerticalDragEnd: (d) =>
                      _handleVerticalDragEnd(d, screenHeight),
                  child: isGlassTheme
                      ? MiniPlayer(onExpand: () => _animatePanelTo(1.0))
                      : MaterialYouPlaybackBar(
                          track: track,
                          provider: musicProvider,
                          accentColor: ColorUtils.getVibrantAccent(
                            musicProvider.paletteGenerator,
                            const Color(0xFF00B4D8),
                          ),
                        ),
                ),
                // Keeps the pill floating above nav bars on routes that have one.
                const SizedBox(height: GlassTokens.playerBottomInset),
              ],
            ),
            ),
          );
        },
        ),
      ),
    );
  }

  double get screenHeight => MediaQuery.sizeOf(context).height;

  /// The artwork URL already warmed at hero resolution, so the guard below is a
  /// string compare rather than a repeated download request.
  String? _precachedArtUrl;

  /// Warms the hero-resolution artwork while the player is still closed.
  ///
  /// The pill holds [AppImageCache.thumbnailMemCache] (160) and the player asks
  /// for [AppImageCache.heroMemCache] (800). Those are different cache keys, so
  /// the first frame of the transition was decoding a fresh 800px bitmap - the
  /// one hitch that was guaranteed on every single open, and the reason the
  /// reveal could read as staged rather than instant.
  ///
  /// The provider here is built with the same URL and the same dimensions the
  /// player's `CachedNetworkImage` uses, so this populates the exact entry that
  /// will be read rather than a near-miss that still has to decode.
  ///
  /// Fire and forget, once per URL. Deliberately not evicting the previous
  /// warm on a track change: it shares the [ImageCache] with images that may be
  /// on screen, and evicting by hand can pull one out from under a widget that
  /// is still using it. The LRU bound is the right mechanism for this, not a
  /// manual cache surgery.
  void _precacheHeroArtwork(Track? track) {
    final art = ImageQualityUtils.getHighResArtwork(track?.albumArtUrl);
    // Local files are already decoded from disk at full size and gain nothing.
    if (art.isEmpty || !art.contains('://')) return;
    if (art == _precachedArtUrl) return;
    _precachedArtUrl = art;

    precacheImage(
      CachedNetworkImageProvider(
        art,
        maxWidth: AppImageCache.heroMemCache,
        maxHeight: AppImageCache.heroMemCache,
      ),
      context,
      // A failure here is not interesting: the player renders its own
      // placeholder, and this is only an optimisation.
    ).then<void>((_) {}, onError: (Object _, StackTrace __) {});
  }
}

class PlayerAwarePopScope extends StatelessWidget {
  final Widget child;

  const PlayerAwarePopScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Selects one boolean. This widget wraps the entire app, so a broad listen
    // here rebuilt the whole tree on every playback tick - the single most
    // expensive thing in the overlay's old frame budget.
    final isPanelOpen = context.select<MusicProvider, bool>(
      (p) => p.isPlayerExpanded,
    );
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    return PopScope(
      canPop: !isPanelOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // Priority 1: the player's own subroute (queue, lyrics) if it has one.
        final playerNav = musicProvider.playerNavigatorKey.currentState;
        if (playerNav != null && playerNav.canPop()) {
          playerNav.pop();
          return;
        }

        // Priority 2: bring the player itself down.
        if (isPanelOpen) musicProvider.setPlayerExpanded(false);
      },
      child: child,
    );
  }
}

class _PlayerNavigatorObserver extends NavigatorObserver {
  final VoidCallback onRoutesChanged;

  _PlayerNavigatorObserver({required this.onRoutesChanged});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    onRoutesChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    onRoutesChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    onRoutesChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    onRoutesChanged();
  }
}
