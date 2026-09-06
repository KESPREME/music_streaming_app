import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../models/track.dart';
import 'canvas_resolution_service.dart';
import 'innertube/innertube_service.dart';

/// Central singleton manager for looping silent video canvas playback.
///
/// Shares a single hardware-accelerated [VideoPlayerController] across both
/// the full-screen blurred background backdrop and the hero motion canvas banner,
/// matching BitChord's [CanvasArtworkPlayer] and [ArtworkMeshBackdrop] architecture.
class CanvasVideoManager {
  CanvasVideoManager._();
  static final CanvasVideoManager instance = CanvasVideoManager._();

  VideoPlayerController? _controller;
  String? _currentTrackId;
  String? _resolvedUrl;
  bool _disposed = false;

  final ValueNotifier<VideoPlayerController?> controllerNotifier =
      ValueNotifier<VideoPlayerController?>(null);
  final ValueNotifier<bool> isRenderedNotifier = ValueNotifier<bool>(false);

  VideoPlayerController? get currentController => _controller;
  bool get isRendered => isRenderedNotifier.value;

  bool get _isTesting =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  /// Attaches a track to the canvas video pipeline.
  /// If the track already matches and is initialized, synchronizes playback state.
  Future<void> attachTrack(Track track, {required bool isPlaying}) async {
    if (track.id.isEmpty) {
      await detach();
      return;
    }

    if (_currentTrackId == track.id && _controller != null) {
      _syncPlayback(isPlaying);
      return;
    }

    _currentTrackId = track.id;
    _resolvedUrl = null;
    isRenderedNotifier.value = false;

    // Detach previous controller
    final oldController = _controller;
    _controller = null;
    controllerNotifier.value = null;
    await oldController?.dispose();

    if (_isTesting) return;

    try {
      final resolved =
          await CanvasResolutionService.instance.resolveCanvas(track);
      if (_currentTrackId != track.id) return;

      if (resolved == null || resolved.isEmpty) {
        isRenderedNotifier.value = false;
        return;
      }
      _resolvedUrl = resolved;

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
      if (_currentTrackId != track.id) {
        await c.dispose();
        return;
      }

      await c.setVolume(0.0);
      await c.setLooping(true);

      if (isPlaying) {
        await c.play();
      }

      _controller = c;
      controllerNotifier.value = c;
      isRenderedNotifier.value = true;
    } catch (e) {
      debugPrint('CanvasVideoManager: video initialization failed: $e');
      isRenderedNotifier.value = false;
      controllerNotifier.value = null;
    }
  }

  /// Synchronizes playback state (play/pause) without re-initializing.
  void setPlaying(bool isPlaying) {
    _syncPlayback(isPlaying);
  }

  void _syncPlayback(bool isPlaying) {
    if (_controller != null && _controller!.value.isInitialized) {
      if (isPlaying && !_controller!.value.isPlaying) {
        _controller!.play();
      } else if (!isPlaying && _controller!.value.isPlaying) {
        _controller!.pause();
      }
    }
  }

  /// Pauses the controller without disposing it.
  void pause() {
    _controller?.pause();
  }

  /// Detaches and disposes the current controller.
  Future<void> detach() async {
    _currentTrackId = null;
    _resolvedUrl = null;
    isRenderedNotifier.value = false;
    final c = _controller;
    _controller = null;
    controllerNotifier.value = null;
    await c?.dispose();
  }
}
