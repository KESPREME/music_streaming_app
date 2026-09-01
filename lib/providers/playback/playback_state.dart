import 'package:flutter/foundation.dart';

import '../../models/track.dart';

enum RepeatMode { off, all, one }

/// Immutable projection of everything the shell, mini-player, player,
/// queue sheet, and lyrics screens need to render playback.
///
/// One object, rebuilt by the owning controller whenever any constituent
/// changes — screens subscribe to a single projection instead of chasing
/// fifteen scattered getters, which keeps glass morph animations stable.
@immutable
class PlaybackState {
  const PlaybackState({
    this.currentTrack,
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.upcoming = const [],
    this.context = const [],
    this.currentIndex = -1,
    this.contextId,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
    this.speed = 1.0,
    this.error,
  });

  /// Active track, or null when nothing is loaded.
  final Track? currentTrack;

  /// Playing vs paused (not "has content").
  final bool isPlaying;

  /// True between track start and first audio frame.
  final bool isBuffering;

  final Duration position;
  final Duration duration;

  /// User queue drained before the playlist context continues.
  final List<Track> upcoming;

  /// The playlist/album/artist context backing playback.
  final List<Track> context;

  /// Index of [currentTrack] inside [context]; -1 when not present.
  final int currentIndex;

  /// Identity of the context (playlist id, album id, 'for_you', …).
  final String? contextId;

  final bool shuffle;
  final RepeatMode repeat;

  /// Playback rate multiplier (1.0 = normal; Lofi mode drives this too).
  final double speed;

  /// Last fatal playback error, surfaced as a glass toast by the shell.
  final String? error;

  bool get hasTrack => currentTrack != null;
  bool get canSkipNext => hasTrack && (upcoming.isNotEmpty || currentIndex < context.length - 1);
  bool get canSkipPrevious => hasTrack && (position > const Duration(seconds: 3) || currentIndex > 0);

  PlaybackState copyWith({
    Track? currentTrack,
    bool clearTrack = false,
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    List<Track>? upcoming,
    List<Track>? context,
    int? currentIndex,
    Object? contextId = _sentinel,
    bool? shuffle,
    RepeatMode? repeat,
    double? speed,
    Object? error = _sentinel,
  }) {
    return PlaybackState(
      currentTrack: clearTrack ? null : (currentTrack ?? this.currentTrack),
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      upcoming: upcoming ?? this.upcoming,
      context: context ?? this.context,
      currentIndex: currentIndex ?? this.currentIndex,
      contextId: contextId == _sentinel ? this.contextId : contextId as String?,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
      speed: speed ?? this.speed,
      error: error == _sentinel ? this.error : error as String?,
    );
  }

  static const Object _sentinel = Object();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackState &&
        other.currentTrack == currentTrack &&
        other.isPlaying == isPlaying &&
        other.isBuffering == isBuffering &&
        other.position == position &&
        other.duration == duration &&
        listEquals(other.upcoming, upcoming) &&
        listEquals(other.context, context) &&
        other.currentIndex == currentIndex &&
        other.contextId == contextId &&
        other.shuffle == shuffle &&
        other.repeat == repeat &&
        other.speed == speed &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(
        currentTrack,
        isPlaying,
        isBuffering,
        position,
        duration,
        Object.hashAll(upcoming),
        Object.hashAll(context),
        currentIndex,
        contextId,
        shuffle,
        repeat,
        speed,
        error,
      );
}
