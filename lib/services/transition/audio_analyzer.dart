// lib/services/transition/audio_analyzer.dart
//
// What AutoMix measures about a song, from its audio.
//
// Pure Dart over a mono PCM signal, so it runs in an isolate, is portable to any
// platform that can decode, and is tested with signals built in the test (a click
// track at a known tempo has a known answer; a recording does not).
//
// WHAT IS MEASURED
//
//   * a level envelope (RMS, 50 ms hops) -> where the music starts, where it
//     ends, and whether it ends in a decay (an outro) or a hard stop
//   * an onset envelope (spectral flux, 23 ms hops) -> tempo, beat positions
//     and bar lines
//
// WHAT IS NOT CLAIMED
//
// The tempo and beat estimate is classic DSP (autocorrelation of onset strength,
// then a comb filter over period and phase), not a trained model. It is exact on
// steady, percussive material and honest about everything else: [beatConfidence]
// falls toward 0 for music without a clear pulse, and the planner only acts on a
// grid it trusts. A wrong answer here would be a mix that is out of time, which
// is worse than a plain crossfade - so doubt costs nothing and certainty must be
// earned.

import 'dart:math' as math;
import 'dart:typed_data';

import 'track_analysis.dart';

/// Everything the analyser needs to know about the signal it is given.
class AnalysisInput {
  const AnalysisInput({
    required this.pcm,
    required this.trackId,
    required this.durationMs,
    this.sampleRate = AudioAnalyzer.sampleRate,
  });

  /// Mono, 16-bit.
  final Int16List pcm;
  final String trackId;

  /// The duration of the SONG (from the player), not of the decoded signal.
  final int durationMs;
  final int sampleRate;
}

/// Isolate entry point ([compute] takes a top-level function).
TrackAnalysis analyzeInput(AnalysisInput input) => AudioAnalyzer.analyze(
      input.pcm,
      trackId: input.trackId,
      durationMs: input.durationMs,
      sampleRate: input.sampleRate,
    );

class AudioAnalyzer {
  const AudioAnalyzer._();

  /// The rate the decoder produces. Four minutes is about 5 MB of samples.
  static const int sampleRate = 11025;

  // Level envelope.
  static const int levelHopMs = 50;
  static const int levelWindowMs = 100;

  // Onset envelope.
  static const int fftSize = 1024;
  static const int hop = 256;

  // Tempo search.
  static const double minBpm = 60;
  static const double maxBpm = 200;

  /// The mean spectral flux per frame below which there is nothing to time.
  static const double minOnsetActivity = 15.0;

  /// Beat tracking needs enough music to see a pulse in.
  static const int minBeatSeconds = 20;

  static TrackAnalysis analyze(
    Int16List pcm, {
    required String trackId,
    required int durationMs,
    int sampleRate = AudioAnalyzer.sampleRate,
  }) {
    if (pcm.length < sampleRate * 2) {
      return TrackAnalysis(trackId: trackId, durationMs: durationMs);
    }

    final levels = _levels(pcm, sampleRate);
    final shape = _shape(levels);

    var bpm = 0.0;
    var confidence = 0.0;
    var beats = const <int>[];
    var downbeats = const <int>[];

    final seconds = pcm.length / sampleRate;
    if (seconds >= minBeatSeconds) {
      final onsets = _onsets(pcm, sampleRate);
      final grid = _beats(onsets, sampleRate);
      if (grid != null) {
        bpm = grid.bpm;
        confidence = grid.confidence;
        beats = grid.beatsMs;
        downbeats = grid.downbeatsMs;
      }
    }

    return TrackAnalysis(
      trackId: trackId,
      durationMs: durationMs,
      audibleStartMs: shape.audibleStartMs,
      outroStartMs: shape.outroStartMs,
      contentEndMs: shape.contentEndMs,
      bpm: bpm,
      beatConfidence: confidence,
      beatsMs: beats,
      downbeatsMs: downbeats,
    );
  }

  // ── Levels ────────────────────────────────────────────────────────────────

  /// dBFS of each 50 ms hop (100 ms window).
  static List<double> _levels(Int16List pcm, int rate) {
    final hopN = rate * levelHopMs ~/ 1000;
    final winN = rate * levelWindowMs ~/ 1000;
    final count = math.max(0, (pcm.length - winN) ~/ hopN + 1);
    final out = List<double>.filled(count, -120.0);
    for (var f = 0; f < count; f++) {
      final start = f * hopN;
      var sum = 0.0;
      for (var i = 0; i < winN; i++) {
        final v = pcm[start + i] / 32768.0;
        sum += v * v;
      }
      final rms = math.sqrt(sum / winN);
      out[f] = rms < 1e-6 ? -120.0 : 20 * math.log(rms) / math.ln10;
    }
    return out;
  }

  static ({int audibleStartMs, int outroStartMs, int contentEndMs}) _shape(
      List<double> db) {
    if (db.isEmpty) return (audibleStartMs: 0, outroStartMs: 0, contentEndMs: 0);

    // A loud reference that one noisy frame cannot move: the 90th percentile of
    // the frames that are not silent.
    final audible = db.where((v) => v > -70).toList()..sort();
    if (audible.isEmpty) return (audibleStartMs: 0, outroStartMs: 0, contentEndMs: 0);
    final ref = audible[(audible.length * 0.9).floor().clamp(0, audible.length - 1)];
    final threshold = math.max(-65.0, ref - 42.0);

    // First sustained sound.
    var first = 0;
    for (var i = 0; i + 2 < db.length; i++) {
      if (db[i] > threshold && db[i + 1] > threshold && db[i + 2] > threshold) {
        first = i;
        break;
      }
    }
    // Last sustained sound.
    var last = db.length - 1;
    for (var i = db.length - 1; i >= 2; i--) {
      if (db[i] > threshold && db[i - 1] > threshold && db[i - 2] > threshold) {
        last = i;
        break;
      }
    }

    // The closing decay: walk back from the last sound while the one-second
    // average stays well under the loud reference.
    const smoothFrames = 1000 ~/ levelHopMs;
    double smooth(int i) {
      final a = math.max(0, i - smoothFrames + 1);
      var s = 0.0;
      for (var k = a; k <= i; k++) {
        s += db[k];
      }
      return s / (i - a + 1);
    }

    final quiet = ref - 6.0;
    var k = last;
    final lookback = math.max(first, last - 20 * smoothFrames);
    while (k > lookback && smooth(k) <= quiet) {
      k--;
    }
    final decayFrames = last - k;
    final outroStart = decayFrames * levelHopMs >= 2500 ? (k + 1) * levelHopMs : 0;

    return (
      audibleStartMs: first * levelHopMs,
      outroStartMs: outroStart,
      contentEndMs: (last + 1) * levelHopMs,
    );
  }

  // ── Onsets ────────────────────────────────────────────────────────────────

  /// Spectral flux, full band and low band, one value per [hop] samples.
  static _Onsets _onsets(Int16List pcm, int rate) {
    final frames = (pcm.length - fftSize) ~/ hop + 1;
    final fft = _Fft(fftSize);
    final window = Float64List(fftSize);
    for (var i = 0; i < fftSize; i++) {
      window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (fftSize - 1));
    }
    const topBin = 320; // ~3.4 kHz at 11 kHz: where the pulse lives
    const lowBin = 14; // ~150 Hz: the kick
    final re = Float64List(fftSize);
    final im = Float64List(fftSize);
    final prev = Float64List(topBin);
    final full = Float64List(frames);
    final low = Float64List(frames);

    for (var f = 0; f < frames; f++) {
      final start = f * hop;
      for (var i = 0; i < fftSize; i++) {
        re[i] = pcm[start + i] / 32768.0 * window[i];
        im[i] = 0.0;
      }
      fft.transform(re, im);
      var flux = 0.0;
      var lowFlux = 0.0;
      for (var b = 1; b < topBin; b++) {
        final mag = math.log(1.0 + 100.0 * math.sqrt(re[b] * re[b] + im[b] * im[b]));
        final d = mag - prev[b];
        if (d > 0) {
          flux += d;
          if (b < lowBin) lowFlux += d;
        }
        prev[b] = mag;
      }
      full[f] = flux;
      low[f] = lowFlux;
    }
    return _Onsets(full, low, rate / hop);
  }

  // ── Beats ─────────────────────────────────────────────────────────────────

  /// The beat grid of [pcm], or null when there is too little music to tell.
  static BeatGrid? beatGrid(Int16List pcm, {int sampleRate = AudioAnalyzer.sampleRate}) =>
      pcm.length < sampleRate * minBeatSeconds
          ? null
          : _beats(_onsets(pcm, sampleRate), sampleRate);

  static BeatGrid? _beats(_Onsets onsets, int rate) {
    final n = onsets.full.length;
    final fr = onsets.frameRate;
    if (n < fr * minBeatSeconds) return null;

    // A spectrum that barely changes has no onsets, however steadily the last
    // rounding error repeats. Measured per frame: a held tone 1.7 (1.1 when
    // quiet), noise 90, sixteen real songs 83-116.
    var activity = 0.0;
    for (final v in onsets.full) {
      activity += v;
    }
    if (activity / n < minOnsetActivity) return null;

    final o = _pulseEnvelope(onsets, fr);
    var energy = 0.0;
    for (final v in o) {
      energy += v;
    }
    if (energy <= 1e-9) return null;

    final lag0 = _pulseLag(o, 0, n, fr);
    if (lag0 <= 0) return null;

    // Comb over period and phase: the grid that sits on the most onset energy.
    var bestPeriod = lag0;
    var bestPhase = 0.0;
    var bestComb = -1.0;
    for (var s = -16; s <= 16; s++) {
      final period = lag0 * (1 + s * 0.0025);
      for (var p = 0.0; p < period; p += 0.5) {
        final score = _combMean(o, period, p);
        if (score > bestComb) {
          bestComb = score;
          bestPeriod = period;
          bestPhase = p;
        }
      }
    }

    // How much more onset energy sits ON the grid than anywhere, and than
    // halfway between beats. A steady pulse is both.
    var all = 0.0;
    for (final v in o) {
      all += v;
    }
    final meanAll = all / n;
    final onBeat = bestComb;
    final offBeat = _combMean(o, bestPeriod, bestPhase + bestPeriod / 2);
    final contrastAll = (onBeat - meanAll) / (onBeat + meanAll + 1e-12);
    final contrastOff = (onBeat - offBeat) / (onBeat + offBeat + 1e-12);

    // Beat times, then bar lines: of the four possible downbeats, the one the
    // kick favours.
    final beatFrames = <double>[];
    for (var t = bestPhase; t < n - 1; t += bestPeriod) {
      beatFrames.add(t);
    }
    if (beatFrames.length < 8) return null;

    var bestOffset = 0;
    var bestKick = -1.0;
    for (var g = 0; g < 4; g++) {
      var s = 0.0;
      var c2 = 0;
      for (var k = g; k < beatFrames.length; k += 4) {
        s += _peakNear(onsets.low, beatFrames[k]);
        c2++;
      }
      final mean = c2 == 0 ? 0.0 : s / c2;
      if (mean > bestKick) {
        bestKick = mean;
        bestOffset = g;
      }
    }

    int toMs(double frame) => (frame * hop * 1000 / rate).round();
    final bpm = 60 * fr / bestPeriod;
    final agreement = _agreement(o, fr, bpm);

    // CONFIDENCE is consistency, not loudness of the pulse. Measured on real
    // recordings of known tempo: the songs whose tempo was right read the same
    // in nearly every stretch (agreement 0.8-1.0), including soft ones with a
    // weak beat; the songs whose tempo came out wrong (a 3:2 slip, a groove the
    // autocorrelation could not settle on) disagreed with themselves (0.4-0.5),
    // however strong their beat looked. So agreement leads, and a pulse that is
    // barely above the noise floor caps it.
    final confidence =
        (agreement * math.min(1.0, contrastAll / 0.45)).clamp(0.0, 1.0).toDouble();

    return BeatGrid(
      bpm: bpm,
      confidence: confidence,
      contrastAll: contrastAll,
      contrastOff: contrastOff,
      agreement: agreement,
      beatsMs: [for (final f in beatFrames) toMs(f)],
      downbeatsMs: [
        for (var k = bestOffset; k < beatFrames.length; k += 4) toMs(beatFrames[k]),
      ],
    );
  }

  /// How much the kick band is added to the full-band onsets, as a multiple of
  /// the full band's own energy.
  ///
  /// Measured, not guessed. With the full band alone, a pulse with a busy hi-hat
  /// reads at 3:2 of its tempo (a 140 BPM pattern as 93; a real song at 102 as
  /// 151) because the hats put as much on the envelope as the kicks do. The kick
  /// is what a listener taps to, so it is weighted up: at 2 the synthetic
  /// patterns read right, and that real song reads 100.6 with a confidence of
  /// 0.21, which the planner will not act on (it read 151 at 0.63, which it
  /// would have).
  static const double kickWeight = 2.0;

  /// The onset envelope the tempo is read from: full-band rises plus the kick
  /// band's, lightly blurred.
  static Float64List _pulseEnvelope(_Onsets onsets, double fr) {
    final window = (fr * 1.0).round();
    final full = _flatten(onsets.full, window);
    final low = _flatten(onsets.low, window);
    var fullSum = 0.0;
    var lowSum = 0.0;
    for (var i = 0; i < full.length; i++) {
      fullSum += full[i];
      lowSum += low[i];
    }
    final scale = lowSum > 1e-9 ? fullSum / lowSum * kickWeight : 0.0;
    final mixed = Float64List(full.length);
    for (var i = 0; i < full.length; i++) {
      mixed[i] = full[i] + scale * low[i];
    }
    return _soften(mixed);
  }
  /// The tempo of one stretch of the onset envelope, by autocorrelation alone.
  static double _segmentBpm(Float64List o, int from, int to, double fr) {
    final lag = _pulseLag(o, from, to, fr);
    return lag <= 0 ? 0 : 60 * fr / lag;
  }

  /// The beat period, in frames, of o[from..to) - 0 when there is none to find.
  ///
  /// Autocorrelation alone is fooled by a groove: a song at 102 BPM with a
  /// strong off-beat reads as 151 (3:2) because the off-beat puts a peak there.
  /// So a lag is scored by its HARMONICS too - a true beat period has peaks at
  /// two, three and four times the lag (the bar), a 3:2 impostor does not - and
  /// the winner is pinned down from its highest harmonic, which is four times as
  /// precise as the first.
  static double _pulseLag(Float64List o, int from, int to, double fr) {
    final n = to - from;
    final minLag = (fr * 60 / maxBpm).floor();
    final maxLag = (fr * 60 / minBpm).ceil();
    if (n < maxLag * 3) return 0;
    const weights = [1.0, 0.8, 0.6, 0.4];
    final limit = math.min(maxLag * weights.length + 2, n ~/ 2);

    final ac = Float64List(limit + 2);
    for (var l = minLag - 1; l <= limit + 1; l++) {
      var s = 0.0;
      for (var i = from; i + l < to; i++) {
        s += o[i] * o[i + l];
      }
      ac[l] = s / (n - l);
    }

    // The strongest of ac[c-1..c+1]: a harmonic lands near, not on, a multiple.
    double near(int c) {
      var m = 0.0;
      for (var k = c - 1; k <= c + 1; k++) {
        if (k >= 0 && k <= limit && ac[k] > m) m = ac[k];
      }
      return m;
    }

    var bestLag = -1;
    var best = -1.0;
    for (var l = minLag + 1; l < maxLag; l++) {
      if (!(ac[l] > ac[l - 1] && ac[l] >= ac[l + 1])) continue;
      var vote = 0.0;
      var weight = 0.0;
      for (var k = 1; k <= weights.length; k++) {
        if (k * l + 1 > limit) break;
        vote += weights[k - 1] * (k == 1 ? ac[l] : near(k * l));
        weight += weights[k - 1];
      }
      final bpm = 60 * fr / l;
      final x = math.log(bpm / 118) / math.ln2 / 0.85;
      final score = vote / weight * math.exp(-0.5 * x * x);
      if (score > best) {
        best = score;
        bestLag = l;
      }
    }
    if (bestLag < 0) return 0;

    // Refine on the highest harmonic that exists, then divide back down.
    var k = weights.length;
    while (k > 1 && k * bestLag + 3 > limit) {
      k--;
    }
    final centre = k * bestLag;
    var peak = centre;
    for (var j = centre - 2; j <= centre + 2; j++) {
      if (j >= 1 && j <= limit && ac[j] > ac[peak]) peak = j;
    }
    if (peak < 1 || peak >= limit) return bestLag.toDouble();
    final a = ac[peak - 1], b = ac[peak], c = ac[peak + 1];
    final d = a - 2 * b + c;
    final lag = d.abs() < 1e-12 ? peak.toDouble() : peak + 0.5 * (a - c) / d;
    return lag / k;
  }

  /// The share of 25-second stretches (every 12 s) whose own tempo is within
  /// [tolerance] of [bpm]. A steady pulse reads the same everywhere; a tempo
  /// that was an accident of one passage does not.
  static double _agreement(Float64List o, double fr, double bpm,
      {double tolerance = 0.03}) {
    final seg = (fr * 25).round();
    final step = (fr * 12).round();
    var total = 0;
    var agree = 0;
    for (var s = 0; s + seg <= o.length; s += step) {
      final b = _segmentBpm(o, s, s + seg, fr);
      if (b <= 0) continue;
      total++;
      if ((b - bpm).abs() / bpm <= tolerance) agree++;
    }
    return total == 0 ? 0.0 : agree / total;
  }

  /// Mean onset strength on a grid of [period] frames starting at [phase],
  /// read with linear interpolation.
  static double _combMean(Float64List o, double period, double phase) {
    var sum = 0.0;
    var count = 0;
    for (var t = phase; t < o.length - 1; t += period) {
      final i = t.floor();
      final f = t - i;
      sum += o[i] * (1 - f) + o[i + 1] * f;
      count++;
    }
    return count == 0 ? 0.0 : sum / count;
  }

  /// The largest value within one frame of [t].
  static double _peakNear(Float64List v, double t) {
    final i = t.round();
    var m = 0.0;
    for (var k = math.max(0, i - 1); k <= math.min(v.length - 1, i + 1); k++) {
      if (v[k] > m) m = v[k];
    }
    return m;
  }

  /// A 1-2-1 blur. An onset lands between two frames as often as on one; without
  /// this the autocorrelation peak of a lag that happens to fall mid-frame is
  /// split in two and loses to one that does not (a 140 BPM pulse read as 93).
  static Float64List _soften(Float64List v) {
    final out = Float64List(v.length);
    for (var i = 0; i < v.length; i++) {
      final a = i > 0 ? v[i - 1] : v[i];
      final b = i + 1 < v.length ? v[i + 1] : v[i];
      out[i] = 0.25 * a + 0.5 * v[i] + 0.25 * b;
    }
    return out;
  }

  /// [v] minus its local mean, rectified: what rises, not what is loud.
  static Float64List _flatten(Float64List v, int window) {
    final n = v.length;
    final out = Float64List(n);
    final half = math.max(1, window ~/ 2);
    var sum = 0.0;
    var lo = 0;
    var hi = -1;
    for (var i = 0; i < n; i++) {
      final newHi = math.min(n - 1, i + half);
      while (hi < newHi) {
        hi++;
        sum += v[hi];
      }
      final newLo = math.max(0, i - half);
      while (lo < newLo) {
        sum -= v[lo];
        lo++;
      }
      final mean = sum / (hi - lo + 1);
      final d = v[i] - mean;
      out[i] = d > 0 ? d : 0.0;
    }
    return out;
  }
}

class _Onsets {
  const _Onsets(this.full, this.low, this.frameRate);
  final Float64List full;
  final Float64List low;
  final double frameRate;
}

/// The beat grid of a song and the evidence for it.
class BeatGrid {
  const BeatGrid({
    required this.bpm,
    required this.confidence,
    required this.beatsMs,
    required this.downbeatsMs,
    this.contrastAll = 0,
    this.contrastOff = 0,
    this.agreement = 0,
  });
  final double bpm;
  final double confidence;
  final List<int> beatsMs;
  final List<int> downbeatsMs;

  /// How far above the average onset energy the beats sit (0..1).
  final double contrastAll;

  /// How far above the energy halfway BETWEEN beats they sit (0..1).
  final double contrastOff;

  /// The share of the song's stretches whose own tempo agrees with the whole's.
  final double agreement;
}

/// An in-place radix-2 FFT.
class _Fft {
  _Fft(this.n)
      : _cos = Float64List(n ~/ 2),
        _sin = Float64List(n ~/ 2),
        _rev = Int32List(n) {
    assert(n & (n - 1) == 0, 'size must be a power of two');
    for (var i = 0; i < n ~/ 2; i++) {
      _cos[i] = math.cos(2 * math.pi * i / n);
      _sin[i] = -math.sin(2 * math.pi * i / n);
    }
    final bits = (math.log(n) / math.ln2).round();
    for (var i = 0; i < n; i++) {
      var r = 0;
      for (var b = 0; b < bits; b++) {
        if (i & (1 << b) != 0) r |= 1 << (bits - 1 - b);
      }
      _rev[i] = r;
    }
  }

  final int n;
  final Float64List _cos;
  final Float64List _sin;
  final Int32List _rev;

  void transform(Float64List re, Float64List im) {
    for (var i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var size = 2; size <= n; size <<= 1) {
      final halfSize = size >> 1;
      final step = n ~/ size;
      for (var start = 0; start < n; start += size) {
        for (var k = 0; k < halfSize; k++) {
          final wr = _cos[k * step];
          final wi = _sin[k * step];
          final a = start + k;
          final b = a + halfSize;
          final tr = re[b] * wr - im[b] * wi;
          final ti = re[b] * wi + im[b] * wr;
          re[b] = re[a] - tr;
          im[b] = im[a] - ti;
          re[a] += tr;
          im[a] += ti;
        }
      }
    }
  }
}
