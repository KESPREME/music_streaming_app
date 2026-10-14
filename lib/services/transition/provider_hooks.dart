// lib/services/transition/provider_hooks.dart
//
// What the transition engine asks of the app, answered by MusicProvider.
// A separate class so the provider does not implement the engine's interface
// itself (and so its public surface stays what the UI uses).

import 'package:just_audio/just_audio.dart' show IndexedAudioSource;

import 'track_analysis.dart';
import 'transition_engine.dart';

class ProviderTransitionHooks implements TransitionHooks {
  ProviderTransitionHooks({
    required this.contextOf,
    required this.stopAfter,
    required this.build,
    required this.handoff,
    required this.settled,
    required this.sleepDone,
    this.analysis,
    this.requestOf,
  });

  final TransitionContext? Function() contextOf;
  final bool Function() stopAfter;
  final Future<IndexedAudioSource?> Function(String trackId) build;
  final void Function(String incomingId) handoff;
  final void Function(bool completed) settled;
  final void Function() sleepDone;
  final TrackAnalysis? Function(String trackId, int durationMs)? analysis;
  final void Function(String trackId)? requestOf;

  @override
  TransitionContext? context() => contextOf();

  @override
  bool get stopAfterTrack => stopAfter();

  @override
  Future<IndexedAudioSource?> buildIncoming(String trackId) => build(trackId);

  @override
  TrackAnalysis? analysisFor(String trackId, int durationMs) =>
      analysis?.call(trackId, durationMs);

  @override
  void requestAnalysis(String trackId) => requestOf?.call(trackId);

  @override
  void onHandoff(String incomingId) => handoff(incomingId);

  @override
  void onSettled({required bool completed}) => settled(completed);

  @override
  void onSleepFadeDone() => sleepDone();
}
