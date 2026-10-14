import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/transition/audio_analyzer.dart';

/// THE ANALYSER THIS FILE PINS.
///
/// Signals are built here, so every answer is known: a drum pattern at 120 BPM
/// IS at 120 BPM, a song that stops at 31.2 s HAS content ending at 31.2 s.
///
/// What these cannot say is how the analyser does on a recording. That was
/// measured separately, on sixteen real songs of known tempo, and is the reason
/// the confidence is built the way it is (see AudioAnalyzer._beats): tempo came
/// out within 0.1 BPM on every 4/4 song checked, and the confidence correctly
/// fell below the planner's 0.55 on the songs where it did not.

const int rate = AudioAnalyzer.sampleRate;

/// A drum pattern: kick on every beat (loudest on the bar line), a snare on 2
/// and 4, hi-hats on the off-beats, and a held bass note - enough texture that
/// the pulse has to be found, not handed over.
Int16List drums({
  required double bpm,
  required double seconds,
  double offsetSeconds = 0,
  int seed = 7,
}) {
  final n = (seconds * rate).round();
  final x = Float64List(n);
  final rng = math.Random(seed);
  final beat = 60.0 / bpm;
  var k = 0;
  for (var t = offsetSeconds; t < seconds; t += beat, k++) {
    final i = (t * rate).round();
    final bar = k % 4;
    // Kick: a falling sine.
    _add(x, i, 0.55 + (bar == 0 ? 0.35 : 0.0), 0.06, (j) => math.sin(2 * math.pi * (110 - 700 * j / rate) * j / rate));
    // Snare on 2 and 4: noise.
    if (bar == 1 || bar == 3) {
      _add(x, i, 0.5, 0.07, (_) => rng.nextDouble() * 2 - 1);
    }
    // Hat on the off-beat.
    final h = ((t + beat / 2) * rate).round();
    _add(x, h, 0.18, 0.025, (_) => rng.nextDouble() * 2 - 1);
  }
  // A held bass note, so the signal is never empty between hits.
  for (var i = 0; i < n; i++) {
    x[i] += 0.08 * math.sin(2 * math.pi * 55 * i / rate);
  }
  return _pcm(x);
}

void _add(Float64List x, int start, double gain, double length,
    double Function(int j) shape) {
  final len = (length * rate).round();
  for (var j = 0; j < len && start + j < x.length; j++) {
    if (start + j < 0) continue;
    x[start + j] += gain * shape(j) * math.exp(-5.0 * j / len);
  }
}

Int16List _pcm(Float64List x) {
  var peak = 1e-9;
  for (final v in x) {
    peak = math.max(peak, v.abs());
  }
  final out = Int16List(x.length);
  for (var i = 0; i < x.length; i++) {
    out[i] = (x[i] / peak * 0.8 * 32767).round().clamp(-32768, 32767);
  }
  return out;
}

Int16List noise(double seconds, {double level = 0.3, int seed = 3}) {
  final rng = math.Random(seed);
  final n = (seconds * rate).round();
  return Int16List.fromList(List<int>.generate(
      n, (_) => ((rng.nextDouble() * 2 - 1) * level * 32767).round()));
}

Int16List tone(double seconds, {double level = 0.5, double hz = 220}) {
  final n = (seconds * rate).round();
  return Int16List.fromList(List<int>.generate(n,
      (i) => (math.sin(2 * math.pi * hz * i / rate) * level * 32767).round()));
}

Int16List join(List<Int16List> parts) {
  final out = Int16List(parts.fold(0, (a, p) => a + p.length));
  var o = 0;
  for (final p in parts) {
    out.setRange(o, o + p.length, p);
    o += p.length;
  }
  return out;
}

Int16List silence(double seconds) => Int16List((seconds * rate).round());

/// A tone that dies away exponentially over [seconds].
Int16List decay(double seconds, {double level = 0.5}) {
  final n = (seconds * rate).round();
  return Int16List.fromList(List<int>.generate(n, (i) {
    final env = math.pow(10, -3.5 * i / n); // -70 dB over the whole tail
    return (math.sin(2 * math.pi * 220 * i / rate) * level * env * 32767).round();
  }));
}

void main() {
  group('tempo', () {
    for (final bpm in <double>[90, 120, 128, 140, 174]) {
      test('finds $bpm BPM and trusts it', () {
        final g = AudioAnalyzer.beatGrid(drums(bpm: bpm, seconds: 45))!;
        // Above ~160 a listener can feel the same pulse at half the speed, and
        // so can the prior; the planner folds octaves (alignTempoOctave), so
        // either reading is a correct one. A 3:2 reading never is.
        final octave = bpm > 160 ? bpm / 2 : bpm;
        final err = math.min((g.bpm - bpm).abs(), (g.bpm - octave).abs());
        expect(err, lessThan(0.8), reason: 'a steady pulse is exact');
        expect(g.confidence, greaterThan(0.55),
            reason: 'and clear enough for the planner to act on');
        expect(g.agreement, greaterThan(0.9));
      });
    }

    test('beats are one period apart and bars are four beats', () {
      final g = AudioAnalyzer.beatGrid(drums(bpm: 120, seconds: 45))!;
      for (var i = 1; i < g.beatsMs.length; i++) {
        expect(g.beatsMs[i] - g.beatsMs[i - 1], closeTo(500, 12));
      }
      expect(g.downbeatsMs.length, closeTo(g.beatsMs.length / 4, 1));
      for (var i = 1; i < g.downbeatsMs.length; i++) {
        expect(g.downbeatsMs[i] - g.downbeatsMs[i - 1], closeTo(2000, 30));
      }
    });

    test('bar lines are where the kick is loudest', () {
      // The truth: bar lines at 0, 2000, 4000... (the loud kick).
      final g = AudioAnalyzer.beatGrid(drums(bpm: 120, seconds: 45))!;
      // Whatever constant latency the onset detector has, it is the SAME for
      // every bar, so bar lines must sit at a fixed offset modulo the bar.
      final offsets = [for (final d in g.downbeatsMs.take(12)) d % 2000];
      final spread = offsets.reduce(math.max) - offsets.reduce(math.min);
      expect(spread, lessThan(60));
      // And that offset is the detector's latency (tens of ms), not half a bar.
      final off = offsets.first;
      expect(math.min(off, 2000 - off), lessThan(120),
          reason: 'bar lines land on the loud kick, not on beat 2 or 3');
    });

    test('shifting the music shifts the grid by the same amount', () {
      final a = AudioAnalyzer.beatGrid(drums(bpm: 120, seconds: 45))!;
      final b = AudioAnalyzer.beatGrid(
          drums(bpm: 120, seconds: 45, offsetSeconds: 0.137))!;
      var d = (b.beatsMs.first - a.beatsMs.first) % 500;
      if (d > 250) d -= 500;
      expect(d, closeTo(137, 25),
          reason: 'phase is what bar-aligned joins are built on');
    });

    test('noise has no pulse and says so', () {
      final g = AudioAnalyzer.beatGrid(noise(45));
      expect(g == null || g.confidence < 0.55, isTrue,
          reason: 'a wrong grid is worse than none');
    });

    test('a steady tone has no pulse and says so', () {
      final g = AudioAnalyzer.beatGrid(tone(45));
      expect(g == null || g.confidence < 0.55, isTrue);
    });

    test('too little music gives no grid', () {
      expect(AudioAnalyzer.beatGrid(drums(bpm: 120, seconds: 10)), isNull);
    });

    test('a pulse that changes tempo is not trusted as one', () {
      final mixed = join([
        drums(bpm: 100, seconds: 25),
        drums(bpm: 150, seconds: 25),
      ]);
      final g = AudioAnalyzer.beatGrid(mixed)!;
      expect(g.confidence, lessThan(0.8),
          reason: 'half the song disagrees with the other half');
    });
  });

  group('shape', () {
    test('finds where the music starts and where it stops', () {
      final a = AudioAnalyzer.analyze(
        join([silence(3.0), drums(bpm: 120, seconds: 30), silence(4.0)]),
        trackId: 't',
        durationMs: 37000,
      );
      expect(a.audibleStartMs, closeTo(3000, 150));
      expect(a.contentEndMs, closeTo(33000, 250));
      expect(a.outroStartMs, 0, reason: 'it stops dead; there is no decay');
    });

    test('recognises a closing decay as an outro', () {
      final a = AudioAnalyzer.analyze(
        join([tone(20, level: 0.6), decay(8)]),
        trackId: 't',
        durationMs: 28000,
      );
      expect(a.outroStartMs, inInclusiveRange(20000, 24500));
      expect(a.contentEndMs, greaterThan(a.outroStartMs));
      expect(a.contentEndMs, lessThanOrEqualTo(28100));
    });

    test('a quiet ending that is just a few moments is not an outro', () {
      final a = AudioAnalyzer.analyze(
        join([tone(20, level: 0.6), tone(1.5, level: 0.04)]),
        trackId: 't',
        durationMs: 21500,
      );
      expect(a.outroStartMs, 0);
    });

    test('a fade-in is not mistaken for silence', () {
      final a = AudioAnalyzer.analyze(
        join([decay(4).reversed.toList().toInt16(), tone(20, level: 0.5)]),
        trackId: 't',
        durationMs: 24000,
      );
      expect(a.audibleStartMs, lessThan(3500));
    });

    test('silence and the very short give an empty analysis, not a crash', () {
      final a = AudioAnalyzer.analyze(silence(30), trackId: 't', durationMs: 30000);
      expect(a.bpm, 0);
      expect(a.beatsMs, isEmpty);
      final b = AudioAnalyzer.analyze(tone(1), trackId: 't', durationMs: 1000);
      expect(b.contentEndMs, 0);
    });

    test('carries the song\'s own duration, not the decoded length', () {
      final a = AudioAnalyzer.analyze(tone(30), trackId: 'x', durationMs: 31234);
      expect(a.durationMs, 31234);
      expect(a.trackId, 'x');
    });

    test('analyseInput is the isolate entry and agrees with analyze', () {
      final pcm = drums(bpm: 128, seconds: 30);
      final a = analyzeInput(
          AnalysisInput(pcm: pcm, trackId: 'i', durationMs: 30000));
      final b = AudioAnalyzer.analyze(pcm, trackId: 'i', durationMs: 30000);
      expect(a.bpm, b.bpm);
      expect(a.beatsMs, b.beatsMs);
    });
  });
}

extension on List<int> {
  Int16List toInt16() => Int16List.fromList(this);
}
