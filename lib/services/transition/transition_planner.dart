// lib/services/transition/transition_planner.dart
//
// Decides HOW one song joins the next: where the incoming song starts, where it
// is cued, how long they overlap. Pure and deterministic - no player, no clock -
// so every rule is a table-test.
//
// TIERS, most to least ambitious
//
//   none          the songs join as they always did (gapless album, too short,
//                 transitions off)
//   crossfade     a fixed-length equal-power fade ending at the song's end
//   smart         AutoMix with analysis: the fade is placed over the song's own
//                 outro, silence is skipped on both sides, the length is chosen
//   beatmatched   smart, plus both songs enter on a bar line, and (if allowed)
//                 the incoming tempo is nudged to the outgoing one
//
// Every tier degrades to the one above it when its evidence is missing, so a
// song that has not been analysed (yet) still gets a clean crossfade.
//
// The numbers (0.55 beat confidence, +-4% tempo, 3-10 s smart fade) are the ones
// BitChord arrived at by measurement; they are starting points to be re-tuned on
// this app's own listening set, not facts about music.

import 'dart:math' as math;

import 'track_analysis.dart';
import 'transition_settings.dart';

enum PlanKind { none, crossfade, smart, beatmatched }

class TransitionPlan {
  const TransitionPlan({
    required this.kind,
    required this.reason,
    this.startAtMs = 0,
    this.endAtMs = 0,
    this.cueMs = 0,
    this.incomingRate = 1.0,
  });

  const TransitionPlan.none(String reason)
      : this(kind: PlanKind.none, reason: reason);

  final PlanKind kind;

  /// Why - for logs and the "AutoMix is doing X" readout.
  final String reason;

  /// Position in the OUTGOING song at which the incoming song becomes audible.
  final int startAtMs;

  /// Position in the outgoing song at which it has faded to silence.
  final int endAtMs;

  /// Where in the INCOMING song playback begins.
  final int cueMs;

  /// Tempo stretch applied to the incoming song (1.0 = none).
  final double incomingRate;

  int get fadeMs => endAtMs - startAtMs;
  bool get isNone => kind == PlanKind.none;

  /// Whether the join is a real mix (as opposed to a plain fade). Drives the
  /// "mixing" indicator: a plain crossfade needs no announcement.
  bool get isMix => kind == PlanKind.smart || kind == PlanKind.beatmatched;

  @override
  String toString() => 'TransitionPlan($kind, $reason, '
      'start=$startAtMs end=$endAtMs cue=$cueMs rate=$incomingRate)';
}

class PlanRequest {
  const PlanRequest({
    required this.durationMs,
    required this.style,
    required this.crossfadeMs,
    this.nextDurationMs = 0,
    this.crossfadeAlbums = false,
    this.matchTempo = false,
    this.albumSequential = false,
    this.outgoing,
    this.incoming,
  });

  final int durationMs;
  final int nextDurationMs;
  final TransitionStyle style;
  final int crossfadeMs;
  final bool crossfadeAlbums;
  final bool matchTempo;

  /// True when this pair is consecutive tracks of one album.
  final bool albumSequential;

  final TrackAnalysis? outgoing;
  final TrackAnalysis? incoming;
}

class TransitionPlanner {
  const TransitionPlanner._();

  /// Never run a transition into the last moments of the file: the player may
  /// already be reading on into the next item there.
  static const int tailGuardMs = 250;

  /// Under this a song is too short to give any of itself to a transition.
  static const int minTrackMs = 6000;

  /// A fade never swallows more than this fraction of the song.
  static const double maxFadeFraction = 1 / 3;

  static const int smartMinFadeMs = 3000;
  static const int smartMaxFadeMs = 10000;

  /// A silent lead-in longer than this is not skipped (it may be deliberate).
  static const int maxSkippedLeadInMs = 8000;

  static const double minBeatConfidence = 0.55;
  static const double maxTempoDeviation = 0.04;

  /// Below this fraction of the song, "the music ends here" is not believed:
  /// it is more likely a hidden track after silence than the end of the song.
  static const double minTrustedContentFraction = 0.6;

  static TransitionPlan plan(PlanRequest r) {
    if (r.durationMs < minTrackMs) return const TransitionPlan.none('too-short');
    if (r.albumSequential && !r.crossfadeAlbums) {
      return const TransitionPlan.none('album-gapless');
    }

    if (r.style == TransitionStyle.automix) {
      final smart = _smart(r);
      if (smart != null) return smart;
    }
    return _crossfade(r, reason: r.style == TransitionStyle.automix ? 'automix-fallback' : 'crossfade');
  }

  // ── Crossfade ─────────────────────────────────────────────────────────────

  static TransitionPlan _crossfade(PlanRequest r, {required String reason}) {
    final fade = _boundedFade(r.crossfadeMs, r.durationMs);
    final end = r.durationMs - tailGuardMs;
    return TransitionPlan(
      kind: PlanKind.crossfade,
      reason: reason,
      startAtMs: end - fade,
      endAtMs: end,
    );
  }

  static int _boundedFade(int wantedMs, int durationMs) {
    final cap = (durationMs * maxFadeFraction).floor();
    return math.max(500, math.min(wantedMs, cap));
  }

  // ── AutoMix ───────────────────────────────────────────────────────────────

  static TransitionPlan? _smart(PlanRequest r) {
    final out = r.outgoing;
    final inc = r.incoming;
    if (out == null || inc == null) return null; // not measured yet
    if (!out.isUsable || !inc.isUsable) return null;
    if (!out.matchesDuration(r.durationMs)) return null;
    if (r.nextDurationMs > 0 && !inc.matchesDuration(r.nextDurationMs)) {
      return null;
    }

    // Where the outgoing song actually stops being music.
    var contentEnd = r.durationMs - tailGuardMs;
    if (out.contentEndMs > 0) {
      if (out.contentEndMs < r.durationMs * minTrustedContentFraction) {
        return null; // implausible: distrust the whole analysis
      }
      contentEnd = math.min(contentEnd, out.contentEndMs);
    }

    // The fade lives over the song's own outro when it has one.
    final outroMs = out.outroStartMs > 0 ? contentEnd - out.outroStartMs : 0;
    var fade = outroMs >= smartMinFadeMs
        ? outroMs.clamp(smartMinFadeMs, smartMaxFadeMs)
        : r.crossfadeMs.clamp(smartMinFadeMs, smartMaxFadeMs);
    fade = math.min(fade, (r.durationMs * maxFadeFraction).floor());

    // Skip dead air at the head of the incoming song.
    var cue = math.min(inc.audibleStartMs, maxSkippedLeadInMs);
    if (cue < 0) cue = 0;

    var startAt = contentEnd - fade;
    var endAt = contentEnd;
    var rate = 1.0;
    var kind = PlanKind.smart;
    var reason = 'smart';

    final beat = _alignOnBars(
      out: out,
      inc: inc,
      contentEnd: contentEnd,
      fade: fade,
      audibleStart: cue,
      matchTempo: r.matchTempo,
      durationMs: r.durationMs,
    );
    if (beat != null) {
      startAt = beat.startAt;
      endAt = beat.endAt;
      cue = beat.cue;
      rate = beat.rate;
      kind = PlanKind.beatmatched;
      reason = rate == 1.0 ? 'beats-aligned' : 'beats-matched';
    }

    if (startAt < r.durationMs * 0.3) return null; // never mid-song
    return TransitionPlan(
      kind: kind,
      reason: reason,
      startAtMs: startAt,
      endAtMs: endAt,
      cueMs: cue,
      incomingRate: rate,
    );
  }

  /// Folds [incoming] by octaves (x2 or /2) toward [outgoing], the way a DJ
  /// counts 63 BPM against 126.
  static double alignTempoOctave(double outgoingBpm, double incomingBpm) {
    if (outgoingBpm <= 0 || incomingBpm <= 0) return incomingBpm;
    var aligned = incomingBpm;
    while (aligned / outgoingBpm > 1.5) {
      aligned /= 2;
    }
    while (aligned / outgoingBpm < 0.67) {
      aligned *= 2;
    }
    return aligned;
  }

  static _BarAlignment? _alignOnBars({
    required TrackAnalysis out,
    required TrackAnalysis inc,
    required int contentEnd,
    required int fade,
    required int audibleStart,
    required bool matchTempo,
    required int durationMs,
  }) {
    if (!out.hasBeats || !inc.hasBeats) return null;
    if (out.beatConfidence < minBeatConfidence ||
        inc.beatConfidence < minBeatConfidence) {
      return null;
    }
    if (out.downbeatsMs.isEmpty || inc.downbeatsMs.isEmpty) return null;

    final incAligned = alignTempoOctave(out.bpm, inc.bpm);
    final ratio = out.bpm / incAligned; // incoming speed that matches the outgoing
    if ((ratio - 1).abs() > maxTempoDeviation) return null;

    // Overlap in whole bars of the outgoing song: 4, 8 or 16 beats.
    final beatMs = 60000.0 / out.bpm;
    final barMs = beatMs * 4;
    final bars = math.max(1, (fade / barMs).round());
    final overlap = (bars * barMs).round();

    // The latest outgoing bar line that still lets the overlap finish inside
    // the music.
    final latestStart = contentEnd - overlap;
    int? start;
    for (final d in out.downbeatsMs) {
      if (d <= latestStart) start = d;
      if (d > latestStart) break;
    }
    if (start == null || latestStart - start > barMs * 1.5) return null;

    // The incoming song enters on ITS first bar line after the dead air.
    int? cue;
    for (final d in inc.downbeatsMs) {
      if (d >= audibleStart) {
        cue = d;
        break;
      }
    }
    if (cue == null || cue > maxSkippedLeadInMs + 4 * barMs) return null;

    // Without permission to stretch, bar alignment is only meaningful when the
    // tempos already agree to within a hair.
    final stretch = matchTempo ? ratio : 1.0;
    if (!matchTempo && (ratio - 1).abs() > 0.01) return null;

    return _BarAlignment(
      startAt: start,
      endAt: start + overlap,
      cue: cue,
      rate: (stretch * 10000).round() / 10000,
    );
  }
}

class _BarAlignment {
  const _BarAlignment({
    required this.startAt,
    required this.endAt,
    required this.cue,
    required this.rate,
  });
  final int startAt;
  final int endAt;
  final int cue;
  final double rate;
}
