import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/transition/loudness.dart';
import 'package:music_streaming_app/services/transition/track_analysis.dart';

/// THE METER THIS FILE PINS.
///
/// The reference values are the standard's own: EBU Tech 3341 / ITU-R BS.1770-4
/// say a 997 Hz sine at -23 dBFS peak, in both channels, reads -23.0 LUFS. The
/// meter was also compared with `ffmpeg -af ebur128` on sixteen real songs
/// (mean error -0.23 LU, worst -0.58, through the Android decoder's resampler);
/// that is a measurement of real music and lives in the plan document, because
/// a test cannot ship the songs.

const int rate = 11025;

Int16List sine(double seconds, {double dbfs = -23.0, double hz = 997}) {
  final n = (seconds * rate).round();
  final a = math.pow(10, dbfs / 20) * 32767;
  return Int16List.fromList(List<int>.generate(
      n, (i) => (a * math.sin(2 * math.pi * hz * i / rate)).round()));
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

void main() {
  group('integrated loudness', () {
    test('the standard\'s reference: 997 Hz at -23 dBFS in both channels is -23 LUFS',
        () {
      // A centred signal: both channels carry the mid, there is no side.
      final p = Loudness.measure(sine(20), null, rate);
      expect(p.integratedLufs, closeTo(-23.0, 0.15));
    });

    test('twice the amplitude is 6 dB louder', () {
      final quiet = Loudness.measure(sine(20, dbfs: -26), null, rate);
      final loud = Loudness.measure(sine(20, dbfs: -20), null, rate);
      expect(loud.integratedLufs - quiet.integratedLufs, closeTo(6.0, 0.1));
    });

    test('a signal that is all side counts as much as one that is all mid', () {
      // L = -R: the mid is zero and the whole signal is in the side. A mono
      // downmix would call this silence; the channels are as loud as the
      // centred case.
      final s = sine(20);
      final centred = Loudness.measure(s, null, rate);
      final wide = Loudness.measure(Int16List(s.length), s, rate);
      expect(wide.integratedLufs, closeTo(centred.integratedLufs, 0.05));
      expect(wide.isMeasured, isTrue);
    });

    test('a mono source is both channels: the mid alone is the centred case', () {
      final s = sine(20);
      expect(Loudness.measure(s, null, rate).integratedLufs,
          closeTo(Loudness.measure(s, Int16List(s.length), rate).integratedLufs, 1e-9));
    });

    test('the relative gate ignores a quiet passage next to a loud one', () {
      // 10 s at -20 dBFS then 30 s at -50: the integrated loudness is the loud
      // part's, not an average that the quiet part drags down.
      final loudOnly = Loudness.measure(sine(10, dbfs: -20), null, rate);
      final mixed = Loudness.measure(
          join([sine(10, dbfs: -20), sine(30, dbfs: -50)]), null, rate);
      expect(mixed.integratedLufs, closeTo(loudOnly.integratedLufs, 0.5));
    });

    test('below the absolute gate is silence, not a very quiet song', () {
      final p = Loudness.measure(sine(20, dbfs: -85), null, rate);
      expect(p.isMeasured, isFalse);
      expect(p.integratedLufs, LoudnessProfile.silent);
      expect(Loudness.measure(Int16List(rate * 20), null, rate).isMeasured, isFalse);
    });

    test('too little audio is not measured, and does not crash', () {
      expect(Loudness.measure(Int16List(100), null, rate).isMeasured, isFalse);
      expect(Loudness.measure(Int16List(0), null, rate).secondsLufs, isEmpty);
    });

    test('the filter is derived for the sampling rate it is given', () {
      // The same tone, 997 Hz, resampled to a different rate, reads the same.
      const hz = 22050;
      final n = hz * 20;
      final a = math.pow(10, -23 / 20) * 32767;
      final s = Int16List.fromList(List<int>.generate(
          n, (i) => (a * math.sin(2 * math.pi * 997 * i / hz)).round()));
      expect(Loudness.measure(s, null, hz).integratedLufs, closeTo(-23.0, 0.15));
    });
  });

  group('the per-second profile', () {
    test('has one value per whole second, in LUFS', () {
      final p = Loudness.measure(sine(12), null, rate);
      expect(p.secondsLufs, hasLength(12));
      for (final v in p.secondsLufs) {
        expect(v, closeTo(-23.0, 0.2));
      }
    });

    test('a window is the energy average of the seconds it covers', () {
      // 5 s at -20 dBFS then 5 s at -40: the window over the join is dominated
      // by the loud half (energy, not dB, is averaged).
      final p = Loudness.measure(
          join([sine(5, dbfs: -20), sine(5, dbfs: -40)]), null, rate);
      final loud = p.windowLufs(0, 5000);
      final quiet = p.windowLufs(5000, 10000);
      final both = p.windowLufs(0, 10000);
      expect(loud - quiet, closeTo(20.0, 0.3));
      expect(both, closeTo(loud - 3.0, 0.3));
    });

    test('a window reaches into partial seconds in proportion', () {
      final p = Loudness.measure(
          join([sine(5, dbfs: -20), sine(5, dbfs: -40)]), null, rate);
      // 4.5 s - 5.5 s: half a loud second and half a quiet one.
      expect(p.windowLufs(4500, 5500), closeTo(p.windowLufs(0, 1000) - 3.0, 0.3));
    });

    test('silence inside a window does not pull its level down', () {
      final p = Loudness.measure(
          join([sine(5, dbfs: -20), Int16List(rate * 5)]), null, rate);
      // The second after the cut still rings in the filters (-46 LUFS) and is
      // counted for what it is; the four silent seconds after it are not a level.
      expect(p.windowLufs(0, 10000), closeTo(p.windowLufs(0, 5000), 1.0));
      expect(p.windowLufs(6000, 10000), LoudnessProfile.silent);
    });

    test('an empty or reversed window is silent', () {
      final p = Loudness.measure(sine(10), null, rate);
      expect(p.windowLufs(3000, 3000), LoudnessProfile.silent);
      expect(p.windowLufs(5000, 1000), LoudnessProfile.silent);
      expect(p.windowLufs(60000, 70000), LoudnessProfile.silent);
    });
  });

  group('stored with the analysis', () {
    test('loudness survives the JSON round trip to a tenth of a dB', () {
      final p = Loudness.measure(sine(8), null, rate);
      final a = TrackAnalysis(
        trackId: 't',
        durationMs: 8000,
        integratedLufs: p.integratedLufs,
        levelsLufs: p.secondsLufs,
      );
      final b = TrackAnalysis.decode(a.encode())!;
      expect(b.hasLoudness, isTrue);
      expect(b.integratedLufs, closeTo(a.integratedLufs, 1e-9));
      expect(b.levelsLufs, hasLength(a.levelsLufs.length));
      for (var i = 0; i < b.levelsLufs.length; i++) {
        expect(b.levelsLufs[i], closeTo(a.levelsLufs[i], 0.051));
      }
      expect(b.lufsBetween(2000, 6000), closeTo(a.lufsBetween(2000, 6000), 0.06));
    });

    test('an analysis from before loudness was measured is measured again', () {
      const old = TrackAnalysis(trackId: 't', durationMs: 8000, version: 1);
      expect(old.isUsable, isFalse);
      expect(old.hasLoudness, isFalse);
      expect(old.lufsBetween(0, 5000), LoudnessProfile.silent);
    });
  });
}
