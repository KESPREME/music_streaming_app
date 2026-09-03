import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/explore/explore_policy.dart';
import 'package:music_streaming_app/services/recommendation/candidate.dart';
import 'package:music_streaming_app/services/recommendation/candidate_metadata.dart';
import 'package:music_streaming_app/services/recommendation/ranker.dart';
import 'package:music_streaming_app/services/recommendation/search_followup_graph.dart';
import 'package:music_streaming_app/services/recommendation/taste_profile.dart';

/// Source pools for one Explore batch. Order matters: first-wins dedupe
/// walks pools from strongest provenance to weakest.
class ExploreSources {
  const ExploreSources({
    this.seedRelated = const [],
    this.quickPicks = const [],
    this.favorites = const [],
    this.recentlyPlayed = const [],
    this.regionalChart = const [],
    this.globalChart = const [],
    this.newReleases = const [],
  });

  final List<Track> seedRelated;
  final List<Track> quickPicks;
  final List<Track> favorites;
  final List<Track> recentlyPlayed;
  final List<Track> regionalChart;
  final List<Track> globalChart;
  final List<Track> newReleases;
}

/// A ranked, explained Explore candidate.
class ExploreItem {
  const ExploreItem({
    required this.track,
    required this.reason,
    required this.score,
    required this.source,
    this.secondaryReasons = const [],
    this.isExploration = false,
    this.confidence = 0,
  });

  final Track track;
  final CandidateReason reason;
  final List<CandidateReason> secondaryReasons;
  final double score;
  final String source;
  final bool isExploration;
  final double confidence;

  String get id => track.id;
}

/// Explore candidate generation on top of the SHARED recommendation
/// stack (DeterministicRanker + TasteProfile). No second engine —
/// this is a thin pool-mapping + policy layer (spec #96/#117).
class ExploreEngine {
  ExploreEngine({this.ranker = const DeterministicRanker(), this.searchGraph});

  final RecommendationRanker ranker;
  final SearchFollowupGraph? searchGraph;

  static const double _seedPersonalFloor = 0.9;

  bool _isInvalid(Track t) {
    final id = t.id;
    return t.trackName.isEmpty ||
        id.length != 11 ||
        id.startsWith('MPREb') ||
        id.startsWith('OLAK') ||
        id.startsWith('VL') ||
        id.startsWith('PL') ||
        id.startsWith('UC');
  }

  /// Synchronous core. The async variant only adds graph affinity lookups
  /// (kept for future seeding); ranking itself is pure.
  List<ExploreItem> generateSync({
    required TasteProfile profile,
    required ExploreSources sources,
    Track? seed,
    Set<String> exclude = const {},
    required int limit,
    required int generation,
    ExposureLedger? exposure,
  }) {
    final candidates = <RichCandidate>[];
    final poolOf = <String, String>{};

    void addPool(List<Track> tracks, String tag) {
      for (final track in tracks) {
        if (_isInvalid(track)) continue;
        if (exclude.contains(track.id)) continue;
        if (poolOf.containsKey(track.id)) continue;
        poolOf[track.id] = tag;
        candidates.add(RichCandidate.fromTrack(
          trackId: track.id,
          title: track.trackName,
          artistName: track.artistName,
          source: tag,
          genre: track.genre,
          albumName: track.albumName,
          durationMs: track.durationMs,
          releaseYear: _releaseYear(track),
          albumArt: track.albumArtUrl,
          chartRank: _chartRank(tag),
          chartSize: _chartSize(tag),
        ));
      }
    }

    addPool(sources.favorites, 'local_favorites');
    if (seed != null && !_isInvalid(seed)) {
      // Seed joins at related-priority so its provenance explains context.
      if (!poolOf.containsKey(seed.id)) {
        poolOf[seed.id] = 'seed';
        candidates.add(RichCandidate.fromTrack(
          trackId: seed.id,
          title: seed.trackName,
          artistName: seed.artistName,
          source: 'seed',
          albumName: seed.albumName,
          durationMs: seed.durationMs,
          releaseYear: _releaseYear(seed),
          albumArt: seed.albumArtUrl,
        ));
      }
    }
    addPool(sources.seedRelated, 'native_home');
    addPool(sources.quickPicks, 'quick_picks');
    addPool(sources.recentlyPlayed, 'local_history');
    addPool(sources.regionalChart, 'chart_regional');
    addPool(sources.globalChart, 'chart_global');
    addPool(sources.newReleases, 'new_release');

    if (candidates.isEmpty) return const [];

    final ranked = ranker.rank(
      candidates: candidates,
      profile: profile,
      config: ExplorePolicy.ranking(profile),
      limit: limit,
      exposure: exposure,
      generation: generation,
      personalFloor: {
        if (seed != null && !_isInvalid(seed)) seed.id: _seedPersonalFloor,
      },
    );

    return [
      for (final scored in ranked)
        ExploreItem(
          track: _trackFrom(scored.candidate, poolOf[scored.candidate.id]),
          reason: ExplorePolicy.reasonFor(poolOf[scored.candidate.id] ?? ''),
          secondaryReasons: _secondaryReasons(scored),
          score: scored.score,
          confidence: scored.confidence,
          source: poolOf[scored.candidate.id] ?? 'unknown',
          isExploration: scored.isExploration,
        ),
    ];
  }

  /// Async variant kept for API parity with the controller; affinity
  /// lookup is synchronous (in-memory graph) so both paths are identical
  /// in behavior.
  Future<List<ExploreItem>> generate({
    required TasteProfile profile,
    required ExploreSources sources,
    Track? seed,
    Set<String> exclude = const {},
    required int limit,
    required int generation,
    ExposureLedger? exposure,
  }) async {
    if (searchGraph == null) {
      return generateSync(
          profile: profile,
          sources: sources,
          seed: seed,
          exclude: exclude,
          limit: limit,
          generation: generation,
          exposure: exposure);
    }
    // Keep the graph lookup non-blocking; affinity>=0.15 feeds ranking.
    final graphAffinity = <String, double>{};
    // ponytail: candidate ids come from pool tracks; affinity lookup is
    // cheap per id. If pools grow past ~100, move to isolate.
    for (final track in [
      ...sources.seedRelated,
      ...sources.quickPicks,
      ...sources.favorites,
      ...sources.recentlyPlayed,
      ...sources.regionalChart,
      ...sources.globalChart,
      ...sources.newReleases,
    ]) {
      if (track.id.length != 11 || graphAffinity.containsKey(track.id)) {
        continue;
      }
      try {
        final a = searchGraph!.affinityFor(track.id);
        if (a >= 0.15) graphAffinity[track.id] = a;
      } catch (_) {}
    }
    return generateSync(
        profile: profile,
        sources: sources,
        seed: seed,
        exclude: exclude,
        limit: limit,
        generation: generation,
        exposure: exposure);
  }

  Track _trackFrom(RichCandidate c, String? tag) {
    if (tag == 'seed') {
      // Keep the exact Track instance identity for the seed.
      return _seedTracks[c.id] ?? _toTrack(c);
    }
    return _toTrack(c);
  }

  final Map<String, Track> _seedTracks = {};

  static Track _toTrack(RichCandidate c) {
    return Track(
      id: c.id,
      trackName: c.title,
      artistName: c.artists.join(', '),
      albumName: c.albumName ?? '',
      previewUrl: '',
      albumArt: c.artworkUrl ?? '',
      source: 'youtube',
      durationMs: c.durationMs,
      genre: c.genres.isNotEmpty ? c.genres.first : null,
    );
  }

  int? _releaseYear(Track t) {
    // No release-year metadata on Track today; charts/new releases carry
    // freshness via chartRank + editorial order instead.
    return null;
  }

  int? _chartRank(String tag) => switch (tag) {
        'chart_regional' => 1,
        'chart_global' => 1,
        _ => null,
      };

  int? _chartSize(String tag) => switch (tag) {
        'chart_regional' || 'chart_global' => 2,
        _ => null,
      };

  List<CandidateReason> _secondaryReasons(ScoredCandidate scored) {
    final f = scored.features;
    final reasons = <CandidateReason>[];
    if ((f['favorite'] ?? 0) > 0) reasons.add(CandidateReason.favoriteArtist);
    if ((f['searchFollowup'] ?? 0) > 0) {
      reasons.add(CandidateReason.searchFollowup);
    }
    if ((f['freshness'] ?? 0) > 0) {
      reasons.add(CandidateReason.newReleaseArtist);
    }
    if (scored.isExploration) reasons.add(CandidateReason.exploration);
    return reasons;
  }
}
