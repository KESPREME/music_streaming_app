// The MIX LAB: renders the transitions the app would make between real songs and
// measures them, so a change to the fade, the level plan or the headroom is
// judged on audio rather than on belief.
//
// It is skipped unless MIX_LAB_SONGS names a folder of songs (the repo carries
// no music). It needs ffmpeg on the PATH.
//
//   $env:MIX_LAB_SONGS = 'C:\path\to\songs'
//   flutter test --no-pub test/lab/mix_lab_test.dart --reporter expanded
//
// Optional: MIX_LAB_PAIRS (default 60 random ordered pairs), MIX_LAB_SECONDS
// (crossfade length, default 6), MIX_LAB_STYLE (crossfade | automix, default
// automix), MIX_LAB_SEED, MIX_LAB_WORK (scratch folder).
//
// WHAT IS RENDERED
//
// The same planner, level planner and gain law the engine uses, applied to the
// full-bandwidth 44.1 kHz stereo decode of both songs, with the gains stepped
// every 30 ms like the engine's tick. The analysis the planner sees comes from
// the 11 kHz signal made by the SAME box-filter resampler the Android decoder
// uses, so the plan is the one a phone would make.
//
// WHAT IS MEASURED
//
//   balance  how much louder one song is than the other at the middle of the
//            fade, in dB (0 = an even blend; 9 = one song is nine times the
//            power of the other and the blend is gone)
//   step     the largest change in loudness between consecutive seconds of the
//            mix, in dB (lower is smoother)
//   overs    the share of samples in the overlap beyond full scale, which a
//            16-bit output clips
//
// WHAT IT CANNOT SAY: how it sounds. It says where the problems are.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/transition/audio_analyzer.dart';
import 'package:music_streaming_app/services/transition/level_plan.dart';
import 'package:music_streaming_app/services/transition/loudness.dart';
import 'package:music_streaming_app/services/transition/track_analysis.dart';
import 'package:music_streaming_app/services/transition/transition_planner.dart';
import 'package:music_streaming_app/services/transition/transition_settings.dart';

const int _hz = 44100;
const int _tickMs = 30;

class _Song {
  _Song(this.name, this.file, this.frames, this.analysis);
  final String name;
  final File file;
  final int frames;
  final TrackAnalysis analysis;
  int get durationMs => frames * 1000 ~/ _hz;
}

class _Pcm {
  _Pcm(int n)
      : l = Float64List(n),
        r = Float64List(n);
  final Float64List l;
  final Float64List r;
  int get length => l.length;
}

/// Samples [from, to) (44.1 kHz frames) of [song], zero outside the song.
_Pcm _read(_Song song, int from, int to) {
  final n = math.max(0, to - from);
  final out = _Pcm(n);
  final lo = math.max(0, from);
  final hi = math.min(song.frames, to);
  if (hi <= lo) return out;
  final raf = song.file.openSync();
  try {
    raf.setPositionSync(lo * 4);
    final bytes = raf.readSync((hi - lo) * 4);
    final s = Int16List.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes ~/ 2);
    for (var i = 0; i < hi - lo; i++) {
      out.l[lo - from + i] = s[2 * i] / 32768.0;
      out.r[lo - from + i] = s[2 * i + 1] / 32768.0;
    }
  } finally {
    raf.closeSync();
  }
  return out;
}

/// Mid and side at 11 025 Hz by the Android decoder's box filter.
({Int16List mid, Int16List side}) _boxMidSide(Float64List l, Float64List r, {int from = 0, int? to}) {
  final end = to ?? l.length;
  final n = (end - from) ~/ 4;
  final mid = Int16List(n);
  final side = Int16List(n);
  for (var i = 0; i < n; i++) {
    var sl = 0.0, sr = 0.0;
    for (var k = 0; k < 4; k++) {
      sl += l[from + 4 * i + k];
      sr += r[from + 4 * i + k];
    }
    sl = (sl / 4).clamp(-1.0, 1.0);
    sr = (sr / 4).clamp(-1.0, 1.0);
    final a = (sl * 32767).round();
    final b = (sr * 32767).round();
    mid[i] = (a + b) >> 1;
    side[i] = (a - b) >> 1;
  }
  return (mid: mid, side: side);
}

Future<_Song> _prepare(File src, Directory work, int index) async {
  final id = index.toString().padLeft(2, '0');
  final pcm = File('${work.path}/$id.s16');
  if (!pcm.existsSync() || pcm.lengthSync() == 0) {
    final r = await Process.run('ffmpeg', [
      '-v', 'error', '-y', '-i', src.path, '-ac', '2', '-ar', '$_hz', '-f', 's16le', pcm.path,
    ]);
    if (r.exitCode != 0) throw StateError('ffmpeg failed on ${src.path}: ${r.stderr}');
  }
  final frames = pcm.lengthSync() ~/ 4;
  final all = _read(_Song('', pcm, frames, const TrackAnalysis(trackId: '', durationMs: 1)), 0, frames);
  final ms = _boxMidSide(all.l, all.r);
  final analysis = AudioAnalyzer.analyze(
    ms.mid,
    side: ms.side,
    trackId: id,
    durationMs: frames * 1000 ~/ _hz,
  );
  final name = src.uri.pathSegments.last.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
  return _Song(name.length > 26 ? name.substring(0, 26) : name, pcm, frames, analysis);
}

class _Metrics {
  _Metrics(this.balanceDb, this.stepDb, this.overs, this.peak, [this.trace = '']);
  final String trace;
  final double balanceDb;
  final double stepDb;
  final double overs;
  final double peak;
}

/// Renders one transition and measures it.
_Metrics _render(_Song a, _Song b, TransitionPlan plan, LevelPlan level) {
  final fade = plan.fadeMs;
  final preMs = 10000;
  final postMs = math.max(14000, level.isNone ? 0 : level.releaseMs + 4000);
  final totalMs = preMs + fade + postMs;
  final n = totalMs * _hz ~/ 1000;

  final aFrom = (plan.startAtMs - preMs) * _hz ~/ 1000;
  final aPcm = _read(a, aFrom, aFrom + n);
  final bStart = plan.cueMs * _hz ~/ 1000;
  final bSpan = (n * plan.incomingRate).ceil() + 8;
  final bPcm = _read(b, bStart, bStart + bSpan);

  final mixL = Float64List(n), mixR = Float64List(n);
  final compAL = Float64List(n), compAR = Float64List(n);
  final compBL = Float64List(n), compBR = Float64List(n);
  var gOut = 1.0, gIn = 0.0;
  var overs = 0, overlapSamples = 0;
  var peak = 0.0;
  for (var i = 0; i < n; i++) {
    final tauMs = i * 1000 / _hz - preMs;
    // The engine updates its gains once per tick.
    if (i % (_tickMs * _hz ~/ 1000) == 0) {
      if (tauMs < 0) {
        gOut = 1.0;
        gIn = 0.0;
      } else if (tauMs < fade) {
        final g = mixGains(tauMs / fade, level: level);
        gOut = g.outgoing;
        gIn = g.incoming;
      } else {
        gOut = 0.0;
        final t = ((tauMs - fade) / math.max(1, level.releaseMs)).clamp(0.0, 1.0);
        gIn = level.incomingDb == 0 ? 1.0 : mixGains(1.0, level: level, incomingRelease: t).incoming;
      }
    }
    final pos = tauMs < 0 ? 0.0 : tauMs * _hz / 1000 * plan.incomingRate;
    double bl = 0, br = 0;
    if (tauMs >= 0) {
      final k = pos.floor();
      final f = pos - k;
      if (k + 1 < bPcm.length) {
        bl = bPcm.l[k] * (1 - f) + bPcm.l[k + 1] * f;
        br = bPcm.r[k] * (1 - f) + bPcm.r[k + 1] * f;
      }
    }
    compAL[i] = aPcm.l[i] * gOut;
    compAR[i] = aPcm.r[i] * gOut;
    compBL[i] = bl * gIn;
    compBR[i] = br * gIn;
    final xl = compAL[i] + compBL[i];
    final xr = compAR[i] + compBR[i];
    mixL[i] = xl;
    mixR[i] = xr;
    if (tauMs >= 0 && tauMs < fade) {
      overlapSamples++;
      if (xl.abs() > 1.0) overs++;
      if (xr.abs() > 1.0) overs++;
      peak = math.max(peak, math.max(xl.abs(), xr.abs()));
    }
  }

  // Loudness trajectory of the mix, clipped like a 16-bit output.
  final ms = _boxMidSide(mixL, mixR);
  final traj = Loudness.measure(ms.mid, ms.side, 11025).secondsLufs;
  var step = 0.0;
  final firstBlock = (preMs - 4000) ~/ 1000;
  final lastBlock = math.min(traj.length - 2, (preMs + fade + 10000) ~/ 1000);
  for (var k = firstBlock; k <= lastBlock; k++) {
    if (traj[k] <= -70 || traj[k + 1] <= -70) continue;
    step = math.max(step, (traj[k + 1] - traj[k]).abs());
  }

  // Balance at the middle of the fade, from the two components alone.
  final midStart = (preMs + fade ~/ 2 - 500) * _hz ~/ 1000;
  double comp(Float64List l, Float64List r) {
    final seg = _boxMidSide(l, r, from: midStart, to: midStart + _hz);
    final prof = Loudness.measure(seg.mid, seg.side, 11025).secondsLufs;
    return prof.isEmpty ? -70 : prof.first;
  }

  final la = comp(compAL, compAR);
  final lb = comp(compBL, compBR);
  final balance = (la <= -70 || lb <= -70) ? 0.0 : (la - lb).abs();

  // Per-second view: the mix, and each song's own contribution.
  final aMs = _boxMidSide(compAL, compAR);
  final bMs = _boxMidSide(compBL, compBR);
  final aProf = Loudness.measure(aMs.mid, aMs.side, 11025).secondsLufs;
  final bProf = Loudness.measure(bMs.mid, bMs.side, 11025).secondsLufs;
  final lines = StringBuffer();
  String f(double v) => v <= -70 ? '  --- ' : v.toStringAsFixed(1).padLeft(6);
  for (var k = 0; k < traj.length; k++) {
    final t = k - preMs ~/ 1000;
    lines.writeln('    t=${t.toString().padLeft(3)}s  mix ${f(traj[k])}   '
        'out ${f(aProf[k])}   in ${f(bProf[k])}');
  }
  return _Metrics(balance, step, overlapSamples == 0 ? 0 : overs / (2 * overlapSamples),
      peak, lines.toString());
}

String _stats(List<double> v) {
  if (v.isEmpty) return 'n/a';
  final s = [...v]..sort();
  final mean = v.reduce((x, y) => x + y) / v.length;
  double q(double p) => s[((s.length - 1) * p).round()];
  return 'mean ${mean.toStringAsFixed(2)}  median ${q(0.5).toStringAsFixed(2)}  '
      'p90 ${q(0.9).toStringAsFixed(2)}  max ${s.last.toStringAsFixed(2)}';
}

void main() {
  final songsDir = Platform.environment['MIX_LAB_SONGS'];
  test('mix lab', () async {
    final dir = Directory(songsDir!);
    final work = Directory(Platform.environment['MIX_LAB_WORK'] ??
        '${Directory.systemTemp.path}/mix_lab')
      ..createSync(recursive: true);
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'\.(mp3|m4a|flac|opus|ogg|wav)$', caseSensitive: false).hasMatch(f.path))
        .toList()
      ..sort((x, y) => x.path.compareTo(y.path));
    final songs = <_Song>[];
    for (var i = 0; i < files.length; i++) {
      songs.add(await _prepare(files[i], work, i + 1));
    }
    // ignore: avoid_print
    print('songs: ${songs.length}');
    for (final s in songs) {
      // ignore: avoid_print
      print('  ${s.name.padRight(26)} ${s.analysis.integratedLufs.toStringAsFixed(1).padLeft(6)} LUFS'
          '  ${s.analysis.bpm.toStringAsFixed(1).padLeft(6)} BPM (conf ${s.analysis.beatConfidence.toStringAsFixed(2)})');
    }

    final style = Platform.environment['MIX_LAB_STYLE'] == 'crossfade'
        ? TransitionStyle.crossfade
        : TransitionStyle.automix;
    final seconds = int.tryParse(Platform.environment['MIX_LAB_SECONDS'] ?? '') ?? 6;
    final wanted = int.tryParse(Platform.environment['MIX_LAB_PAIRS'] ?? '') ?? 60;
    final rng = math.Random(int.tryParse(Platform.environment['MIX_LAB_SEED'] ?? '') ?? 1);

    final pairs = <(int, int)>[
      for (var i = 0; i < songs.length; i++)
        for (var j = 0; j < songs.length; j++)
          if (i != j) (i, j),
    ]..shuffle(rng);
    final only = Platform.environment['MIX_LAB_TRACE'];
    if (only != null) {
      final p = only.split(',').map(int.parse).toList();
      pairs.insert(0, (p[0], p[1]));
    }

    final plain = <_Metrics>[];
    final leveled = <_Metrics>[];
    var triggered = 0;
    var kinds = <PlanKind, int>{};
    for (final (i, j) in pairs.take(only != null ? 1 : wanted)) {
      final a = songs[i], b = songs[j];
      final plan = TransitionPlanner.plan(PlanRequest(
        durationMs: a.durationMs,
        nextDurationMs: b.durationMs,
        style: style,
        crossfadeMs: seconds * 1000,
        matchTempo: true,
        outgoing: a.analysis,
        incoming: b.analysis,
      ));
      if (plan.isNone) continue;
      kinds[plan.kind] = (kinds[plan.kind] ?? 0) + 1;
      final level = LevelPlanner.plan(mix: plan, outgoing: a.analysis, incoming: b.analysis);
      if (!level.isNone) triggered++;
      final mp = _render(a, b, plan, LevelPlan.none);
      final ml = _render(a, b, plan, level);
      plain.add(mp);
      leveled.add(ml);
      if (Platform.environment['MIX_LAB_TRACE'] == '$i,$j') {
        // ignore: avoid_print
        print('\n${a.name} -> ${b.name}\n  $plan\n  $level\n  PLAIN\n${mp.trace}  LEVELED\n${ml.trace}');
      }
    }

    // ignore: avoid_print
    print('\n${plain.length} transitions, style $style, fade ${seconds}s, kinds $kinds');
    // ignore: avoid_print
    print('level plan acted on $triggered of ${plain.length}');
    for (final (label, set) in [('plain   ', plain), ('leveled ', leveled)]) {
      // ignore: avoid_print
      print('\n$label balance dB : ${_stats([for (final m in set) m.balanceDb])}');
      // ignore: avoid_print
      print('$label step    dB : ${_stats([for (final m in set) m.stepDb])}');
      // ignore: avoid_print
      print('$label overs   %  : ${_stats([for (final m in set) m.overs * 100])}'
          '   pairs with overs > 0.01 %: ${set.where((m) => m.overs > 0.0001).length}');
      // ignore: avoid_print
      print('$label peak       : ${_stats([for (final m in set) m.peak])}');
    }
  },
      skip: songsDir == null ? 'set MIX_LAB_SONGS to a folder of songs' : false,
      timeout: Timeout.none);
}
