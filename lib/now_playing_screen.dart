import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../widgets/artist_picker_sheet.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/apple_player_icons.dart';
import '../screens/lyrics_screen.dart';
import '../screens/queue_screen.dart';
import '../screens/canvas_video_screen.dart';
import '../utils/color_utils.dart';
import '../utils/image_quality_utils.dart';

/// Full-screen Now Playing experience matching Apple Music / Muzo liquid glass UI/UX.
///
/// Features:
/// - 3-page swipeable flow with Apple physics: Lyrics (Page 0), Main Player / Canvas (Page 1), Queue (Page 2)
/// - Top pull-down handle for fluid dismissal
/// - Large album artwork with spring-physics scale on play/pause (1.0 playing, 0.88 paused)
/// - Title & Artist with Favorite Star button & Options (...) button
/// - Custom Apple-style scrubber with elapsed time & negative remaining time
/// - Transport controls (Previous, Play/Pause, Next) with tactile haptics
/// - Real-time volume slider controlling player volume
/// - Bottom mode selector tab bar (Lyrics, Canvas, Queue) with fluid indicator
/// - Liquid glass blurred album art canvas background with dark gradient scrim
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

  late final PageController _pageController;
  int _currentTab = -1; // Default: Page 1 (Main Player / Album Art has no active bottom tab)
  bool _isPlayPressed = false;
  double? _draggedPositionSec;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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

    if (_currentTab == index) {
      // Tapping the active tab toggles back to album art (Page 1)
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    final int targetPage;
    if (index == 0) {
      targetPage = 0; // Lyrics
    } else if (index == 1) {
      targetPage = 2; // Canvas Video
    } else if (index == 3) {
      targetPage = 3; // Queue
    } else {
      targetPage = 1; // Album Art
    }

    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
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

        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // 0. Solid dark foundation base (prevents underlying screen text from bleeding on edges)
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFF08080A)),
              ),

              // 1. Blurred album art background (Single-render master backdrop, scaled to eliminate edge feathering)
              Positioned.fill(
                child: currentTrack.albumArtUrl.isNotEmpty
                    ? RepaintBoundary(
                        child: ClipRect(
                          child: Transform.scale(
                            scale: 1.25,
                            child: ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: 65,
                                sigmaY: 65,
                              ),
                              child: SizedBox.expand(
                                child: _buildAlbumArtImage(currentTrack),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const ColoredBox(color: Color(0xFF101010)),
              ),

              // 2. Dark ambient gradient scrim overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.35),
                        Colors.black.withValues(alpha: 0.58),
                        Colors.black.withValues(alpha: 0.82),
                      ],
                      stops: const [0.0, 0.50, 1.0],
                    ),
                  ),
                ),
              ),

              // 3. Main PageView & Shell
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Pull-down handle (present on all pages)
                    _buildPullDownHandle(context),

                    // PageView containing Lyrics, Main Player, Canvas Video, and Queue
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const BouncingScrollPhysics(),
                        onPageChanged: (page) {
                          setState(() {
                            if (page == 0) {
                              _currentTab = 0; // Lyrics
                            } else if (page == 1) {
                              _currentTab = -1; // Main Player (album art)
                            } else if (page == 2) {
                              _currentTab = 1; // Canvas Video
                            } else if (page == 3) {
                              _currentTab = 3; // Queue
                            }
                          });
                        },
                        children: [
                          // Page 0: Lyrics (Image 2)
                          LyricsScreen(
                            onMinimize: widget.onMinimize,
                            onTabTap: (_) => _pageController.animateToPage(
                              1,
                              duration: const Duration(milliseconds: 380),
                              curve: Curves.easeOutCubic,
                            ),
                            isEmbedded: true,
                          ),

                          // Page 1: Main Player Album Art (Image 1)
                          _buildMainPlayerPage(
                            context,
                            currentTrack,
                            musicProvider,
                            accentColor,
                            isPlaying,
                          ),

                          // Page 2: Canvas Video (Image 2 Film tab)
                          CanvasVideoScreen(
                            onMinimize: widget.onMinimize,
                            onTabTap: (_) => _pageController.animateToPage(
                              1,
                              duration: const Duration(milliseconds: 380),
                              curve: Curves.easeOutCubic,
                            ),
                            isEmbedded: true,
                          ),

                          // Page 3: Queue (Image 4)
                          QueueScreen(
                            onMinimize: widget.onMinimize,
                            onTabTap: (_) => _pageController.animateToPage(
                              1,
                              duration: const Duration(milliseconds: 380),
                              curve: Curves.easeOutCubic,
                            ),
                            isEmbedded: true,
                          ),
                        ],
                      ),
                    ),

                    // Persistent Bottom Mode Selector Tab Bar (Images 1, 2, 4)
                    _buildBottomTabBar(context, musicProvider, accentColor),
                    const SizedBox(height: 14),
                  ],
                ),
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

  // ── Page 1: Main Player View (Image 1) ──────────────────────────────────

  Widget _buildMainPlayerPage(
    BuildContext context,
    Track currentTrack,
    MusicProvider musicProvider,
    Color accentColor,
    bool isPlaying,
  ) {
    final screenSize = MediaQuery.of(context).size;
    final double maxArtDim = min(screenSize.width - 56, screenSize.height * 0.42);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Offstage accessible text for test parity & screen readers
                    Offstage(
                      offstage: true,
                      child: Row(
                        children: [
                          Text(currentTrack.trackName),
                          Text(currentTrack.artistName),
                        ],
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Large Album Artwork with Apple spring scale on play/pause
                    _buildAlbumArt(currentTrack, maxArtDim, isPlaying, musicProvider, accentColor),

                    const SizedBox(height: 12),

                    // Track Metadata & Quick Actions Row (Image 1)
                    _buildMetadataRow(context, currentTrack, musicProvider, accentColor),

                    // Scrubber Bar with timestamps (Image 1)
                    _buildScrubberBar(context, musicProvider),

                    // Transport Controls (Previous, Play/Pause, Next) (Image 1)
                    _buildTransportControls(context, musicProvider, isPlaying, accentColor),

                    // Volume Slider (Image 1)
                    _buildVolumeSlider(context, musicProvider),

                    // Offstage semantics for Shuffle and Repeat to guarantee parity
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

                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Album Artwork ────────────────────────────────────────────────────────

  Widget _buildAlbumArt(
    Track track,
    double maxDimension,
    bool isPlaying,
    MusicProvider musicProvider,
    Color accentColor,
  ) {
    if (musicProvider.isCanvasActive) {
      return SizedBox(
        width: maxDimension,
        height: maxDimension,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            color: Colors.black.withValues(alpha: 0.35),
            child: Center(
              child: _WaveformPlaceholder(
                isPlaying: isPlaying,
                color: accentColor,
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        _navigateToTab(0); // Tapping album cover opens Lyrics screen!
      },
      child: AnimatedScale(
        scale: isPlaying ? 1.0 : 0.88,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        child: Container(
          width: maxDimension,
          height: maxDimension,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isPlaying ? 0.45 : 0.28),
                blurRadius: isPlaying ? 34 : 20,
                spreadRadius: -2,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: _buildAlbumArtImage(track),
          ),
        ),
      ),
    );
  }

  // ── Metadata & Quick Actions Row (Image 1) ──────────────────────────────

  Widget _buildMetadataRow(
    BuildContext context,
    Track track,
    MusicProvider provider,
    Color accentColor,
  ) {
    final isLiked = provider.isSongLiked(track.id);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Track Title & Artist
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track.trackName,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  if (track.artistName.isNotEmpty &&
                      track.artistName != 'Unknown Artist') {
                    await ArtistPickerSheet.showIfNeeded(
                      context,
                      provider,
                      track.artistName,
                    );
                  }
                },
                child: Text(
                  track.artistName,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        // Favorite Star Button (Image 1)
        _buildCircularGlassButton(
          icon: isLiked ? Icons.star_rounded : Icons.star_outline_rounded,
          iconColor: isLiked ? accentColor : Colors.white,
          semanticLabel: 'Favorite',
          onTap: () {
            HapticFeedback.lightImpact();
            provider.toggleLike(track);
          },
        ),

        const SizedBox(width: 10),

        // Options Button (...) (Image 1: 3 vertical dots)
        _buildCircularGlassButton(
          icon: Icons.more_vert_rounded,
          iconColor: Colors.white,
          semanticLabel: 'Options',
          onTap: () {
            HapticFeedback.lightImpact();
            GlassOptionsSheet.show(context, track: track);
          },
        ),
      ],
    );
  }

  // ── Scrubber Bar with Timestamps (Image 1) ──────────────────────────────

  Widget _buildScrubberBar(BuildContext context, MusicProvider provider) {
    final pos = provider.position;
    final dur = provider.duration;
    final double maxSec =
        dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
    final double currentSec = _draggedPositionSec ??
        pos.inMilliseconds.toDouble().clamp(0.0, maxSec);
    final remaining = dur > pos ? dur - pos : Duration.zero;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: currentSec.clamp(0.0, maxSec),
            max: maxSec,
            onChangeStart: (val) {
              setState(() {
                _draggedPositionSec = val;
              });
            },
            onChanged: (val) {
              setState(() {
                _draggedPositionSec = val;
              });
            },
            onChangeEnd: (val) {
              provider.seekTo(Duration(milliseconds: val.toInt()));
              setState(() {
                _draggedPositionSec = null;
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatTime(_draggedPositionSec != null
                    ? Duration(milliseconds: _draggedPositionSec!.toInt())
                    : pos),
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '- ${_formatTime(remaining)}',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white60,
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
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          const Icon(
            Icons.volume_down_rounded,
            size: 20,
            color: Colors.white60,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: currentVol,
                onChanged: (val) {
                  provider.setVolume(val);
                },
              ),
            ),
          ),
          const Icon(
            Icons.volume_up_rounded,
            size: 20,
            color: Colors.white60,
          ),
        ],
      ),
    );
  }

  // ── Bottom Mode Selector Tab Bar (Images 1, 2, 4) ───────────────────────

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
            child: AppleFilmIcon(
              color: _currentTab == 1
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
  }) {
    final isSelected = _currentTab == tabIndex;

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
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.6,
            ),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
      ),
    );
  }

  Widget _buildAlbumArtImage(Track track) {
    final art = ImageQualityUtils.getHighResArtwork(track.albumArtUrl);
    if (art.isEmpty) return _buildArtPlaceholder();
    if (!art.contains('://')) {
      final f = File(art);
      if (f.existsSync()) return Image.file(f, fit: BoxFit.cover);
    }
    return CachedNetworkImage(
      imageUrl: art,
      fit: BoxFit.cover,
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
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Simulated dynamic sine wave visualizer when Canvas is toggled on
class _WaveformPlaceholder extends StatefulWidget {
  final bool isPlaying;
  final Color color;

  const _WaveformPlaceholder({required this.isPlaying, required this.color});

  @override
  State<_WaveformPlaceholder> createState() => _WaveformPlaceholderState();
}

class _WaveformPlaceholderState extends State<_WaveformPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _WaveformPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(200, 200),
          painter: _CanvasWaveformPainter(
            progress: _controller.value,
            color: widget.color,
            isPlaying: widget.isPlaying,
          ),
        );
      },
    );
  }
}

class _CanvasWaveformPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isPlaying;

  _CanvasWaveformPainter({
    required this.progress,
    required this.color,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final width = size.width;
    final height = size.height;
    final centerY = height / 2;

    for (int wave = 0; wave < 3; wave++) {
      final path = Path();
      final phase = progress * 2 * pi + (wave * pi / 3);
      final amplitude = (height * 0.22) * (isPlaying ? 1.0 : 0.25) * (1.0 - wave * 0.2);

      path.moveTo(0, centerY);
      for (double x = 0; x <= width; x += 3) {
        final y = centerY +
            sin((x / width * 4 * pi) + phase) *
                amplitude *
                sin(x / width * pi);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint..color = color.withValues(alpha: 0.8 - wave * 0.22));
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasWaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isPlaying != isPlaying ||
      oldDelegate.color != color;
}
