// lib/services/transition/loudness.dart
//
// How loud a song is, measured the way broadcasters measure it.
//
// ITU-R BS.1770-4 / EBU R128: the signal is K-weighted (a head-related high
// shelf, then a 38 Hz high-pass), its mean square is taken over 400 ms blocks
// that overlap by 75 %, and the blocks are gated - nothing under -70 LUFS, then
// nothing more than 10 LU under what is left - before they are averaged. That
// is "integrated loudness", the number Apple's Sound Check, Spotify and YouTube
// normalise to, and the number `ffmpeg -af ebur128` prints. The tests compare
// this implementation to ffmpeg's on real songs.
//
// WHAT IS DIFFERENT HERE, and what it costs:
//
//   * The input is the analyser's 11 025 Hz signal (mid and side), not the
//     master. The K-weighting is designed for any sampling rate (the
//     coefficients below are derived for [rate], not copied from the 48 kHz
//     table), but the band above 5.5 kHz is gone. How much that matters was
//     measured against ffmpeg on real songs, not assumed.
//   * Besides the integrated value it keeps a 1-second profile, so the planner
//     can ask how loud the last ten seconds of a song are - the part that is
//     actually heard during a transition - instead of how loud the whole song
//     is on average.

import 'dart:math' as math;
import 'dart:typed_data';

/// What the loudness meter reports for one song.
class LoudnessProfile {
  const LoudnessProfile({
    required this.integratedLufs,
    required this.secondsLufs,
  });

  /// Gated integrated loudness, LUFS. [silent] when there was nothing to gate.
  final double integratedLufs;

  /// Loudness of each consecutive second (ungated, 1 s blocks), LUFS.
  /// [silent] for a silent second.
  final List<double> secondsLufs;

  /// Anything at or under this is silence, not a level.
  static const double silent = -70.0;

  bool get isMeasured => integratedLufs > silent;

  /// The loudness of [fromMs, toMs) of the song: the energy average of the
  /// seconds it touches, weighted by how much of each it covers. Silence
  /// (-70) does not drag the average down below what is audible - a window of
  /// pure silence returns [silent].
  double windowLufs(int fromMs, int toMs) {
    if (secondsLufs.isEmpty || toMs <= fromMs) return silent;
    var energy = 0.0;
    var weight = 0.0;
    final first = math.max(0, fromMs ~/ 1000);
    final last = math.min(secondsLufs.length - 1, (toMs - 1) ~/ 1000);
    for (var s = first; s <= last; s++) {
      final lo = math.max(fromMs, s * 1000);
      final hi = math.min(toMs, (s + 1) * 1000);
      final w = (hi - lo) / 1000.0;
      if (w <= 0) continue;
      final l = secondsLufs[s];
      if (l <= silent) continue; // silence is not a level
      energy += w * math.pow(10, (l + 0.691) / 10);
      weight += w;
    }
    if (weight <= 0) return silent;
    return -0.691 + 10 * math.log(energy / weight) / math.ln10;
  }
}

class Loudness {
  const Loudness._();

  /// Measures a stereo signal given as MID = (L+R)/2 and SIDE = (L-R)/2.
  ///
  /// BS.1770 sums the K-weighted power of the channels. With L = M+S and
  /// R = M-S, `L^2 + R^2 = 2(M^2 + S^2)` at every sample, and the K-weighting is
  /// linear, so the sum is `2 (ms(K(M)) + ms(K(S)))` exactly - the analyser can
  /// keep the mono signal it already needs and carry the side as a second
  /// signal, rather than carrying two channels. A [side] of null is a mono
  /// source: both channels are the mid, and the sum is `2 ms(K(M))`.
  ///
  /// (The mono downmix on its own cannot do this. Measured against ffmpeg on
  /// sixteen real songs it read between 0.0 and 2.9 dB low, by how wide each
  /// mix is; with the side it reads within 0.6 dB.)
  static LoudnessProfile measure(Int16List mid, Int16List? side, int rate) {
    final blockN = rate ~/ 10; // 100 ms
    final count = mid.length ~/ blockN;
    if (count < 4) {
      return const LoudnessProfile(
          integratedLufs: LoudnessProfile.silent, secondsLufs: <double>[]);
    }

    // Mean square of the K-weighted signal, per 100 ms, both channels summed.
    final ms = _blockPower(mid, rate, blockN, count);
    if (side != null && side.length >= count * blockN) {
      final s = _blockPower(side, rate, blockN, count);
      for (var b = 0; b < count; b++) {
        ms[b] += s[b];
      }
    }
    for (var b = 0; b < count; b++) {
      ms[b] *= 2;
    }

    // 400 ms blocks, hop 100 ms.
    final blocks = <double>[];
    for (var b = 0; b + 4 <= count; b++) {
      blocks.add((ms[b] + ms[b + 1] + ms[b + 2] + ms[b + 3]) / 4);
    }
    final integrated = _gated(blocks);

    // One value per second (10 hundred-millisecond blocks), ungated.
    final seconds = <double>[];
    for (var s = 0; s + 10 <= count; s += 10) {
      var e = 0.0;
      for (var k = 0; k < 10; k++) {
        e += ms[s + k];
      }
      seconds.add(_lufs(e / 10));
    }
    return LoudnessProfile(
      integratedLufs: integrated,
      secondsLufs: seconds,
    );
  }

  static Float64List _blockPower(Int16List x, int rate, int blockN, int count) {
    final stage1 = _Biquad.preFilter(rate);
    final stage2 = _Biquad.highPass(rate);
    final ms = Float64List(count);
    for (var b = 0; b < count; b++) {
      var sum = 0.0;
      final start = b * blockN;
      for (var i = 0; i < blockN; i++) {
        final v = x[start + i] / 32768.0;
        final y = stage2.step(stage1.step(v));
        sum += y * y;
      }
      ms[b] = sum / blockN;
    }
    return ms;
  }
  static double _lufs(double meanSquare) => meanSquare <= 1e-12
      ? LoudnessProfile.silent
      : math.max(LoudnessProfile.silent,
          -0.691 + 10 * math.log(meanSquare) / math.ln10);

  /// BS.1770-4 gating: absolute -70 LUFS, then relative -10 LU.
  static double _gated(List<double> blocks) {
    final absGate = math.pow(10, (-70 + 0.691) / 10).toDouble();
    var sum = 0.0;
    var n = 0;
    for (final b in blocks) {
      if (b > absGate) {
        sum += b;
        n++;
      }
    }
    if (n == 0) return LoudnessProfile.silent;
    final relGate = (sum / n) / 10; // -10 LU
    var sum2 = 0.0;
    var n2 = 0;
    for (final b in blocks) {
      if (b > absGate && b > relGate) {
        sum2 += b;
        n2++;
      }
    }
    if (n2 == 0) return LoudnessProfile.silent;
    return _lufs(sum2 / n2);
  }
}

/// A second-order section in transposed direct form II.
class _Biquad {
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  final double b0, b1, b2, a1, a2;
  double _z1 = 0, _z2 = 0;

  double step(double x) {
    final y = b0 * x + _z1;
    _z1 = b1 * x - a1 * y + _z2;
    _z2 = b2 * x - a2 * y;
    return y;
  }

  /// BS.1770 stage 1: the high shelf (+4 dB above ~1.7 kHz) that models the
  /// head. Constants f0, G, Q are the standard's; the bilinear transform is
  /// done for [rate].
  factory _Biquad.preFilter(int rate) {
    const f0 = 1681.974450955533;
    const gain = 3.999843853973347; // dB
    const q = 0.7071752369554196;
    final k = math.tan(math.pi * f0 / rate);
    final vh = math.pow(10, gain / 20).toDouble();
    final vb = math.pow(vh, 0.4996667741545416).toDouble();
    final a0 = 1 + k / q + k * k;
    return _Biquad(
      (vh + vb * k / q + k * k) / a0,
      2 * (k * k - vh) / a0,
      (vh - vb * k / q + k * k) / a0,
      2 * (k * k - 1) / a0,
      (1 - k / q + k * k) / a0,
    );
  }

  /// BS.1770 stage 2: the RLB high-pass (~38 Hz).
  factory _Biquad.highPass(int rate) {
    const f0 = 38.13547087602444;
    const q = 0.5003270373238773;
    final k = math.tan(math.pi * f0 / rate);
    final a0 = 1 + k / q + k * k;
    return _Biquad(
      1.0,
      -2.0,
      1.0,
      2 * (k * k - 1) / a0,
      (1 - k / q + k * k) / a0,
    );
  }
}
