// lib/services/lyrics/lyric_clock.dart
// Smooth playback position for the lyrics sweep.
//
// WHY THIS EXISTS
//
// `positionStream` is just_audio's. It emits roughly every 200ms and the gap
// between readings is uneven, so a word-by-word wipe built directly on it
// stutters. Stretching it with an interval timer is worse: a 16ms timer
// calling setState rebuilds the whole lyric list sixty times a second, which is
// how this used to work and is exactly why a sweep could not be added without
// taking the frame budget with it.
//
// So the clock is local. It runs on the display's own tick, interpolates
// between readings, and treats a reading as an occasional correction rather
// than as the source of truth. Three things follow from that:
//
//   * a smooth 60Hz sweep with no dependency on stream cadence;
//   * a rebuild scoped to the one line that is animating, because a line that
//     is outside its own window never rebuilds at all (see [isAnimating]);
//   * immunity to the readings being late, coarse or missing entirely.
//
// POSITION MODEL
//
// An anchor plus elapsed wall time, not a running total:
//
//   position = anchorMs + (now - anchorAt) * rate
//
// A reading that disagrees with the prediction by more than
// [glitchToleranceMs] is a seek or a stall rather than jitter, and those need
// a different answer - see [report].

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// How far a reading may drift from the interpolated position before it is
/// treated as a discontinuity rather than as measurement noise.
const int glitchToleranceMs = 400;

/// Playback rate is a user-visible setting, so a change in it is real signal.
/// Values outside this band are assumed to be a misread, not a speed.
const double minPlausibleRate = 0.25;
const double maxPlausibleRate = 4.0;

/// Smooth playback position for lyric highlighting.
///
/// Notifies at display rate while running. Callers that only care about the
/// current line should subscribe per-line and gate on [isAnimating] rather
/// than rebuilding a list on every tick.
class LyricClock extends ChangeNotifier {
  LyricClock({TickerProvider? vsync}) : _vsync = vsync;

  final TickerProvider? _vsync;
  final Stopwatch _stopwatch = Stopwatch()..start();

  Ticker? _ticker;
  bool _disposed = false;

  /// Position the clock was last anchored at, in milliseconds.
  double _anchorMs = 0;

  /// When that position was true, on the stopwatch timeline.
  Duration _anchorAt = Duration.zero;

  /// Multiplier applied to elapsed wall time.
  double _rate = 1.0;

  /// Whether the clock advances. False while paused.
  bool _running = false;

  /// Whole milliseconds lyrics should be drawn at.
  int _positionMs = 0;

  /// Fractional position, for callers that want sub-millisecond motion (the
  /// countdown dots read better on it). A word wipe does not need it, and
  /// waking every line for it would defeat the isolation this class buys.
  double _positionMsPrecise = 0;

  /// Where the player last said the song was, regardless of interpolation.
  int _reportedMs = 0;

  int get positionMs => _positionMs;

  double get positionMsPrecise => _positionMsPrecise;

  int get reportedMs => _reportedMs;

  bool get isRunning => _running;

  double get rate => _rate;

  /// Begin advancing.
  void start() {
    if (_running || _disposed) return;
    _running = true;
    _anchorAt = _now();
    _syncTicker();
    _notify();
  }

  /// Stop advancing, holding the current position.
  void stop() {
    if (!_running || _disposed) return;
    _anchorMs = _positionMsPrecise;
    _anchorAt = _now();
    _running = false;
    _syncTicker();
    _notify();
  }

  /// Force a discontinuity: a seek the app made, or a track change.
  void resync(int positionMs) {
    _anchorMs = positionMs.toDouble();
    _anchorAt = _now();
    _reportedMs = positionMs;
    _positionMs = positionMs;
    _positionMsPrecise = positionMs.toDouble();
    _syncTicker();
    _notify();
  }

  /// Feed a reading from the player.
  ///
  /// [rate] is the speed the song is playing at. Adopting it is what lets the
  /// sweep survive a speed change without visibly lurching.
  void report(int positionMs, {double? rate}) {
    _reportedMs = positionMs;

    if (rate != null && rate > 0 && rate.isFinite) {
      _rate = rate.clamp(minPlausibleRate, maxPlausibleRate).toDouble();
    }

    if (!_running) {
      // Paused: a reading is the whole truth, which is how a seek made while
      // paused still moves the words.
      resync(positionMs);
      return;
    }

    final drift = positionMs - _interpolate(_now());
    if (drift.abs() > glitchToleranceMs) {
      // A seek or a stall. Snap and re-anchor rather than easing, so the next
      // frame is measured from here.
      _anchorMs = positionMs.toDouble();
      _anchorAt = _now();
      _notify();
    }
    // Inside the tolerance: keep interpolating. Correcting on every reading
    // would reintroduce the stutter this class exists to remove.
  }

  Duration _now() => _stopwatch.elapsed;

  double _interpolate(Duration now) {
    final elapsedMs = (now - _anchorAt).inMicroseconds / 1000.0;
    return _anchorMs + elapsedMs * _rate;
  }

  void _syncTicker() {
    if (_running && _ticker == null && _vsync != null) {
      _ticker = _vsync!.createTicker(_onTick)..start();
    } else if (!_running) {
      _ticker?.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (_disposed) return;

    final next = _interpolate(_now());
    // Negative means the anchor is newer than the clock's idea of now, which
    // happens on the frame right after a resync. Holding is correct: the next
    // frame is not.
    if (next >= 0) {
      _positionMsPrecise = next;
      final whole = next.round();
      if (whole != _positionMs) {
        _positionMs = whole;
        _notify();
        return;
      }
    }
    // Sub-millisecond movement only. Nothing needs waking for it.
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }

  /// Whether a line animating over `[fromMs, untilMs]` needs to repaint now.
  ///
  /// The whole isolation argument rests on this: a line outside its own window
  /// never rebuilds, so a 60Hz clock costs one line's subtree rather than the
  /// list's. One millisecond of slack on each side keeps a line from popping
  /// out of existence on the frame its neighbour takes over.
  static bool isAnimating({
    required int nowMs,
    required int fromMs,
    required int untilMs,
  }) =>
      nowMs >= fromMs - 1 && nowMs <= untilMs + 1;

  /// Clamp a revealed character count into its line.
  static double clampRevealed(double chars, int lineLength) =>
      math.max(0.0, math.min(chars, lineLength.toDouble())).toDouble();
}