import 'candidate_metadata.dart';
import 'taste_profile.dart';

/// Tunable ranking weights (spec #25/#26: configurable, NOT claimed
/// optimal). Two documented operating points — cold (low history
/// confidence) and warm — linearly blended by
/// [TasteProfile.personalizationConfidence] (spec #57).
class RankingConfig {
  const RankingConfig({
    required this.weights,
    required this.penalties,
    this.artistSoftCap = 2,
    this.artistCapRelaxAffinity = 0.85,
    this.artistCapRelaxed = 3,
    this.albumSoftCap = 3,
    this.explorationFraction = 0.34,
    this.explorationMinPopularity = 0.5,
    this.exposurePenaltyPerShow = -0.08,
    this.exposureWindowGenerations = 2,
  });

  /// Feature weights. Keys: personalAffinity, favorite, artistAffinity,
  /// genreAffinity, languageAffinity (scaffold — always 0 today),
  /// searchFollowup, popularity, freshness, editorialRank, nativeTrust.
  final Map<String, double> weights;

  /// Negative weights: skipPenalty, overexposurePenalty.
  final Map<String, double> penalties;

  final int artistSoftCap;
  final double artistCapRelaxAffinity;
  final int artistCapRelaxed;
  final int albumSoftCap;

  /// Exploration budget share of the limit (spec #23/#25).
  final double explorationFraction;
  final double explorationMinPopularity;
  final double exposurePenaltyPerShow;
  final int exposureWindowGenerations;

  static const cold = RankingConfig(weights: {
    'personalAffinity': 0.05,
    'favorite': 0.20,
    'artistAffinity': 0.20,
    'genreAffinity': 0.08,
    'languageAffinity': 0.0,
    'searchFollowup': 0.10,
    'popularity': 0.30,
    'freshness': 0.05,
    'editorialRank': 0.10,
    'nativeTrust': 0.04,
  }, penalties: {
    'skipPenalty': -0.35,
    'overexposurePenalty': -0.15,
  });

  static const warm = RankingConfig(weights: {
    'personalAffinity': 0.30,
    'favorite': 0.25,
    'artistAffinity': 0.25,
    'genreAffinity': 0.10,
    'languageAffinity': 0.0,
    'searchFollowup': 0.12,
    'popularity': 0.12,
    'freshness': 0.04,
    'editorialRank': 0.02,
    'nativeTrust': 0.03,
  }, penalties: {
    'skipPenalty': -0.35,
    'overexposurePenalty': -0.15,
  });

  /// Linear blend by personalization confidence (spec #57): very low
  /// confidence → popularity-heavy; high → personalized-heavy.
  static RankingConfig forConfidence(double confidence) {
    final c = confidence.clamp(0.0, 1.0);
    Map<String, double> blend(Map<String, double> a, Map<String, double> b) => {
          for (final key in {...a.keys, ...b.keys})
            key: (a[key] ?? 0) + ((b[key] ?? 0) - (a[key] ?? 0)) * c,
        };
    return RankingConfig(
      weights: blend(cold.weights, warm.weights),
      penalties: blend(cold.penalties, warm.penalties),
      artistSoftCap: warm.artistSoftCap,
      artistCapRelaxAffinity: warm.artistCapRelaxAffinity,
      artistCapRelaxed: warm.artistCapRelaxed,
      albumSoftCap: warm.albumSoftCap,
      explorationFraction: warm.explorationFraction,
      explorationMinPopularity: warm.explorationMinPopularity,
      exposurePenaltyPerShow: warm.exposurePenaltyPerShow,
      exposureWindowGenerations: warm.exposureWindowGenerations,
    );
  }
}

/// Future rankers (ML, collaborative — spec #87/#88) implement this;
/// the rest of Home must not know which ranker ran.
abstract class RecommendationRanker {
  List<ScoredCandidate> rank({
    required List<RichCandidate> candidates,
    required TasteProfile profile,
    required RankingConfig config,
    required int limit,
    ExposureLedger? exposure,
    required int generation,
    Map<String, double> searchGraphAffinity = const {},
    Map<String, double> personalFloor = const {},
  });
}

/// Per-candidate scoring output — explainable (spec #69/#70).
class ScoredCandidate {
  ScoredCandidate({
    required this.candidate,
    required this.score,
    required this.features,
    required this.confidence,
    this.isExploration = false,
  });

  final RichCandidate candidate;
  final double score;

  /// Normalized 0-1 feature values used in the score (spec #27).
  final Map<String, double> features;
  final double confidence;
  final bool isExploration;
}

/// Session-scoped impression memory (spec #35): what was shown in which
/// refresh generation. Deterministic — no Random anywhere (spec #86).
class ExposureLedger {
  final Map<String, List<int>> _shown = {};

  void recordGeneration(int generation, Iterable<String> ids) {
    for (final id in ids) {
      _shown.putIfAbsent(id, () => []).add(generation);
    }
  }

  /// How many times [id] was shown inside the recent window.
  int recentShows(String id, int generation, {int window = 2}) {
    final gens = _shown[id];
    if (gens == null) return 0;
    return gens.where((g) => g >= generation - window && g < generation).length;
  }

  bool shownLastGeneration(String id, int generation) =>
      recentShows(id, generation, window: 1) > 0;
}

/// Deterministic feature-based ranker (spec #26/#86): normalized
/// features → weighted sum → penalties → exposure → diversity caps →
/// controlled rotation. Stable tie-breaking: score → freshness → trust →
/// semantic id. No Random.
class DeterministicRanker implements RecommendationRanker {
  const DeterministicRanker();

  @override
  List<ScoredCandidate> rank({
    required List<RichCandidate> candidates,
    required TasteProfile profile,
    required RankingConfig config,
    required int limit,
    ExposureLedger? exposure,
    required int generation,
    Map<String, double> searchGraphAffinity = const {},
    Map<String, double> personalFloor = const {},
  }) {
    final now = DateTime.now();
    final scored = <ScoredCandidate>[];

    for (final candidate in candidates) {
      final f = _features(candidate, profile, config);
      // Explicit favorite/like = strong personal evidence (spec #60),
      // even when the track itself has no recorded play signal yet.
      final floor = personalFloor[candidate.id] ?? 0;
      if (floor > (f['personalAffinity'] ?? 0)) {
        f['personalAffinity'] = floor;
      }
      // Search feature: direct query match OR graph transition evidence
      // (spec #12/#13) — the stronger signal wins, never both stacked.
      f['searchFollowup'] =
          (f['searchFollowup'] ?? 0) > (searchGraphAffinity[candidate.id] ?? 0)
              ? f['searchFollowup']!
              : (searchGraphAffinity[candidate.id] ?? 0);
      var score = 0.0;
      f.forEach((name, value) {
        score += (config.weights[name] ?? 0) * value;
      });

      // Exploration (spec #23): plausible-relevance candidates the user
      // never played. Scored by base features ONLY — the flag reserves
      // rotation slots; it must never overtake personal evidence (#24).
      final isExplorable =
          (f['popularity'] ?? 0) >= config.explorationMinPopularity &&
              (f['personalAffinity'] ?? 0) == 0 &&
              (f['artistAffinity'] ?? 0) == 0 &&
              (f['searchFollowup'] ?? 0) == 0;
      final explorationBudget =
          (limit * config.explorationFraction).round().clamp(1, 2);
      final isExploration = isExplorable &&
          scored.where((s) => s.isExploration).length < explorationBudget;

      // Penalties (spec #59/#35).
      final signalPenalty = _behaviorPenalty(candidate, profile);
      score += config.penalties['skipPenalty']! * signalPenalty.skipComponent;
      score += config.penalties['overexposurePenalty']! *
          signalPenalty.overexposureComponent;

      // Exposure: recently-shown demoted, never banned (spec #35/#38).
      if (exposure != null) {
        final shows = exposure.recentShows(
          candidate.id,
          generation,
          window: config.exposureWindowGenerations,
        );
        score += config.exposurePenaltyPerShow *
            shows.clamp(0, config.exposureWindowGenerations);
      }

      scored.add(ScoredCandidate(
        candidate: candidate,
        score: score.clamp(0.0, 2.0),
        features: f,
        confidence: _confidence(f),
        isExploration: isExploration,
      ));
    }

    // Deterministic ordering (spec #86): score → freshness → trust → id.
    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      final fa = a.features['freshness'] ?? 0;
      final fb = b.features['freshness'] ?? 0;
      if (fa != fb) return fb.compareTo(fa);
      final ta = a.candidate.sourceTrust.index;
      final tb = b.candidate.sourceTrust.index;
      if (ta != tb) return ta.compareTo(tb); // low < medium < high
      return a.candidate.id.compareTo(b.candidate.id);
    });

    return _diversifyAndRotate(
        scored, profile, config, limit, exposure, generation);
  }

  Map<String, double> _features(
    RichCandidate candidate,
    TasteProfile profile,
    RankingConfig config,
  ) {
    final personal = profile.trackAffinity(candidate.id);
    var artist = 0.0;
    for (final artistName in candidate.artists) {
      final a = profile.artistAffinity(artistName);
      // Collaboration affinity (spec #16): featured artists get partial
      // credit so A+B collaborations bridge two listening worlds.
      final weight = artistName == candidate.primaryArtist ? 1.0 : 0.6;
      final contribution = a * weight;
      if (contribution > artist) artist = contribution;
    }
    var genre = 0.0;
    for (final g in candidate.genres) {
      final value = profile.genreAffinity(g);
      if (value > genre) genre = value;
    }
    var language = 0.0; // scaffold (spec #8/#89): no language metadata yet
    for (final l in candidate.languages) {
      final value = profile.genreAffinity(l);
      if (value > language) language = value;
    }
    final popularity = candidate.popularity ?? 0.0;
    final freshness = _freshness(candidate.releaseYear, DateTime.now());
    final editorial = candidate.editorialRank == null
        ? 0.0
        : (candidate.editorialRank! / 100).clamp(0.0, 1.0);

    return {
      'personalAffinity': personal.clamp(0.0, 1.0),
      'artistAffinity': artist.clamp(0.0, 1.0),
      'genreAffinity': genre.clamp(0.0, 1.0),
      'languageAffinity': language.clamp(0.0, 1.0),
      'searchFollowup': _searchFeature(candidate, profile),
      'popularity': popularity.clamp(0.0, 1.0),
      'freshness': freshness,
      // Trusted editorial position (spec #30): shelf/chart order is real
      // curation signal — keeps cold-start picks sensible, not id-sorted.
      'editorialRank': editorial,
      // Explicit like = strong evidence at ANY profile maturity (spec #60).
      // Separate from personalAffinity so cold-start damping can't drown it.
      'favorite': candidate.source == 'local_favorites' ? 1.0 : 0.0,
      // An origin is not a recommendation (spec #31): native trust is a
      // small prior — native-only candidates need another signal to rise.
      'nativeTrust': candidate.source == 'native_home' ? 1.0 : 0.0,
    };
  }

  double _searchFeature(RichCandidate candidate, TasteProfile profile) {
    // Query→item resolution is coarse today (spec #62): a recent search
    // matching the candidate's artist/title is moderate evidence.
    return profile.searchAffinityFor(candidate);
  }

  double _freshness(int? releaseYear, DateTime now) {
    if (releaseYear == null) return 0; // unknown ≠ fresh (no fabrication)
    final age = now.year - releaseYear;
    if (age <= 0) return 1.0;
    if (age == 1) return 0.6;
    if (age == 2) return 0.3;
    return 0.0;
  }

  ({double skipComponent, double overexposureComponent}) _behaviorPenalty(
    RichCandidate candidate,
    TasteProfile profile,
  ) {
    final signal = profile.trackSignals[candidate.id];
    if (signal == null) return (skipComponent: 0, overexposureComponent: 0);
    final skip =
        signal.skipCount > 2 && signal.completionRate < 0.3 ? 1.0 : 0.0;
    final over = signal.playCount > 10 ? 1.0 : 0.0;
    return (skipComponent: skip, overexposureComponent: over);
  }

  double _confidence(Map<String, double> f) {
    final personal = f['personalAffinity'] ?? 0;
    final artist = f['artistAffinity'] ?? 0;
    final genre = f['genreAffinity'] ?? 0;
    final search = f['searchFollowup'] ?? 0;
    return (personal * 0.4 + artist * 0.3 + genre * 0.15 + search * 0.15)
        .clamp(0.0, 1.0);
  }

  /// Diversity caps + controlled rotation (spec #32-34/#38).
  List<ScoredCandidate> _diversifyAndRotate(
    List<ScoredCandidate> scored,
    TasteProfile profile,
    RankingConfig config,
    int limit,
    ExposureLedger? exposure,
    int generation,
  ) {
    // Rotation slots: reserve deterministic positions for candidates NOT
    // shown last generation (spec #38: A B C D E F → A C G D H F).
    final unseen = generation > 0
        ? scored
            .where((s) =>
                !(exposure?.shownLastGeneration(s.candidate.id, generation) ??
                    false))
            .toList()
        : <ScoredCandidate>[];
    final rotationCount = unseen.isEmpty ? 0 : (limit / 3).floor().clamp(1, 2);
    final slotIndices = const [1, 3];

    final rotation = unseen.take(rotationCount).toList();
    final rotationIds = rotation.map((s) => s.candidate.id).toSet();

    final artistCounts = <String, int>{};
    final albumCounts = <String, int>{};
    final picked = <ScoredCandidate>[];
    final remaining =
        scored.where((s) => !rotationIds.contains(s.candidate.id));

    for (final s in remaining) {
      if (picked.length >= limit - rotationCount) break;
      final c = s.candidate;
      // Artist soft cap (spec #33): relaxes for artist-dominant profiles.
      var cap = config.artistSoftCap;
      for (final artistName in c.artists) {
        if (profile.artistAffinity(artistName) >=
            config.artistCapRelaxAffinity) {
          cap = config.artistCapRelaxed;
        }
      }
      final artistKey = c.primaryArtist.toLowerCase().trim();
      if (artistKey.isNotEmpty) {
        final count = artistCounts[artistKey] ?? 0;
        if (count >= cap) continue;
        artistCounts[artistKey] = count + 1;
      }
      // Album soft cap (spec #34) — only when album identity is known.
      final albumKey = c.albumName?.toLowerCase().trim();
      if (albumKey != null && albumKey.isNotEmpty) {
        final count = albumCounts[albumKey] ?? 0;
        if (count >= config.albumSoftCap) continue;
        albumCounts[albumKey] = count + 1;
      }
      picked.add(s);
    }

    // Interleave rotation picks at deterministic slot indices (#38).
    final result = <ScoredCandidate>[];
    var rotationIdx = 0;
    var pickedIdx = 0;
    for (var i = 0; i < limit; i++) {
      if (rotationCount > 0 &&
          slotIndices.contains(i) &&
          rotationIdx < rotation.length) {
        result.add(rotation[rotationIdx++]);
      } else if (pickedIdx < picked.length) {
        result.add(picked[pickedIdx++]);
      } else if (rotationIdx < rotation.length) {
        result.add(rotation[rotationIdx++]);
      } else {
        break;
      }
    }
    return result;
  }
}

/// Behavior-signal view the ranker needs from the profile (spec #35/#59).
class BehaviorSignal {
  BehaviorSignal({
    this.playCount = 0,
    this.skipCount = 0,
    this.completionRate = 0,
  });

  final int playCount;
  final int skipCount;
  final double completionRate;
}
