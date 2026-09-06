import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/track.dart';
import '../services/canvas_resolution_service.dart';
import '../services/innertube/innertube_service.dart';

/// In-place looping animated cover art (canvas video) player matching BitChord
/// and Apple Music motion artwork architecture.
///
/// Mounts silently directly inside the hero artwork slot on the normal player screen,
/// keeping the still album art underneath and crossfading in when the first frame is ready.
class InPlaceCanvasPlayer extends StatefulWidget {
  final Track track;
  final bool isPlaying;
  final BoxFit fit;
  final ValueChanged<bool>? onRenderedChanged;

  const InPlaceCanvasPlayer({
    required this.track,
    required this.isPlaying,
    this.fit = BoxFit.cover,
    this.onRenderedChanged,
    super.key,
  });

  @override
  State<InPlaceCanvasPlayer> createState() => _InPlaceCanvasPlayerState();
}

class _InPlaceCanvasPlayerState extends State<InPlaceCanvasPlayer>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  String? _currentTrackId;
  String? _resolvedUrl;
  bool _isRendered = false;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  bool get _isTesting =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _initForTrack();
  }

  @override
  void didUpdateWidget(covariant InPlaceCanvasPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.track.id != oldWidget.track.id) {
      _initForTrack();
    } else if (widget.isPlaying != oldWidget.isPlaying) {
      if (_controller != null && _controller!.value.isInitialized) {
        if (widget.isPlaying && !_controller!.value.isPlaying) {
          _controller!.play();
        } else if (!widget.isPlaying && _controller!.value.isPlaying) {
          _controller!.pause();
        }
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initForTrack() async {
    final track = widget.track;
    if (_currentTrackId == track.id && _controller != null) return;
    _currentTrackId = track.id;

    _fadeController.reset();
    _isRendered = false;
    widget.onRenderedChanged?.call(false);

    await _controller?.dispose();
    _controller = null;

    if (_isTesting || track.id.isEmpty) return;

    final resolved =
        await CanvasResolutionService.instance.resolveCanvas(track);
    if (!mounted || _currentTrackId != track.id) return;

    if (resolved == null || resolved.isEmpty) return;
    _resolvedUrl = resolved;

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
        if (uri == null) return;
        final ua = InnerTubeService.userAgentForStreamUrl(resolved);
        c = VideoPlayerController.networkUrl(
          uri,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          httpHeaders: ua != null ? {'User-Agent': ua} : const {},
        );
      }

      await c.initialize();
      if (!mounted || _currentTrackId != track.id) {
        await c.dispose();
        return;
      }

      await c.setVolume(0.0);
      await c.setLooping(true);
      if (widget.isPlaying) {
        await c.play();
      }

      _controller = c;
      _isRendered = true;
      widget.onRenderedChanged?.call(true);
      _fadeController.forward();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('InPlaceCanvasPlayer: video initialization failed: $e');
      _isRendered = false;
      widget.onRenderedChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final videoSize = _controller!.value.size;
    if (videoSize.width <= 0 || videoSize.height <= 0) {
      return const SizedBox.shrink();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SizedBox.expand(
        child: FittedBox(
          fit: widget.fit,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: videoSize.width,
            height: videoSize.height,
            child: VideoPlayer(_controller!),
          ),
        ),
      ),
    );
  }
}
