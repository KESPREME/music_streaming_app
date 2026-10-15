// lib/services/transition/audio_service_decks.dart
//
// The engine's view of the real decks: a thin adapter, so the engine can be
// tested against fakes and AudioService stays free of transition logic.

import 'package:just_audio/just_audio.dart'
    show IndexedAudioSource, ProcessingState;

import '../audio_service.dart';
import 'transition_engine.dart';

class AudioServiceDecks implements TransitionDecks {
  AudioServiceDecks(this._audio);

  final AudioService _audio;

  @override
  Duration? get activeDuration => _audio.activeDuration;

  @override
  Duration get activePosition => _audio.activePosition;

  @override
  bool get activePlaying => _audio.activePlaying;

  @override
  String? get currentId => _audio.currentWindowId;

  @override
  double get userSpeed => _audio.speed;

  @override
  Duration get standbyPosition => _audio.standbyPosition;

  @override
  bool get standbyAlive => _audio.standbyProcessing != ProcessingState.idle;

  @override
  Future<void> prepareStandby(IndexedAudioSource source,
          {required Duration cue, required double rate}) =>
      _audio.prepareStandby(source, cue: cue, rate: rate);

  @override
  void playStandby() => _audio.playStandby();

  @override
  void setGains({required double active, required double standby}) =>
      _audio.setDeckGains(active: active, standby: standby);

  @override
  void mirror() => _audio.mirrorDecks();

  @override
  Future<void> swap() => _audio.swapDecks();

  @override
  Future<void> retireStandby() => _audio.retireStandby();

  @override
  Future<void> settleActive({bool resetSpeed = true}) =>
      _audio.settleActive(resetSpeed: resetSpeed);

  @override
  Future<void> setActiveRate(double rate) => _audio.setActiveRate(rate);

  @override
  Future<void> setStandbyRate(double rate) => _audio.setStandbyRate(rate);
}
