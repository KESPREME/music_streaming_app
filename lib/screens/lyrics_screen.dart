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
import '../widgets/glass_snackbar.dart';
import '../theme/glass_tokens.dart';

/// Real-time Animated Kinetic Lyrics Screen matching Image 2 with Apple Music liquid glass design.
class LyricsScreen extends StatefulWidget {
  final VoidCallback? onMinimize;
  final Function(int)? onTabTap;
  final bool isEmbedded;

  const LyricsScreen({
    super.key,
    this.onMinimize,
    this.onTabTap,
    this.isEmbedded = false,
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
      const Duration(milliseconds: 100),
      (_) => _updateCurrentLine(),
    );
  }

  void _updateCurrentLine() {
    if (!mounted) return;

    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final lyrics = musicProvider.currentLyrics;

    if (lyrics == null || lyrics.isEmpty) return;

    _ensureKeys(lyrics.length);
    final positionMs = musicProvider.position.inMilliseconds;
    final newIndex = LyricsUtils.findCurrentLineIndex(lyrics, positionMs);

    if (newIndex != _currentLineIndex && newIndex >= 0) {
      setState(() {
        _currentLineIndex = newIndex;
      });

      if (_autoScrollEnabled && !_isUserScrolling) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToCurrentLine();
        });
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
          alignment: 0.45,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      } else if (_scrollController.hasClients) {
        final screenHeight = MediaQuery.of(context).size.height;
        final paddingTop = screenHeight * 0.25;
        const double estimatedItemHeight = 85.0;
        final itemTop = paddingTop + (_currentLineIndex * estimatedItemHeight);
        final targetOffset =
            itemTop - (screenHeight * 0.45) + (estimatedItemHeight / 2);

        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 1. Blurred album art background (only when standalone)
          if (!widget.isEmbedded) ...[
            Positioned.fill(
              child: track != null && track.albumArtUrl.isNotEmpty
                  ? RepaintBoundary(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: GlassTokens.playerBackdropBlur,
                          sigmaY: GlassTokens.playerBackdropBlur,
                        ),
                        child: SizedBox.expand(
                          child: _buildAlbumArtImage(track),
                        ),
                      ),
                    )
                  : const ColoredBox(color: Color(0xFF101010)),
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
          ],

          // 2. Lyrics scrolling list
          Positioned.fill(
            child: _buildLyricsBody(context, musicProvider),
          ),

          // 3. Top Header (Pill handle + Mini Track Card)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: widget.isEmbedded
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (track != null)
                        _buildTopMiniTrackHeader(
                          context,
                          track,
                          musicProvider,
                          accentColor,
                        ),
                    ],
                  )
                : SafeArea(
                    bottom: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPullHandle(context),
                        if (track != null)
                          _buildTopMiniTrackHeader(
                            context,
                            track,
                            musicProvider,
                            accentColor,
                          ),
                      ],
                    ),
                  ),
          ),

          // 4. Bottom Mini Player Scrubber (Image 2)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomMiniPlayerScrubber(
              context,
              musicProvider,
              accentColor,
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Row(
        children: [
          // Album art thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 46,
              height: 46,
              child: _buildAlbumArtImage(track),
            ),
          ),
          const SizedBox(width: 12),

          // Title & Artist
          Expanded(
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

          // Translation / Pronunciation button ("aあ")
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
              showGlassSnackBar(context, 'Lyrics translation / phonetics');
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

  Widget _buildLyricsBody(BuildContext context, MusicProvider musicProvider) {
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
    final screenHeight = MediaQuery.of(context).size.height;

    return FadeTransition(
      opacity: _fadeController,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(
          top: screenHeight * 0.18,
          bottom: screenHeight * 0.28,
          left: 24,
          right: 24,
        ),
        physics: const BouncingScrollPhysics(),
        itemCount: lyrics.length,
        itemBuilder: (context, index) {
          return _buildKineticLyricLine(index, lyrics);
        },
      ),
    );
  }

  Widget _buildKineticLyricLine(int index, List<LyricsEntry> lyrics) {
    final entry = lyrics[index];
    final isCurrentLine = index == _currentLineIndex;

    if (entry.text.trim().isEmpty) return const SizedBox(height: 28);

    Key? key;
    if (index < _itemKeys.length) {
      key = _itemKeys[index];
    }

    return GestureDetector(
      key: key,
      onTap: () => _onLineTap(index, lyrics),
      behavior: HitTestBehavior.translucent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 14),
        child: isCurrentLine
            ? Text(
                entry.text,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.35,
                  shadows: [
                    Shadow(
                      color: Colors.white.withValues(alpha: 0.60),
                      blurRadius: 18,
                    ),
                  ],
                ),
              )
            : ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 0.6, sigmaY: 0.6),
                child: Text(
                  entry.text,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.38),
                    height: 1.35,
                  ),
                ),
              ),
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
    final double currentSec =
        pos.inMilliseconds.toDouble().clamp(0.0, maxSec);
    final remaining = dur > pos ? dur - pos : Duration.zero;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
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
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),

          // Scrubber slider
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
                value: currentSec,
                max: maxSec,
                onChanged: (val) {
                  provider.seekTo(Duration(milliseconds: val.toInt()));
                },
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Remaining time (Image 2: "-2:37")
          Text(
            '-${_formatTime(remaining)}',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
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
    final art = track.albumArtUrl;
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
