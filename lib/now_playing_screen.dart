import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../services/canvas_video_manager.dart';
import '../widgets/artist_picker_sheet.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/apple_player_icons.dart';
import '../widgets/thin_slider.dart';
import '../widgets/audio_quality_language_sheet.dart';
import '../widgets/in_place_canvas_player.dart';
import '../screens/lyrics_screen.dart';
import '../screens/queue_screen.dart';
import '../screens/canvas_video_screen.dart';
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

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();
    // Page 0: Main Player (with morphing Lyrics); Page 1: Canvas Video; Page 2: Queue
    _pageController = PageController(initialPage: 0);
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
    _morphController.dispose();
    super.dispose();
  }

  void _openLyrics() {
    if (_isLyricsOpen) return;
    setState(() {
      _isLyricsOpen = true;
      _currentTab = 0;
    });
    _morphController.forward();
  }

  void _closeLyrics() {
    if (!_isLyricsOpen) return;
    setState(() {
      _isLyricsOpen = false;
      _currentTab = -1;
    });
    _morphController.reverse();
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
    setState(() {
      _currentTab = -1;
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
      // Wave / Lofi tab: Toggle lofi on/off only! Do not change page.
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

    // Tab 3: Queue (Queue tab)
    if (_isLyricsOpen) {
      _closeLyrics();
    }

    if (_currentTab == index) {
      _returnToAlbum();
      return;
    }

    setState(() {
      _currentTab = index;
    });

    if (_pageController.hasClients) {
      _pageController.animateToPage(
        1, // Page 1 is QueueScreen
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final currentTrack = musicProvider.currentTrack ?? widget.track;
        final palette = musicProvider.paletteGenerator;
        final accentColor =
            ColorUtils.getVibrantAccent(palette, _defaultPrimaryColor);
        final isPlaying = musicProvider.isPlaying;
        final mq = MediaQuery.of(context);
        final statusBarHeight = mq.padding.top;

        if (musicProvider.animatedCanvasEnabled) {
          CanvasVideoManager.instance
              .attachTrack(currentTrack, isPlaying: isPlaying);
        } else {
          CanvasVideoManager.instance.pause();
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
                        // Base still album art blur
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
              Column(
                children: [
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (page) {
                        setState(() {
                          if (page == 0) {
                            _currentTab = _isLyricsOpen
                                ? 0
                                : (musicProvider.animatedCanvasEnabled ? 1 : -1);
                          } else if (page == 1) {
                            _currentTab = 3; // Queue (Queue tab)
                            if (_isLyricsOpen) _closeLyrics();
                          }
                        });
                      },
                      children: [
                        // Page 0: Main Player (with In-Place Motion Artwork & Morphing Lyrics)
                        _buildMainPlayerPage(
                          context,
                          currentTrack,
                          musicProvider,
                          accentColor,
                          isPlaying,
                        ),

                        // Page 1: Queue (Queue tab)
                        QueueScreen(
                          onMinimize: widget.onMinimize,
                          onTabTap: (_) => _returnToAlbum(),
                          isEmbedded: true,
                        ),
                      ],
                    ),
                  ),

                  // Persistent Bottom Mode Selector Tab Bar
                  _buildBottomTabBar(context, musicProvider, accentColor),
                  SizedBox(
                    height: mq.padding.bottom > 0
                        ? mq.padding.bottom + 4
                        : 14,
                  ),
                ],
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
  ) {
    final mq = MediaQuery.of(context);
    final statusBarHeight = mq.padding.top;
    final isLiked = musicProvider.isSongLiked(currentTrack.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth;
        final totalH = constraints.maxHeight;

        // Controlled hero height: ~48% of total height (BitChord title at 51.6% parity)
        final double heroH = (totalH * 0.48).clamp(280.0, totalH * 0.52);
        const double fixedControlsH = 220.0;
        final double slack =
            (totalH - heroH - 76.0 - fixedControlsH).clamp(0.0, 300.0);

        // Proportional, generous vertical breathing room:
        // Lyric Snippet to Seekbar: 14-22dp
        final double gapLyricsToScrubber =
            (14.0 + slack * 0.08).clamp(12.0, 22.0);
        // Seekbar to Transport: 20-38dp
        final double gapScrubberToTransport =
            (20.0 + slack * 0.12).clamp(18.0, 38.0);
        // Transport to Volume: 18-34dp
        final double gapTransportToVolume =
            (18.0 + slack * 0.10).clamp(16.0, 34.0);

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
                          showBottomScrubber: true,
                        ),
                      ),
                    ),
                  ),

                // ── LAYER 2: Main Player Controls (fades out as t -> 1.0) ──
                // Pinned to bottom = 0 matching BitChord foot-pinned controls architecture.
                // Leaves natural, unhurried breathing space between the artist name and the lyric strip.
                if (t < 0.999)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Opacity(
                      opacity: (1.0 - t * 1.5).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 28.0 * t),
                        child: IgnorePointer(
                          ignoring: t > 0.1,
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Real-time lyric preview snippet
                                _buildLyricPreviewSnippet(
                                  context,
                                  currentTrack,
                                  musicProvider,
                                ),

                                SizedBox(height: gapLyricsToScrubber),

                                // iPhone / BitChord Scrubber Bar with timestamps
                                _buildScrubberBar(
                                  context,
                                  musicProvider,
                                  accentColor: accentColor,
                                ),

                                SizedBox(height: gapScrubberToTransport),

                                // Transport Controls (Previous, Play/Pause, Next)
                                _buildTransportControls(
                                  context,
                                  musicProvider,
                                  isPlaying,
                                  accentColor,
                                ),

                                SizedBox(height: gapTransportToVolume),

                                // iPhone / BitChord Volume Slider
                                _buildVolumeSlider(context, musicProvider),

                                // Accessibility parity semantics
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

                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── LAYER 3: Morphing Hero Artwork ──
                Positioned(
                  left: lerpDouble(0.0, 20.0, t)!,
                  top: lerpDouble(0.0, statusBarHeight + 32.0, t)!,
                  width: lerpDouble(totalW, 46.0, t)!,
                  height: lerpDouble(heroH, 46.0, t)!,
                  child: GestureDetector(
                    key: const ValueKey('now_playing_album_art'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _toggleLyrics();
                    },
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(lerpDouble(0.0, 8.0, t)!),
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) {
                          if (t >= 0.05) {
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
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SizedBox.expand(
                              child: _buildAlbumArtImage(currentTrack),
                            ),
                            // In-place animated motion canvas overlay
                            if (musicProvider.animatedCanvasEnabled && t < 0.5)
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
    String displayText = 'Let it breathe';
    bool isInstrumental = true;

    if (provider.isLoadingLyrics) {
      final idx = track.id.hashCode.abs() % _lyricsIntroPhrases.length;
      displayText = _lyricsIntroPhrases[idx];
      isInstrumental = true;
    } else if (provider.hasSyncedLyrics &&
        provider.currentLyrics != null &&
        provider.currentLyrics!.isNotEmpty) {
      final lyrics = provider.currentLyrics!;
      final posMs = _draggedPositionSec != null
          ? _draggedPositionSec!.toInt()
          : provider.position.inMilliseconds;
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
          final pIdx = track.id.hashCode.abs() % _lyricsIntroPhrases.length;
          displayText = _lyricsIntroPhrases[pIdx];
          isInstrumental = true;
        }
      } else {
        final pIdx = track.id.hashCode.abs() % _lyricsIntroPhrases.length;
        displayText = _lyricsIntroPhrases[pIdx];
        isInstrumental = true;
      }
    } else {
      final idx = track.id.hashCode.abs() % _lyricsIntroPhrases.length;
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
                    key: ValueKey<String>('$isInstrumental:$displayText'),
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
  }

  // ── Scrubber Bar with Timestamps (Image 1) ──────────────────────────────

  Widget _buildScrubberBar(
    BuildContext context,
    MusicProvider provider, {
    Color? accentColor,
  }) {
    final pos = provider.position;
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
              _draggedPositionSec = currentSec;
            });
          },
          onValueChange: (val) {
            setState(() {
              _draggedPositionSec = val * maxSec;
            });
          },
          onValueChangeFinished: () {
            if (_draggedPositionSec != null) {
              provider
                  .seekTo(Duration(milliseconds: _draggedPositionSec!.toInt()));
              setState(() {
                _draggedPositionSec = null;
              });
            }
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
    final double currentVol = provider.volume.clamp(0.0, 1.0);

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
            child: ThinSlider(
              value: currentVol,
              idleHeight: 6.0,
              activeHeight: 11.0,
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.24),
              semanticLabel: 'Volume',
              onValueChange: (val) {
                provider.setVolume(val);
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

  // ── Bottom Mode Selector Tab Bar (Images 1, 2, 4) ───────────────────────

  Widget _buildBottomTabBar(
    BuildContext context,
    MusicProvider musicProvider,
    Color accentColor,
  ) {
    final isLofiActive = musicProvider.isLofiEnabled;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Tab 0: Lyrics (Image 1 & 2)
          _buildTabItem(
            tabIndex: 0,
            semanticLabel: 'Lyrics tab',
            child: AppleLyricsIcon(
              color: _currentTab == 0
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.42),
              size: 23,
            ),
          ),

          // Tab 1: Film / Canvas Video (Image 2)
          _buildTabItem(
            tabIndex: 1,
            semanticLabel: 'Film tab',
            isSelectedOverride:
                _currentTab == 1 || musicProvider.animatedCanvasEnabled,
            child: AppleFilmIcon(
              color: (_currentTab == 1 || musicProvider.animatedCanvasEnabled)
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.42),
              size: 24,
            ),
          ),

          // Tab 2: Wave (Lofi Mode / Visualizer Canvas Toggle) (Image 1 & 2)
          _buildTabItem(
            tabIndex: 2,
            semanticLabel: 'Canvas tab',
            child: Stack(
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
                            color: accentColor.withValues(alpha: 0.8),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Tab 3: Queue (Image 1 & 4)
          _buildTabItem(
            tabIndex: 3,
            semanticLabel: 'Queue tab',
            child: Icon(
              Icons.format_list_bulleted_rounded,
              color: _currentTab == 3
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.42),
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required int tabIndex,
    required String semanticLabel,
    required Widget child,
    bool? isSelectedOverride,
  }) {
    final isSelected = isSelectedOverride ?? (_currentTab == tabIndex);

    return Semantics(
      label: semanticLabel,
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _navigateToTab(tabIndex),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
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

  Widget _buildAlbumArtImage(Track track, {BoxFit fit = BoxFit.cover}) {
    final art = ImageQualityUtils.getHighResArtwork(track.albumArtUrl);
    if (art.isEmpty) return _buildArtPlaceholder();
    if (!art.contains('://')) {
      final f = File(art);
      if (f.existsSync()) return Image.file(f, fit: fit);
    }
    return CachedNetworkImage(
      imageUrl: art,
      fit: fit,
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
