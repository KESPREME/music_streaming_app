import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_streaming_app/services/transition/fade_curves.dart';
import 'package:music_streaming_app/services/transition/track_analysis.dart';
import 'package:music_streaming_app/services/transition/transition_engine.dart';
import 'package:music_streaming_app/services/transition/transition_planner.dart';
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

  /// How long after playStandby() the incoming deck's position starts moving:
  /// the timer tick, the channel call, the decoder starting.
  int standbyStartLagMs = 0;
  int _lagLeft = 0;
  double _frac = 0;

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
    _lagLeft = standbyStartLagMs;
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
    final r = activeRate;
    activeRate = standbyRate;
    standbyRate = r;
    current = incoming;
  }

  @override
  Future<void> retireStandby() async {
    retires++;
    standbyGain = 0;
    standbyPlay = false;
  }

  @override
  Future<void> settleActive({bool resetSpeed = true}) async {
    settles++;
    activeGain = 1.0;
    if (resetSpeed) activeRate = 1.0;
  }

  @override
  Future<void> setActiveRate(double rate) async => activeRate = rate;

  @override
  Future<void> setStandbyRate(double rate) async => standbyRate = rate;

  /// Time passes: both decks that are playing move.
  void advance(int ms) {
    if (activePlay) activePos += _carry(ms * activeRate, active: true);
    if (standbyPlay) {
      var moving = ms;
      if (_lagLeft > 0) {
        final used = math.min(ms, _lagLeft);
        _lagLeft -= used;
        moving = ms - used;
      }
      standbyPos += _carry(moving * standbyRate, active: false);
    }
  }

  // Fractional milliseconds are carried: a 30 ms step at 0.9756 is 29.27, and
  // rounding each one down would be a 1 % tempo error of the fake's own.
  double _fracActive = 0;
  int _carry(double ms, {required bool active}) {
    var f = (active ? _fracActive : _frac) + ms;
    final whole = f.floor();
    f -= whole;
    if (active) {
      _fracActive = f;
    } else {
      _frac = f;
    }
    return whole;
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

  final Map<String, TrackAnalysis> analyses = <String, TrackAnalysis>{};

  @override
  TrackAnalysis? analysisFor(String trackId, int durationMs) => analyses[trackId];
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

  group('loudness balance', () {
    TrackAnalysis measured(String id, double lufs) => TrackAnalysis(
          trackId: id,
          durationMs: 100000,
          integratedLufs: lufs,
          levelsLufs: List<double>.filled(100, lufs),
        );

    Future<Rig> rigWith(double outLufs, double inLufs, {bool matching = true}) async {
      final r = await Rig.make();
      await r.settings.setLevelMatching(matching);
      r.hooks.analyses['a'] = measured('a', outLufs);
      r.hooks.analyses['b'] = measured('b', inLufs);
      await r.seekTo(90000);
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);
      return r;
    }

    test('a louder incoming song is held down through the overlap', () async {
      final plain = await rigWith(-14, -5, matching: false);
      final r = await rigWith(-14, -5);
      // (The held-down song's release adds a gain update after the mix.)
      expect(r.decks.gains.length, greaterThanOrEqualTo(plain.decks.gains.length),
          reason: 'same mix, same ticks');
      for (final k in [plain.decks.gains.length ~/ 4, plain.decks.gains.length ~/ 2]) {
        final held = r.decks.gains[k];
        final flat = plain.decks.gains[k];
        expect(held.inn / flat.inn, closeTo(math.pow(10, -9 / 20), 0.01));
        expect(held.out, closeTo(flat.out, 1e-9), reason: 'the outgoing is untouched');
      }
      expect(r.engine.lastMix.value!.level.incomingDb, closeTo(-9.0, 0.1));
    });

    test('with level matching off the gains are the plain curves', () async {
      final r = await rigWith(-14, -5, matching: false);
      expect(r.engine.lastMix.value!.level.isNone, isTrue);
      final cross = r.decks.gains.reduce((a, b) =>
          (a.out - a.inn).abs() < (b.out - b.inn).abs() ? a : b);
      expect(cross.inn / cross.out, closeTo(1.0, 0.05));
    });

    test('a quieter incoming song brings the outgoing one down early', () async {
      final plain = await rigWith(-5, -14, matching: false);
      final r = await rigWith(-5, -14);
      final k = plain.decks.gains.length ~/ 3; // inside the ramp (35 % of the fade)
      expect(r.decks.gains[k].out, lessThan(plain.decks.gains[k].out * 0.8),
          reason: 'the loud song under the quiet one is brought down');
      expect(r.decks.gains[k].inn, closeTo(plain.decks.gains[k].inn, 1e-9));
      expect(r.engine.lastMix.value!.level.outgoingDb, closeTo(-9.0, 0.1));
    });
    test('the held-down song climbs back to its own level, and settles there',
        () async {
      final r = await rigWith(-14, -5);
      // Right after the mix the song is still held down...
      expect(r.decks.activeGain, lessThan(0.5));
      final gains = <double>[];
      for (var i = 0; i < 90; i++) {
        r.clock += 100;
        r.engine.releaseStep();
        gains.add(r.decks.activeGain);
      }
      // ...rises, never falls, and is exactly full level when the release ends.
      for (var i = 1; i < gains.length; i++) {
        expect(gains[i], greaterThanOrEqualTo(gains[i - 1] - 1e-12));
      }
      expect(gains.last, closeTo(1.0, 1e-12));
    });

    test('a skip during the climb puts the volume back at once', () async {
      final r = await rigWith(-14, -5);
      expect(r.decks.activeGain, lessThan(0.5));
      r.engine.bail();
      expect(r.decks.activeGain, 1.0);
    });
  });

  group('the beat', () {
    TrackAnalysis grid(String id, double bpm) {
      final beat = 60000 / bpm;
      return TrackAnalysis(
        trackId: id,
        durationMs: 100000,
        bpm: bpm,
        beatConfidence: 0.9,
        beatsMs: [for (var t = 0.0; t < 100000; t += beat) t.round()],
        downbeatsMs: [for (var t = 0.0; t < 100000; t += beat * 4) t.round()],
      );
    }

    Future<Rig> beatRig({required double outBpm, required double inBpm, int lag = 0}) async {
      final r = await Rig.make();
      await r.settings.setStyle(TransitionStyle.automix);
      r.decks.standbyStartLagMs = lag;
      r.hooks.analyses['a'] = grid('a', outBpm);
      r.hooks.analyses['b'] = grid('b', inBpm);
      await r.seekTo(89000); // inside the arming lead of a bar-aligned start at 92 s
      return r;
    }

    test('a start that lags the plan is pulled onto the beat during the mix',
        () async {
      final r = await beatRig(outBpm: 120, inBpm: 120, lag: 90);
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);
      final t = r.engine.lastMix.value!;
      expect(t.plan.kind, PlanKind.beatmatched);
      expect(t.peakTrim, greaterThan(0), reason: 'it had to speed the incoming up');
      expect(t.peakTrim, lessThanOrEqualTo(0.03 + 1e-9));
      expect(t.lastPhaseErrorMs!.abs(), lessThan(20),
          reason: 'and it did, by the end');
      expect(t.firstPhaseErrorMs!.abs(), greaterThan(t.lastPhaseErrorMs!.abs()));
    });

    test('a start that is already on the beat is not touched', () async {
      final r = await beatRig(outBpm: 120, inBpm: 120, lag: 0);
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);
      final t = r.engine.lastMix.value!;
      expect(t.plan.kind, PlanKind.beatmatched);
      expect(t.peakTrim, 0.0);
    });

    test('a plain crossfade has no lock to run', () async {
      final r = await Rig.make();
      r.decks.standbyStartLagMs = 90;
      await r.seekTo(90000);
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);
      final t = r.engine.lastMix.value!;
      expect(t.peakTrim, 0.0);
      expect(t.firstPhaseErrorMs, isNull);
    });

    test('a stretched incoming song is walked back to normal speed, not snapped',
        () async {
      final r = await beatRig(outBpm: 120, inBpm: 123);
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);
      final stretched = r.decks.activeRate;
      expect(r.engine.lastMix.value!.plan.incomingRate, closeTo(120 / 123, 1e-3));
      expect(stretched, closeTo(120 / 123, 0.01),
          reason: 'settling the deck must not undo the stretch before the walk back');
      var last = stretched;
      for (var i = 0; i < 12; i++) {
        r.engine.easeStep();
        await pumpEventQueue();
        expect(r.decks.activeRate, greaterThanOrEqualTo(last - 1e-9),
            reason: 'monotonic toward 1.0');
        last = r.decks.activeRate;
      }
      expect(r.decks.activeRate, 1.0);
    });

    test('the trace says what happened', () async {
      final r = await beatRig(outBpm: 120, inBpm: 120, lag: 60);
      await r.runUntil(() => r.engine.phase == TransitionPhase.idle);
      final t = r.engine.lastMix.value!;
      expect(t.completed, isTrue);
      expect(t.ticks, greaterThan(100));
      expect(t.maxTickGapMs, lessThanOrEqualTo(30));
      expect(t.toString(), contains('MIX_TRACE beatmatched'));
    });
  });

  group('what the engine says is coming', () {
    test('a playing song with a next one announces its transition early', () async {
      final r = await Rig.make();
      await r.seekTo(10000); // far from the end: nothing armed, but planned
      final u = r.engine.upcoming.value;
      expect(u, isNotNull);
      expect(u!.kind, PlanKind.crossfade);
      expect(u.startAtMs, 93750);
      expect(u.endAtMs, 99750);
      expect(u.fadeMs, 6000);
      expect(u.durationMs, 100000);
      expect(u.nextId, 'b');
      expect(u.analysed, isFalse);
      expect(r.decks.calls, isEmpty, reason: 'announcing is not arming');
    });

    test('a paused player still says what it would do', () async {
      final r = await Rig.make();
      r.decks.activePlay = false;
      r.engine.poke();
      expect(r.engine.upcoming.value?.kind, PlanKind.crossfade);
      expect(r.decks.calls, isEmpty);
    });

    test('album tracks say "gapless" rather than nothing', () async {
      final r = await Rig.make();
      r.hooks.ctx = const TransitionContext(
          currentId: 'a', nextId: 'b', albumSequential: true);
      await r.seekTo(10000);
      expect(r.engine.upcoming.value?.kind, PlanKind.none);
      expect(r.engine.upcoming.value?.reason, 'album-gapless');
    });

    test('with transitions off there is nothing to announce', () async {
      final r = await Rig.make(enabled: false);
      r.engine.poke();
      await r.seekTo(10000);
      expect(r.engine.upcoming.value, isNull);
    });

    test('turning transitions off takes the announcement back', () async {
      final r = await Rig.make();
      await r.seekTo(10000);
      expect(r.engine.upcoming.value, isNotNull);
      await r.settings.setEnabled(false);
      r.engine.poke();
      await r.seekTo(10000);
      expect(r.engine.upcoming.value, isNull);
    });

    test('nothing after this song means nothing announced', () async {
      final r = await Rig.make();
      await r.seekTo(10000);
      r.hooks.ctx = null;
      r.engine.poke();
      await r.seekTo(10001);
      expect(r.engine.upcoming.value, isNull);
    });

    test('it reports the analysed plan once both songs are measured', () async {
      final r = await Rig.make();
      await r.settings.setStyle(TransitionStyle.automix);
      await r.seekTo(10000);
      expect(r.engine.upcoming.value?.analysed, isFalse);
      r.hooks.analyses['a'] = const TrackAnalysis(
          trackId: 'a', durationMs: 100000, contentEndMs: 97000, outroStartMs: 91000);
      r.hooks.analyses['b'] = const TrackAnalysis(trackId: 'b', durationMs: 100000);
      await r.seekTo(10001);
      final u = r.engine.upcoming.value!;
      expect(u.analysed, isTrue);
      expect(u.kind, PlanKind.smart, reason: 'placed over the song\'s own outro');
      expect(u.endAtMs, 97000);
    });

    test('it is withdrawn when the session moves to the incoming song', () async {
      final r = await Rig.make();
      await r.seekTo(90000);
      await r.runUntil(() => r.decks.swaps == 1);
      expect(r.engine.upcoming.value, isNull);
    });
  });
}