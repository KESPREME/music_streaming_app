// lib/services/playback/mine_audio_handler.dart
//
// The media session: what the notification, lock screen, headset buttons,
// Bluetooth controls and Android Auto talk to.
//
// WHY THIS EXISTS
//
// just_audio_background does this job, but for exactly one AudioPlayer, and a
// crossfade needs two. So the session is ours: [AudioService] mirrors the
// session deck into this handler, and the handler forwards the system's
// commands back to the provider.
//
// It owns no playback state. It publishes what it is told and relays what it is
// asked, which is why it is small and why it can be tested without a player.

import 'package:audio_service/audio_service.dart' as svc;
import 'package:just_audio/just_audio.dart' show ProcessingState;

/// The commands the system can send. Set by [MusicProvider].
class MineAudioHandler extends svc.BaseAudioHandler with svc.SeekHandler {
  MineAudioHandler();

  /// The handler the app initialised, or null before that (and in tests, where
  /// every publish is a no-op).
  static MineAudioHandler? shared;

  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onStop;
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;
  Future<void> Function(Duration position)? onSeek;

  @override
  Future<void> play() async => await onPlay?.call();

  @override
  Future<void> pause() async => await onPause?.call();

  @override
  Future<void> stop() async {
    await onStop?.call();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => await onSkipToNext?.call();

  @override
  Future<void> skipToPrevious() async => await onSkipToPrevious?.call();

  @override
  Future<void> seek(Duration position) async => await onSeek?.call(position);

  // ── Publishing ────────────────────────────────────────────────────────────

  /// Publishes the session deck's transport state.
  void publish({
    required bool playing,
    required ProcessingState processing,
    required Duration position,
    required Duration buffered,
    required double speed,
    required int? queueIndex,
  }) {
    playbackState.add(buildPlaybackState(
      previous: playbackState.value,
      playing: playing,
      processing: processing,
      position: position,
      buffered: buffered,
      speed: speed,
      queueIndex: queueIndex,
    ));
  }

  void publishMedia(svc.MediaItem? item) {
    if (mediaItem.value?.id == item?.id &&
        mediaItem.value?.duration == item?.duration) {
      return;
    }
    mediaItem.add(item);
  }

  void publishQueue(List<svc.MediaItem> items) => queue.add(items);

  /// The transport state for a given player snapshot. Pure, so the mapping the
  /// system relies on (which buttons exist, what "loading" means) is testable.
  static svc.PlaybackState buildPlaybackState({
    required svc.PlaybackState previous,
    required bool playing,
    required ProcessingState processing,
    required Duration position,
    required Duration buffered,
    required double speed,
    required int? queueIndex,
  }) {
    return previous.copyWith(
      controls: <svc.MediaControl>[
        svc.MediaControl.skipToPrevious,
        if (playing) svc.MediaControl.pause else svc.MediaControl.play,
        svc.MediaControl.skipToNext,
      ],
      systemActions: const <svc.MediaAction>{
        svc.MediaAction.seek,
        svc.MediaAction.seekForward,
        svc.MediaAction.seekBackward,
      },
      androidCompactActionIndices: const <int>[0, 1, 2],
      processingState: processingStateOf(processing),
      playing: playing,
      updatePosition: position,
      bufferedPosition: buffered,
      speed: speed,
      queueIndex: queueIndex,
    );
  }

  static svc.AudioProcessingState processingStateOf(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return svc.AudioProcessingState.idle;
      case ProcessingState.loading:
        return svc.AudioProcessingState.loading;
      case ProcessingState.buffering:
        return svc.AudioProcessingState.buffering;
      case ProcessingState.ready:
        return svc.AudioProcessingState.ready;
      case ProcessingState.completed:
        return svc.AudioProcessingState.completed;
    }
  }
}
