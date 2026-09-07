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
  bool _isInitializing = false;

  final ValueNotifier<VideoPlayerController?> controllerNotifier =
      ValueNotifier<VideoPlayerController?>(null);
  final ValueNotifier<bool> isRenderedNotifier = ValueNotifier<bool>(false);

  VideoPlayerController? get currentController => _controller;
  bool get isRendered => isRenderedNotifier.value;
  bool get hasActiveController =>
      _controller != null && _controller!.value.isInitialized;

  Widget buildVideoPlayer({BoxFit fit = BoxFit.cover}) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();
    return FittedBox(
      fit: fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
      ),
    );
  }

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
      if (_controller!.value.isInitialized) {
        if (!isRenderedNotifier.value) {
          isRenderedNotifier.value = true;
        }
        _syncPlayback(isPlaying);
      }
      return;
    }

    if (_isInitializing && _currentTrackId == track.id) {
      return;
    }

    _isInitializing = true;
    _currentTrackId = track.id;
    _resolvedUrl = null;
    isRenderedNotifier.value = false;

    // Detach previous controller safely
    final oldController = _controller;
    _controller = null;
    controllerNotifier.value = null;
    if (oldController != null) {
      try {
        await oldController.dispose();
      } catch (e) {
        debugPrint('CanvasVideoManager: old controller disposal error: $e');
      }
    }

    if (_isTesting) {
      _isInitializing = false;
      return;
    }

    try {
      final resolved =
          await CanvasResolutionService.instance.resolveCanvas(track);
      if (_currentTrackId != track.id) {
        _isInitializing = false;
        return;
      }

      if (resolved == null || resolved.isEmpty) {
        isRenderedNotifier.value = false;
        _isInitializing = false;
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
        if (uri == null) {
          _isInitializing = false;
          return;
        }
        final ua = InnerTubeService.userAgentForStreamUrl(resolved);
        c = VideoPlayerController.networkUrl(
          uri,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          httpHeaders: ua != null ? {'User-Agent': ua} : const {},
        );
      }

      await c.initialize();
      if (_currentTrackId != track.id) {
        try {
          await c.dispose();
        } catch (_) {}
        _isInitializing = false;
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
    } finally {
      _isInitializing = false;
    }
  }

  /// Synchronizes playback state (play/pause) without re-initializing.
  void setPlaying(bool isPlaying) {
    _syncPlayback(isPlaying);
  }

  void _syncPlayback(bool isPlaying) {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        if (isPlaying && !_controller!.value.isPlaying) {
          _controller!.play();
        } else if (!isPlaying && _controller!.value.isPlaying) {
          _controller!.pause();
        }
      } catch (e) {
        debugPrint('CanvasVideoManager: syncPlayback error: $e');
      }
    }
  }

  /// Pauses the controller without disposing it (e.g. when lyrics view covers screen).
  void pause() {
    try {
      if (_controller != null && _controller!.value.isInitialized && _controller!.value.isPlaying) {
        _controller?.pause();
      }
    } catch (_) {}
  }

  /// Resumes playback of the canvas video (e.g. when returning to normal screen).
  void resume() {
    try {
      if (_controller != null && _controller!.value.isInitialized && !_controller!.value.isPlaying) {
        _controller?.play();
      }
    } catch (_) {}
  }

  /// Detaches and disposes the current controller.
  Future<void> detach() async {
    _isInitializing = false;
    _currentTrackId = null;
    _resolvedUrl = null;
    isRenderedNotifier.value = false;
    final c = _controller;
    _controller = null;
    controllerNotifier.value = null;
    if (c != null) {
      try {
        await c.dispose();
      } catch (e) {
        debugPrint('CanvasVideoManager: detach dispose error: $e');
      }
    }
  }
}
