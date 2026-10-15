// lib/services/transition/phase_lock.dart
//
// Keeps a beat-matched mix on the beat after it has started.
//
// WHY IT IS NEEDED
//
// The planner puts a bar line of the incoming song on a bar line of the
// outgoing one: it picks `startAt` in the outgoing song and `cue` in the
// incoming one. The engine can only ask for the incoming deck to PLAY when the
// outgoing position reaches `startAt`; the incoming audio then begins some tens
// of milliseconds later (the timer tick, the platform-channel call, the decoder
// starting), and that delay differs from mix to mix. Two kicks 40 ms apart sound
// like a flam, not a groove, and it stays that way for the whole overlap.
//
// WHAT IT DOES
//
// It reads both decks' positions, works out how far the incoming song is from
// where the plan wants it, and trims the incoming deck's SPEED by a fraction of
// a percent until the error is gone. A speed trim (rather than a seek) because
// a seek is a glitch and a 1 % tempo change is not audible; the time stretch is
// already pitch-preserving. The trim is small, slow, and bounded:
//
//   * it waits [warmupMs] for the incoming deck to actually be playing, because
//     a deck's position is not trustworthy in its first instants;
//   * it acts on the median of three readings, not on one;
//   * it never trims more than [maxTrim], and aims to remove the error over
//     [horizonMs];
//   * an error over [maxErrorMs] is treated as a bad reading or a failed start,
//     not chased: the lock lets go and the mix plays as planned.
//
// WHAT IT CANNOT KNOW: whether the positions the players report are the sound
// that is coming out of the speaker (they include the output pipeline's delay
// the same way for both decks, which cancels). That has to be checked on a
// device; the mix trace the engine keeps (see MixTrace) is how.

import 'dart:math' as math;

class PhaseLock {
  PhaseLock({
    required this.startAtMs,
    required this.cueMs,
    required this.rate,
    this.userSpeed = 1.0,
  });

  /// Where in the OUTGOING song the incoming song was meant to begin.
  final int startAtMs;

  /// Where in the INCOMING song it was meant to begin.
  final int cueMs;

  /// The tempo stretch of the plan (incoming speed relative to the listener's).
  final double rate;

  final double userSpeed;

  static const int warmupMs = 300;
  static const double deadbandMs = 8.0;
  static const double maxErrorMs = 250.0;
  static const double horizonMs = 1500.0;
  static const double maxTrim = 0.03;
  static const int sampleEveryMs = 100;
  static const double trimStep = 0.0025;

  final List<double> _window = <double>[];
  int _lastSampleAt = -1 << 30;
  double _trim = 0.0;
  bool _released = false;

  /// The first and the latest median error, for the trace.
  double? firstErrorMs;
  double? lastErrorMs;
  double peakTrim = 0.0;
  int corrections = 0;

  /// The incoming deck's current speed multiplier, relative to the plan's rate.
  double get trim => _trim;

  /// The lock gave up on this mix (the error was implausible).
  bool get released => _released;

  /// How far the incoming song is BEHIND where the plan wants it, in ms of the
  /// outgoing song's time (positive: late; negative: early). With both decks
  /// at the same wall-clock time since the start:
  ///   outgoing has advanced  outPos - startAt
  ///   incoming has advanced  (inPos - cue) / rate   (in outgoing-song time)
  double errorMs(int outPosMs, int inPosMs) =>
      (outPosMs - startAtMs) - (inPosMs - cueMs) / rate;

  /// Feed one reading. Returns the incoming deck's new speed multiplier relative
  /// to the plan's rate (1.0 = as planned), or null when nothing should change.
  double? update({
    required int wallMs,
    required int outPosMs,
    required int inPosMs,
  }) {
    if (_released) return null;
    if (wallMs - _lastSampleAt < sampleEveryMs) return null;
    if ((inPosMs - cueMs) < warmupMs * rate) return null;
    _lastSampleAt = wallMs;

    _window.add(errorMs(outPosMs, inPosMs));
    if (_window.length > 3) _window.removeAt(0);
    if (_window.length < 3) return null;

    final sorted = [..._window]..sort();
    final err = sorted[1];
    firstErrorMs ??= err;
    lastErrorMs = err;

    if (err.abs() > maxErrorMs) {
      _released = true;
      return _setTrim(0.0);
    }

    final target = err.abs() <= deadbandMs
        ? 0.0
        : (err / (horizonMs * userSpeed)).clamp(-maxTrim, maxTrim);
    return _setTrim(target);
  }

  double? _setTrim(double target) {
    final q = (target / trimStep).round() * trimStep;
    if ((q - _trim).abs() < trimStep / 2) return null;
    _trim = q;
    peakTrim = math.max(peakTrim, q.abs());
    corrections++;
    return 1.0 + _trim;
  }
}
