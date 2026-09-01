import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:just_audio/just_audio.dart' show ProcessingState;

import '../../models/track.dart';
import '../../services/audio_service.dart';
import 'playback_state.dart';

/// Minimal shape of MusicProvider the projection needs — keeps the
/// controller decoupled from the God object (and test-friendly).
abstract class MusicProviderLike {
  Track? get currentTrack;
  List<Track> get queue;
  List<Track>? get currentPlayingTracks;
  int get currentIndex;
  String? get currentPlaylistId;
  bool get shuffleEnabled;
  RepeatMode get repeatMode;
  double get playbackSpeed;
}

/// Single read-projection over [AudioService] streams.
///
/// MusicProvider keeps owning playback decisions (what plays, queue
/// semantics); this controller only projects its state into an immutable
/// [PlaybackState] so glass surfaces subscribe to one object.
class PlaybackController extends ChangeNotifier {
  PlaybackController(this._audioService) {
    _subs.add(_audioService.onPositionChanged.listen((p) {
      if (_state.position != p) {
        _state = _state.copyWith(position: p);
        _notifyThrottled();
      }
    }));
    _subs.add(_audioService.onDurationChanged.listen((d) {
      if (_state.duration != d) {
        _state = _state.copyWith(duration: d);
        _notifyThrottled();
      }
    }));
    _subs.add(_audioService.onPlaybackStateChanged.listen((playing) {
      if (_state.isPlaying != playing) {
        _state = _state.copyWith(isPlaying: playing, isBuffering: false);
        notifyListeners();
      }
    }));
    _subs.add(_audioService.playerStateStream.listen((playerState) {
      final buffering =
          playerState.processingState == ProcessingState.buffering;
      if (_state.isBuffering != buffering) {
        _state = _state.copyWith(isBuffering: buffering);
        notifyListeners();
      }
    }));
    _subs.add(_audioService.onPlaybackError.listen((error) {
      _state = _state.copyWith(error: error);
      notifyListeners();
    }));
  }

  final AudioService _audioService;
  final List<StreamSubscription<dynamic>> _subs = [];

  PlaybackState _state = const PlaybackState();
  PlaybackState get state => _state;

  Timer? _throttle;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Position ticks at 60Hz; project at most ~20Hz to the UI.
  void _notifyThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds >= 50) {
      _lastNotify = now;
      notifyListeners();
      return;
    }
    _throttle ??= Timer(const Duration(milliseconds: 50), () {
      _throttle = null;
      _lastNotify = DateTime.now();
      notifyListeners();
    });
  }

  /// Mirror MusicProvider's queue/context/speed/shuffle/repeat bookkeeping
  /// into the projection. Called by MusicProvider after mutations.
  void syncFromProvider({
    Track? currentTrack,
    required List<Track> queue,
    required List<Track> context,
    required int currentIndex,
    String? contextId,
    required bool shuffle,
    required RepeatMode repeat,
    double? speed,
    String? error,
  }) {
    _state = _state.copyWith(
      currentTrack: currentTrack,
      clearTrack: currentTrack == null,
      upcoming: List.unmodifiable(queue),
      context: List.unmodifiable(context),
      currentIndex: currentIndex,
      contextId: contextId,
      shuffle: shuffle,
      repeat: repeat,
      speed: speed,
      error: error,
    );
    notifyListeners();
  }

  void clearError() {
    if (_state.error == null) return;
    _state = _state.copyWith(error: null);
    notifyListeners();
  }

  /// Project from MusicProvider's live getters. Single sync point —
  /// MusicProvider calls this once per notifyListeners via its override.
  void projectFromProvider(MusicProviderLike p) {
    _state = _state.copyWith(
      currentTrack: p.currentTrack,
      clearTrack: p.currentTrack == null,
      upcoming: List.unmodifiable(p.queue),
      context: List.unmodifiable(p.currentPlayingTracks ?? const <Track>[]),
      currentIndex: p.currentIndex,
      contextId: p.currentPlaylistId,
      shuffle: p.shuffleEnabled,
      repeat: p.repeatMode,
      speed: p.playbackSpeed,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _throttle?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    super.dispose();
  }
}
