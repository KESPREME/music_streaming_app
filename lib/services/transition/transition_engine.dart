// lib/services/transition/transition_engine.dart
//
// The state machine that performs a transition on the two decks.
//
//   idle ──(plan says "arm now")──> arming ──(incoming ready, start reached)──>
//   fading ──(p >= 0.5: HANDOFF)──> fading ──(p >= 1)──> idle
//
//   any of arming/fading ──(skip, seek, new window)──> bailing ──> idle
//
// DESIGN RULES (each one is a bug BitChord, which ships this design, hit first)
//
//  * The standby deck carries the INCOMING song only, started at its cue. The
//    decks never hold the same audio, so there is nothing to align and nothing
//    is rendered twice. The handoff is a role swap at the midpoint, not a seek.
//  * Progress comes from PLAYER POSITIONS, never from a wall clock. A pause
//    freezes the fade by itself; a stall cannot run the outgoing song to silence
//    on a timer.
//  * A pressed "next" is not a transition. Crossfade is a property of songs
//    RUNNING OUT; blending a manual skip leaves the song you just rejected
//    audible over the one you asked for. Anything the listener does (skip, seek,
//    a new window) abandons the mix with a short ramp, not a cut.
//  * Nothing wakes the CPU mid-song. In idle the engine sleeps until shortly
//    before it is needed (a one-shot timer), and every event that could change
//    the answer - play/pause, a new track, a settings change, analysis landing -
//    calls [poke].
//  * A missed crossfade is acceptable; a broken one is not. If the incoming deck
//    is not ready in time, the engine steps aside and the songs join as they
//    always did.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' show IndexedAudioSource;

import 'fade_curves.dart';
import 'level_plan.dart';
import 'phase_lock.dart';
import 'track_analysis.dart';
import 'transition_planner.dart';
import 'transition_settings.dart';

enum TransitionPhase { idle, arming, fading, bailing, sleepFade }

/// What one transition did, for the diagnostics card and the log.
///
/// The audio cannot be heard from here, so this is the engine's account of
/// itself: what it planned, how late it started, how far off the beat the
/// incoming song was and what it did about it, and how regular its own ticks
/// were. Those are the numbers that say whether a mix that sounded wrong was
/// planned wrong or performed wrong.
@immutable
class MixTrace {
  const MixTrace({
    required this.plan,
    required this.level,
    required this.fadeMs,
    required this.startedLateMs,
    required this.completed,
    required this.ticks,
    required this.maxTickGapMs,
    this.firstPhaseErrorMs,
    this.lastPhaseErrorMs,
    this.peakTrim = 0.0,
    this.phaseReleased = false,
  });

  final TransitionPlan plan;
  final LevelPlan level;

  /// The overlap actually performed (a late start shortens it).
  final int fadeMs;

  /// How far past the planned start the incoming song was started.
  final int startedLateMs;

  /// The mix reached its end (as opposed to being abandoned).
  final bool completed;

  /// Gain updates made, and the longest gap between two of them (the engine
  /// asks for 30 ms; a gap of hundreds means the UI isolate was busy).
  final int ticks;
  final int maxTickGapMs;

  /// Beat-matched mixes only: the incoming song's distance from the beat grid
  /// when first measured and when last measured, in ms (positive = late).
  final double? firstPhaseErrorMs;
  final double? lastPhaseErrorMs;

  /// The largest speed trim the phase lock applied (fraction, 0.01 = 1 %).
  final double peakTrim;

  /// The lock gave up (its readings were implausible).
  final bool phaseReleased;

  @override
  String toString() => 'MIX_TRACE ${plan.kind.name} (${plan.reason}) '
      'fade=${fadeMs}ms late=${startedLateMs}ms rate=${plan.incomingRate} '
      '$level ticks=$ticks maxGap=${maxTickGapMs}ms '
      'phase=${firstPhaseErrorMs?.toStringAsFixed(0)}->${lastPhaseErrorMs?.toStringAsFixed(0)}ms '
      'trim=${(peakTrim * 100).toStringAsFixed(2)}%'
      '${phaseReleased ? ' (lock released)' : ''} '
      '${completed ? 'completed' : 'abandoned'}';
}

/// What the engine intends to do at the end of the current song, as far as it
/// can tell now. The scrubber draws it as a mark, and the queue names it between
/// the playing song and the next one.
@immutable
class UpcomingMix {
  const UpcomingMix({
    required this.currentId,
    required this.nextId,
    required this.durationMs,
    required this.kind,
    required this.reason,
    this.startAtMs = 0,
    this.endAtMs = 0,
    this.incomingRate = 1.0,
    this.analysed = false,
  });

  final String currentId;
  final String nextId;

  /// The length of the playing song this was planned against.
  final int durationMs;

  final PlanKind kind;
  final String reason;
  final int startAtMs;
  final int endAtMs;
  final double incomingRate;

  /// Both songs had been analysed when this was planned.
  final bool analysed;

  bool get isNone => kind == PlanKind.none;
  bool get isMix => kind == PlanKind.smart || kind == PlanKind.beatmatched;
  int get fadeMs => endAtMs - startAtMs;

  @override
  bool operator ==(Object other) =>
      other is UpcomingMix &&
      other.currentId == currentId &&
      other.nextId == nextId &&
      other.durationMs == durationMs &&
      other.kind == kind &&
      other.reason == reason &&
      other.startAtMs == startAtMs &&
      other.endAtMs == endAtMs &&
      other.incomingRate == incomingRate &&
      other.analysed == analysed;

  @override
  int get hashCode => Object.hash(currentId, nextId, durationMs, kind, reason,
      startAtMs, endAtMs, incomingRate, analysed);
}

/// What the UI needs to move in step with the audio.
@immutable
class TransitionUiState {
  const TransitionUiState({
    this.phase = TransitionPhase.idle,
    this.progress = 0.0,
    this.outgoingId,
    this.incomingId,
    this.isMix = false,
    this.handedOff = false,
  });

  static const TransitionUiState idle = TransitionUiState();

  final TransitionPhase phase;

  /// 0..1 across the overlap, the same number that drives the audio gains.
  final double progress;
  final String? outgoingId;
  final String? incomingId;

  /// AutoMix is genuinely mixing (not a plain fade) - worth announcing.
  final bool isMix;

  /// The session has already moved to the incoming song.
  final bool handedOff;

  bool get isFading => phase == TransitionPhase.fading;

  @override
  bool operator ==(Object other) =>
      other is TransitionUiState &&
      other.phase == phase &&
      other.progress == progress &&
      other.outgoingId == outgoingId &&
      other.incomingId == incomingId &&
      other.isMix == isMix &&
      other.handedOff == handedOff;

  @override
  int get hashCode =>
      Object.hash(phase, progress, outgoingId, incomingId, isMix, handedOff);
}

/// The pair, as the engine sees it.
abstract class TransitionDecks {
  Duration? get activeDuration;
  Duration get activePosition;
  bool get activePlaying;
  String? get currentId;
  double get userSpeed;

  Duration get standbyPosition;
  bool get standbyAlive;

  Future<void> prepareStandby(IndexedAudioSource source,
      {required Duration cue, required double rate});
  void playStandby();
  void setGains({required double active, required double standby});
  void mirror();
  Future<void> swap();
  Future<void> retireStandby();
  /// Back to plain playback: full gain and, unless [resetSpeed] is false, the
  /// listener's own speed (the engine walks a stretched song back itself).
  Future<void> settleActive({bool resetSpeed = true});
  Future<void> setActiveRate(double rate);

  /// Sets the standby deck's speed relative to the listener's own (1.0 = theirs).
  Future<void> setStandbyRate(double rate);
}

@immutable
class TransitionContext {
  const TransitionContext({
    required this.currentId,
    required this.nextId,
    this.nextDurationMs = 0,
    this.albumSequential = false,
    this.repeatOne = false,
    this.casting = false,
  });

  final String currentId;
  final String nextId;
  final int nextDurationMs;
  final bool albumSequential;
  final bool repeatOne;
  final bool casting;
}

/// What the engine needs from the rest of the app.
abstract class TransitionHooks {
  /// The pair that is about to join, or null when nothing follows.
  TransitionContext? context();

  /// The sleep timer is set to end playback when this song ends.
  bool get stopAfterTrack;

  /// A fresh source for [trackId] that is safe to play WHILE another deck holds
  /// the same song's cache (it never writes the shared cache file).
  Future<IndexedAudioSource?> buildIncoming(String trackId);

  TrackAnalysis? analysisFor(String trackId, int durationMs);
  void requestAnalysis(String trackId);

  /// The session moved to [incomingId] (halfway through the mix).
  void onHandoff(String incomingId);

  /// The mix is over (or was abandoned): refresh anything that assumed a window.
  void onSettled({required bool completed});

  /// A sleep fade finished: stop playback.
  void onSleepFadeDone();
}

class TransitionEngine {
  TransitionEngine({
    required this.decks,
    required this.hooks,
    required this.settings,
    int Function()? nowMs,
    this.autoSchedule = true,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    settings.addListener(poke);
  }

  final TransitionDecks decks;
  final TransitionHooks hooks;
  final TransitionSettings settings;
  final int Function() _nowMs;

  /// Tests step the engine by hand.
  final bool autoSchedule;

  final ValueNotifier<TransitionUiState> ui =
      ValueNotifier<TransitionUiState>(TransitionUiState.idle);

  /// The account of the most recent transition (null before the first).
  final ValueNotifier<MixTrace?> lastMix = ValueNotifier<MixTrace?>(null);

  /// What will happen when the playing song ends (null: nothing, or unknown).
  final ValueNotifier<UpcomingMix?> upcoming = ValueNotifier<UpcomingMix?>(null);

  // Timings (ms).
  static const int armLeadMs = 4000;
  static const int armTimeoutMs = 12000;
  static const int armTickMs = 40;
  static const int fadeTickMs = 30;
  static const int bailMs = 120;
  static const double handoffAt = 0.5;
  static const int sleepFadeMs = 8000;

  TransitionPhase _phase = TransitionPhase.idle;
  TransitionPhase get phase => _phase;

  Timer? _timer;
  bool _disposed = false;
  bool _busy = false; // a swap/finish is awaiting

  // Plan cache.
  String? _planKey;
  TransitionPlan? _planCached;
  String? _blockedPair;

  // The mix in flight.
  TransitionPlan? _plan;
  TransitionContext? _ctx;
  int _token = 0;
  int _armedAt = 0;
  bool _ready = false;
  bool _failed = false;
  int _fadeStartPos = 0;
  int _fadeLen = 1;
  int _cue = 0;
  double _rate = 1.0;
  bool _handedOff = false;
  double _lastP = 0.0;
  double _gActive = 1.0;
  double _gStandby = 0.0;

  // Loudness balance, phase lock, and the account of the mix.
  LevelPlan _level = LevelPlan.none;
  PhaseLock? _lock;
  double _incomingRate = 1.0; // the incoming deck's current stretch
  int _startedLateMs = 0;
  int _ticks = 0;
  int _maxGapMs = 0;
  int _lastTickAt = 0;

  // After a mix: the louder incoming song climbs back to its own level.
  Timer? _releaseTimer;
  LevelPlan? _releasing;
  int _releaseStartedAt = 0;

  // Bail ramp.
  int _bailStartedAt = 0;
  double _bailFromActive = 1.0;
  double _bailFromStandby = 0.0;

  // Sleep fade.
  int _sleepStartedAt = 0;
  int _sleepStartPos = 0;
  int _sleepLen = sleepFadeMs;
  bool _sleepByPosition = false;

  // Tempo ease-back after a stretched mix.
  Timer? _easeTimer;
  bool _easing = false;
  double _easeFrom = 1.0;
  int _easeK = 0;

  // ── Public ────────────────────────────────────────────────────────────────

  /// Something that could change what the engine should do just happened.
  void poke() {
    if (_disposed) return;
    // Idle with nothing to watch for: stay asleep. This is what keeps a player
    // with transitions off from owning a single timer, in production and in the
    // widget tests that build the real provider.
    if (_phase == TransitionPhase.idle && !_watching) {
      _timer?.cancel();
      _timer = null;
      // Nothing to wait for, but what WOULD happen is still worth showing (a
      // paused queue names its next transition): a computation, no timer.
      _refreshUpcoming();
      return;
    }
    _reschedule(const Duration(milliseconds: 1));
  }

  /// Whether idle has anything to wait for.
  bool get _watching =>
      decks.activePlaying &&
      (settings.active || (settings.sleepFade && hooks.stopAfterTrack));

  /// The listener (or the app) is about to change what is playing.
  void bail() {
    if (_disposed) return;
    _cancelEase(reset: true);
    _cancelRelease();
    switch (_phase) {
      case TransitionPhase.idle:
      case TransitionPhase.bailing:
        return;
      case TransitionPhase.arming:
        _abort('bail');
        return;
      case TransitionPhase.sleepFade:
        _cancelSleepFade();
        return;
      case TransitionPhase.fading:
        _phase = TransitionPhase.bailing;
        _bailStartedAt = _nowMs();
        _bailFromActive = _gActive;
        _bailFromStandby = _gStandby;
        _publish(phase: TransitionPhase.bailing);
        _reschedule(const Duration(milliseconds: fadeTickMs));
    }
  }

  /// Fades the song out over [duration] and then stops. Used by the sleep timer.
  void fadeOutNow({Duration duration = const Duration(milliseconds: sleepFadeMs)}) {
    if (_disposed) return;
    if (_phase != TransitionPhase.idle) bail();
    _beginSleepFade(byPosition: false, lengthMs: duration.inMilliseconds);
  }

  void cancelSleepFade() => _cancelSleepFade();

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _easeTimer?.cancel();
    _releaseTimer?.cancel();
    settings.removeListener(poke);
    ui.dispose();
    lastMix.dispose();
    upcoming.dispose();
  }

  // ── The step ──────────────────────────────────────────────────────────────

  /// One step of whichever phase is current. Public so tests can drive it.
  void tick() {
    if (_disposed) return;
    Duration? next;
    switch (_phase) {
      case TransitionPhase.idle:
        next = _tickIdle();
      case TransitionPhase.arming:
        next = _tickArming();
      case TransitionPhase.fading:
        next = _tickFading();
      case TransitionPhase.bailing:
        next = _tickBailing();
      case TransitionPhase.sleepFade:
        next = _tickSleepFade();
    }
    _reschedule(next);
  }

  void _reschedule(Duration? after) {
    _timer?.cancel();
    _timer = null;
    if (!autoSchedule || _disposed || after == null) return;
    _timer = Timer(after, tick);
  }

  // ── Idle ──────────────────────────────────────────────────────────────────

  Duration? _tickIdle() {
    final dur = decks.activeDuration;
    if (dur == null || dur <= Duration.zero) return const Duration(seconds: 2);
    if (!decks.activePlaying) return null; // poke() on play

    final durMs = dur.inMilliseconds;
    final pos = decks.activePosition.inMilliseconds;
    final speed = decks.userSpeed <= 0 ? 1.0 : decks.userSpeed;

    // The sleep timer ending the song comes first: it needs no next song.
    if (hooks.stopAfterTrack && settings.sleepFade) {
      final len = math.min(sleepFadeMs, (durMs * 0.33).floor());
      final startAt = durMs - TransitionPlanner.tailGuardMs - len;
      final wait = ((startAt - pos) / speed).round();
      if (wait <= 0) {
        _beginSleepFade(byPosition: true, lengthMs: len);
        return const Duration(milliseconds: fadeTickMs);
      }
      return Duration(milliseconds: wait.clamp(250, 30000));
    }

    if (!settings.active) {
      _setUpcoming(null);
      return null;
    }
    final ctx = hooks.context();
    if (ctx == null) {
      _setUpcoming(null);
      return const Duration(seconds: 5);
    }
    if (ctx.repeatOne || ctx.casting) {
      _setUpcoming(null);
      return null;
    }
    if (_blockedPair == '${ctx.currentId}>${ctx.nextId}') {
      _setUpcoming(null);
      return null;
    }

    // Both songs are measured for AutoMix (beats, outro) and for level matching
    // (loudness), which Crossfade uses too.
    if (settings.isAutomix || settings.levelMatching) {
      hooks.requestAnalysis(ctx.currentId);
      hooks.requestAnalysis(ctx.nextId);
    }
    final plan = _planFor(ctx, durMs);
    if (plan.isNone) return null;

    final remainingWall = ((plan.startAtMs - pos) / speed).round();
    if (remainingWall > armLeadMs) {
      // Nothing to do until shortly before it is needed.
      return Duration(
          milliseconds: (remainingWall - armLeadMs).clamp(250, 30000));
    }
    _startArming(plan, ctx);
    return const Duration(milliseconds: armTickMs);
  }

  TransitionPlan _planFor(TransitionContext ctx, int durMs) {
    final outgoing = hooks.analysisFor(ctx.currentId, durMs);
    final incoming = hooks.analysisFor(ctx.nextId, ctx.nextDurationMs);
    final key = '${ctx.currentId}>${ctx.nextId}|$durMs|${ctx.nextDurationMs}'
        '|${settings.planVersion}|${ctx.albumSequential}'
        '|${identityHashCode(outgoing)}|${identityHashCode(incoming)}';
    if (key == _planKey && _planCached != null) {
      _setUpcoming(_upcomingOf(ctx, durMs, _planCached!, outgoing, incoming));
      return _planCached!;
    }
    final plan = TransitionPlanner.plan(PlanRequest(
      durationMs: durMs,
      nextDurationMs: ctx.nextDurationMs,
      style: settings.style,
      crossfadeMs: settings.crossfade.inMilliseconds,
      crossfadeAlbums: settings.crossfadeAlbums,
      matchTempo: settings.matchTempo,
      albumSequential: ctx.albumSequential,
      outgoing: outgoing,
      incoming: incoming,
    ));
    _planKey = key;
    _planCached = plan;
    _setUpcoming(_upcomingOf(ctx, durMs, plan, outgoing, incoming));
    if (kDebugMode) debugPrint('TransitionEngine: $plan');
    return plan;
  }

  UpcomingMix _upcomingOf(TransitionContext ctx, int durMs, TransitionPlan plan,
          TrackAnalysis? outgoing, TrackAnalysis? incoming) =>
      UpcomingMix(
        currentId: ctx.currentId,
        nextId: ctx.nextId,
        durationMs: durMs,
        kind: plan.kind,
        reason: plan.reason,
        startAtMs: plan.startAtMs,
        endAtMs: plan.endAtMs,
        incomingRate: plan.incomingRate,
        analysed: outgoing != null && incoming != null,
      );

  void _setUpcoming(UpcomingMix? v) {
    if (_disposed) return;
    if (upcoming.value != v) upcoming.value = v;
  }

  /// Works out what the end of this song will hold, without arming anything.
  void _refreshUpcoming() {
    if (!settings.active) {
      _setUpcoming(null);
      return;
    }
    final dur = decks.activeDuration;
    final ctx = hooks.context();
    if (dur == null ||
        dur <= Duration.zero ||
        ctx == null ||
        ctx.repeatOne ||
        ctx.casting) {
      _setUpcoming(null);
      return;
    }
    _planFor(ctx, dur.inMilliseconds);
  }

  // ── Arming ────────────────────────────────────────────────────────────────

  void _startArming(TransitionPlan plan, TransitionContext ctx) {
    _cancelEase(reset: true);
    _phase = TransitionPhase.arming;
    _plan = plan;
    _ctx = ctx;
    _ready = false;
    _failed = false;
    _armedAt = _nowMs();
    final token = ++_token;
    _publish(phase: TransitionPhase.arming);
    unawaited(_prepare(token, plan, ctx));
  }

  Future<void> _prepare(
      int token, TransitionPlan plan, TransitionContext ctx) async {
    try {
      final source = await hooks.buildIncoming(ctx.nextId);
      if (token != _token) return;
      if (source == null) {
        _failed = true;
        return;
      }
      await decks.prepareStandby(
        source,
        cue: Duration(milliseconds: plan.cueMs),
        rate: plan.incomingRate,
      );
      if (token != _token) return;
      _ready = true;
    } catch (e) {
      if (token == _token) _failed = true;
      if (kDebugMode) debugPrint('TransitionEngine: arming failed: $e');
    }
  }

  Duration? _tickArming() {
    final ctx = _ctx!;
    final plan = _plan!;
    if (_failed || _nowMs() - _armedAt > armTimeoutMs) {
      _abort('arm-failed');
      return null;
    }
    if (decks.currentId != ctx.currentId) {
      _abort('track-changed');
      return null;
    }
    if (!_ready) return const Duration(milliseconds: armTickMs);

    final pos = decks.activePosition.inMilliseconds;
    if (pos >= plan.endAtMs - 1000) {
      _abort('too-late');
      return null;
    }
    if (decks.activePlaying && pos >= plan.startAtMs - 20) {
      _startFade(pos);
      return const Duration(milliseconds: fadeTickMs);
    }
    return const Duration(milliseconds: armTickMs);
  }

  // ── Fading ────────────────────────────────────────────────────────────────

  void _startFade(int pos) {
    final plan = _plan!;
    // A song still climbing back from the last mix has no business under a new
    // one; settle it so the new fade starts from full level.
    _cancelRelease();
    _fadeStartPos = pos;
    // A late start shortens the fade; it never lengthens it.
    _fadeLen = math.max(1000, math.min(plan.fadeMs, plan.endAtMs - pos));
    _cue = decks.standbyPosition.inMilliseconds;
    _rate = plan.incomingRate;
    _incomingRate = plan.incomingRate;
    _handedOff = false;
    _lastP = 0.0;
    _gActive = 1.0;
    _gStandby = 0.0;
    _startedLateMs = math.max(0, pos - plan.startAtMs);
    _ticks = 0;
    _maxGapMs = 0;
    _lastTickAt = _nowMs();

    // Loudness balance, from what is known NOW (analysis may have landed since
    // the engine armed), and the lock that keeps a beat-matched mix on the beat.
    final ctx = _ctx!;
    _level = settings.levelMatching
        ? LevelPlanner.plan(
            mix: plan,
            outgoing: hooks.analysisFor(ctx.currentId, decks.activeDuration?.inMilliseconds ?? 0),
            incoming: hooks.analysisFor(ctx.nextId, ctx.nextDurationMs),
          )
        : LevelPlan.none;
    _lock = plan.kind == PlanKind.beatmatched
        ? PhaseLock(
            startAtMs: plan.startAtMs,
            cueMs: plan.cueMs,
            rate: plan.incomingRate,
            userSpeed: decks.userSpeed <= 0 ? 1.0 : decks.userSpeed,
          )
        : null;
    decks.setGains(active: 1.0, standby: 0.0);
    decks.playStandby();
    _phase = TransitionPhase.fading;
    _publish(phase: TransitionPhase.fading, progress: 0);
  }

  Duration? _tickFading() {
    if (_busy) return const Duration(milliseconds: fadeTickMs);

    // A deck that vanished mid-mix (error, stop) must not leave the other one
    // fading into nothing.
    if (!_handedOff && !decks.standbyAlive) {
      bail();
      return const Duration(milliseconds: fadeTickMs);
    }

    decks.mirror();

    final outPos =
        (_handedOff ? decks.standbyPosition : decks.activePosition).inMilliseconds;
    final inPos =
        (_handedOff ? decks.activePosition : decks.standbyPosition).inMilliseconds;
    final pOut = (outPos - _fadeStartPos) / _fadeLen;
    final pIn = (inPos - _cue) / (_fadeLen * _rate);
    final p = math.max(_lastP, math.max(pOut, pIn).clamp(0.0, 1.0));
    _lastP = p;

    final g = mixGains(p, level: _level);
    _gActive = _handedOff ? g.incoming : g.outgoing;
    _gStandby = _handedOff ? g.outgoing : g.incoming;
    decks.setGains(active: _gActive, standby: _gStandby);
    _publish(phase: TransitionPhase.fading, progress: p);

    final now = _nowMs();
    if (_ticks > 0) _maxGapMs = math.max(_maxGapMs, now - _lastTickAt);
    _lastTickAt = now;
    _ticks++;
    _holdBeat(now, outPos, inPos);

    if (!_handedOff && p >= handoffAt) {
      unawaited(_handoff());
      return const Duration(milliseconds: fadeTickMs);
    }
    if (p >= 1.0) {
      unawaited(_finish(completed: true));
      return null;
    }
    return const Duration(milliseconds: fadeTickMs);
  }

  Future<void> _handoff() async {
    if (_busy) return;
    _busy = true;
    try {
      await decks.swap();
      _handedOff = true;
      // Roles traded: what was the incoming gain is now the active gain.
      final a = _gActive;
      _gActive = _gStandby;
      _gStandby = a;
      hooks.onHandoff(_ctx!.nextId);
      _setUpcoming(null); // it described the song that has just left
      _publish(phase: TransitionPhase.fading, progress: _lastP);
    } finally {
      _busy = false;
    }
  }

  Future<void> _finish({required bool completed}) async {
    if (_busy) return;
    _busy = true;
    final rate = _incomingRate;
    final handed = _handedOff;
    // A stretched incoming song is walked back to the listener's speed below;
    // settling must not snap it there first.
    final easing = (rate - 1.0).abs() > 1e-4 && completed;
    try {
      if (!_handedOff) {
        // Reached the end without a handoff (a very short mix): hand off now so
        // the session is on the song that is still playing.
        await decks.swap();
        _handedOff = true;
        hooks.onHandoff(_ctx!.nextId);
      }
      await decks.retireStandby();
      await decks.settleActive(resetSpeed: !easing);
    } finally {
      _busy = false;
    }
    _recordTrace(completed: completed);
    _setUpcoming(null);
    final level = _level;
    _phase = TransitionPhase.idle;
    _blockedPair = null;
    _plan = null;
    _lock = null;
    _publish(phase: TransitionPhase.idle);
    hooks.onSettled(completed: completed || handed);
    if (easing) _easeRateBack(rate);
    if (completed && level.incomingDb < 0) _startRelease(level);
    poke();
  }

  /// Keeps the incoming song on the beat: see PhaseLock.
  void _holdBeat(int now, int outPos, int inPos) {
    final lock = _lock;
    if (lock == null || lock.released) return;
    final next = lock.update(wallMs: now, outPosMs: outPos, inPosMs: inPos);
    if (next == null) return;
    _incomingRate = _rate * next;
    unawaited((_handedOff
            ? decks.setActiveRate(_incomingRate)
            : decks.setStandbyRate(_incomingRate))
        .catchError((Object _) {}));
  }

  // ── Release ───────────────────────────────────────────────────────────────

  /// A song that had to be held down to blend with a quieter one climbs back to
  /// its own level, over [LevelPlan.releaseMs], once it is playing alone.
  void _startRelease(LevelPlan level) {
    _releasing = level;
    _releaseStartedAt = _nowMs();
    decks.setGains(active: level.incomingGain, standby: 0.0);
    if (!autoSchedule) return; // tests step it by hand
    _releaseTimer?.cancel();
    _releaseTimer = Timer.periodic(
        const Duration(milliseconds: 100), (_) => releaseStep());
  }

  /// One step of the climb. Public so tests can drive it.
  void releaseStep() {
    final level = _releasing;
    if (level == null) return;
    final done = ((_nowMs() - _releaseStartedAt) / level.releaseMs).clamp(0.0, 1.0);
    final g = mixGains(1.0, level: level, incomingRelease: done).incoming;
    decks.setGains(active: g, standby: 0.0);
    if (done >= 1.0) _endRelease();
  }

  void _endRelease() {
    _releasing = null;
    _releaseTimer?.cancel();
    _releaseTimer = null;
  }

  void _cancelRelease() {
    if (_releasing == null) return;
    _endRelease();
    decks.setGains(active: 1.0, standby: 0.0);
  }
  void _recordTrace({required bool completed}) {
    final plan = _plan;
    if (plan == null || _ticks == 0) return;
    final lock = _lock;
    final trace = MixTrace(
      plan: plan,
      level: _level,
      fadeMs: _fadeLen,
      startedLateMs: _startedLateMs,
      completed: completed,
      ticks: _ticks,
      maxTickGapMs: _maxGapMs,
      firstPhaseErrorMs: lock?.firstErrorMs,
      lastPhaseErrorMs: lock?.lastErrorMs,
      peakTrim: lock?.peakTrim ?? 0.0,
      phaseReleased: lock?.released ?? false,
    );
    lastMix.value = trace;
    if (!kReleaseMode) debugPrint('$trace');
  }

  // ── Bail ──────────────────────────────────────────────────────────────────

  Duration? _tickBailing() {
    final t = ((_nowMs() - _bailStartedAt) / bailMs).clamp(0.0, 1.0);
    final a = _bailFromActive + (1.0 - _bailFromActive) * t;
    final s = _bailFromStandby * (1.0 - t);
    _gActive = a;
    _gStandby = s;
    decks.setGains(active: a, standby: s);
    if (t < 1.0) return const Duration(milliseconds: 15);
    unawaited(_endBail());
    return null;
  }

  Future<void> _endBail() async {
    if (_busy) return;
    _busy = true;
    try {
      await decks.retireStandby();
      await decks.settleActive();
    } finally {
      _busy = false;
    }
    _recordTrace(completed: false);
    _setUpcoming(null);
    _phase = TransitionPhase.idle;
    _plan = null;
    _lock = null;
    _publish(phase: TransitionPhase.idle);
    hooks.onSettled(completed: false);
    poke();
  }

  void _abort(String reason) {
    if (kDebugMode) debugPrint('TransitionEngine: abort ($reason)');
    _token++; // abandons an in-flight prepare
    final ctx = _ctx;
    if (reason != 'bail' && ctx != null) {
      // Do not retry the same pair on every tick.
      _blockedPair = '${ctx.currentId}>${ctx.nextId}';
    }
    _phase = TransitionPhase.idle;
    _plan = null;
    _publish(phase: TransitionPhase.idle);
    unawaited(decks.retireStandby());
    hooks.onSettled(completed: false);
    poke();
  }

  // ── Tempo ease-back ───────────────────────────────────────────────────────

  void _easeRateBack(double from) {
    _easeFrom = from;
    _easeK = 0;
    _easing = true;
    if (!autoSchedule) return; // tests step it by hand
    _easeTimer?.cancel();
    _easeTimer = Timer.periodic(
        const Duration(milliseconds: 500), (_) => easeStep());
  }

  /// One half-second of the walk back to the listener's speed. Public so tests
  /// can drive it.
  void easeStep() {
    if (!_easing) return;
    const steps = 12;
    _easeK++;
    final rate = _easeFrom + (1.0 - _easeFrom) * (_easeK / steps);
    unawaited(decks.setActiveRate(_easeK >= steps ? 1.0 : rate));
    if (_easeK >= steps) _endEase();
  }

  void _endEase() {
    _easing = false;
    _easeTimer?.cancel();
    _easeTimer = null;
  }

  void _cancelEase({required bool reset}) {
    if (!_easing) return;
    _endEase();
    if (reset) unawaited(decks.setActiveRate(1.0));
  }
  // ── Sleep fade ────────────────────────────────────────────────────────────

  void _beginSleepFade({required bool byPosition, required int lengthMs}) {
    _phase = TransitionPhase.sleepFade;
    _sleepByPosition = byPosition;
    _sleepLen = math.max(500, lengthMs);
    _sleepStartedAt = _nowMs();
    _sleepStartPos = decks.activePosition.inMilliseconds;
    _publish(phase: TransitionPhase.sleepFade);
    _reschedule(const Duration(milliseconds: 1));
  }

  Duration? _tickSleepFade() {
    final p = _sleepByPosition
        ? (decks.activePosition.inMilliseconds - _sleepStartPos) / _sleepLen
        : (_nowMs() - _sleepStartedAt) / _sleepLen;
    final g = fallGain(p.clamp(0.0, 1.0));
    decks.setGains(active: g, standby: 0.0);
    if (p < 1.0) return const Duration(milliseconds: fadeTickMs);
    _phase = TransitionPhase.idle;
    _publish(phase: TransitionPhase.idle);
    hooks.onSleepFadeDone();
    return null;
  }

  void _cancelSleepFade() {
    if (_phase != TransitionPhase.sleepFade) return;
    _phase = TransitionPhase.idle;
    decks.setGains(active: 1.0, standby: 0.0);
    _publish(phase: TransitionPhase.idle);
    poke();
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  void _publish({required TransitionPhase phase, double progress = 0.0}) {
    if (_disposed) return;
    final ctx = _ctx;
    ui.value = phase == TransitionPhase.idle || phase == TransitionPhase.sleepFade
        ? TransitionUiState(phase: phase)
        : TransitionUiState(
            phase: phase,
            progress: progress,
            outgoingId: ctx?.currentId,
            incomingId: ctx?.nextId,
            isMix: _plan?.isMix ?? false,
            handedOff: _handedOff,
          );
  }
}
