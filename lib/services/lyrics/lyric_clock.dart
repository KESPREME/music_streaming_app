// lib/services/lyrics/lyric_clock.dart
// The lyric playhead: a clock that runs on its own frames and is STEERED by the
// player's readings rather than set by them.
//
// Port of BitChord's `LyricClock.kt` (the engine) and `rememberLyricClock`
// (the frame loop). Two classes, split on purpose:
//
//   * [LyricPlayhead] is plain arithmetic with no Flutter in it. It can be
//     driven frame by frame from a test, which is how its rules are pinned.
//   * [LyricClock] is the driver: a [Ticker], the readings, the pause/seek
//     plumbing, and a [ChangeNotifier] that line painters listen to.
//
// THREE RULES, each the answer to a way this has gone wrong before
//
//  1. A reading is dated by when it was TAKEN, not when it was seen. The player
//     is read a few times a second and a reading can wait behind a busy frame.
//     Dated on arrival, a reading from before a half-second stall looks half a
//     second old: snapping to it rolls the words back, refusing to go back
//     freezes them, easing back rolls them a line. All three are the same
//     mistake.
//  2. Nothing but an ANNOUNCED jump moves the words backwards. The app says
//     when it seeks or changes track ([LyricClock.jump], [LyricClock.reset]);
//     that, and only that, may roll them back. A reading that disagrees without
//     one is held until the next confirms it, and a confirmed gap behind the
//     words is absorbed by running slower - never by stopping, never by
//     reversing.
//  3. Readings STEER, they do not set. The newest reading, carried forward at
//     the learned playback rate, is where the song is; the words close the gap
//     to it by running up to [_maxSlew] faster or [_maxSlow] slower.
//
// WHAT THE OLD CLOCK GOT WRONG
//
// It stopped its ticker when the song paused or the lyrics were swapped for a
// provider switch, and its restart logic only created a ticker when none
// existed - after the first stop the ticker was stopped but non-null, so
// `start()` matched neither branch and the position froze for the rest of the
// State's life. That was the "lyrics stop when I switch provider" bug, and the
// strip going dim after a pause. [_sync] now (re)starts an inactive ticker
// whenever there is a reason to run, and there is a test that says so.
//
// WHEN IT RUNS
//
// Only while the song is playing AND somebody is listening, and then at one of
// two speeds:
//
//   * FRAMES (a vsync [Ticker]) while a painter has called [LyricClock.retainFrames]:
//     a word-synced line inside its animation window, or an active gap-dots
//     row. These are the only things that change every frame.
//   * COARSE (a [LyricClock.coarsePeriod] timer) for everyone else - the
//     strip, the panel's current-line index. A line that only changes once a
//     second does not need sixty notifications a second, and a ticker that
//     fires while nothing animates keeps a frame scheduled for nothing: the
//     screen never goes idle, and pumpAndSettle never returns.
//
// Paused, or nobody listening: neither runs.

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

// ── Engine constants (LyricClock.kt, bottom of file) ─────────────────────────

/// A dated reading this far off where the song should be is not noise. Dated
/// properly, readings land within a few tens of milliseconds; this is several
/// times that, and well inside anything a listener would call out of sync.
const double _outlierMs = 250.0;

/// Extra allowance per millisecond between readings for a rate not known
/// exactly - and a wider one until it has been measured at all, or a song at
/// 1.5x looks like a run of jumps while the clock still thinks it is at 1x.
const double _rateSlack = 0.2;
const double _unsettledRateSlack = 0.75;

/// Readings refused in a row before the next is taken whatever it says.
const int _maxRejections = 2;

/// The rate is measured across readings at least [_minRateSpanMs] and at most
/// [_rateWindowMs] apart: closer, the player's own jitter is most of what the
/// measurement says; further, a real change of rate is followed too late.
const double _minRateSpanMs = 900.0;
const double _rateWindowMs = 4000.0;
const int _history = 16;

/// Before then, a rough step from each pair at least this far apart.
const double _minPairSpanMs = 300.0;
const double _pairLearning = 0.5;

/// Playback rates the clock is allowed to conclude; a measurement outside
/// these is noise.
const double minPlausibleRate = 0.25;
const double maxPlausibleRate = 4.0;

/// The gap closes with a time constant of [_correctionMs] - 60ms behind runs
/// about 10% fast - capped at [_maxSlew] faster and [_maxSlow] slower. A
/// sweep's speed changes far more than that from one word to the next, so the
/// correction never reads as anything; and at half speed at the slowest the
/// words never read as stopped.
const double _correctionMs = 600.0;
const double _maxSlew = 0.25;
const double _maxSlow = 0.5;

/// Behind by this much, the words catch up over [_glideMs] rather than by
/// running fast.
const double _glideFromMs = 300.0;

/// am-lyrics eases its rewinds over 260ms with the same smoothstep.
const double _glideMs = 260.0;

/// An announced jump further than this is taken at once rather than rolled
/// through.
const double _glideMaxMs = 2000.0;

/// A confirmed gap this wide either way is another part of the song, and is
/// jumped to.
const double _lostMs = 3000.0;

double _smoothstep(double fraction) {
  final t = fraction.clamp(0.0, 1.0).toDouble();
  return t * t * (3.0 - 2.0 * t);
}

/// The steering engine. All times are milliseconds on one monotonic timeline
/// chosen by the caller; nothing here reads a real clock.
class LyricPlayhead {
  LyricPlayhead({int startMs = 0}) : _displayedMs = startMs.toDouble();

  double _displayedMs;

  /// Where the lyrics are drawn, in song milliseconds.
  double get displayedMs => _displayedMs;

  /// The playback rate, learned from how far the song moves between readings.
  double get rate => _rate;
  double _rate = 1.0;

  /// Whether the rate has been measured across a long enough stretch to be
  /// trusted.
  bool get rateSettled => _rateSettled;
  bool _rateSettled = false;

  double _lastNowMs = double.nan;

  // The newest reading seen, to tell a new one from the same one again.
  int? _lastReportMs;
  double _lastSampledAtMs = double.nan;

  /// When playback was last seen stopped; a reading taken before then was taken
  /// standing still.
  double _heldAtMs = double.negativeInfinity;

  int? _lastDiscontinuity;
  bool _jumpPending = false;

  // The newest reading believed: where the song was, and when.
  double _anchorAtMs = double.nan;
  double _anchorMs = 0.0;

  // Readings believed since the playhead last jumped, oldest first: what the
  // rate is measured across.
  final Float64List _historyAt = Float64List(_history);
  final Float64List _historyMs = Float64List(_history);
  int _historySize = 0;

  // A reading that disagreed with the anchor, kept until the next one says
  // whether the song really moved or the reading was wrong.
  double _suspectAtMs = double.nan;
  int _suspectMs = 0;
  int _rejections = 0;

  double _glideStartMs = double.nan;
  double _glideOffsetMs = 0.0;

  /// Forget the run so far: frames stopped arriving - playback paused, or the
  /// app left the screen - and the next [frame] starts a new one.
  void restart() {
    _lastNowMs = double.nan;
    _jumpPending = false;
    _glideStartMs = double.nan;
    _clearSuspect();
  }

  /// Playback is not moving: settle on [positionMs] outright, as of [nowMs].
  /// Called again for every reading that arrives while stopped, which is how a
  /// seek made while paused still moves the words.
  void hold(int positionMs, double nowMs) {
    restart();
    _displayedMs = positionMs.toDouble();
    _heldAtMs = nowMs;
  }

  /// Adopts a playback speed the app set, so the first second at 1.5x is not
  /// spent believing it is at 1x. The history is dropped: it measured the old
  /// rate.
  void seedRate(double rate) {
    if (!rate.isFinite || rate <= 0) return;
    _rate = rate.clamp(minPlausibleRate, maxPlausibleRate).toDouble();
    _rateSettled = false;
    _historySize = 0;
  }

  /// Advance to the frame at [nowMs] and return where the lyrics should be
  /// drawn.
  ///
  /// [reportedMs] is the player's latest reading and [sampledAtMs] when it was
  /// taken, or NaN where nobody said - it is then dated by the first frame that
  /// sees it, the best that can be done. [discontinuity] is any value that
  /// changes when the playhead jumps on purpose; only its changing matters.
  int frame(
    double nowMs,
    int reportedMs,
    double sampledAtMs,
    int discontinuity,
  ) {
    final firstOfRun = _lastNowMs.isNaN;
    if (discontinuity != _lastDiscontinuity) {
      if (_lastDiscontinuity != null && !firstOfRun) _jumpPending = true;
      _lastDiscontinuity = discontinuity;
    }
    final isNew = reportedMs != _lastReportMs ||
        (!sampledAtMs.isNaN && sampledAtMs != _lastSampledAtMs);
    _lastReportMs = reportedMs;
    _lastSampledAtMs = sampledAtMs;

    if (firstOfRun) {
      _lastNowMs = nowMs;
      // Taken while playback stood still - the last reading before a pause, or
      // one made during it - it is where the song still is now, however long
      // ago it was taken. Taken while playing, the song has moved on since by
      // exactly how long ago that was.
      final takenAt = (sampledAtMs.isNaN || sampledAtMs <= _heldAtMs)
          ? nowMs
          : math.min(sampledAtMs, nowMs);
      _anchor(takenAt, reportedMs);
      _displayedMs = _targetAt(nowMs);
      return _displayedMs.toInt();
    }

    // Carried up to this frame on what was known before it, and only then
    // corrected by anything new: a jump folded in first would be advanced by
    // this frame a second time.
    final dt = math.max(0.0, nowMs - _lastNowMs);
    _lastNowMs = nowMs;
    _advance(nowMs, dt);

    if (isNew) {
      // A stamp from the future is a frame clock running a hair behind the
      // reading; one from before the anchor is out of order, and says nothing
      // the anchor does not.
      final takenAt =
          sampledAtMs.isNaN ? nowMs : math.min(sampledAtMs, nowMs);
      if (takenAt >= _anchorAtMs || _jumpPending) {
        _take(nowMs, takenAt, reportedMs);
      }
    }
    return _displayedMs.toInt();
  }

  /// Folds one new reading in - or holds it back, if it disagrees with the song
  /// so far.
  void _take(double nowMs, double takenAt, int reportedMs) {
    if (_jumpPending) {
      // The reading the jump was announced with: where the song landed.
      _jumpPending = false;
      _clearSuspect();
      _anchor(takenAt, reportedMs);
      _jumpTo(nowMs);
      return;
    }
    final elapsed = takenAt - _anchorAtMs;
    if ((reportedMs - (_anchorMs + elapsed * _rate)).abs() <=
        _tolerance(elapsed)) {
      _clearSuspect();
      _anchor(takenAt, reportedMs, continues: true);
      return;
    }
    // Off with nothing announced. One reading like that is a bad reading; a
    // second agreeing with it is the song somewhere else. And a run of them,
    // however they disagree, means the picture so far is what is wrong - taken
    // rather than refused forever, which is a clock that has stopped listening.
    final sinceSuspect = takenAt - _suspectAtMs;
    final agrees = !_suspectAtMs.isNaN &&
        sinceSuspect >= 0 &&
        (reportedMs - (_suspectMs + sinceSuspect * _rate)).abs() <=
            _tolerance(sinceSuspect);
    _rejections++;
    if (agrees) {
      // The two agree with each other, so between them they are the start of
      // the song's new stretch - and its first rate measurement.
      final firstAt = _suspectAtMs;
      final first = _suspectMs;
      _clearSuspect();
      _anchor(firstAt, first);
      _anchor(takenAt, reportedMs, continues: true);
    } else if (_rejections > _maxRejections) {
      _clearSuspect();
      _anchor(takenAt, reportedMs);
      // From here [_advance] closes the gap: ahead of the words it glides
      // forward; behind them it slows down - still never backwards.
    } else {
      _suspectAtMs = takenAt;
      _suspectMs = reportedMs;
    }
  }

  /// How far a reading [elapsedMs] after the last may stray before it is
  /// doubted: a fixed allowance for the player's own noise, and a little more
  /// the longer the gap, for a rate not yet learned exactly.
  double _tolerance(double elapsedMs) =>
      _outlierMs +
      elapsedMs.abs() * (_rateSettled ? _rateSlack : _unsettledRateSlack);

  /// Believes a reading. [continues] says it carries on from the one before -
  /// the song has not jumped between them - so the two can measure the rate.
  void _anchor(double atMs, int positionMs, {bool continues = false}) {
    _anchorAtMs = atMs;
    _anchorMs = positionMs.toDouble();
    if (!continues) _historySize = 0;
    if (_historySize == _history) {
      _historyAt.setRange(0, _history - 1, _historyAt, 1);
      _historyMs.setRange(0, _history - 1, _historyMs, 1);
      _historySize--;
    }
    _historyAt[_historySize] = atMs;
    _historyMs[_historySize] = _anchorMs;
    _historySize++;
    _learnRate();
  }

  /// The rate, measured from the oldest reading within [_rateWindowMs] to the
  /// newest. Measured between neighbours half a second apart, a few
  /// milliseconds of the player's own jitter was a few percent of rate; across
  /// seconds the same jitter is a fraction of a percent, and a rate that really
  /// is changing is still followed within the window.
  void _learnRate() {
    final newest = _historySize - 1;
    if (newest < 1) return;
    var oldest = 0;
    while (oldest < newest &&
        _historyAt[newest] - _historyAt[oldest] > _rateWindowMs) {
      oldest++;
    }
    final span = _historyAt[newest] - _historyAt[oldest];
    if (span >= _minRateSpanMs) {
      _rate = ((_historyMs[newest] - _historyMs[oldest]) / span)
          .clamp(minPlausibleRate, maxPlausibleRate)
          .toDouble();
      _rateSettled = true;
      return;
    }
    // Not enough of a stretch yet: a rough step from the last two, so the first
    // second of a song at 1.5x is not spent believing it is at 1x.
    final pairSpan = _historyAt[newest] - _historyAt[newest - 1];
    if (!_rateSettled && pairSpan >= _minPairSpanMs) {
      final measured =
          ((_historyMs[newest] - _historyMs[newest - 1]) / pairSpan)
              .clamp(minPlausibleRate, maxPlausibleRate)
              .toDouble();
      _rate += (measured - _rate) * _pairLearning;
    }
  }

  void _clearSuspect() {
    _suspectAtMs = double.nan;
    _rejections = 0;
  }

  void _advance(double nowMs, double dt) {
    final target = _targetAt(nowMs);
    // What this frame moves the words by on its own, and how far from the song
    // that leaves them.
    final step = dt * _rate;
    final error = target - (_displayedMs + step);
    if (!_glideStartMs.isNaN) {
      final progress = (nowMs - _glideStartMs) / _glideMs;
      if (progress >= 1.0) {
        _displayedMs = target;
        _glideStartMs = double.nan;
      } else {
        // The offset eases out while the target keeps moving, so the glide
        // lands on a playhead that is still running.
        _displayedMs =
            target + _glideOffsetMs * (1.0 - _smoothstep(progress));
      }
    } else if (error <= -_lostMs || error >= _lostMs) {
      // Confirmed, unannounced, and far: the song is somewhere else entirely
      // and no amount of slowing down will get there.
      _displayedMs = target;
    } else if (error >= _glideFromMs) {
      _startGlide(nowMs - dt, _displayedMs - (target - step));
      _displayedMs =
          target + _glideOffsetMs * (1.0 - _smoothstep(dt / _glideMs));
    } else {
      // Behind runs fast, ahead runs slow - and slow is floored well above
      // zero, so the words never stop to wait. The share of the gap closed
      // grows with the frame but never reaches all of it, so a long frame after
      // a stall cannot carry the words past the song.
      final closing = error * (dt / (dt + _correctionMs));
      _displayedMs += step +
          closing.clamp(-_maxSlow * step, _maxSlew * step).toDouble();
    }
  }

  /// An announced jump: rolled to over [_glideMs] when it is near, taken at
  /// once when it is not.
  void _jumpTo(double nowMs) {
    final offset = _displayedMs - _targetAt(nowMs);
    if (offset.abs() > _glideMaxMs) {
      _displayedMs = _targetAt(nowMs);
      _glideStartMs = double.nan;
    } else {
      _startGlide(nowMs, offset);
    }
  }

  void _startGlide(double startMs, double offsetMs) {
    _glideStartMs = startMs;
    _glideOffsetMs = offsetMs;
  }

  /// Where the song is at [atMs]: the newest reading believed, carried forward.
  double _targetAt(double atMs) => _anchorMs + (atMs - _anchorAtMs) * _rate;
}

/// Smooth playback position for lyric highlighting.
///
/// Notifies when the whole-millisecond position changes. Painters subscribe
/// directly and gate on [isAnimating] so a line outside its own window costs a
/// comparison, not a repaint.
class LyricClock extends ChangeNotifier {
  /// [vsync] drives the frame loop; omit it and nothing ticks on its own (a
  /// test can then call [advanceFrame]). [now] replaces the monotonic time
  /// source, in milliseconds.
  LyricClock({
    TickerProvider? vsync,
    double Function()? now,
    int startMs = 0,
  })  : _vsync = vsync,
        _nowOverride = now,
        _head = LyricPlayhead(startMs: startMs),
        _positionMs = startMs,
        _reportedMs = startMs;

  final TickerProvider? _vsync;
  final double Function()? _nowOverride;
  final Stopwatch _stopwatch = Stopwatch()..start();
  final LyricPlayhead _head;

  Ticker? _ticker;
  Timer? _coarse;
  bool _disposed = false;
  bool _playing = false;

  /// Who needs EVERY frame right now (see [retainFrames]).
  final Set<Object> _frameDemand = HashSet<Object>.identity();

  int _positionMs;
  int _reportedMs;
  double _sampledAtMs = double.nan;
  int _discontinuity = 0;

  // ── Time ───────────────────────────────────────────────────────────────────
  //
  // ONE timeline for frames AND for readings. While the ticker runs it is
  // advanced by the frame clock's own elapsed time, and a reading that arrives
  // between frames is placed at "the last frame plus however much wall time
  // has passed since". With no ticker it is plain wall time.
  //
  // Why not wall time alone: frame time is what a widget test advances with
  // `pump(Duration)`, and a clock on `Stopwatch` alone does not move under fake
  // time - so nothing driven by this clock could be tested. On a device the two
  // agree to within a frame.

  double _timelineMs = 0;
  double _stopwatchAtFrameMs = 0;
  Duration _lastElapsed = Duration.zero;

  double _stopwatchMs() => _stopwatch.elapsedMicroseconds / 1000.0;

  double _nowMs() {
    final override = _nowOverride;
    if (override != null) return override();
    return _timelineMs + (_stopwatchMs() - _stopwatchAtFrameMs);
  }

  /// Carries the timeline across a gap in frames: folds the wall time since the
  /// last frame into it, so a ticker that stops and restarts never sees time
  /// stand still or run backwards.
  void _foldTimeline() {
    _timelineMs = _nowMs();
    _stopwatchAtFrameMs = _stopwatchMs();
  }

  /// Whole milliseconds lyrics should be drawn at.
  ///
  /// While a ticker is running this is the last published frame. While none is
  /// (nobody is listening yet, or the song is paused) it is the best estimate
  /// right now, so a widget that builds before its first frame still draws the
  /// right line.
  int get positionMs => _live ? _positionMs : displayedMs.toInt();

  /// Whether the playhead is being advanced right now, by frames or by the
  /// coarse timer. When it is not, the position is an extrapolation.
  bool get _live => isRunning || _coarse != null;

  /// Fractional position, for callers that want sub-millisecond motion.
  double get displayedMs {
    if (_live) return _head.displayedMs;
    if (!_playing || _sampledAtMs.isNaN) return _head.displayedMs;
    // Playing, not ticking: carry the newest reading forward by its age.
    final age = math.max(0.0, _nowMs() - _sampledAtMs);
    return _reportedMs + age * _head.rate;
  }

  /// Where the player last said the song was, regardless of interpolation.
  int get reportedMs => _reportedMs;

  /// Whether the per-frame loop is currently running.
  bool get isRunning => _ticker?.isActive == true;

  /// Whether the clock is only ticking coarsely: somebody is listening, but
  /// nobody needs every frame.
  bool get isCoarse => _coarse != null;

  /// Whether the song is advancing (not whether the ticker happens to run).
  bool get isPlaying => _playing;

  double get rate => _head.rate;

  /// Whether anything is listening. For tests that pin "this widget does not
  /// subscribe to the clock".
  @visibleForTesting
  bool get hasListenersForTest => hasListeners;

  // ── Driving it ─────────────────────────────────────────────────────────────

  /// Feed a reading from the player. Dated now: the stream delivers it within a
  /// frame of being taken, which is as close as this layer can get.
  void report(int positionMs) {
    _reportedMs = positionMs;
    _sampledAtMs = _nowMs();
    if (!_playing) {
      // Paused: a reading is the whole truth, which is how a seek made while
      // paused still moves the words.
      _head.hold(positionMs, _sampledAtMs);
      _publish(positionMs);
    }
    // Playing: the next frame folds it in (or, with nothing listening, the next
    // time somebody does).
  }

  /// The app moved the playhead on purpose - a seek, a line tap, a scrub end.
  /// Only this may roll the words backwards.
  void jump(int positionMs) {
    _discontinuity++;
    _reportedMs = positionMs;
    _sampledAtMs = _nowMs();
    if (!_live || !_playing) {
      _head.hold(positionMs, _sampledAtMs);
      _publish(positionMs);
    }
  }

  /// A new track: forget everything and sit at [positionMs].
  void reset([int positionMs = 0]) {
    _discontinuity++;
    _reportedMs = positionMs;
    _sampledAtMs = _nowMs();
    _head.hold(positionMs, _sampledAtMs);
    _publish(positionMs);
  }

  /// Playing or not. Pausing settles on exactly what is on screen, so the words
  /// stay where the listener last saw them; the next reading, which is exact
  /// when paused, then corrects it.
  void setPlaying(bool playing) {
    if (_playing == playing) return;
    if (playing) {
      _playing = true;
      _head.restart();
    } else {
      // Read BEFORE the flag flips: while playing without a ticker the position
      // is an extrapolation, and once `_playing` is false it would fall back to
      // a stale playhead.
      final at = displayedMs.round();
      _playing = false;
      final now = _nowMs();
      _reportedMs = at;
      _sampledAtMs = now;
      _head.hold(at, now);
      _publish(at);
    }
    _sync();
  }

  /// The playback speed the app set (1.0 = normal).
  void setSpeed(double speed) {
    if ((speed - _head.rate).abs() < 0.001) return;
    _head.seedRate(speed);
  }

  /// One frame, by hand. For tests and for owners without a [TickerProvider].
  @visibleForTesting
  void advanceFrame() => _onTick(Duration.zero);

  // ── Frame loop ─────────────────────────────────────────────────────────────

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _sync();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _sync();
  }

  /// Asks for EVERY frame, on behalf of [holder].
  ///
  /// A word being swept needs sixty positions a second. The strip's "which line
  /// is it" and the panel's "which line is active" need about ten. Running the
  /// vsync ticker for everyone meant a lyric view with nothing to animate - a
  /// plain line-synced song, a gap, a paused screen's neighbours - still drew a
  /// frame every 16ms for as long as the player was open: wasted battery, and a
  /// page that never went idle.
  ///
  /// So a painter holds the ticker only while it is inside its animation window
  /// (plus a short lead-in), and lets go the moment it is not. Everyone else is
  /// served by the coarse timer.
  void retainFrames(Object holder) {
    if (_frameDemand.add(holder)) _sync();
  }

  /// The counterpart of [retainFrames]. Safe to call without having retained.
  void releaseFrames(Object holder) {
    if (_frameDemand.remove(holder)) _sync();
  }

  /// How often listeners hear about the position when nobody needs every frame.
  ///
  /// 100ms is fast enough that a line change lands within a tenth of a second and
  /// a painter sees a window coming (they ask for frames 300ms ahead), and slow
  /// enough that the screen can sleep between ticks.
  static const Duration coarsePeriod = Duration(milliseconds: 100);

  /// Runs exactly the machinery there is a reason to:
  ///
  ///   * nothing, when the song is paused or nobody listens;
  ///   * the coarse timer, when somebody listens;
  ///   * the vsync ticker, when somebody listening needs every frame.
  ///
  /// THE FIX that started this: an inactive ticker is STARTED again, not merely
  /// left alone when it already exists. The old version created a ticker once and
  /// treated "I have one" as "it is running", so every stop was permanent.
  void _sync() {
    if (_disposed) return;
    final vsync = _vsync;
    final live = _playing && hasListeners && vsync != null;
    final wantFrames = live && _frameDemand.isNotEmpty;
    final wantCoarse = live && !wantFrames;
    final wasLive = _live;

    // Frames.
    if (wantFrames) {
      final ticker = _ticker ??= vsync.createTicker(_onTick);
      if (!ticker.isActive) {
        _foldTimeline();
        _lastElapsed = Duration.zero;
        if (!wasLive) _head.restart();
        ticker.start();
      }
    } else {
      final ticker = _ticker;
      if (ticker != null && ticker.isActive) {
        _foldTimeline();
        ticker.stop();
      }
    }

    // Coarse.
    if (wantCoarse) {
      if (_coarse == null) {
        if (!wasLive) _head.restart();
        _coarse = Timer.periodic(coarsePeriod, (_) => _onCoarse());
      }
    } else if (_coarse != null) {
      _coarse!.cancel();
      _coarse = null;
    }
  }

  void _onCoarse() {
    if (_disposed) return;
    _publish(_head.frame(_nowMs(), _reportedMs, _sampledAtMs, _discontinuity));
  }

  void _onTick(Duration elapsed) {
    if (_disposed) return;
    if (_nowOverride == null) {
      final step = elapsed - _lastElapsed;
      _lastElapsed = elapsed;
      if (!step.isNegative) _timelineMs += step.inMicroseconds / 1000.0;
      _stopwatchAtFrameMs = _stopwatchMs();
    }
    final ms = _head.frame(_nowMs(), _reportedMs, _sampledAtMs, _discontinuity);
    _publish(ms);
  }
  void _publish(int ms) {
    if (_disposed || ms == _positionMs) return;
    _positionMs = ms;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _coarse?.cancel();
    _coarse = null;
    _frameDemand.clear();
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }

  /// Whether a line animating over `[fromMs, untilMs]` needs to repaint now.
  ///
  /// The whole isolation argument rests on this: a line outside its own window
  /// never repaints, so a 60Hz clock costs one line rather than the list. One
  /// millisecond of slack on each side keeps a line from popping out of
  /// existence on the frame its neighbour takes over.
  static bool isAnimating({
    required int nowMs,
    required int fromMs,
    required int untilMs,
  }) =>
      nowMs >= fromMs - 1 && nowMs <= untilMs + 1;
}
