// lib/screens/lyrics_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/music_provider.dart';
import '../models/track.dart';
import '../models/lyrics_entry.dart';
import '../utils/lyrics_utils.dart';
import '../utils/color_utils.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/audio_quality_language_sheet.dart';
import '../widgets/thin_slider.dart';
import '../utils/image_quality_utils.dart';

/// Real-time Animated Kinetic Lyrics Screen matching Image 2 with Apple Music liquid glass design.
class LyricsScreen extends StatefulWidget {
  final VoidCallback? onMinimize;
  final Function(int)? onTabTap;
  final VoidCallback? onReturnToAlbum;
  final bool isEmbedded;
  final bool showHeader;
  final bool showBottomScrubber;

  const LyricsScreen({
    super.key,
    this.onMinimize,
    this.onTabTap,
    this.onReturnToAlbum,
    this.isEmbedded = false,
    this.showHeader = true,
    this.showBottomScrubber = true,
  });

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

  int _currentLineIndex = 0;
  bool _isUserScrolling = false;
  bool _autoScrollEnabled = true;
  Timer? _scrollResumeTimer;
  Timer? _positionUpdateTimer;
  String? _currentTrackId;

  late AnimationController _fadeController;
  final List<GlobalKey> _itemKeys = [];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLyrics();
      _startPositionUpdates();
      _fadeController.forward();
    });

    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<MusicProvider>(context, listen: false);
    final track = provider.currentTrack;

    if (track != null && _currentTrackId != track.id) {
      final wasNull = _currentTrackId == null;
      _currentTrackId = track.id;
      _currentLineIndex = 0;
      _itemKeys.clear();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          provider.fetchLyrics(forceRefresh: !wasNull);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollResumeTimer?.cancel();
    _positionUpdateTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _checkLyrics() {
    final provider = Provider.of<MusicProvider>(context, listen: false);
    if (provider.currentTrack != null) {
      _currentTrackId = provider.currentTrack!.id;
      if (!provider.hasSyncedLyrics || provider.currentLyrics == null) {
        provider.fetchLyrics();
      } else {
        _ensureKeys(provider.currentLyrics!.length);
      }
    }
  }

  void _ensureKeys(int count) {
    if (_itemKeys.length != count) {
      _itemKeys.clear();
      for (var i = 0; i < count; i++) {
        _itemKeys.add(GlobalKey());
      }
    }
  }

  void _onScroll() {
    if (!_isUserScrolling &&
        _scrollController.position.isScrollingNotifier.value) {
      if (mounted) {
        setState(() {
          _isUserScrolling = true;
          _autoScrollEnabled = false;
        });
      }
    }

    if (_isUserScrolling) {
      _scrollResumeTimer?.cancel();
      _scrollResumeTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) {
          setState(() {
            _isUserScrolling = false;
            _autoScrollEnabled = true;
            if (_autoScrollEnabled) _scrollToCurrentLine();
          });
        }
      });
    }
  }

  void _startPositionUpdates() {
    _positionUpdateTimer = Timer.periodic(
      const Duration(milliseconds: 16), // 60 FPS fluid kinetic motion
      (_) => _updateLyricsProgress(),
    );
  }

  void _updateLyricsProgress() {
    if (!mounted) return;

    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final lyrics = musicProvider.currentLyrics;

    if (lyrics == null || lyrics.isEmpty) return;

    final positionMs = musicProvider.position.inMilliseconds;
    final newIndex = LyricsUtils.findCurrentLineIndex(lyrics, positionMs);

    if (newIndex != _currentLineIndex && newIndex >= 0) {
      _ensureKeys(lyrics.length);
      setState(() {
        _currentLineIndex = newIndex;
      });

      if (_autoScrollEnabled && !_isUserScrolling) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToCurrentLine();
        });
      }
    } else if (musicProvider.isPlaying) {
      final isNearCountdown = _currentLineIndex == 0 &&
          positionMs < lyrics[0].timeMs &&
          (lyrics[0].timeMs - positionMs) <= 4500;
      if (isNearCountdown) {
        setState(() {});
      }
    }
  }

  void _onLineTap(int index, List<LyricsEntry> lyrics) {
    if (index < 0 || index >= lyrics.length) return;

    final entry = lyrics[index];
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    HapticFeedback.lightImpact();
    musicProvider.seekTo(Duration(milliseconds: entry.timeMs));

    setState(() {
      _currentLineIndex = index;
      _autoScrollEnabled = true;
      _isUserScrolling = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentLine());
  }

  void _scrollToCurrentLine() {
    if (_currentLineIndex >= 0 && _currentLineIndex < _itemKeys.length) {
      final key = _itemKeys[_currentLineIndex];
      final keyContext = key.currentContext;

      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.32,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
        );
      } else if (_scrollController.hasClients) {
        final screenHeight = MediaQuery.of(context).size.height;
        final paddingTop = screenHeight * 0.22;
        const double estimatedItemHeight = 78.0;
        final itemTop = paddingTop + (_currentLineIndex * estimatedItemHeight);
        final targetOffset =
            itemTop - (screenHeight * 0.32) + (estimatedItemHeight / 2);

        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final track = musicProvider.currentTrack;
    final palette = musicProvider.paletteGenerator;
    final accentColor = ColorUtils.getVibrantAccent(
      palette,
      const Color(0xFFE89838),
    );

    final Widget mainContent = Column(
      children: [
        if (track != null && widget.showHeader)
          _buildTopMiniTrackHeader(
            context,
            track,
            musicProvider,
            accentColor,
          )
        else if (widget.isEmbedded)
          SizedBox(height: MediaQuery.of(context).padding.top + 90.0),
        Expanded(
          child: _buildLyricsBody(context, musicProvider, accentColor),
        ),
        if (widget.showBottomScrubber)
          _buildBottomMiniPlayerScrubber(
            context,
            musicProvider,
            accentColor,
          ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: widget.isEmbedded
          ? mainContent
          : Stack(
              children: [
                // 1. Blurred album art background (only when standalone)
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFF08080A)),
                ),
                if (track != null && track.albumArtUrl.isNotEmpty)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: ClipRect(
                        child: Transform.scale(
                          scale: 1.25,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: 65,
                              sigmaY: 65,
                            ),
                            child: SizedBox.expand(
                              child: _buildAlbumArtImage(track),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.black.withValues(alpha: 0.65),
                          Colors.black.withValues(alpha: 0.85),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _buildPullHandle(context),
                      Expanded(child: mainContent),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPullHandle(BuildContext context) {
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

  Widget _buildTopMiniTrackHeader(
    BuildContext context,
    Track track,
    MusicProvider provider,
    Color accentColor,
  ) {
    final isLiked = provider.isSongLiked(track.id);
    final topPadding = widget.isEmbedded
        ? (MediaQuery.of(context).padding.top + 32.0)
        : 6.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, 8),
      child: Row(
        children: [
          // Album art thumbnail (tapping returns to normal album view)
          GestureDetector(
            key: const ValueKey('now_playing_album_art'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              if (widget.onReturnToAlbum != null) {
                widget.onReturnToAlbum!();
              } else if (widget.onTabTap != null) {
                widget.onTabTap!(0);
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 46,
                height: 46,
                child: _buildAlbumArtImage(track),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Title & Artist (tapping returns to normal album view)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                if (widget.onReturnToAlbum != null) {
                  widget.onReturnToAlbum!();
                } else if (widget.onTabTap != null) {
                  widget.onTabTap!(0);
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.trackName,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artistName,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // Star button (Favorite)
          _buildCircleButton(
            icon: isLiked ? Icons.star_rounded : Icons.star_outline_rounded,
            iconColor: isLiked ? accentColor : Colors.white,
            semanticLabel: 'Favorite',
            onTap: () {
              HapticFeedback.lightImpact();
              provider.toggleLike(track);
            },
          ),

          const SizedBox(width: 8),

          // Translation / Audio Quality button ("aあ")
          _buildCircleButtonWidget(
            semanticLabel: 'Pronunciation',
            child: Text(
              'aあ',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              AudioQualityLanguageSheet.show(context);
            },
          ),

          const SizedBox(width: 8),

          // Options button (vertical 3 dots matching Image 2)
          _buildCircleButton(
            icon: Icons.more_vert_rounded,
            iconColor: Colors.white,
            semanticLabel: 'Options',
            onTap: () {
              HapticFeedback.lightImpact();
              GlassOptionsSheet.show(context, track: track);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsBody(
    BuildContext context,
    MusicProvider musicProvider,
    Color accentColor,
  ) {
    if (musicProvider.isLoadingLyrics) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              'Loading lyrics...',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white60,
                fontSize: 15,
              ),
            ),
          ],
        ),
      );
    }

    final lyrics = musicProvider.currentLyrics;
    if (lyrics == null || lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 56,
              color: Colors.white.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              'Lyrics not available',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    _ensureKeys(lyrics.length);

    return FadeTransition(
      opacity: _fadeController,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (Rect bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0.0, 0.05, 0.95, 1.0],
          ).createShader(bounds);
        },
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 16,
          ),
          physics: const BouncingScrollPhysics(),
          itemCount: lyrics.length,
          itemBuilder: (context, index) {
            return _buildKineticLyricLine(
              index,
              lyrics,
              accentColor,
              musicProvider,
            );
          },
        ),
      ),
    );
  }

  Widget _buildCountdownDots(int remainingMs, Color accentColor) {
    // 3-dot vocal countdown indicator matching 00:03 in reference video
    final int activeDot = remainingMs <= 1100 ? 2 : (remainingMs <= 2200 ? 1 : 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final isLit = i <= activeDot;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: isLit ? 10 : 8,
            height: isLit ? 10 : 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLit ? Colors.white : Colors.white.withValues(alpha: 0.28),
              boxShadow: isLit
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.35),
                        blurRadius: 6,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildKineticLyricLine(
    int index,
    List<LyricsEntry> lyrics,
    Color accentColor,
    MusicProvider musicProvider,
  ) {
    final entry = lyrics[index];
    if (entry.text.trim().isEmpty) return const SizedBox(height: 28);

    final int delta = index - _currentLineIndex;
    final bool isCurrentLine = delta == 0;
    final bool isPastLine = delta < 0;
    final double dist = delta.abs().toDouble();
    final int currentPosMs = musicProvider.position.inMilliseconds;

    // ── 3D Barrel Cylinder Target Geometry ──
    final double targetAngle;
    if (isCurrentLine) {
      targetAngle = 0.0;
    } else if (isPastLine) {
      targetAngle = (0.085 * dist).clamp(0.0, 0.32);
    } else {
      targetAngle = -(0.075 * dist).clamp(-0.28, 0.0);
    }

    // ── Target Scale ──
    final double targetScale;
    if (isCurrentLine) {
      targetScale = 1.0;
    } else if (isPastLine) {
      targetScale = (1.0 - dist * 0.055).clamp(0.80, 1.0);
    } else {
      targetScale = (1.0 - dist * 0.045).clamp(0.82, 1.0);
    }

    // ── Target Opacity (clean, crisp, no glow) ──
    final double targetOpacity;
    if (isCurrentLine) {
      targetOpacity = 1.0;
    } else if (isPastLine) {
      targetOpacity = (dist <= 1 ? 0.55 : (0.42 - (dist - 1) * 0.09).clamp(0.12, 0.42));
    } else {
      targetOpacity = (dist <= 1 ? 0.50 : (0.38 - (dist - 1) * 0.08).clamp(0.10, 0.38));
    }

    // ── Target Progressive Blur (0 blur on ±1 for crisp reading) ──
    final double targetBlur;
    if (isCurrentLine || dist <= 1) {
      targetBlur = 0.0;
    } else if (dist <= 2) {
      targetBlur = 1.2;
    } else {
      targetBlur = (1.2 + (dist - 2) * 1.5).clamp(0.0, 5.0);
    }

    final targetState = _LineVisualState(
      angle: targetAngle,
      scale: targetScale,
      opacity: targetOpacity,
      blur: targetBlur,
    );

    Key? key;
    if (index < _itemKeys.length) {
      key = _itemKeys[index];
    }

    final int firstVocalIdx =
        lyrics.indexWhere((e) => e.text.trim().isNotEmpty && !e.isMusicalBreak);
    final bool isFirstSungLine = index == firstVocalIdx;
    final bool showCountdown = isFirstSungLine &&
        currentPosMs < entry.timeMs &&
        (entry.timeMs - currentPosMs) <= 4500 &&
        (entry.timeMs - currentPosMs) >= 200;

    return GestureDetector(
      key: key,
      onTap: () => _onLineTap(index, lyrics),
      behavior: HitTestBehavior.translucent,
      child: TweenAnimationBuilder<_LineVisualState>(
        tween: _LineVisualStateTween(end: targetState),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
        builder: (context, state, child) {
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateX(state.angle);

          // Clean, crisp Apple typography — NO shadows, NO glow
          final textWidget = Text(
            entry.text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: isCurrentLine ? FontWeight.w800 : FontWeight.w700,
              color: Colors.white.withValues(alpha: state.opacity),
              height: 1.35,
            ),
          );

          final blurred = state.blur > 0.1
              ? ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: state.blur,
                    sigmaY: state.blur,
                  ),
                  child: textWidget,
                )
              : textWidget;

          Widget completeContent = blurred;
          if (showCountdown) {
            completeContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCountdownDots(entry.timeMs - currentPosMs, accentColor),
                blurred,
              ],
            );
          }

          return Transform(
            transform: transform,
            alignment: Alignment.centerLeft,
            child: Transform.scale(
              scale: state.scale,
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 18.0),
                child: completeContent,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomMiniPlayerScrubber(
    BuildContext context,
    MusicProvider provider,
    Color accentColor,
  ) {
    final isPlaying = provider.isPlaying;
    final pos = provider.position;
    final dur = provider.duration;
    final double maxSec =
        dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
    final double fraction =
        (pos.inMilliseconds.toDouble() / maxSec).clamp(0.0, 1.0);
    final remaining = dur > pos ? dur - pos : Duration.zero;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Scrubber Row: Play Button + Elapsed + ThinSlider + Remaining
          Row(
            children: [
              // Play / Pause compact white circle button (Image 2)
              Semantics(
                label: isPlaying ? 'Pause' : 'Play',
                button: true,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (isPlaying) {
                      provider.pauseTrack();
                    } else {
                      provider.resumeTrack();
                    }
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Elapsed time (Image 2: "0:22")
              Text(
                _formatTime(pos),
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withValues(alpha: 0.70),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),

              // iPhone / BitChord style ThinSlider scrubber
              Expanded(
                child: ThinSlider(
                  value: fraction,
                  idleHeight: 7.0,
                  activeHeight: 12.0,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white.withValues(alpha: 0.24),
                  onValueChange: (val) {
                    provider.seekTo(Duration(milliseconds: (val * maxSec).toInt()));
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Remaining time (Image 2: "-2:37")
              Text(
                '-${_formatTime(remaining)}',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withValues(alpha: 0.70),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 2. Volume Slider Row (iPhone style ThinSlider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              children: [
                Icon(
                  Icons.volume_down_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.50),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ThinSlider(
                    value: provider.volume.clamp(0.0, 1.0),
                    idleHeight: 6.0,
                    activeHeight: 10.0,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white.withValues(alpha: 0.24),
                    onValueChange: (val) {
                      provider.setVolume(val);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.volume_up_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.50),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
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
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }

  Widget _buildCircleButtonWidget({
    required Widget child,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildAlbumArtImage(Track track) {
    final rawArt = track.albumArtUrl;
    if (rawArt.isEmpty) return _buildArtPlaceholder();
    final art = ImageQualityUtils.getHighResArtwork(rawArt);
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
        child: Icon(Icons.music_note, color: Colors.white30, size: 24),
      ),
    );
  }

  String _formatTime(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Composite visual state for a lyric line in the 3D barrel cylinder.
class _LineVisualState {
  final double angle;
  final double scale;
  final double opacity;
  final double blur;

  const _LineVisualState({
    required this.angle,
    required this.scale,
    required this.opacity,
    required this.blur,
  });

  static _LineVisualState lerp(_LineVisualState a, _LineVisualState b, double t) {
    return _LineVisualState(
      angle: lerpDouble(a.angle, b.angle, t) ?? b.angle,
      scale: lerpDouble(a.scale, b.scale, t) ?? b.scale,
      opacity: lerpDouble(a.opacity, b.opacity, t) ?? b.opacity,
      blur: lerpDouble(a.blur, b.blur, t) ?? b.blur,
    );
  }
}

/// Tween for buttery-smooth watery interpolation between line visual states.
class _LineVisualStateTween extends Tween<_LineVisualState> {
  _LineVisualStateTween({super.begin, super.end});

  @override
  _LineVisualState lerp(double t) {
    if (begin == null) return end!;
    return _LineVisualState.lerp(begin!, end!, t);
  }
}
