import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../services/canvas_resolution_service.dart';
import '../utils/color_utils.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/audio_quality_language_sheet.dart';

/// Full-screen or embedded Canvas Video experience matching Muzo's film tab (Image 2).
///
/// Loops the most watchable scene / chorus (~30% offset) seamlessly with hardware acceleration.
class CanvasVideoScreen extends StatefulWidget {
  final VoidCallback? onMinimize;
  final Function(int)? onTabTap;
  final bool isEmbedded;

  const CanvasVideoScreen({
    super.key,
    this.onMinimize,
    this.onTabTap,
    this.isEmbedded = true,
  });

  @override
  State<CanvasVideoScreen> createState() => _CanvasVideoScreenState();
}

class _CanvasVideoScreenState extends State<CanvasVideoScreen> {
  String? _currentTrackId;
  bool _isLoading = true;
  VideoPlayerController? _videoController;
  bool _isSeekingLoop = false;
  Duration _highlightStart = Duration.zero;
  static const Duration _highlightDuration = Duration(seconds: 18);
  Timer? _watchdogTimer;

  bool get _isTesting =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initForTrack());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<MusicProvider>(context);
    final track = provider.currentTrack;
    if (track != null && track.id != _currentTrackId) {
      _currentTrackId = track.id;
      _initForTrack();
    } else if (_videoController != null && _videoController!.value.isInitialized) {
      if (provider.isPlaying && !_videoController!.value.isPlaying) {
        _videoController!.play();
      } else if (!provider.isPlaying && _videoController!.value.isPlaying) {
        _videoController!.pause();
      }
    }
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initForTrack() async {
    final provider = Provider.of<MusicProvider>(context, listen: false);
    final track = provider.currentTrack;
    if (track == null) return;

    if (_isTesting) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    _watchdogTimer?.cancel();
    await _videoController?.dispose();
    _videoController = null;

    final resolved = await CanvasResolutionService.instance.resolveCanvas(track);
    if (!mounted) return;

    if (resolved == null || resolved.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    try {
      final isLocal = resolved.startsWith('/') ||
          resolved.startsWith('file://') ||
          (resolved.length > 2 && resolved[1] == ':');

      final VideoPlayerController c;
      if (isLocal) {
        final filePath = resolved.replaceFirst('file://', '');
        c = VideoPlayerController.file(
          File(filePath),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      } else {
        final uri = Uri.tryParse(resolved);
        if (uri == null) {
          setState(() => _isLoading = false);
          return;
        }
        c = VideoPlayerController.networkUrl(
          uri,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          httpHeaders: const {
            'User-Agent':
                'com.google.ios.youtube/20.51.39 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)',
          },
        );
      }

      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }

      await c.setVolume(0.0); // Muted to not conflict with audio music stream
      await c.setLooping(false); // Managed loop to pin highlight scene

      // Pick main most watchable scene (chorus / peak ~30% into track duration)
      final total = c.value.duration;
      if (total > const Duration(seconds: 32)) {
        final targetMs = (total.inMilliseconds * 0.30).round();
        final clampedMs = targetMs.clamp(
          25000,
          max(25000, total.inMilliseconds - 22000),
        );
        _highlightStart = Duration(milliseconds: clampedMs.toInt());
        await c.seekTo(_highlightStart);
      } else {
        _highlightStart = Duration.zero;
      }

      if (provider.isPlaying) {
        await c.play();
      }

      _videoController = c;
      _watchdogTimer = Timer.periodic(const Duration(milliseconds: 300), (_) => _checkLoop());

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('CanvasVideoScreen init error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _checkLoop() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized || !mounted) return;

    final pos = c.value.position;
    final total = c.value.duration;
    final loopEnd = total > const Duration(seconds: 32)
        ? _highlightStart + _highlightDuration
        : total;

    final isAtEnd = (total > const Duration(seconds: 32) && pos >= loopEnd) ||
        pos >= total ||
        (total - pos) <= const Duration(milliseconds: 250);

    if (isAtEnd && !_isSeekingLoop) {
      _isSeekingLoop = true;
      c.seekTo(_highlightStart).then((_) {
        _isSeekingLoop = false;
        if (!mounted) return;
        final provider = Provider.of<MusicProvider>(context, listen: false);
        if (provider.isPlaying && !c.value.isPlaying) {
          c.play();
        }
      }).catchError((_) {
        _isSeekingLoop = false;
      });
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
      body: Column(
        children: [
          // 1. Top Mini Track Header (Unified, zero frosted cutoffs)
          if (track != null)
            _buildTopMiniTrackHeader(context, track, musicProvider, accentColor),

          // 2. Main Canvas Video Viewport
          Expanded(
            child: _buildCanvasBody(context, track, accentColor),
          ),

          // 3. Bottom Mini Player Scrubber (Unified on ambient background)
          _buildBottomMiniPlayerScrubber(context, musicProvider, accentColor),
        ],
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
          // Album art thumbnail (tapping returns to normal album view)
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onTabTap?.call(1);
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
                widget.onTabTap?.call(1);
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

          // Options button (vertical 3 dots)
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

  Widget _buildCanvasBody(
    BuildContext context,
    Track? track,
    Color accentColor,
  ) {
    if (track == null) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    final cardW = size.width - 48;
    final cardH = size.height * 0.54;

    final hasActiveVideo = _videoController != null &&
        _videoController!.value.isInitialized &&
        !_isLoading;

    return Center(
      child: Container(
        width: cardW,
        height: cardH,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.50),
              blurRadius: 32,
              spreadRadius: -4,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Fallback base: high-res album artwork
              _buildAlbumArtImage(track),

              // 2. Video Canvas player (loops watchable scene seamlessly)
              if (hasActiveVideo)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController!.value.size.width > 0
                        ? _videoController!.value.size.width
                        : cardW,
                    height: _videoController!.value.size.height > 0
                        ? _videoController!.value.size.height
                        : cardH,
                    child: VideoPlayer(_videoController!),
                  ),
                ),

              // 3. Subtle glass vignette border
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.20),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                    ],
                  ),
                ),
              ),

              // 4. Loading indicator or Canvas badge
              Positioned(
                bottom: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasActiveVideo ? Icons.movie_filter_rounded : Icons.lens_blur_rounded,
                        color: hasActiveVideo ? accentColor : Colors.white60,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        hasActiveVideo ? 'Canvas' : (_isLoading ? 'Loading...' : 'Visualizer'),
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
          // Play / Pause compact white circle button
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

          // Elapsed time
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

          // Remaining time
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
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }

  Widget _buildCircleButtonWidget({
    required String semanticLabel,
    required Widget child,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  Widget _buildAlbumArtImage(Track track) {
    if (track.albumArtUrl.isEmpty) {
      return Container(
        color: const Color(0xFF16161A),
        child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 40),
      );
    }
    return CachedNetworkImage(
      imageUrl: ImageQualityUtils.getHighResArtwork(track.albumArtUrl),
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: const Color(0xFF16161A),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white30),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: const Color(0xFF16161A),
        child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 40),
      ),
    );
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
