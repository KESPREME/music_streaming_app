import 'package:flutter/foundation.dart';

import '../../models/track.dart';
import 'candidate.dart' show CandidateReason;

/// Trending engine (spec #2B/#35): "what is broadly popular right now."
///
/// NOT personalized. Regional + global chart evidence, ranked by
/// popularity evidence + freshness. Deliberately distinct from Quick Picks.
class TrendingEngine {
  TrendingEngine();

  /// Generate the Trending section. [regionalChart] and [globalChart] come
  /// from trusted chart endpoints; [nativeTrending] from native shelves
  /// whose title contains trending/chart semantics.
  static List<Track> generate({
    required List<Track> regionalChart,
    required List<Track> globalChart,
    required List<Track> nativeTrending,
    int limit = 8,
  }) {
    // Merge with section-local dedupe by id; native chart placement wins
    // first (YTM chart order is editorially meaningful), then regional,
    // then global fills gaps.
    final seen = <String>{};
    final result = <Track>[];

    void addAll(List<Track> source, CandidateReason reason) {
      for (final track in source) {
        if (!_isValid(track) || !seen.add(track.id)) continue;
        if (kDebugMode && result.length < 3) {
          debugPrint(
              'TRENDING pick="${track.trackName}" reason=${reason.name}');
        }
        result.add(track);
        if (result.length >= limit) return;
      }
    }

    addAll(nativeTrending, CandidateReason.nativeRecommendation);
    if (result.length < limit) {
      addAll(regionalChart, CandidateReason.regionalTrending);
    }
    if (result.length < limit) {
      addAll(globalChart, CandidateReason.globalTrending);
    }

    if (kDebugMode) {
      debugPrint(
          'TRENDING_ENGINE: ${result.length} items (native=${nativeTrending.length} '
          'regional=${regionalChart.length} global=${globalChart.length})');
    }
    return result;
  }

  static bool _isValid(Track t) =>
      t.id.isNotEmpty &&
      t.trackName.isNotEmpty &&
      t.id.length == 11 && // playable video id
      !t.id.startsWith(RegExp(r'(MPREb|OLAK|VL|PL|UC)'));
}

/// New Releases engine (spec #2C/#30): "recently released music actually
/// worth surfacing."
///
/// Sources: trusted native release shelves + the project's
/// getNewReleases() browse endpoint. Ranking: freshness first, then
/// artist affinity, then popularity placement. No generic search results.
class NewReleasesEngine {
  NewReleasesEngine();

  /// [artistAffinity] = lowercase artist-name fragments the listener has
  /// affinity for (from taste profile). Matching releases get boosted.
  static List<Track> generate({
    required List<Track> nativeReleases,
    required List<Track> affinityArtistsTracks,
    List<String> artistAffinity = const [],
    int limit = 10,
  }) {
    final seen = <String>{};
    final scored = <(Track, double)>[];

    void score(List<Track> source, double baseScore, bool fromAffinityPool) {
      for (final track in source) {
        if (!_isValid(track) || !seen.add(track.id)) continue;
        var score = baseScore;
        if (artistAffinity.any((a) =>
            a.isNotEmpty &&
            track.artistName.toLowerCase().contains(a.toLowerCase()))) {
          score += _affinityBoost;
        }
        scored.add((track, score));
      }
    }

    // Native release shelf = editorial trust (spec #30).
    score(nativeReleases, 0.6, false);
    // Artist-affinity pool = personal relevance (spec #32).
    score(affinityArtistsTracks, 0.4, true);

    // Deterministic: score DESC, then id ASC (spec #71).
    scored.sort((a, b) {
      final cmp = b.$2.compareTo(a.$2);
      if (cmp != 0) return cmp;
      return a.$1.id.compareTo(b.$1.id);
    });

    final result = scored.take(limit).map((s) => s.$1).toList(growable: false);
    if (kDebugMode && result.isNotEmpty) {
      debugPrint('NEW_RELEASES_ENGINE: ${result.length} items from '
          '${nativeReleases.length} native + ${affinityArtistsTracks.length} affinity');
    }
    return result;
  }

  static const _affinityBoost = 0.25;

  static bool _isValid(Track t) => t.id.isNotEmpty && t.trackName.isNotEmpty;
}
