import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:palette_generator/palette_generator.dart';

import '../models/track.dart';
import '../core/perf_trace.dart';
import '../providers/music_provider.dart';
import '../services/audio_output_service.dart';
import '../services/canvas_video_manager.dart';
import '../utils/app_image_cache.dart';
import '../widgets/artist_picker_sheet.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/apple_player_icons.dart';
import '../widgets/thin_slider.dart';
import '../widgets/device_volume_slider.dart';
import '../widgets/audio_output_sheet.dart';
import '../widgets/audio_quality_language_sheet.dart';
import '../widgets/liquid_glass_pill.dart';
import '../widgets/scroll_collapse_tracker.dart';
import '../widgets/stagger_in.dart';
import '../widgets/in_place_canvas_player.dart';
import '../screens/lyrics_screen.dart';
import '../screens/queue_screen.dart';
import '../utils/color_utils.dart';
import '../utils/lyrics_utils.dart';
import '../utils/image_quality_utils.dart';

/// Full-screen Now Playing experience matching Apple Music / Muzo liquid glass UI/UX
/// and BitChord full-bleed hero artwork architecture.
class NowPlayingScreen extends StatefulWidget {
  final Track track;
  final VoidCallback? onMinimize;

  const NowPlayingScreen({required this.track, this.onMinimize, super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

@immutable
class _NowPlayingStateData {
  final Track track;
  final PaletteGenerator? palette;
  final bool isPlaying;
  final bool animatedCanvasEnabled;
  final bool isOfflineMode;
  final bool shuffleEnabled;
  final RepeatMode repeatMode;
  final bool isLiked;
  final bool isLofiEnabled;

  const _NowPlayingStateData({
    required this.track,
    required this.palette,
    required this.isPlaying,
    required this.animatedCanvasEnabled,
    required this.isOfflineMode,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.isLiked,
    required this.isLofiEnabled,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _NowPlayingStateData &&
          other.track.id == track.id &&
          other.track.albumArtUrl == track.albumArtUrl &&
          other.isPlaying == isPlaying &&
          other.animatedCanvasEnabled == animatedCanvasEnabled &&
          other.isOfflineMode == isOfflineMode &&
          other.shuffleEnabled == shuffleEnabled &&
          other.repeatMode == repeatMode &&
          other.isLiked == isLiked &&
          other.isLofiEnabled == isLofiEnabled &&
          other.palette == palette;

  @override
  int get hashCode => Object.hash(
        track.id,
        track.albumArtUrl,
        isPlaying,
        animatedCanvasEnabled,
        isOfflineMode,
        shuffleEnabled,
        repeatMode,
        isLiked,
        isLofiEnabled,
        palette,
      );
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with TickerProviderStateMixin {
  static const Color _defaultPrimaryColor = Color(0xFFE89838);

  static const List<String> _lyricsIntroPhrases = [
    'Just the groove for now',
    'Warming up',
    'Bass first, words later',
    'The beat is landing',
    'Setting the mood',
    'Feel that build',
    'Let it breathe',
    'The hook is on the way',
    'Cue the vocals',
    'First notes in',
    'Wait for it',
    'The song is starting',
  ];

  late final PageController _pageController;
  late final AnimationController _morphController;
  late final Animation<double> _morphAnim;
  bool _isLyricsOpen = false;

  int _currentTab = -1; // Default: Album mode has no active bottom tab
  bool _isPlayPressed = false;
  double? _draggedPositionSec;
  bool _isScrubbing = false;
  String? _lastAttachedTrackId;
  bool? _lastAttachedCanvasEnabled;

  // Gesture-phase collapse drivers (stable State fields, never rebuilt):
  // the queue list and the lyrics body share one threshold language, so a
  // collapse works the same whether words or rows are scrolling.
  final ScrollCollapseTracker _queueCollapse = ScrollCollapseTracker();
  final ScrollCollapseTracker _lyricsCollapse = ScrollCollapseTracker();

  // Queue shared-element morph (lyrics-mini language, rects mirrored from
  // _buildMainPlayerPage layers 3-4): the album flies to the top-left 46px
  // mini with title sliding right beside it, then HOLDS as the queue
  // header. Same 380ms easeInOutCubic. Pages swap instantly underneath at
  // q=0, where the overlay covers the hero pixel-perfect, so the swap is
  // invisible and all the eye tracks is the flight. Tap the mini to fly
  // home. At rest (open or shut) no ticker runs: one cached image + texts.
  late final AnimationController _queueMorphController;
  bool _queueMorphOpen = false;
  int _queueMorphGen = 0;

  // Shared-deck visibility (BitChord SlidingPlayerDeck parity): the deck
  // hides when scrolled down and returns on scroll up. Combined with the
  // lyrics idle flag, either one hides the deck.
  bool _deckVisible = true;

  // Lyrics idle chrome (BitChord 5s rule): while lyrics are open and the
  // finger has been still for 5s, the bottom chrome fades and the words
  // own the screen. Any tap/scroll/track change wakes it back up. The
  // timer is one-shot and only ever runs while lyrics are open.
  static const Duration _kLyricsIdleTimeout = Duration(seconds: 5);

  /// Horizontal travel on the artwork that counts as "show me the lyrics".
  static const double _kArtSwipeThreshold = 56;

  /// Corner radius at the hero end of the morph. The reference animates the
  /// radius rather than holding it, so the small end reads as a card.
  static const double _kHeroStartRadius = 20;

  /// Hoisted so the fade shaders are not re-allocated per frame.
  static const LinearGradient _kOpaqueFade = LinearGradient(
    colors: [Colors.white, Colors.white],
  );
  static const LinearGradient _kBottomFade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.white, Colors.white, Colors.transparent],
    stops: [0.0, 0.58, 1.0],
  );

  /// Accumulated artwork drag. Read only on pointer-up, so a swipe that the
  /// PageView also claims cannot double-fire.
  double _artDragDx = 0;
  double _artDragDy = 0;

  /// Rightward artwork swipe opens the lyrics.
  ///
  /// Deliberately a raw [Listener], not a GestureDetector: a horizontal drag
  /// recognizer would enter the gesture arena against the PageView and could
  /// win it, which would break the existing artwork -> queue swipe. A Listener
  /// observes without claiming, so the PageView keeps every gesture it already
  /// handles and this only reacts to the one direction nothing else wants
  /// (page 0 has no page to its left, so rightward travel is otherwise inert).
  void _onArtPointerDown(PointerDownEvent event) {
    _artDragDx = 0;
    _artDragDy = 0;
  }

  void _onArtPointerMove(PointerMoveEvent event) {
    _artDragDx += event.delta.dx;
    _artDragDy += event.delta.dy;
  }

  void _onArtPointerUp(PointerUpEvent event) {
    final dx = _artDragDx;
    final dy = _artDragDy;
    _artDragDx = 0;
    _artDragDy = 0;
    if (_queueMorphOpen || _isLyricsOpen) return;
    if (dx <= 0) return; // leftward belongs to the PageView (queue)
    if (dx < _kArtSwipeThreshold) return;
    // Mostly-vertical intent is a scroll or a tap, not a page change.
    if (dx.abs() < dy.abs() * 1.4) return;
    HapticFeedback.selectionClick();
    _openLyrics();
  }
  Timer? _lyricsIdleTimer;
  bool _lyricsChromeHidden = false;
  String? _idleTrackId;

  @override
  void initState() {
    super.initState();
    // Page 0: Main Player (with morphing Lyrics); Page 1: Queue.
    // Both share ONE deck below (lyric line, scrubber, transport, volume,
    // pill, output), so nothing jumps geometry switching between them.
    _pageController = PageController(initialPage: 0);
    _queueMorphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _morphAnim = CurvedAnimation(
      parent: _morphController,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _queueMorphController.dispose();
    _lyricsIdleTimer?.cancel();
    _morphController.dispose();
    // Performance & Battery Optimization: Pause silent canvas video when NowPlaying screen is dismissed
    CanvasVideoManager.instance.pause();
    super.dispose();
  }

  /// Opens the lyrics view.
  ///
  /// [silent] swaps to lyrics from the queue without touching the artwork
  /// morph. Both surfaces rest at the *same* 46px mini header, so when the
  /// mini is already landed the two are interchangeable and the honest
  /// transition is a page swap, not a flight. Without this the queue played
  /// the full mini -> hero -> mini round trip: the album and title visibly
  /// climbed to the top and came back for a change that never moved them.
  void _openLyrics({bool silent = false}) {
    if (_isLyricsOpen) return;

    // Arriving from the queue: retire the queue flight and swap the page.
    final fromQueue = _queueMorphOpen;
    if (fromQueue) {
      _queueMorphGen++;
      _queueMorphOpen = false;
      _queueMorphController.value = 0;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    }

    setState(() {
      _isLyricsOpen = true;
      _currentTab = 0;
    });

    if (silent || fromQueue) {
      // Hold the mini. Page 0 already draws its header at the landed rect, so
      // holding the morph at 1 makes the swap invisible.
      _morphController.value = 1.0;
    } else {
      _morphController.forward();
    }
    _startLyricsIdle();
    // Battery & CPU Optimization: Pause video canvas decoding while lyrics screen covers the viewport
    CanvasVideoManager.instance.pause();
  }

  void _closeLyrics({bool silent = false}) {
    if (!_isLyricsOpen) return;
    final provider = Provider.of<MusicProvider>(context, listen: false);
    setState(() {
      _isLyricsOpen = false;
      // Properly restore tab indicator to motion canvas (1) if enabled, otherwise album mode (-1)
      _currentTab = provider.animatedCanvasEnabled ? 1 : -1;
    });
    // A silent close keeps the mini in place because the caller is about to
    // hand the same header to the queue page.
    if (!silent) {
      _morphController.reverse();
    }
    _cancelLyricsIdle();
    // Resume video canvas playback immediately upon returning to player
    if (provider.animatedCanvasEnabled && provider.isPlaying) {
      CanvasVideoManager.instance.resume();
    }
  }

  // Lyrics idle chrome: 5s of stillness hides the bottom chrome so the
  // words own the screen. Any tap/scroll/track change calls
  // _pokeLyricsIdle to reveal + restart. One-shot timer, lyrics-only,
  // so there is no background cost anywhere else.
  void _startLyricsIdle() {
    _cancelLyricsIdle();
    final provider = Provider.of<MusicProvider>(context, listen: false);
    _idleTrackId = provider.currentTrack?.id ?? widget.track.id;
    _lyricsIdleTimer = Timer(_kLyricsIdleTimeout, () {
      if (!mounted || !_isLyricsOpen) return;
      setState(() => _lyricsChromeHidden = true);
    });
  }

  void _cancelLyricsIdle() {
    _lyricsIdleTimer?.cancel();
    _lyricsIdleTimer = null;
    if (_lyricsChromeHidden && mounted) {
      setState(() => _lyricsChromeHidden = false);
    }
  }

  void _pokeLyricsIdle() {
    if (!_isLyricsOpen) return;
    if (_lyricsChromeHidden && mounted) {
      setState(() => _lyricsChromeHidden = false);
    }
    _startLyricsIdle();
  }

  void _toggleLyrics() {
    if (_isLyricsOpen) {
      _closeLyrics();
    } else {
      _openLyrics();
    }
  }

  void _returnToAlbum() {
    HapticFeedback.selectionClick();
    // Queue open: the morph owns the way home (flight, then swap).
    if (_queueMorphOpen) {
      _closeQueueMorph();
      return;
    }
    final provider = Provider.of<MusicProvider>(context, listen: false);
    setState(() {
      _currentTab = provider.animatedCanvasEnabled ? 1 : -1;
      _deckVisible = true;
    });
    if (_isLyricsOpen) {
      _closeLyrics();
    }
    if (_pageController.hasClients &&
        (_pageController.page ?? 0).round() != 0) {
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _navigateToTab(int index) {
    HapticFeedback.selectionClick();
    final provider = Provider.of<MusicProvider>(context, listen: false);

    if (index == 2) {
      // Wave / Canvas tab: Toggle lofi on/off and toggle visualizer canvas state!
      provider.lofi.toggle();
      provider.toggleCanvas();
      final isLofi = provider.isLofiEnabled;
      HapticFeedback.mediumImpact();
      GlassSnackBar.show(
        context,
        message: isLofi
            ? 'Lofi Vibe Active • 0.9× Speed, Warm Pitch'
            : 'Lofi Mode Off • Original Speed',
      );
      return;
    }

    if (index == 1) {
      // Film / Animated Cover Art tab:
      // Toggles motion canvas video in-place directly on the hero artwork!
      // BitChord architecture: no separate screen.
      if (_isLyricsOpen) {
        _closeLyrics();
      }
      if (_pageController.hasClients &&
          (_pageController.page ?? 0).round() != 0) {
        _pageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      }
      final newEnabled = !provider.animatedCanvasEnabled;
      provider.setAnimatedCanvasEnabled(newEnabled);
      if (newEnabled) {
        CanvasVideoManager.instance.attachTrack(
          provider.currentTrack ?? widget.track,
          isPlaying: provider.isPlaying,
        );
      } else {
        CanvasVideoManager.instance.pause();
      }
      HapticFeedback.mediumImpact();
      GlassSnackBar.show(
        context,
        message: newEnabled
            ? 'Motion Artwork Enabled'
            : 'Still Artwork Active',
      );
      setState(() {
        _currentTab = newEnabled ? 1 : -1;
      });
      return;
    }

    if (index == 0) {
      // Tab 0: Lyrics
      // Lyrics owns the viewport: a held queue header snaps shut
      // instantly underneath its morph (invisible, no flight to watch).
      if (_queueMorphOpen) {
        _queueMorphGen++;
        _queueMorphController.value = 0;
        if (_pageController.hasClients) _pageController.jumpToPage(0);
        setState(() => _queueMorphOpen = false);
      }
      if (_currentTab == 0 && _isLyricsOpen) {
        _closeLyrics();
      } else {
        if (_pageController.hasClients &&
            (_pageController.page ?? 0).round() != 0) {
          _pageController.jumpToPage(0);
        }
        _openLyrics();
      }
      return;
    }

    // Tab 3: Queue shared-element morph (lyrics language, not a slide).
    if (_queueMorphOpen) {
      _returnToAlbum();
      return;
    }
    _openQueueMorph();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<MusicProvider, _NowPlayingStateData>(
      selector: (_, p) {
        final current = p.currentTrack ?? widget.track;
        return _NowPlayingStateData(
          track: current,
          palette: p.paletteGenerator,
          isPlaying: p.isPlaying,
          animatedCanvasEnabled: p.animatedCanvasEnabled,
          isOfflineMode: p.isOfflineMode,
          shuffleEnabled: p.shuffleEnabled,
          repeatMode: p.repeatMode,
          isLiked: p.isSongLiked(current.id),
          isLofiEnabled: p.isLofiEnabled,
        );
      },
      builder: (context, data, child) {
        final musicProvider = context.read<MusicProvider>();
        final currentTrack = data.track;
        // A new track restarts the lyrics idle clock (the words get their
        // 5s grace again). Field write only - the poke defers past build
        // because setState cannot run synchronously inside one.
        if (currentTrack.id != _idleTrackId) {
          _idleTrackId = currentTrack.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (!_deckVisible) setState(() => _deckVisible = true);
            _pokeLyricsIdle();
          });
        }
        final palette = data.palette;
        final accentColor =
            ColorUtils.getVibrantAccent(palette, _defaultPrimaryColor);
        final isPlaying = data.isPlaying;
        final mq = MediaQuery.of(context);
        final statusBarHeight = mq.padding.top;

        if (_lastAttachedTrackId != currentTrack.id ||
            _lastAttachedCanvasEnabled != data.animatedCanvasEnabled) {
          _lastAttachedTrackId = currentTrack.id;
          _lastAttachedCanvasEnabled = data.animatedCanvasEnabled;
          if (data.animatedCanvasEnabled) {
            CanvasVideoManager.instance
                .attachTrack(currentTrack, isPlaying: isPlaying);
          } else {
            CanvasVideoManager.instance.pause();
          }
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // 0. Solid dark foundation base
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFF08080A)),
              ),

              // 1. Master Backdrop: Blurred album art base + Whole-screen blurred video canvas (BitChord ArtworkMeshBackdrop)
              Positioned.fill(
                child: RepaintBoundary(
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Base still album art blur.
                        //
                        // The real blur is back: replacing it with a tiny
                        // decode + upscale was cheaper on paper but visibly
                        // degraded the wash, and it bought almost nothing —
                        // this subtree sits inside its own RepaintBoundary, so
                        // the blur rasterises once and is not what was costing
                        // the morph its frames.
                        if (currentTrack.albumArtUrl.isNotEmpty)
                          Transform.scale(
                            scale: 1.6,
                            alignment: Alignment.topCenter,
                            child: ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: 60,
                                sigmaY: 60,
                              ),
                              child: SizedBox.expand(
                                child: _buildAlbumArtImage(
                                  currentTrack,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          )
                        else
                          const ColoredBox(color: Color(0xFF101010)),

                        // Whole-screen video canvas blur overlay
                        if (musicProvider.animatedCanvasEnabled)
                          ValueListenableBuilder<VideoPlayerController?>(
                            valueListenable:
                                CanvasVideoManager.instance.controllerNotifier,
                            builder: (context, vController, _) {
                              if (vController == null ||
                                  !vController.value.isInitialized) {
                                return const SizedBox.shrink();
                              }
                              final vSize = vController.value.size;
                              if (vSize.width <= 0 || vSize.height <= 0) {
                                return const SizedBox.shrink();
                              }
                              return ValueListenableBuilder<bool>(
                                valueListenable:
                                    CanvasVideoManager.instance.isRenderedNotifier,
                                builder: (context, isRendered, _) {
                                  return AnimatedOpacity(
                                    opacity: isRendered ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 400),
                                    curve: Curves.easeOutCubic,
child: Transform.scale(
                                        scale: 1.35,
                                        alignment: Alignment.center,
                                        child: ImageFiltered(
                                          imageFilter: ImageFilter.blur(
                                            sigmaX: 55,
                                            sigmaY: 55,
                                          ),
                                        child: SizedBox.expand(
                                          child: FittedBox(
                                            fit: BoxFit.cover,
                                            clipBehavior: Clip.hardEdge,
                                            child: SizedBox(
                                              width: vSize.width,
                                              height: vSize.height,
                                              child: VideoPlayer(vController),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // 1.5 Dual radiant color mesh layers (BitChord ArtworkMeshBackdrop: vibrant luminous glow)
              Positioned.fill(
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(begin: accentColor, end: accentColor),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (context, color, child) {
                    final dynColor = color ?? accentColor;
                    return Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0.0, -0.25),
                              radius: 1.25,
                              colors: [
                                dynColor.withValues(alpha: 0.46),
                                dynColor.withValues(alpha: 0.18),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.52, 1.0],
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0.45, 0.65),
                              radius: 1.15,
                              colors: [
                                dynColor.withValues(alpha: 0.26),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 1.0],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // 2. Gentle ambient gradient scrim overlay (BitChord ArtworkMeshBackdrop: luminous 0.06 -> 0.32)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.06),
                        Colors.black.withValues(alpha: 0.16),
                        Colors.black.withValues(alpha: 0.32),
                      ],
                      stops: const [0.0, 0.50, 1.0],
                    ),
                  ),
                ),
              ),

              // 2.5 Soft top scrim gradient behind status bar and pull handle
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: true,
                  child: Container(
                    height: statusBarHeight + 52.0,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.40),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Main PageView & Shell (Edge-to-Edge full bleed till top y = 0)
              // Passive interaction witness for the lyrics idle timer:
              // Listener never consumes (zero gesture impact). Only
              // finger-driven scrolls restart the stillness clock -
              // programmatic ones (lyric auto-advance) must not, or the
              // timer could never fire while words scroll by themselves.
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _pokeLyricsIdle(),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is ScrollUpdateNotification &&
                          n.dragDetails != null) {
                        _pokeLyricsIdle();
                      }
                      // Deck collapse routing: the queue page follows its
                      // list, the lyrics screen its body. The tracker admits
                      // only finger-phase gestures (see its docs) and reports
                      // through the single setState gate below.
                      if (_currentTab == 3) {
                        return _queueCollapse.handle(n, _onDeckCollapse);
                      }
                      if (_isLyricsOpen) {
                        return _lyricsCollapse.handle(n, _onDeckCollapse);
                      }
                      return false;
                    },
                  child: Column(
                children: [
                  Expanded(
                    // Page metrics hoist: heroH derives from the real page
                    // height once, shared by the player page and the queue
                    // morph overlay so both agree to the pixel.
                    child: LayoutBuilder(
                      builder: (context, pageBox) {
                        final pageH = pageBox.maxHeight;
                        final heroH =
                            (pageH - 100.0).clamp(0.0, pageH);
                        final totalW = pageBox.maxWidth;
                        return Stack(
                          children: [
                            PageView(
                              controller: _pageController,
                              physics: (_isScrubbing || _queueMorphOpen)
                                  ? const NeverScrollableScrollPhysics()
                                  : const BouncingScrollPhysics(),
                      onPageChanged: (page) {
                        // Every page owns its own collapse state. Carrying it
                        // across a page change is what made a queue the
                        // listener had scrolled down come back with the deck
                        // already hidden and no way to tell why.
                        _queueCollapse.reset();
                        _lyricsCollapse.reset();
                        setState(() {
                          _deckVisible = true;
                          if (page == 0) {
                            if (_queueMorphOpen) {
                              // Manual swipe home: snap the held header shut
                              // (no flight to watch on the way out).
                              _queueMorphGen++;
                              _queueMorphController.value = 0;
                              _queueMorphOpen = false;
                            }
                            _currentTab = _isLyricsOpen
                                        ? 0
                                        : (musicProvider.animatedCanvasEnabled
                                            ? 1
                                            : -1);
                                    if (musicProvider
                                            .animatedCanvasEnabled &&
                                        musicProvider.isPlaying &&
                                        !_isLyricsOpen) {
                                      CanvasVideoManager.instance.resume();
                                    }
                          } else if (page == 1) {
                            if (!_queueMorphOpen &&
                                _queueMorphController.value == 0) {
                              // Manual swipe in: land the header instantly
                              // (no hero to fly from on this path).
                              _queueMorphGen++;
                              _queueMorphOpen = true;
                              _queueMorphController.value = 1;
                            }
                            _currentTab = 3; // Queue (Queue tab)
                                    if (_isLyricsOpen) _closeLyrics();
                                    CanvasVideoManager.instance.pause();
                                  }
                                });
                              },
                              children: [
                                // Page 0: Main Player (artwork + titles; the
                                // deck below carries lyric line, scrubber,
                                // transport and volume on both pages).
                                _buildMainPlayerPage(
                                  context,
                                  currentTrack,
                                  musicProvider,
                                  accentColor,
                                  isPlaying,
                                  heroH,
                                ),

                                // Page 1: Queue fullscreen (no internal mini:
                                // the morph overlay above holds the header).
                                // Staged entrance (BitChord panelsSettled
                                // language): the flight lands first, then the
                                // content fades + rises in on the morph's last
                                // stretch. Same controller, child cached so
                                // only this wrapper rebuilds mid-flight.
                                AnimatedBuilder(
                                  animation: _queueMorphController,
                                  builder: (context, child) {
                                    final q = _queueMorphController.value
                                        .clamp(0.0, 1.0);
                                    final e =
                                        const Interval(0.6, 1.0, curve: Curves.easeOutCubic)
                                            .transform(q);
                                    return Opacity(
                                      opacity: e,
                                      child: Transform.translate(
                                        offset: Offset(0, 16 * (1 - e)),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: QueueScreen(
                                    onMinimize: widget.onMinimize,
                                    onTabTap: (_) => _returnToAlbum(),
                                    isEmbedded: true,
                                    showPlayingNow: false,
                                    showMiniHeader: true,
                                  ),
                                ),
                              ],
                            ),
                            // Shared-element flight + held header (lyrics
                            // morph language: same rects, same 380ms
                            // easeInOutCubic).
                            _buildQueueMorphOverlay(
                              totalW: totalW,
                              heroH: heroH,
                              statusBarHeight:
                                  MediaQuery.of(context).padding.top,
                              currentTrack: currentTrack,
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  // Shared player deck (BitChord SlidingPlayerDeck parity):
                  // lyric line, scrubber, transport, volume, pill, output.
                  // One block under both pages, so nothing jumps switching
                  // between them. Hides on queue-scroll-down and on 5s
                  // lyrics idle; any reveal path restores it.
                  _buildPlayerDeck(
                    context,
                    musicProvider,
                    accentColor,
                    isPlaying,
                    currentTrack,
                  ),
                ],
                  ),
                ),
              ),

              // 4. Floating pull-down handle (floats on top of all pages at top: statusBarHeight + 8)
              Positioned(
                top: statusBarHeight + 8,
                left: 0,
                right: 0,
                child: _buildPullDownHandle(context),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Pull-down handle ────────────────────────────────────────────────────

  Widget _buildPullDownHandle(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        HapticFeedback.lightImpact();
        if (widget.onMinimize != null) {
          widget.onMinimize!();
        } else if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: Center(
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 6),
          width: 38,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
  }

  // ── Page 1: Main Player (BitChord Hero Full Bleed Artwork & Compact Controls) ─

  Widget _buildMainPlayerPage(
    BuildContext context,
    Track currentTrack,
    MusicProvider musicProvider,
    Color accentColor,
    bool isPlaying,
    double heroH,
  ) {
    final mq = MediaQuery.of(context);
    final statusBarHeight = mq.padding.top;
    final isLiked = musicProvider.isSongLiked(currentTrack.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth;

        return AnimatedBuilder(
          animation: _morphAnim,
          builder: (context, _) {
            final t = _morphAnim.value;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // ── LAYER 1: Full Kinetic Lyrics View (fades in as t -> 1.0) ──
                if (_isLyricsOpen || t > 0.001)
                  Positioned.fill(
                    child: Opacity(
                      opacity: t,
                      child: IgnorePointer(
                        ignoring: t < 0.6,
                        child: LyricsScreen(
                          onMinimize: widget.onMinimize,
                          onReturnToAlbum: _closeLyrics,
                          onTabTap: _navigateToTab,
                          isEmbedded: true,
                          showHeader: false,
                          // Deck below owns seek/volume now: one set only.
                          showBottomScrubber: false,
                        ),
                      ),
                    ),
                  ),

                // ── LAYER 2 retired into the shared deck below ──


                // ── LAYER 3: Morphing Hero Artwork ──
                Positioned(
                  left: lerpDouble(0.0, 20.0, t)!,
                  top: lerpDouble(0.0, statusBarHeight + 32.0, t)!,
                  width: lerpDouble(totalW, 46.0, t)!,
                  height: lerpDouble(heroH, 46.0, t)!,
                  child: Listener(
                    onPointerDown: _onArtPointerDown,
                    onPointerMove: _onArtPointerMove,
                    onPointerUp: _onArtPointerUp,
                    child: GestureDetector(
                      key: const ValueKey('now_playing_album_art'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _toggleLyrics();
                      },
                      child: ClipRRect(
                      // Radius ramp is part of the motion: the small end has to
                      // read as a rounded card, not a shrunken rectangle.
                      borderRadius: BorderRadius.circular(
                        lerpDouble(_kHeroStartRadius, 8.0, t)!,
                      ),
                      // Own repaint boundary. Without one this subtree is
                      // re-rasterised on every frame of the flight; with one,
                      // the artwork rasterises once and only the layer matrix
                      // changes. This is the single biggest win for the morph.
                      child: RepaintBoundary(
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          // Hoisted: building these gradients inside the
                          // callback allocated two shader objects per frame
                          // for the whole flight.
                          shaderCallback: (bounds) => (t >= 0.05
                                  ? _kOpaqueFade
                                  : _kBottomFade)
                              .createShader(bounds),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              SizedBox.expand(
                                child: _buildAlbumArtImage(
                                  currentTrack,
                                  // Small once it is on its way to the pill:
                                  // an 800px bitmap resampled into a 46dp box
                                  // is pure waste for 380ms.
                                  cacheSize: t > 0.5
                                      ? AppImageCache.morphMemCache
                                      : AppImageCache.heroMemCache,
                                ),
                              ),
                              // In-place animated motion canvas overlay
                              if (musicProvider.animatedCanvasEnabled)
                                Positioned.fill(
                                  child: InPlaceCanvasPlayer(
                                    track: currentTrack,
                                    isPlaying: isPlaying,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ),
                  ),
                ),

                // ── LAYER 4: Morphing Title & Artist ──
                Positioned(
                  left: lerpDouble(24.0, 78.0, t)!,
                  top: lerpDouble(heroH + 20.0, statusBarHeight + 34.0, t)!,
                  width: lerpDouble(
                      totalW - 48.0 - 104.0, totalW - 78.0 - 110.0, t)!,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      if (t >= 0.5) {
                        HapticFeedback.lightImpact();
                        _closeLyrics();
                      } else {
                        if (currentTrack.artistName.isNotEmpty &&
                            currentTrack.artistName != 'Unknown Artist') {
                          await ArtistPickerSheet.showIfNeeded(
                            context,
                            musicProvider,
                            currentTrack.artistName,
                          );
                        }
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentTrack.trackName,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: lerpDouble(24.0, 15.0, t)!,
                            fontWeight: FontWeight.w700,
                            letterSpacing: lerpDouble(-0.3, 0.0, t)!,
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: lerpDouble(3.0, 2.0, t)!),
                        Text(
                          currentTrack.artistName,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white
                                .withValues(alpha: lerpDouble(0.68, 0.65, t)!),
                            fontSize: lerpDouble(17.0, 13.0, t)!,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── LAYER 5: Action Buttons (Favorite Star, Options, Pronunciation) ──
                // Favorite Star
                Positioned(
                  right: lerpDouble(76.0, 58.0, t)!,
                  top: lerpDouble(heroH + 20.0, statusBarHeight + 34.0, t)!,
                  child: _buildCircularGlassButton(
                    icon: isLiked
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    iconColor: isLiked ? accentColor : Colors.white,
                    semanticLabel: 'Favorite',
                    size: lerpDouble(42.0, 36.0, t)!,
                    iconSize: lerpDouble(22.0, 19.0, t)!,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      musicProvider.toggleLike(currentTrack);
                    },
                  ),
                ),

                // Options Button
                Positioned(
                  right: lerpDouble(24.0, 14.0, t)!,
                  top: lerpDouble(heroH + 20.0, statusBarHeight + 34.0, t)!,
                  child: _buildCircularGlassButton(
                    icon: Icons.more_horiz_rounded,
                    iconColor: Colors.white,
                    semanticLabel: 'Options',
                    size: lerpDouble(42.0, 36.0, t)!,
                    iconSize: lerpDouble(22.0, 19.0, t)!,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      GlassOptionsSheet.show(
                        context,
                        track: currentTrack,
                        accentColor: accentColor,
                      );
                    },
                  ),
                ),

                // Pronunciation Button ("aあ")
                if (t > 0.05)
                  Positioned(
                    right: 102.0,
                    top: statusBarHeight + 34.0,
                    child: Opacity(
                      opacity: ((t - 0.25) / 0.75).clamp(0.0, 1.0),
                      child: Semantics(
                        label: 'Pronunciation',
                        button: true,
                        excludeSemantics: true,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            AudioQualityLanguageSheet.show(context);
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                                width: 0.6,
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'aあ',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Real-Time Lyric Preview Snippet (Above Seek Bar matching Screenshot) ─

  Widget _buildLyricPreviewSnippet(
    BuildContext context,
    Track track,
    MusicProvider provider,
  ) {
    return Consumer<MusicProvider>(
      builder: (context, musicProv, _) {
        final activeTrack = musicProv.currentTrack ?? track;
        return StreamBuilder<Duration>(
          stream: musicProv.positionStream,
          initialData: musicProv.position,
          builder: (context, snapshot) {
            String displayText = 'Let it breathe';
            bool isInstrumental = true;

            final isMatchingTrack = musicProv.lyricsTrackId == activeTrack.id;

            if (musicProv.isLoadingLyrics || !isMatchingTrack) {
              final idx = activeTrack.id.hashCode.abs() % _lyricsIntroPhrases.length;
              displayText = _lyricsIntroPhrases[idx];
              isInstrumental = true;
            } else if (musicProv.hasSyncedLyrics &&
                musicProv.currentLyrics != null &&
                musicProv.currentLyrics!.isNotEmpty) {
              final lyrics = musicProv.currentLyrics!;
              final posMs = _draggedPositionSec != null
                  ? _draggedPositionSec!.toInt()
                  : (snapshot.data?.inMilliseconds ?? musicProv.position.inMilliseconds);
              final idx = LyricsUtils.findCurrentLineIndex(lyrics, posMs);

              if (idx >= 0 && idx < lyrics.length) {
                final line = lyrics[idx];
                final text = line.text.trim();
                final firstVocalIdx = lyrics.indexWhere(
                  (e) => e.text.trim().isNotEmpty && !e.isMusicalBreak,
                );
                final isBeforeFirstVocal = firstVocalIdx >= 0 &&
                    (idx < firstVocalIdx || posMs < lyrics[firstVocalIdx].timeMs);

                if (text.isNotEmpty && !line.isMusicalBreak && !isBeforeFirstVocal) {
                  displayText = text;
                  isInstrumental = false;
                } else {
                  final pIdx = activeTrack.id.hashCode.abs() % _lyricsIntroPhrases.length;
                  displayText = _lyricsIntroPhrases[pIdx];
                  isInstrumental = true;
                }
              } else {
                final pIdx = activeTrack.id.hashCode.abs() % _lyricsIntroPhrases.length;
                displayText = _lyricsIntroPhrases[pIdx];
                isInstrumental = true;
              }
            } else {
              final idx = activeTrack.id.hashCode.abs() % _lyricsIntroPhrases.length;
              displayText = _lyricsIntroPhrases[idx];
              isInstrumental = true;
            }

            return Semantics(
              label: 'Current lyric: $displayText. Tap to open full lyrics.',
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _navigateToTab(0);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                  child: Row(
                    children: [
                      if (isInstrumental) ...[
                        Icon(
                          Icons.music_note_rounded,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 380),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.0, 0.28),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            displayText,
                            key: ValueKey<String>('${activeTrack.id}:$isInstrumental:$displayText'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: isInstrumental
                                  ? Colors.white.withValues(alpha: 0.60)
                                  : Colors.white.withValues(alpha: 0.95),
                              fontSize: 14.5,
                              fontWeight:
                                  isInstrumental ? FontWeight.w500 : FontWeight.w600,
                              letterSpacing: -0.15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: Colors.white.withValues(alpha: 0.50),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Scrubber Bar with Timestamps (Image 1) ──────────────────────────────

  Widget _buildScrubberBar(
    BuildContext context,
    MusicProvider provider, {
    Color? accentColor,
  }) {
    return StreamBuilder<Duration>(
      stream: provider.positionStream,
      initialData: provider.position,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? provider.position;
        final dur = provider.duration;
        final double maxSec =
            dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
        final double currentSec = _draggedPositionSec ??
            pos.inMilliseconds.toDouble().clamp(0.0, maxSec);
        final double fraction = (currentSec / maxSec).clamp(0.0, 1.0);
        final remaining = dur > Duration(milliseconds: currentSec.toInt())
            ? dur - Duration(milliseconds: currentSec.toInt())
            : Duration.zero;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThinSlider(
              value: fraction,
              idleHeight: 7.0,
              activeHeight: 12.0,
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.24),
              semanticLabel: 'Scrubber',
              onValueChangeStart: () {
                setState(() {
                  _isScrubbing = true;
                  _draggedPositionSec = currentSec;
                });
              },
              onValueChange: (val) {
                setState(() {
                  _draggedPositionSec = val * maxSec;
                });
              },
              onValueChangeFinished: () {
                final targetSec = _draggedPositionSec;
                if (targetSec != null) {
                  provider
                      .seekTo(Duration(milliseconds: targetSec.toInt()));
                }
                setState(() {
                  _isScrubbing = false;
                  _draggedPositionSec = null;
                });
              },
            ),
            Transform.translate(
              offset: const Offset(0, -9.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatTime(_draggedPositionSec != null
                        ? Duration(milliseconds: _draggedPositionSec!.toInt())
                        : pos),
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '-${_formatTime(remaining)}',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Transport Controls (Previous, Play/Pause, Next) (Image 1) ───────────

  Widget _buildTransportControls(
    BuildContext context,
    MusicProvider provider,
    bool isPlaying,
    Color accentColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Previous track (Image 1: <<)
        Semantics(
          label: 'Previous track',
          button: true,
          child: IconButton(
            iconSize: 44,
            icon: const Icon(
              Icons.skip_previous_rounded,
              color: Colors.white,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              provider.skipToPrevious();
            },
          ),
        ),

        // Play / Pause (Image 1: Large solid white icon directly on backdrop)
        Semantics(
          label: isPlaying ? 'Pause' : 'Play',
          button: true,
          child: GestureDetector(
            onTapDown: (_) => setState(() => _isPlayPressed = true),
            onTapUp: (_) => setState(() => _isPlayPressed = false),
            onTapCancel: () => setState(() => _isPlayPressed = false),
            onTap: () {
              HapticFeedback.lightImpact();
              if (isPlaying) {
                provider.pauseTrack();
              } else {
                provider.resumeTrack();
              }
            },
            child: AnimatedScale(
              scale: _isPlayPressed ? 0.90 : 1.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              child: Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 58,
                ),
              ),
            ),
          ),
        ),

        // Next track (Image 1: >>)
        Semantics(
          label: 'Next track',
          button: true,
          child: IconButton(
            iconSize: 44,
            icon: const Icon(
              Icons.skip_next_rounded,
              color: Colors.white,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              provider.skipToNext();
            },
          ),
        ),
      ],
    );
  }

  // ── Volume Slider (Image 1) ─────────────────────────────────────────────

  Widget _buildVolumeSlider(BuildContext context, MusicProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Row(
        children: [
          Icon(
            Icons.volume_down_rounded,
            size: 20,
            color: Colors.white.withValues(alpha: 0.50),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DeviceVolumeSlider(
              idleHeight: 6.0,
              activeHeight: 11.0,
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.24),
              onDragStart: () {
                setState(() {
                  _isScrubbing = true;
                });
              },
              onDragEnd: () {
                setState(() {
                  _isScrubbing = false;
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.volume_up_rounded,
            size: 20,
            color: Colors.white.withValues(alpha: 0.50),
          ),
        ],
      ),
    );
  }

  // ── Output Sink Row ───────────────────────────────────────────────────

  Widget _buildOutputRow(BuildContext context) {
    final audio = Provider.of<AudioOutputService?>(context);
    if (audio == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AudioOutputSheet.show(context);
        },
        child: Semantics(
          label: 'Audio output',
          button: true,
          child: Text(
            audio.activeName,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  // ── Bottom Mode Selector Tab Bar (Images 1, 2, 4) ───────────────────────

  // ── Bottom Mode Selector Tab Bar (segmented pill) ──────────────────────
  //
  // One joined capsule cut into four segments by dividers (BitChord parity),
  // instead of four separate buttons. Fixed segment widths keep the row from
  // changing size as selection moves, so the glyphs never slide. Dividers hide
  // next to the active segment so a line never sits on white.

  // Persistent bottom bar shared by the player page and the queue page:
  // lyrics button left, queue button right, context pill in the middle.
  // Player page shows canvas/lofi (2 segments); the queue page shows the
  // queue controls (shuffle/repeat/autoplay) so the queue screen carries
  // exactly one pill. An AnimatedSwitcher cross-fades the pills on settle.

  // Queue-list scroll drives the shared deck (BitChord collapsePlayerOnScroll
  // parity): list scrolling down hides the deck, scrolling back up reveals
  // it. State-gated so a fling settling produces no rebuild storm.
  void _onDeckCollapse(bool hide) {
    if (hide == !_deckVisible) return;
    setState(() => _deckVisible = !hide);
  }

  // Shared player deck (BitChord SlidingPlayerDeck parity): lyric line,
  // scrubber, transport, volume, mode pill, output - ONE block measured at
  // its natural height and pinned under both pages. Same geometry on player
  // and queue, so switching screens never moves a control by a pixel.
  // Visibility is the AND of the queue-scroll flag and the lyrics idle
  // flag; either hides with a 300ms fade + short rise, any reveal restores.
  Widget _buildPlayerDeck(
    BuildContext context,
    MusicProvider musicProvider,
    Color accentColor,
    bool isPlaying,
    Track currentTrack,
  ) {
    final shown = _deckVisible && !_lyricsChromeHidden;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    // Size collapses too (not just fade): the page above grows into the
    // freed space, so lyrics go full-page and the queue list goes full
    // length instead of staring at a blank strip. One 300ms shot.
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: shown
            ? AnimatedOpacity(
                key: const Key('npPlayerDeck'),
        opacity: shown ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: IgnorePointer(
          ignoring: !shown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Control cluster keeps the old page's 20dp side inset, so
              // the scrubber/transport/volume measure exactly as before.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Real-time lyric preview snippet (tappable into lyrics)
                    _buildLyricPreviewSnippet(
                      context,
                      currentTrack,
                      musicProvider,
                    ),

                    const SizedBox(height: 12),

                    // Scrubber Bar with timestamps
                    _buildScrubberBar(
                      context,
                      musicProvider,
                      accentColor: accentColor,
                    ),

                    const SizedBox(height: 16),

                    // Transport Controls (Previous, Play/Pause, Next)
                    _buildTransportControls(
                      context,
                      musicProvider,
                      isPlaying,
                      accentColor,
                    ),

                    const SizedBox(height: 14),

                    // Volume Slider
                    _buildVolumeSlider(context, musicProvider),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Accessibility parity semantics (transport carries no labels)
              Semantics(
                label: 'Shuffle',
                button: true,
                enabled: true,
                onTap: musicProvider.toggleShuffle,
                child: const SizedBox.shrink(),
              ),
              Semantics(
                label: 'Repeat',
                button: true,
                enabled: true,
                onTap: musicProvider.cycleRepeatMode,
                child: const SizedBox.shrink(),
              ),

              // Mode pill + side buttons (lyrics left, queue right)
              _buildBottomBar(context, musicProvider, accentColor),

              // Output sink: where audio is reaching; tap opens the sheet.
              _buildOutputRow(context),

              SizedBox(
                height: bottomPad > 0 ? bottomPad + 2 : 10,
              ),
            ],
          ),
        ),
      )
            : const SizedBox.shrink(),
      ),
    );
  }

  // Plain side button (BitChord parity): no circle, no fill. Active is
  // full white, idle is dimmed. Haptics stay with the navigation calls.
  Widget _plainSideButton({
    required String semanticLabel,
    required bool isActive,
    required VoidCallback onTap,
    required Widget icon,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      selected: isActive,
      // House press physics (SquishOnPress): navigation calls below already
      // play their own haptic, so nothing double-buzzes.
      child: SquishOnPress(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: icon,
        ),
      ),
    );
  }

  // Queue open: instant page swap under the overlay (invisible at q=0 -
  // pixel-perfect hero cover), then the 380ms flight to the mini.
  void _openQueueMorph() {
    if (_queueMorphOpen) return;

    // Swapping out of lyrics: the mini is already on screen, so hand it over
    // instead of flying it home first. Same state the queue rests in, so the
    // transition is a page swap - see [_openLyrics].
    final fromLyrics = _isLyricsOpen;
    final miniLanded =
        fromLyrics && _morphController.value >= 0.999;
    if (fromLyrics) _closeLyrics(silent: true);

    _queueMorphGen++;
    setState(() {
      _queueMorphOpen = true;
      _currentTab = 3;
      _deckVisible = true;
    });
if (_pageController.hasClients) _pageController.jumpToPage(1);
    if (miniLanded) {
      _queueMorphController.value = 1.0;
      PerfTrace.summary('queue-morph-open-instant');
    } else {
      PerfTrace.mark('queue-morph-open');
      _queueMorphController
          .forward(from: 0)
          .then((_) => PerfTrace.summary('queue-morph-open'));
    }
    // The collapse trackers belong to the page you just left. Carrying their
    // state across meant returning to a scrolled-down queue with the deck
    // already collapsed, which reads as a stuck deck rather than a remembered
    // scroll position.
    _lyricsCollapse.reset();
  }

  // Queue close: flight home over the queue page, then the invisible swap
  // back (the overlay lands exactly on the hero rect). Stale completions
  // from toggle spam are dropped by generation.
  void _closeQueueMorph() {
    if (!_queueMorphOpen) return;
    final gen = ++_queueMorphGen;
    final provider = Provider.of<MusicProvider>(context, listen: false);
    setState(() {
      _currentTab = provider.animatedCanvasEnabled ? 1 : -1;
      _deckVisible = true;
    });
    PerfTrace.mark('queue-morph-close');
    unawaited(_queueMorphController.reverse().then((_) {
      PerfTrace.summary('queue-morph-close');
      if (!mounted || gen != _queueMorphGen) return;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      setState(() => _queueMorphOpen = false);
    }));
    _queueCollapse.reset();
  }

  // Queue shared-element morph, mirroring _buildMainPlayerPage layers 3-4
  // rect-for-rect (same 46px mini destination, same type ramp, same 380ms
  // easeInOutCubic): the album flies top-left with title/artist sliding
  // right beside it, then holds as the queue header. Tap the mini to fly
  // home. Canvas is deliberately not mirrored: a 380ms still over motion
  // is invisible under an exact-cover swap.
  Widget _buildQueueMorphOverlay({
    required double totalW,
    required double heroH,
    required double statusBarHeight,
    required Track currentTrack,
  }) {
    return AnimatedBuilder(
      animation: _queueMorphController,
      builder: (context, _) {
        final q = Curves.easeInOutCubic.transform(
          _queueMorphController.value.clamp(0.0, 1.0),
        );
        if (!_queueMorphOpen && q <= 0) {
          return const SizedBox.shrink();
        }
        // Landed. The queue page's own header now owns the resting state, so the
        // flight retires instead of lingering as a title-shaped ghost - which is
        // what used to hide the star / pronunciation / options buttons, since
        // the overlay had no way to carry them.
        if (q >= 1) return const SizedBox.shrink();
        return Stack(
          children: [
            // Art flight: lyrics-mini rects exactly.
            Positioned(
              left: lerpDouble(0.0, 20.0, q)!,
              top: lerpDouble(0.0, statusBarHeight + 32.0, q)!,
              width: lerpDouble(totalW, 46.0, q)!,
              height: lerpDouble(heroH, 46.0, q)!,
              child: GestureDetector(
                key: const ValueKey('queueMorphArt'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _closeQueueMorph();
                },
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(lerpDouble(0.0, 8.0, q)!),
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) {
                      if (q >= 0.05) {
                        return const LinearGradient(
                          colors: [Colors.white, Colors.white],
                        ).createShader(bounds);
                      }
                      return const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.58, 1.0],
                      ).createShader(bounds);
                    },
                    child: SizedBox.expand(
                      child: _buildAlbumArtImage(
                      // This copy only ever lives in flight, and it only ever
                      // grows smaller. Decoding it at hero size meant two
                      // 800px textures alive for the same image mid-morph.
                      currentTrack,
                      cacheSize: AppImageCache.morphMemCache,
                    ),
                    ),
                  ),
                ),
              ),
            ),
            // Title flight: lyrics-mini rects + type ramp exactly.
            Positioned(
              left: lerpDouble(24.0, 78.0, q)!,
              top: lerpDouble(heroH + 20.0, statusBarHeight + 34.0, q)!,
              width: lerpDouble(
                  totalW - 48.0 - 104.0, totalW - 78.0 - 228.0, q)!,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _closeQueueMorph();
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentTrack.trackName,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: lerpDouble(24.0, 15.0, q)!,
                        fontWeight: FontWeight.w700,
                        letterSpacing: lerpDouble(-0.3, 0.0, q)!,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: lerpDouble(3.0, 2.0, q)!),
                    Text(
                      currentTrack.artistName,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white.withValues(
                            alpha: lerpDouble(0.68, 0.65, q)!),
                        fontSize: lerpDouble(17.0, 13.0, q)!,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    MusicProvider musicProvider,
    Color accentColor,
  ) {
    final onQueuePage = _currentTab == 3;
    final isLofiActive = musicProvider.isLofiEnabled;
    final canvasActive =
        _currentTab == 1 || musicProvider.animatedCanvasEnabled;
    final lyricsActive = _isLyricsOpen && !onQueuePage;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Row(
        children: [
          _plainSideButton(
            semanticLabel: 'Lyrics tab',
            isActive: lyricsActive,
            onTap: () => _navigateToTab(0),
            icon: AppleLyricsIcon(
              color: lyricsActive
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.55),
              size: 24,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.12),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: onQueuePage
                  ? LiquidGlassSegmented(
                      key: const ValueKey('controls'),
                      segments: queueControlSegments(
                        shuffleActive: musicProvider.shuffleEnabled,
                        repeatActive:
                            musicProvider.repeatMode != RepeatMode.off,
                        repeatOne:
                            musicProvider.repeatMode == RepeatMode.one,
                        autoplayActive: musicProvider.autoplayEnabled,
                        onShuffle: () {
                          HapticFeedback.selectionClick();
                          musicProvider.toggleShuffle();
                        },
                        onRepeat: () {
                          HapticFeedback.selectionClick();
                          musicProvider.cycleRepeatMode();
                        },
                        onAutoplay: () {
                          HapticFeedback.selectionClick();
                          musicProvider.toggleAutoplay();
                        },
                      ),
                    )
                  : LiquidGlassSegmented(
                      key: const ValueKey('tabs'),
                      segments: [
                        GlassSegment(
                          semanticLabel: 'Film tab',
                          isActive: canvasActive,
                          onTap: () => _navigateToTab(1),
                          icon: AppleFilmIcon(
                            color: canvasActive
                                ? Colors.black
                                : Colors.white.withValues(alpha: 0.42),
                            size: 24,
                          ),
                        ),
                        GlassSegment(
                          semanticLabel: 'Canvas tab',
                          isActive: false,
                          onTap: () => _navigateToTab(2),
                          icon: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              AppleCanvasIcon(
                                color: isLofiActive
                                    ? accentColor
                                    : Colors.white.withValues(alpha: 0.42),
                                size: 24,
                              ),
                              if (isLofiActive)
                                Positioned(
                                  top: -2,
                                  right: -4,
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: accentColor,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: accentColor.withValues(
                                              alpha: 0.8),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 10),
          _plainSideButton(
            semanticLabel: 'Queue tab',
            isActive: onQueuePage,
            onTap: () {
              if (onQueuePage) {
                _returnToAlbum();
              } else {
                _navigateToTab(3);
              }
            },
            icon: Icon(
              Icons.format_list_bulleted_rounded,
              color: onQueuePage
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.55),
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularGlassButton({
    required IconData icon,
    required Color iconColor,
    required String semanticLabel,
    required VoidCallback onTap,
    double size = 44,
    double iconSize = 24,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.6,
            ),
          ),
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }

  Widget _buildAlbumArtImage(
    Track track, {
    BoxFit fit = BoxFit.cover,
    int? cacheSize,
  }) {
    final art = ImageQualityUtils.getHighResArtwork(track.albumArtUrl);
    if (art.isEmpty) return _buildArtPlaceholder();
    if (!art.contains('://')) {
      final f = File(art);
      if (f.existsSync()) return Image.file(f, fit: fit);
    }
    final size = cacheSize ?? AppImageCache.heroMemCache;
    return CachedNetworkImage(
      imageUrl: art,
      fit: fit,
      memCacheWidth: size,
      memCacheHeight: size,
      errorWidget: (_, __, ___) => _buildArtPlaceholder(),
    );
  }

  Widget _buildArtPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Icon(Icons.music_note, color: Colors.white30, size: 48),
      ),
    );
  }

  String _formatTime(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
