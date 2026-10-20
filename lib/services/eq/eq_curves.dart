// lib/services/eq/eq_curves.dart
//
// The maths of the equalizer, kept free of Flutter and of the platform so it can
// be tested to the decibel.
//
//   * Presets are defined as ten ISO-style control points and RESAMPLED onto
//     whatever bands the phone has (5 is typical, 10 exists), interpolating in
//     log-frequency - because octaves, not hertz, are what the ear measures.
//   * The response curve drawn on screen is the sum, in dB, of one RBJ peaking
//     filter per band, using each band's real width. It is an estimate of what
//     the DSP does, and the UI says so.
//   * Headroom: boosting a band raises the signal and can clip. The cure is to
//     lower everything by the biggest boost.

import 'dart:math' as math;

import 'eq_models.dart';

/// The ten control frequencies every preset is written against.
const List<double> kIsoHz = [
  31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000, //
];

/// Interpolates `(freqs, db)` at [hz], linear in log-frequency, flat beyond
/// the ends.
double interpolateDb(List<double> freqs, List<double> db, double hz) {
  assert(freqs.length == db.length && freqs.isNotEmpty);
  if (hz <= freqs.first) return db.first;
  if (hz >= freqs.last) return db.last;
  var i = 0;
  while (i < freqs.length - 1 && freqs[i + 1] < hz) {
    i++;
  }
  final a = math.log(freqs[i]);
  final b = math.log(freqs[i + 1]);
  final t = (math.log(hz) - a) / (b - a);
  // Smoothstep rather than a straight line: a preset reads as a curve, and two
  // adjacent bands should not make a visible kink at the control point.
  final s = t * t * (3 - 2 * t);
  return db[i] + (db[i + 1] - db[i]) * s;
}

/// Ten ISO-point gains resampled onto [centersHz].
List<double> resampleTenBand(List<double> tenBandDb, List<double> centersHz) {
  assert(tenBandDb.length == kIsoHz.length);
  return [for (final c in centersHz) _round(interpolateDb(kIsoHz, tenBandDb, c))];
}

/// Arbitrary (Hz, dB) control points resampled onto [centersHz].
List<double> resamplePoints(
    List<(double, double)> points, List<double> centersHz) {
  if (points.isEmpty) return List<double>.filled(centersHz.length, 0);
  final f = [for (final p in points) p.$1];
  final d = [for (final p in points) p.$2];
  return [for (final c in centersHz) _round(interpolateDb(f, d, c))];
}

/// Rounded to the 0.5 dB the sliders move in, so a resampled preset lands on
/// values the listener could have set by hand.
double _round(double v) => (v * 2).round() / 2;

/// The curve to draw: the summed response of the bands at [gains], sampled at
/// [count] log-spaced frequencies from [minHz] to [maxHz].
List<(double, double)> responseCurve(
  List<EqBand> bands,
  List<double> gains, {
  int count = 96,
  double minHz = 20,
  double maxHz = 20000,
}) {
  final out = <(double, double)>[];
  final lo = math.log(minHz);
  final hi = math.log(maxHz);
  for (var i = 0; i < count; i++) {
    final hz = math.exp(lo + (hi - lo) * i / (count - 1));
    out.add((hz, responseDb(hz, bands, gains)));
  }
  return out;
}

/// Gain in dB at [hz] of the bands at [gains] (an RBJ peaking filter each).
double responseDb(double hz, List<EqBand> bands, List<double> gains) {
  var total = 0.0;
  for (var i = 0; i < bands.length && i < gains.length; i++) {
    if (gains[i] == 0) continue;
    total += _peakingDb(hz, bands[i], gains[i]);
  }
  return total;
}

const double _fs = 48000;

double _peakingDb(double hz, EqBand band, double gainDb) {
  final f0 = band.centerHz;
  final width = (band.highHz - band.lowHz).abs();
  // Bandwidth-Q. A device that reports a zero-width band gets a sane default.
  final q = width <= 0 ? 1.0 : (f0 / width).clamp(0.3, 4.0);
  final a = math.pow(10, gainDb / 40).toDouble();
  final w0 = 2 * math.pi * f0 / _fs;
  final alpha = math.sin(w0) / (2 * q);
  final cosW0 = math.cos(w0);
  final b0 = 1 + alpha * a;
  final b1 = -2 * cosW0;
  final b2 = 1 - alpha * a;
  final a0 = 1 + alpha / a;
  final a1 = -2 * cosW0;
  final a2 = 1 - alpha / a;

  final w = 2 * math.pi * hz / _fs;
  final c1 = math.cos(w), s1 = math.sin(w);
  final c2 = math.cos(2 * w), s2 = math.sin(2 * w);
  // |B(e^jw)|^2 and |A(e^jw)|^2 with e^{-jkw} = cos(kw) - j sin(kw).
  final nr = b0 + b1 * c1 + b2 * c2;
  final ni = -(b1 * s1 + b2 * s2);
  final dr = a0 + a1 * c1 + a2 * c2;
  final di = -(a1 * s1 + a2 * s2);
  final mag2 = (nr * nr + ni * ni) / (dr * dr + di * di);
  return 10 * math.log(mag2) / math.ln10;
}

/// How far everything must come down so the boosted bands cannot clip.
///
/// The loudest thing the equalizer does to the signal is its biggest boost plus
/// the pre-amp; anything over 0 dB is headroom that has to be paid back.
double headroomDb(List<double> gains, double preampDb) {
  if (gains.isEmpty) return math.max(0, preampDb);
  final peak = gains.reduce(math.max) + preampDb;
  return peak > 0 ? peak : 0;
}

/// The level each band is actually set to: gain + pre-amp − headroom, clamped to
/// what the device accepts.
List<double> effectiveLevels(
  List<double> gains, {
  required double preampDb,
  required bool autoHeadroom,
  required double minDb,
  required double maxDb,
}) {
  final cut = autoHeadroom ? headroomDb(gains, preampDb) : 0.0;
  return [
    for (final g in gains) (g + preampDb - cut).clamp(minDb, maxDb).toDouble()
  ];
}

/// "60 Hz", "3.6 kHz", "14 kHz".
String formatHz(double hz) {
  if (hz >= 1000) {
    final k = hz / 1000;
    final s = k >= 10 || k == k.roundToDouble()
        ? k.round().toString()
        : k.toStringAsFixed(1);
    return '$s kHz';
  }
  return '${hz.round()} Hz';
}

/// The compact axis label: "60", "3.6k", "14k".
String formatHzShort(double hz) {
  if (hz >= 1000) {
    final k = hz / 1000;
    final s = k >= 10 || k == k.roundToDouble()
        ? k.round().toString()
        : k.toStringAsFixed(1);
    return '${s}k';
  }
  return hz.round().toString();
}

/// "+3.5 dB", "−2 dB", "0 dB" (a real minus sign, not a hyphen).
String formatDb(double db, {bool unit = true}) {
  final v = (db * 2).round() / 2;
  final body = v == v.roundToDouble() ? v.abs().toStringAsFixed(0) : v.abs().toStringAsFixed(1);
  final sign = v > 0 ? '+' : (v < 0 ? '\u2212' : '');
  return '$sign$body${unit ? ' dB' : ''}';
}

/// Snaps to the 0.5 dB grid and the device range.
double snapDb(double db, double minDb, double maxDb) =>
    ((db * 2).round() / 2).clamp(minDb, maxDb).toDouble();
