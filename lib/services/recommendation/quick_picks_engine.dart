import 'package:flutter/foundation.dart';

import '../../models/track.dart';
import 'candidate.dart' show CandidateReason;
import 'search_followup_graph.dart';

/// Quick Picks engine (spec #2A/#17/#18): generates ranked song
/// candidates from multiple signal pools, scores deterministically, and
/// diversifies.
///
/// Signals combined:
///   1. recent strong listening (existing RecommendationService signals)
///   2. search-followup transitions
///   3. favorites
///   4. artist affinity
///   5. trending/chart candidates as popularity prior
///   6. native feed items as trusted editorial signal
///
/// No randomization. Same profile + candidates → same ranking (spec #71).
class QuickPicksEngine {
  QuickPicksEngine({
    required this.signalProvider,
    this.searchGraph,
  });

  /// Existing RecommendationService signal access.
  final QuickPicksSignalProvider signalProvider;
  final SearchFollowupGraph? searchGraph;

  // ── Signal weights (spec #11/#18, documented) ──────────────────────────
  static const _wRecentStrong = 0.30;
  static const _wFrequent = 0.20;
  static const _wFavorite = 0.25;
  static const _wArtistAffinity = 0.15;
  static const _wSearchFollowup = 0.15;
  static const _wPopularity = 0.10;
  static const _wDiscovery = 0.05;
  static const _wSkipPenalty = -0.20;
  static const _wOverexposure = -0.10;

  /// Artist cap per section (spec #27): soft, not absolute.
  static const _maxPerArtist = 2;

  /// Generate ranked Quick Picks. [nativeTracks] come from the composed
  /// HomeFeed (trusted editorial); [chartTracks] from trending/chart;
  /// [favorites] and [recentlyPlayed] from local state.
  List<QuickPickCandidate> generate({
    required List<Track> nativeTracks,
    required List<Track> chartTracks,
    required List<Track> favorites,
    required List<Track> recentlyPlayed,
    required List<Track> newReleases,
    int limit = 8,
  }) {
    final candidates = <String, QuickPickCandidate>{};

    // Pool 1: recent plays with strong completion (spec #11.1).
    for (final track in recentlyPlayed) {
      if (_isInvalid(track) || candidates.containsKey(track.id)) continue;
      final signal = signalProvider.signalFor(track.id);
      final isStrong = signal == null ||
          (signal.completionRate > 0.6 || signal.replayCount > 0);
      if (!isStrong) continue;
      candidates[track.id] = QuickPickCandidate(
        track: track,
        reason: CandidateReason.recentlyPlayed,
        score: _wRecentStrong,
        secondaryReasons: signal != null && signal.playCount > 3
            ? [CandidateReason.frequentArtist]
            : [],
        source: 'local_history',
      );
    }

    // Pool 2: favorites (spec #21 — strongest positive signal).
    for (final track in favorites) {
      if (_isInvalid(track)) continue;
      final existing = candidates[track.id];
      if (existing != null) {
        existing.score += _wFavorite;
        existing.secondaryReasons.add(CandidateReason.favoriteArtist);
        continue;
      }
      candidates[track.id] = QuickPickCandidate(
        track: track,
        reason: CandidateReason.favoriteArtist,
        score: _wFavorite,
        source: 'local_favorites',
      );
    }

    // Pool 3: search-followup graph (spec #7).
    final graph = searchGraph;
    if (graph != null) {
      for (final track in [
        ...nativeTracks,
        ...chartTracks,
        ...recentlyPlayed
      ]) {
        if (_isInvalid(track) || candidates.containsKey(track.id)) continue;
        final affinity = graph.affinityFor(track.id);
        if (affinity < 0.15) continue;
        candidates[track.id] = QuickPickCandidate(
          track: track,
          reason: CandidateReason.searchFollowup,
          score: _wSearchFollowup * (1 + affinity),
          secondaryReasons: [CandidateReason.relatedToListening],
          source: 'search_followup',
        );
      }
    }

    // Pool 4: artist affinity from existing taste model (spec #22).
    final topArtists = signalProvider.topArtists(limit: 10);
    if (topArtists.isNotEmpty) {
      for (final track in [...nativeTracks, ...newReleases]) {
        if (_isInvalid(track) || candidates.containsKey(track.id)) continue;
        final artistMatch = topArtists.any(
            (a) => track.artistName.toLowerCase().contains(a.toLowerCase()));
        if (!artistMatch) continue;
        candidates[track.id] = QuickPickCandidate(
          track: track,
          reason: CandidateReason.frequentArtist,
          score: _wArtistAffinity,
          source: 'artist_affinity',
        );
      }
    }

    // Pool 5: chart/popularity prior (spec #12/#13).
    for (final track in chartTracks) {
      if (_isInvalid(track) || candidates.containsKey(track.id)) continue;
      candidates[track.id] = QuickPickCandidate(
        track: track,
        reason: CandidateReason.regionalTrending,
        score: _wPopularity,
        source: 'chart',
      );
    }

    // Pool 6: native feed (trusted editorial, spec #17).
    for (final track in nativeTracks) {
      if (_isInvalid(track) || candidates.containsKey(track.id)) continue;
      candidates[track.id] = QuickPickCandidate(
        track: track,
        reason: CandidateReason.nativeRecommendation,
        score: _wDiscovery,
        source: 'native_home',
      );
    }

    // Apply skip/overexposure penalties (spec #19/#20).
    for (final candidate in candidates.values) {
      final signal = signalProvider.signalFor(candidate.track.id);
      if (signal != null) {
        if (signal.skipCount > 2 && signal.completionRate < 0.3) {
          candidate.score += _wSkipPenalty;
        }
        if (signal.playCount > 10) {
          candidate.score += _wOverexposure; // heard enough
        }
      }
    }

    // Deterministic sort (spec #71): score DESC, then track id ASC for
    // stable tie-breaking.
    final ranked = candidates.values.toList()
      ..sort((a, b) {
        final cmp = b.score.compareTo(a.score);
        if (cmp != 0) return cmp;
        return a.track.id.compareTo(b.track.id);
      });

    // Artist diversity cap (spec #27).
    final artistCount = <String, int>{};
    final diversified = <QuickPickCandidate>[];
    for (final candidate in ranked) {
      final artistKey = candidate.track.artistName.toLowerCase().trim();
      if (artistKey.isNotEmpty) {
        final count = artistCount[artistKey] ?? 0;
        if (count >= _maxPerArtist) continue;
        artistCount[artistKey] = count + 1;
      }
      diversified.add(candidate);
      if (diversified.length >= limit) break;
    }

    if (kDebugMode && diversified.isNotEmpty) {
      debugPrint('QUICK_PICKS_ENGINE: generated ${diversified.length} picks '
          'from ${candidates.length} candidates');
      for (final c in diversified.take(3)) {
        debugPrint(
            '  PICK "${c.track.trackName}" score=${c.score.toStringAsFixed(2)} '
            'reason=${c.reason.name} source=${c.source}');
      }
    }

    return diversified;
  }

  static bool _isInvalid(Track track) =>
      track.id.isEmpty ||
      track.trackName.isEmpty ||
      track.id.length != 11 || // not a video id
      track.id.startsWith(RegExp(r'(MPREb|OLAK|VL|PL|UC)'));
}

/// Access to the RecommendationService's internal signal cache without
/// leaking the full class into the engine.
abstract class QuickPicksSignalProvider {
  QuickPicksTrackSignal? signalFor(String trackId);
  List<String> topArtists({int limit = 10});
}

/// Minimal signal shape the engine needs (decoupled from the service).
class QuickPicksTrackSignal {
  QuickPicksTrackSignal({
    required this.trackId,
    required this.artistName,
    this.playCount = 0,
    this.skipCount = 0,
    this.replayCount = 0,
    this.completionRate = 0.0,
  });

  final String trackId;
  final String artistName;
  int playCount;
  int skipCount;
  int replayCount;
  double completionRate;
}

/// QuickPickCandidate with mutable score for signal accumulation.
/// Standalone (not extending immutable Candidate) because score is
/// built up across multiple signal pools.
class QuickPickCandidate {
  QuickPickCandidate({
    required this.track,
    required this.reason,
    required this.score,
    this.secondaryReasons = const [],
    this.source,
  });

  final Track track;
  final CandidateReason reason;
  double score;
  List<CandidateReason> secondaryReasons;
  final String? source;

  @override
  String toString() =>
      'QuickPick(${track.trackName} score=${score.toStringAsFixed(2)} reason=${reason.name})';
}
