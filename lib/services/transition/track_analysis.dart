// lib/services/transition/track_analysis.dart
//
// What AutoMix knows about a song. A plain value type with a JSON form, so it
// can be produced by any analyser (and by tests) and stored by the app.

import 'dart:convert';

class TrackAnalysis {
  const TrackAnalysis({
    required this.trackId,
    required this.durationMs,
    this.audibleStartMs = 0,
    this.outroStartMs = 0,
    this.contentEndMs = 0,
    this.bpm = 0,
    this.beatConfidence = 0,
    this.beatsMs = const <int>[],
    this.downbeatsMs = const <int>[],
    this.version = currentVersion,
  });

  /// Bump when the analyser changes in a way that makes old results wrong.
  static const int currentVersion = 1;

  final String trackId;

  /// The duration the analysis was made against. A different rendition of the
  /// same song (different cut) has different timing, so results are only reused
  /// when this matches the track being played.
  final int durationMs;

  /// The first moment that is actually audible (after any silence), ms.
  final int audibleStartMs;

  /// Where the closing fade/decay begins, ms. 0 when the song ends abruptly.
  final int outroStartMs;

  /// The last audible moment, ms. 0 when unknown (callers use the duration).
  final int contentEndMs;

  /// Tempo, beats per minute. 0 when no reliable tempo was found.
  final double bpm;

  /// 0..1: how much the beat grid can be trusted.
  final double beatConfidence;

  final List<int> beatsMs;

  /// Bar lines (the first beat of each bar), ms.
  final List<int> downbeatsMs;

  final int version;

  bool get hasBeats => bpm > 0 && beatsMs.length >= 8;

  bool get isUsable => version == currentVersion && durationMs > 0;

  /// Whether this analysis describes a song of [actualDurationMs]. Renditions
  /// of one recording differ by a second or so; more than that is a different
  /// cut and its timestamps are wrong.
  bool matchesDuration(int actualDurationMs) =>
      actualDurationMs <= 0 || (durationMs - actualDurationMs).abs() <= 1500;

  Map<String, Object?> toJson() => <String, Object?>{
        'v': version,
        'id': trackId,
        'dur': durationMs,
        'as': audibleStartMs,
        'os': outroStartMs,
        'ce': contentEndMs,
        'bpm': bpm,
        'bc': beatConfidence,
        'b': beatsMs,
        'db': downbeatsMs,
      };

  String encode() => jsonEncode(toJson());

  static TrackAnalysis? decode(String source) {
    try {
      final m = jsonDecode(source) as Map<String, dynamic>;
      return TrackAnalysis(
        version: (m['v'] as num?)?.toInt() ?? 0,
        trackId: m['id'] as String,
        durationMs: (m['dur'] as num).toInt(),
        audibleStartMs: (m['as'] as num?)?.toInt() ?? 0,
        outroStartMs: (m['os'] as num?)?.toInt() ?? 0,
        contentEndMs: (m['ce'] as num?)?.toInt() ?? 0,
        bpm: (m['bpm'] as num?)?.toDouble() ?? 0,
        beatConfidence: (m['bc'] as num?)?.toDouble() ?? 0,
        beatsMs: ((m['b'] as List?) ?? const <Object>[])
            .map((e) => (e as num).toInt())
            .toList(growable: false),
        downbeatsMs: ((m['db'] as List?) ?? const <Object>[])
            .map((e) => (e as num).toInt())
            .toList(growable: false),
      );
    } catch (_) {
      return null;
    }
  }
}
