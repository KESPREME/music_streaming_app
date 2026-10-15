import 'dart:async';

import 'package:audio_service/audio_service.dart' as svc;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:music_streaming_app/services/playback/decks.dart';
import 'package:music_streaming_app/services/playback/mine_audio_handler.dart';
import 'package:music_streaming_app/services/transition/track_analysis.dart';
import 'package:music_streaming_app/services/transition/transition_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The pieces around the engine: what the listener chose, the streams that
/// follow whichever deck is the session deck, and what the lock screen is told.

void main() {
  group('TransitionSettings', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('a listener who never opens the screen hears what they always heard',
        () async {
      final s = TransitionSettings();
      await s.load();
      expect(s.enabled, isFalse);
      expect(s.active, isFalse);
      expect(s.style, TransitionStyle.crossfade);
      expect(s.crossfadeSeconds, 6);
      expect(s.crossfadeAlbums, isFalse, reason: 'albums stay gapless');
      expect(s.matchTempo, isTrue,
          reason: 'matching tempo is what AutoMix is; Crossfade never stretches');
      expect(s.levelMatching, isTrue);
      expect(s.sleepFade, isTrue);
      expect(s.skipSilence, isFalse);
      expect(s.analyzeOnCellular, isFalse);
    });

    test('everything persists and reloads', () async {
      final a = TransitionSettings();
      await a.load();
      await a.setEnabled(true);
      await a.setStyle(TransitionStyle.automix);
      await a.setCrossfadeSeconds(9);
      await a.setCrossfadeAlbums(true);
      await a.setMatchTempo(false);
      await a.setLevelMatching(false);
      await a.setSleepFade(false);
      await a.setSkipSilence(true);
      await a.setAnalyzeOnCellular(true);

      final b = TransitionSettings();
      await b.load();
      expect(b.enabled, isTrue);
      expect(b.isAutomix, isTrue);
      expect(b.crossfadeSeconds, 9);
      expect(b.crossfadeAlbums, isTrue);
      expect(b.matchTempo, isFalse);
      expect(b.levelMatching, isFalse);
      expect(b.sleepFade, isFalse);
      expect(b.skipSilence, isTrue);
      expect(b.analyzeOnCellular, isTrue);
    });

    test('the length is held to Apple Music\'s one to twelve seconds', () async {
      final s = TransitionSettings();
      await s.load();
      await s.setCrossfadeSeconds(0);
      expect(s.crossfadeSeconds, 1);
      await s.setCrossfadeSeconds(99);
      expect(s.crossfadeSeconds, 12);
    });

    test('automix is only automix while transitions are on', () async {
      final s = TransitionSettings();
      await s.load();
      await s.setStyle(TransitionStyle.automix);
      expect(s.isAutomix, isFalse);
      await s.setEnabled(true);
      expect(s.isAutomix, isTrue);
    });

    test('a changed plan input changes planVersion; an irrelevant one does not',
        () async {
      final s = TransitionSettings();
      await s.load();
      final v0 = s.planVersion;
      await s.setSkipSilence(true);
      await s.setSleepFade(false);
      expect(s.planVersion, v0);
      await s.setCrossfadeSeconds(3);
      expect(s.planVersion, isNot(v0));
    });

    test('setting a value it already has notifies nobody', () async {
      final s = TransitionSettings();
      await s.load();
      var n = 0;
      s.addListener(() => n++);
      await s.setEnabled(false);
      await s.setCrossfadeSeconds(6);
      expect(n, 0);
    });

    test('garbage in the store falls back to defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        TransitionSettings.keyStyle: 'disco',
        TransitionSettings.keyCrossfadeSeconds: 400,
      });
      final s = TransitionSettings();
      await s.load();
      expect(s.style, TransitionStyle.crossfade);
      expect(s.crossfadeSeconds, 12);
    });
  });

  group('DeckRelay', () {
    test('follows whichever source it was last pointed at', () async {
      final relay = DeckRelay<int>();
      final a = StreamController<int>();
      final b = StreamController<int>();
      final seen = <int>[];
      relay.stream.listen(seen.add);

      relay.follow(a.stream);
      a.add(1);
      await pumpEventQueue();
      relay.follow(b.stream);
      a.add(2); // the old deck is no longer heard
      b.add(3);
      await pumpEventQueue();

      expect(seen, <int>[1, 3]);
      await relay.dispose();
    });

    test('a replaying relay tells a late listener the latest value', () async {
      final relay = DeckRelay<String>(replay: true);
      final src = StreamController<String>();
      relay.follow(src.stream);
      src.add('first');
      src.add('second');
      await pumpEventQueue();

      final late = <String>[];
      relay.stream.listen(late.add);
      await pumpEventQueue();
      expect(late, <String>['second']);
      await relay.dispose();
    });

    test('a plain relay does not replay (a position is only true when it arrives)',
        () async {
      final relay = DeckRelay<int>();
      final src = StreamController<int>();
      relay.follow(src.stream);
      src.add(5);
      await pumpEventQueue();
      final late = <int>[];
      relay.stream.listen(late.add);
      await pumpEventQueue();
      expect(late, isEmpty);
      await relay.dispose();
    });

    test('errors reach listeners instead of becoming uncaught', () async {
      final relay = DeckRelay<int>();
      final src = StreamController<int>();
      final errors = <Object>[];
      relay.stream.listen((_) {}, onError: errors.add);
      relay.follow(src.stream);
      src.addError(StateError('player'));
      await pumpEventQueue();
      expect(errors, hasLength(1));
      await relay.dispose();
    });

    test('the stream object is stable, so StreamBuilders do not resubscribe',
        () {
      final plain = DeckRelay<int>();
      // StreamBuilder compares with ==, and a controller's stream is equal to
      // itself.
      expect(plain.stream == plain.stream, isTrue);
    });
  });

  group('the media session', () {
    final idle = svc.PlaybackState();

    svc.PlaybackState build({
      bool playing = false,
      ProcessingState processing = ProcessingState.ready,
    }) =>
        MineAudioHandler.buildPlaybackState(
          previous: idle,
          playing: playing,
          processing: processing,
          position: const Duration(seconds: 12),
          buffered: const Duration(seconds: 60),
          speed: 1.0,
          queueIndex: 2,
        );

    test('the notification has previous, play/pause and next', () {
      final paused = build();
      expect(paused.controls.map((c) => c.action), <svc.MediaAction>[
        svc.MediaAction.skipToPrevious,
        svc.MediaAction.play,
        svc.MediaAction.skipToNext,
      ]);
      final playing = build(playing: true);
      expect(playing.controls[1].action, svc.MediaAction.pause);
      expect(playing.androidCompactActionIndices, <int>[0, 1, 2]);
    });

    test('the lock screen can seek', () {
      expect(build().systemActions, contains(svc.MediaAction.seek));
    });

    test('every player state maps to a session state', () {
      expect(MineAudioHandler.processingStateOf(ProcessingState.idle),
          svc.AudioProcessingState.idle);
      expect(MineAudioHandler.processingStateOf(ProcessingState.loading),
          svc.AudioProcessingState.loading);
      expect(MineAudioHandler.processingStateOf(ProcessingState.buffering),
          svc.AudioProcessingState.buffering);
      expect(MineAudioHandler.processingStateOf(ProcessingState.ready),
          svc.AudioProcessingState.ready);
      expect(MineAudioHandler.processingStateOf(ProcessingState.completed),
          svc.AudioProcessingState.completed);
    });

    test('position, buffer and queue index are carried through', () {
      final s = build(playing: true);
      expect(s.updatePosition, const Duration(seconds: 12));
      expect(s.bufferedPosition, const Duration(seconds: 60));
      expect(s.queueIndex, 2);
      expect(s.playing, isTrue);
    });

    test('system commands reach whoever bound them', () async {
      final h = MineAudioHandler();
      final log = <String>[];
      h.onPlay = () async => log.add('play');
      h.onPause = () async => log.add('pause');
      h.onSkipToNext = () async => log.add('next');
      h.onSkipToPrevious = () async => log.add('prev');
      h.onSeek = (p) async => log.add('seek ${p.inSeconds}');
      await h.play();
      await h.pause();
      await h.skipToNext();
      await h.skipToPrevious();
      await h.seek(const Duration(seconds: 30));
      expect(log, <String>['play', 'pause', 'next', 'prev', 'seek 30']);
    });

    test('with nothing bound a command is a quiet no-op', () async {
      final h = MineAudioHandler();
      await h.play();
      await h.skipToNext();
    });
  });

  group('TrackAnalysis', () {
    test('survives a round trip through the store', () {
      const a = TrackAnalysis(
        trackId: 'abc',
        durationMs: 201000,
        audibleStartMs: 1200,
        outroStartMs: 190000,
        contentEndMs: 197000,
        bpm: 123.5,
        beatConfidence: 0.8,
        beatsMs: <int>[500, 1000, 1500],
        downbeatsMs: <int>[500],
      );
      final b = TrackAnalysis.decode(a.encode())!;
      expect(b.trackId, 'abc');
      expect(b.durationMs, 201000);
      expect(b.bpm, 123.5);
      expect(b.beatsMs, <int>[500, 1000, 1500]);
      expect(b.downbeatsMs, <int>[500]);
      expect(b.isUsable, isTrue);
    });

    test('corrupt or foreign data is rejected, not trusted', () {
      expect(TrackAnalysis.decode('not json'), isNull);
      expect(TrackAnalysis.decode('{"v":1}'), isNull);
    });

    test('an older analyser version is not usable', () {
      final old = TrackAnalysis.decode(
          '{"v":0,"id":"x","dur":1000,"as":0,"os":0,"ce":0,"bpm":0,"bc":0,"b":[],"db":[]}')!;
      expect(old.isUsable, isFalse);
    });

    test('a different cut of the song does not match', () {
      const a = TrackAnalysis(trackId: 'x', durationMs: 200000);
      expect(a.matchesDuration(200800), isTrue);
      expect(a.matchesDuration(205000), isFalse);
      expect(a.matchesDuration(0), isTrue, reason: 'unknown duration: no objection');
    });
  });
}
