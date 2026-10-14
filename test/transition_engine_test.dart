import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_streaming_app/services/transition/fade_curves.dart';
import 'package:music_streaming_app/services/transition/track_analysis.dart';
import 'package:music_streaming_app/services/transition/transition_engine.dart';
import 'package:music_streaming_app/services/transition/transition_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// THE ENGINE THIS FILE PINS.
///
/// A crossfade is a state machine over two decks and a clock, and the cases that
/// ruin it are the ones nobody hears in development: a skip in the middle of a
/// mix, a pause, an incoming song that never loads, a seek into the last seconds.
/// Here the decks are fakes and time is a number, so every one of those is a
/// test that runs in milliseconds and says exactly what happened.

class FakeDecks implements TransitionDecks {
  FakeDecks({required this.durationMs});

  final int durationMs;
  int activePos = 0;
  int standbyPos = 0;
  bool activePlay = true;
  bool standbyPlay = false;
  bool alive = true;
  double standbyRate = 1.0;
  double activeRate = 1.0;
  String? current = 'a';
  String? incoming;
  bool swapped = false;

  // What the engine asked for.
  final List<String> calls = <String>[];
  final List<({double out, double inn})> gains = <({double out, double inn})>[];
  double activeGain = 1.0;
  double standbyGain = 0.0;
  int swaps = 0;
  int retires = 0;
  int settles = 0;

  Completer<void>? prepareGate;
  bool prepareThrows = false;

  @override
  Duration? get activeDuration => Duration(milliseconds: durationMs);
  @override
  Duration get activePosition => Duration(milliseconds: activePos);
  @override
  bool get activePlaying => activePlay;
  @override
  String? get currentId => current;
  @override
  double get userSpeed => 1.0;
  @override
  Duration get standbyPosition => Duration(milliseconds: standbyPos);
  @override
  bool get standbyAlive => alive;

  @override
  Future<void> prepareStandby(IndexedAudioSource source,
      {required Duration cue, required double rate}) async {
    calls.add('prepare cue=${cue.inMilliseconds} rate=$rate');
    await prepareGate?.future;
    if (prepareThrows) throw StateError('no network');
    standbyPos = cue.inMilliseconds;
    standbyRate = rate;
  }

  @override
  void playStandby() {
    calls.add('playStandby');
    standbyPlay = true;
  }

  @override
  void setGains({required double active, required double standby}) {
    activeGain = active;
    standbyGain = standby;
    gains.add(swapped ? (out: standby, inn: active) : (out: active, inn: standby));
  }

  @override
  void mirror() {
    calls.add('mirror');
    standbyPlay = activePlay && standbyPlay;
    if (!activePlay) standbyPlay = false;
  }

  @override
  Future<void> swap() async {
    swaps++;
    swapped = true;
    final p = activePos;
    activePos = standbyPos;
    standbyPos = p;
    final pl = activePlay;
    activePlay = standbyPlay;
    standbyPlay = pl;
    final g = activeGain;
    activeGain = standbyGain;
    standbyGain = g;
    current = incoming;
  }

  @override
  Future<void> retireStandby() async {
    retires++;
    standbyGain = 0;
    standbyPlay = false;
  }

  @override
  Future<void> settleActive() async {
    settles++;
    activeGain = 1.0;
  }

  @override
  Future<void> setActiveRate(double rate) async => activeRate = rate;

  /// Time passes: both decks that are playing move.
  void advance(int ms) {
    if (activePlay) activePos += ms;
    if (standbyPlay) standbyPos += (ms * standbyRate).round();
  }
}

class FakeHooks implements TransitionHooks {
  FakeHooks(this.decks);

  final FakeDecks decks;
  TransitionContext? ctx = const TransitionContext(currentId: 'a', nextId: 'b');
  bool stopAfter = false;
  bool builds = true;
  final List<String> handoffs = <String>[];
  final List<bool> settled = <bool>[];
  int sleepDone = 0;

  @override
  TransitionContext? context() => ctx;
  @override
  bool get stopAfterTrack => stopAfter;
  @override
  Future<IndexedAudioSource?> buildIncoming(String trackId) async {
    decks.incoming = trackId;
    if (!builds) return null;
    return AudioSource.uri(Uri.parse('https://example.com/$trackId.m4a'));
  }

  @override
  TrackAnalysis? analysisFor(String trackId, int durationMs) => null;
  @override
  void requestAnalysis(String trackId) {}
  @override
  void onHandoff(String incomingId) => handoffs.add(incomingId);
  @override
  void onSettled({required bool completed}) => settled.add(completed);
  @override
  void onSleepFadeDone() => sleepDone++;
}

class Rig {
  Rig._(this.decks, this.hooks, this.settings, this.engine);

  final FakeDecks decks;
  final FakeHooks hooks;
  final TransitionSettings settings;
  final TransitionEngine engine;
  int clock = 0;

  static Future<Rig> make({
    int durationMs = 100000,
    bool enabled = true,
    int fadeSeconds = 6,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = TransitionSettings();
    await settings.setEnabled(enabled);
    await settings.setCrossfadeSeconds(fadeSeconds);
    final decks = FakeDecks(durationMs: durationMs);
    final hooks = FakeHooks(decks);
    late Rig rig;
    final engine = TransitionEngine(
      decks: decks,
      hooks: hooks,
      settings: settings,
      nowMs: () => rig.clock,
      autoSchedule: false,
    );
    rig = Rig._(decks, hooks, settings, engine);
    return rig;
  }

  /// Time passes by [ms], then the engine takes a step and the event queue
  /// drains (the engine awaits swaps and prepares).
  Future<void> step(int ms) async {
    clock += ms;
    decks.advance(ms);
    engine.tick();
    await pumpEventQueue();
  }

  /// Jumps the outgoing song to [pos] without time passing.
  Future<void> seekTo(int pos) async {
    decks.activePos = pos;
    engine.tick();
    await pumpEventQueue();
  }

  Future<void> runUntil(bool Function() done, {int stepMs = 30, int maxSteps = 2000}) async {
    for (var i = 0; i < maxSteps && !done(); i++) {
      await step(stepMs);
    }
  }
}

void main() {
  group('a crossfade', () {
    test('does nothing until shortly before it is needed', () async {
      final r = await Rig.make();
      await r.seekTo(10000);
      expect(r.engine.phase, TransitionPhase.idle);
      expect(r.decks.calls, isEmpty, reason: 'no standby work 83 seconds early');
    });

    test('arms inside the lead, then mixes and hands over once', () async {
      final r = await Rig.make(); // 100 s, 6 s fade: starts at 93.75 s
      await r.seekTo(90000);
      expect(r.engine.phase, TransitionPhase.arming);
      expect(r.decks.calls.first, startsWith('prepare cue=0'));

      await r.step(40);
      expect(r.engine.phase, TransitionPhase.arming, reason: 'waits for its moment');
      expect(r.decks.standbyPlay, isFalse, reason: 'silent until then');

      await r.runUntil(() => r.engine.phase == TransitionPhase.fading);
      expect(r.decks.standbyPlay, isTrue);
      expect(r.decks.activePos, inInclusiveRange(93700, 93800));

      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);
      expect(r.decks.swaps, 1, reason: 'exactly one handoff');
      expect(r.hooks.handoffs, <String>['b']);
      expect(r.decks.current, 'b');
      expect(r.decks.retires, 1, reason: 'the outgoing deck is released');
      expect(r.decks.activeGain, 1.0, reason: 'settles on full volume');
      expect(r.decks.standbyGain, 0.0);
      expect(r.hooks.settled.last, isTrue);
    });

    test('hands over at the midpoint, not before', () async {
      final r = await Rig.make();
      await r.seekTo(90000);
      await r.runUntil(() => r.engine.phase == TransitionPhase.fading);
      final start = r.decks.activePos;

      await r.runUntil(() => r.decks.swaps == 1);
      // 3s into a 6s mix.
      final into = r.decks.standbyPos - 0; // after the swap the old song is standby
      expect(into - start, inInclusiveRange(2900, 3200));
      expect(r.engine.ui.value.progress, closeTo(0.5, 0.06));
    });

    test('holds constant power through the whole mix', () async {
      final r = await Rig.make();
      await r.seekTo(90000);
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);

      final mix = r.decks.gains.where((g) => g.inn > 0 || g.out < 1).toList();
      expect(mix.length, greaterThan(100));
      var prevOut = 1.1;
      var prevIn = -0.1;
      for (final g in mix) {
        expect(g.out, lessThanOrEqualTo(prevOut + 1e-9), reason: 'outgoing only falls');
        expect(g.inn, greaterThanOrEqualTo(prevIn - 1e-9), reason: 'incoming only rises');
        prevOut = g.out;
        prevIn = g.inn;
        final power = g.out * g.out + g.inn * g.inn;
        // Headroom trim takes at most 1.5 dB off at the midpoint (power 0.707).
        expect(power, inInclusiveRange(0.69, 1.001));
        expect(g.out + g.inn, lessThanOrEqualTo(1.19));
      }
    });

    test('reaches the end of the music before the file does', () async {
      final r = await Rig.make();
      await r.seekTo(90000);
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);
      expect(r.decks.standbyPos, lessThan(100000 - 250 + 100));
    });
  });

  group('the listener acts', () {
    test('a skip during the mix ramps out, never hands over, and settles',
        () async {
      final r = await Rig.make();
      await r.seekTo(90000);
      await r.runUntil(() => r.engine.phase == TransitionPhase.fading);
      await r.step(1500); // a quarter of the way in
      expect(r.decks.swaps, 0);

      r.engine.bail();
      expect(r.engine.phase, TransitionPhase.bailing);
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);

      expect(r.decks.swaps, 0, reason: 'a skip is not a transition');
      expect(r.decks.retires, 1);
      expect(r.decks.activeGain, 1.0, reason: 'the song that follows is at full volume');
      expect(r.decks.standbyGain, 0.0);
      expect(r.hooks.settled.last, isFalse);
    });

    test('a skip while arming abandons it and the prepare cannot come back',
        () async {
      final r = await Rig.make();
      r.decks.prepareGate = Completer<void>();
      await r.seekTo(90000);
      expect(r.engine.phase, TransitionPhase.arming);

      r.engine.bail();
      expect(r.engine.phase, TransitionPhase.idle);
      r.decks.prepareGate!.complete();
      await pumpEventQueue();

      await r.seekTo(50000);
      expect(r.engine.phase, TransitionPhase.idle);
      expect(r.decks.standbyPlay, isFalse);
    });

    test('a pause freezes the mix where it is', () async {
      final r = await Rig.make();
      await r.seekTo(90000);
      await r.runUntil(() => r.engine.phase == TransitionPhase.fading);
      await r.step(2000);
      r.decks.activePlay = false;
      await r.step(30); // the other deck follows within one tick
      final p = r.engine.ui.value.progress;
      for (var i = 0; i < 20; i++) {
        await r.step(30);
      }
      expect(r.engine.ui.value.progress, p, reason: 'driven by positions, not a clock');
      expect(r.decks.standbyPlay, isFalse, reason: 'the other deck pauses too');

      r.decks.activePlay = true;
      r.decks.standbyPlay = true;
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);
      expect(r.decks.swaps, 1);
    });

    test('a seek into the last seconds still mixes, with a shorter fade',
        () async {
      final r = await Rig.make();
      await r.seekTo(96500); // 3.25 s of music left to fade over
      await r.runUntil(() => r.engine.phase == TransitionPhase.fading);
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);
      expect(r.decks.swaps, 1);
      expect(r.decks.standbyPos, lessThanOrEqualTo(100000));
    });

    test('a seek past the point of no return skips the mix', () async {
      final r = await Rig.make();
      r.decks.prepareGate = Completer<void>();
      await r.seekTo(90000);
      await r.step(40);
      r.decks.activePos = 98900; // within a second of the end
      r.decks.prepareGate!.complete();
      await pumpEventQueue();
      await r.step(40);
      expect(r.engine.phase, TransitionPhase.idle);
      expect(r.decks.swaps, 0);
    });
  });

  group('when something goes wrong', () {
    test('an incoming song that never loads is abandoned after 12 seconds',
        () async {
      final r = await Rig.make();
      r.decks.prepareGate = Completer<void>(); // never completes
      await r.seekTo(90000);
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle,
          stepMs: 200, maxSteps: 100);

      expect(r.engine.phase, TransitionPhase.idle);
      expect(r.decks.swaps, 0);
      expect(r.decks.activeGain, 1.0, reason: 'the outgoing song was never touched');
    });

    test('a pair that failed is not retried on every step', () async {
      final r = await Rig.make();
      r.hooks.builds = false;
      await r.seekTo(90000);
      await r.step(40);
      expect(r.engine.phase, TransitionPhase.idle);
      await r.step(1000);
      await r.step(1000);
      expect(r.decks.calls.where((c) => c.startsWith('prepare')).length, 0);
      expect(r.engine.phase, TransitionPhase.idle);
    });

    test('a failing prepare is abandoned too', () async {
      final r = await Rig.make();
      r.decks.prepareThrows = true;
      await r.seekTo(90000);
      await r.step(40);
      expect(r.engine.phase, TransitionPhase.idle);
      await r.step(40);
      expect(r.decks.calls.where((c) => c.startsWith('prepare')).length, 1);
    });

    test('a track change while arming abandons the mix', () async {
      final r = await Rig.make();
      await r.seekTo(90000);
      r.decks.current = 'z';
      await r.step(40);
      expect(r.engine.phase, TransitionPhase.idle);
      expect(r.decks.swaps, 0);
    });

    test('an incoming deck that dies mid-mix gives the outgoing song back',
        () async {
      final r = await Rig.make();
      await r.seekTo(90000);
      await r.runUntil(() => r.engine.phase == TransitionPhase.fading);
      await r.step(1200);
      r.decks.alive = false;
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);
      expect(r.decks.swaps, 0);
      expect(r.decks.activeGain, 1.0);
    });
  });

  group('when no mix is wanted', () {
    test('transitions off: the songs join as they always did', () async {
      final r = await Rig.make(enabled: false);
      await r.seekTo(98000);
      expect(r.engine.phase, TransitionPhase.idle);
      expect(r.decks.calls, isEmpty);
    });

    test('album tracks stay gapless', () async {
      final r = await Rig.make();
      r.hooks.ctx = const TransitionContext(
          currentId: 'a', nextId: 'b', albumSequential: true);
      await r.seekTo(98000);
      expect(r.engine.phase, TransitionPhase.idle);
      expect(r.decks.calls, isEmpty);
    });

    test('repeat-one and casting never mix', () async {
      final r = await Rig.make();
      r.hooks.ctx =
          const TransitionContext(currentId: 'a', nextId: 'b', repeatOne: true);
      await r.seekTo(98000);
      expect(r.engine.phase, TransitionPhase.idle);
      r.hooks.ctx =
          const TransitionContext(currentId: 'a', nextId: 'b', casting: true);
      await r.seekTo(98000);
      expect(r.engine.phase, TransitionPhase.idle);
    });

    test('nothing after this song means nothing to do', () async {
      final r = await Rig.make();
      r.hooks.ctx = null;
      await r.seekTo(98000);
      expect(r.engine.phase, TransitionPhase.idle);
    });

    test('a paused player is never armed', () async {
      final r = await Rig.make();
      r.decks.activePlay = false;
      await r.seekTo(98000);
      expect(r.engine.phase, TransitionPhase.idle);
    });
  });

  group('the sleep timer', () {
    test('"stop after this song" fades the song out as it ends, then stops',
        () async {
      final r = await Rig.make(enabled: false); // works without transitions
      r.hooks.stopAfter = true;
      await r.seekTo(50000);
      expect(r.engine.phase, TransitionPhase.idle);

      await r.seekTo(92000); // 100s - 250ms - 8s = 91.75s
      expect(r.engine.phase, TransitionPhase.sleepFade);
      await r.runUntil(() => r.hooks.sleepDone > 0);
      expect(r.hooks.sleepDone, 1);
      expect(r.decks.activeGain, closeTo(0, 0.01));
      expect(r.decks.swaps, 0);
    });

    test('turning the fade off leaves the song alone', () async {
      final r = await Rig.make(enabled: false);
      await r.settings.setSleepFade(false);
      r.hooks.stopAfter = true;
      await r.seekTo(92000);
      expect(r.engine.phase, TransitionPhase.idle);
    });

    test('a timer that fires fades over eight seconds on the wall clock',
        () async {
      final r = await Rig.make(enabled: false);
      r.engine.fadeOutNow();
      expect(r.engine.phase, TransitionPhase.sleepFade);
      await r.step(4000);
      expect(r.decks.activeGain, closeTo(0.707, 0.05));
      await r.runUntil(() => r.hooks.sleepDone > 0, stepMs: 100);
      expect(r.hooks.sleepDone, 1);
    });

    test('cancelling the timer brings the volume back', () async {
      final r = await Rig.make(enabled: false);
      r.engine.fadeOutNow();
      await r.step(4000);
      r.engine.cancelSleepFade();
      expect(r.engine.phase, TransitionPhase.idle);
      expect(r.decks.activeGain, 1.0);
    });
  });

  group('the curves', () {
    test('power is constant for any two different songs', () {
      for (var i = 0; i <= 100; i++) {
        final p = i / 100;
        expect(riseGain(p) * riseGain(p) + fallGain(p) * fallGain(p), closeTo(1, 1e-12));
      }
    });

    test('a linear fade would dip 3 dB at the midpoint; this does not', () {
      expect(riseGain(0.5) * riseGain(0.5) + fallGain(0.5) * fallGain(0.5), closeTo(1, 1e-12));
      expect(0.5 * 0.5 + 0.5 * 0.5, 0.5); // what linear gives
    });

    test('headroom is only taken when the sum would clip, and never over 1.5 dB',
        () {
      expect(headroomTrim(0.0, 1.0), 1.0);
      expect(headroomTrim(1.0, 0.0), 1.0);
      final mid = headroomTrim(riseGain(0.5), fallGain(0.5));
      expect(mid, closeTo(0.8409, 1e-3));
      expect(20 * math.log(mid) / math.ln10, greaterThan(-1.6));
    });

    test('out-of-range progress is clamped, not extrapolated', () {
      expect(riseGain(-1), 0);
      expect(riseGain(2), closeTo(1, 1e-12));
      expect(fallGain(2), closeTo(0, 1e-12));
      expect(riseGain(double.nan), 0);
    });
  });
}

