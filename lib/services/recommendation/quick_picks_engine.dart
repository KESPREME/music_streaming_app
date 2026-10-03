import 'package:flutter/foundation.dart';

import '../../models/track.dart';
import 'candidate.dart' show CandidateReason;
import 'candidate_metadata.dart';
import 'ranker.dart';
import 'search_followup_graph.dart';
import 'taste_profile.dart';

/// Recommendation candidate/ranker versions (spec #66/#68/#92) — bump on
/// semantic changes so caches/debug output stay interpretable.
const kCandidateVersion = '2';
const kRankerVersion = '2';

/// Quick Picks engine v2 (spec: Recommendation Engine 2.0).
///
/// Pipeline (spec #3):
///   candidate generation (typed pools)
///     → validation gate (identity/playability — quality floor #85)
///     → metadata enrichment (RichCandidate: artists[], genre, chart rank)
///     → feature extraction + deterministic scoring (DeterministicRanker)
///     → diversity (artist/album soft caps) + exposure control
///     → controlled rotation (no Random — ever, spec #86)
///
/// Key quality rule (spec #31): "From your Home feed" is an ORIGIN, not a
/// recommendation reason. Native candidates carry a tiny trust prior and
/// must earn their slot via affinity, popularity, freshness or search
/// evidence.
class QuickPicksEngine {
  QuickPicksEngine({
    this.signalProvider,
    this.searchGraph,
    this.ranker = const DeterministicRanker(),
    RankingConfig? config,
  }) : configOverride = config;

  /// Legacy signal facade (read-only). When no explicit [TasteProfile] is
  /// passed to generate(), a profile is synthesized from it so the
  /// provider can keep using this engine without new plumbing.
  final QuickPicksSignalProvider? signalProvider;
  final SearchFollowupGraph? searchGraph;
  final RecommendationRanker ranker;
  final RankingConfig? configOverride;

  // Pool base evidence (documented, spec #26-style). These fold into the
  // personal feature: an explicit favorite is strong, a chart slot is a
  // popularity prior, a native shelf item is nearly nothing on its own.
  static const _favoritePersonalFloor = 0.75;

  /// Generate ranked Quick Picks.
  List<QuickPickCandidate> generate({
    required List<Track> nativeTracks,
    required List<Track> chartTracks,
    required List<Track> favorites,
    required List<Track> recentlyPlayed,
    required List<Track> newReleases,
    TasteProfile? profile,
    List<String> searchQueries = const [],
    int generation = 0,
    ExposureLedger? exposure,
    int limit = 8,
  }) {
    final effectiveProfile = profile ??
        _synthesizeProfile(
          signalProvider: signalProvider,
          candidates: [
            ...chartTracks,
            ...favorites,
            ...recentlyPlayed,
            ...nativeTracks,
            ...newReleases,
          ],
          favorites: favorites,
          searchQueries: searchQueries,
        );

    // ── Candidate generation + validation gate (spec #85) ───────────────
    final provider = signalProvider;
    final recentsFiltered = recentlyPlayed.where((track) {
      final hasSignal = profile != null
          ? profile.trackSignals.containsKey(track.id)
          : (provider?.signalFor(track.id) != null);
      if (!hasSignal) return true;
      final completion = profile != null
          ? (profile.trackSignals[track.id]?.completionRate ?? 0)
          : (provider?.signalFor(track.id)?.completionRate ?? 0);
      final replays = profile != null
          ? 0
          : (provider?.signalFor(track.id)?.replayCount ?? 0);
      return completion > 0.4 || replays > 0;
    }).toList();

    final candidates = <RichCandidate>[];
    final seenIds = <String>{};
    var raw = 0;
    void addPool(List<Track> tracks, String source,
        {int? chartRank, int? chartSize}) {
      final editorialSize = tracks.length;
      for (var i = 0; i < tracks.length; i++) {
        raw++;
        final track = tracks[i];
        if (_isInvalid(track)) continue;
        // First-wins across pools (pool priority = add order): a favorited
        // song that also charts keeps its favorite identity, not trending.
        if (!seenIds.add(track.id)) continue;
        candidates.add(RichCandidate.fromTrack(
          trackId: track.id,
          title: track.trackName,
          artistName: track.artistName,
          source: source,
          genre: track.genre,
          albumName: track.albumName,
          durationMs: track.durationMs,
          chartRank: chartRank ?? (source == 'chart' ? i : null),
          chartSize: chartSize ?? (source == 'chart' ? tracks.length : null),
          playlistId: null,
          albumArt: track.albumArtUrl,
          editorialRank: editorialSize > 0
              ? ((1 - i / editorialSize) * 100).round()
              : null,
        ));
      }
    }

    // Pool priority = dedupe first-wins. Favorites and local recents outrank chart:
    // Jump Back In & personal taste signals take priority over generic trending.
    addPool(favorites, 'local_favorites');
    addPool(recentsFiltered, 'local_history');
    addPool(chartTracks, 'chart');
    addPool(nativeTracks, 'native_home');
    addPool(newReleases, 'new_release');

    final validated = candidates.length;
    if (candidates.isEmpty) {
      _traceLoad(
        raw: raw,
        validated: 0,
        ranked: 0,
        finalCount: 0,
        profile: effectiveProfile,
      );
      return [];
    }

    // Search-followup graph affinity (spec #12/#13): searched → played →
    // replayed transitions. Feeds the search feature alongside direct
    // query matching.
    final graph = searchGraph;
    final graphAffinity = <String, double>{};
    if (graph != null) {
      for (final candidate in candidates) {
        final affinity = graph.affinityFor(candidate.id);
        if (affinity >= 0.15) graphAffinity[candidate.id] = affinity;
      }
    }

    final ranked = ranker.rank(
      candidates: candidates,
      profile: effectiveProfile,
      config: configOverride ??
          RankingConfig.forConfidence(
              effectiveProfile.personalizationConfidence),
      limit: limit,
      exposure: exposure,
      generation: generation,
      searchGraphAffinity: graphAffinity,
      personalFloor: {
        for (final track in favorites)
          if (!_isInvalid(track)) track.id: _favoritePersonalFloor,
      },
    );

    _traceLoad(
      raw: raw,
      validated: validated,
      ranked: ranked.length,
      finalCount: ranked.length,
      profile: effectiveProfile,
    );

    // ── Output mapping with explainable reasons (spec #69/#70) ──────────
    final output = <QuickPickCandidate>[];
    for (final scored in _dedupeBySong(ranked)) {
      final c = scored.candidate;
      final track = Track(
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
      final (reason, secondary) = _explain(scored, graphAffinity);
      output.add(QuickPickCandidate(
        track: track,
        reason: reason,
        score: scored.score,
        secondaryReasons: secondary,
        source: c.source,
        confidence: scored.confidence,
        features: scored.features,
        isExploration: scored.isExploration,
        trackId: c.id,
      ));
    }

    if (kDebugMode && output.isNotEmpty) {
      for (final c in output.take(6)) {
        debugPrint('RECOMMENDATION_ITEM rank=${output.indexOf(c) + 1} '
            'title="${c.track.trackName}" artist="${c.track.artistName}" '
            'score=${c.score.toStringAsFixed(2)} '
            'confidence=${c.confidence.toStringAsFixed(2)} '
            'primary=${c.reason.name} secondary=${c.secondaryReasons.map((r) => r.name).join("+")}');
      }
      // BAD_CANDIDATE_ANALYSIS (spec #99): a native-only candidate with no
      // personal evidence reaching the top-3 is a tuning alarm.
      for (var i = 0; i < output.take(3).length; i++) {
        final c = output[i];
        final f = c.features;
        final unexplained = (f['personalAffinity'] ?? 0) == 0 &&
            (f['artistAffinity'] ?? 0) == 0 &&
            (f['popularity'] ?? 0) == 0 &&
            (f['searchFollowup'] ?? 0) == 0;
        if (unexplained) {
          debugPrint('BAD_CANDIDATE_ANALYSIS item="${c.track.trackName}" '
              'rank=${i + 1} relevance=low reason=${c.reason.name} '
              'score=${c.score.toStringAsFixed(2)} '
              '(native origin with no personal/popularity/search evidence)');
        }
      }
    }

    return output;
  }

  /// Rank pre-built candidates (used by tests and future callers that
  /// carry richer metadata than Track can hold).
  List<QuickPickCandidate> generateRich({
    required List<RichCandidate> candidates,
    required TasteProfile profile,
    List<String> searchQueries = const [],
    Map<String, double> searchGraphAffinity = const {},
    int generation = 0,
    ExposureLedger? exposure,
    int limit = 8,
  }) {
    final ranked = ranker.rank(
      candidates: candidates,
      profile: profile,
      config: configOverride ??
          RankingConfig.forConfidence(profile.personalizationConfidence),
      limit: limit,
      exposure: exposure,
      generation: generation,
      searchGraphAffinity: searchGraphAffinity,
    );
    return _dedupeBySong(ranked).map((scored) {
      final c = scored.candidate;
      final (reason, secondary) = _explain(scored, searchGraphAffinity);
      return QuickPickCandidate(
        track: Track(
          id: c.id,
          trackName: c.title,
          artistName: c.artists.join(', '),
          albumName: c.albumName ?? '',
          previewUrl: '',
          albumArt: c.artworkUrl ?? '',
          source: 'youtube',
          durationMs: c.durationMs,
          genre: c.genres.isNotEmpty ? c.genres.first : null,
        ),
        reason: reason,
        score: scored.score,
        secondaryReasons: secondary,
        source: c.source,
        confidence: scored.confidence,
        features: scored.features,
        isExploration: scored.isExploration,
        trackId: c.id,
      );
    }).toList();
  }

  /// Song-identity dedupe (live bug: "Loser" twice — liked copy + native
  /// copy under different videoIds). Ranked order is score order, so
  /// keep-first preserves the strongest evidence (favorites outrank).
  /// Key is normalized title + primary artist only: same title by a
  /// different artist (covers) is a different song. This is candidate
  /// hygiene, NOT feed dedupe (spec #11 untouched — shelves keep repeats).
  static List<ScoredCandidate> _dedupeBySong(List<ScoredCandidate> ranked) {
    final seen = <String>{};
    return ranked.where((scored) {
      final c = scored.candidate;
      final title = c.title.trim().toLowerCase();
      final artist = c.primaryArtist.trim().toLowerCase();
      if (title.isEmpty || artist.isEmpty) return true;
      return seen.add('$title|$artist');
    }).toList();
  }

  /// Explainable reason selection (spec #69). Priority: explicit search
  /// intent > favorite > recent play > artist affinity > exploration >
  /// chart popularity > native origin.
  (CandidateReason, List<CandidateReason>) _explain(
    ScoredCandidate scored,
    Map<String, double> graphAffinity,
  ) {
    final f = scored.features;
    final secondary = <CandidateReason>[];
    final graph = graphAffinity[scored.candidate.id] ?? 0;
    final search = (f['searchFollowup'] ?? 0) + graph;

    if ((f['artistAffinity'] ?? 0) > 0.05) {
      secondary.add(CandidateReason.frequentArtist);
    }
    if ((f['genreAffinity'] ?? 0) > 0.02) {
      secondary.add(CandidateReason.genreAffinity);
    }
    if ((f['popularity'] ?? 0) > 0.3) {
      secondary.add(CandidateReason.regionalTrending);
    }
    if (scored.isExploration) secondary.add(CandidateReason.exploration);

    CandidateReason primary;
    if (scored.candidate.source == 'local_favorites') {
      // Explicit favorite outranks popularity — the user chose this (#60).
      primary = CandidateReason.favoriteArtist;
    } else if (search > 0.15 && scored.candidate.source == 'local_history') {
      primary = CandidateReason.searchFollowup;
    } else if (scored.candidate.source == 'local_history') {
      primary = CandidateReason.recentlyPlayed;
    } else if ((f['artistAffinity'] ?? 0) > 0.05) {
      primary = CandidateReason.frequentArtist;
    } else if (scored.candidate.source == 'chart') {
      primary = CandidateReason.regionalTrending;
    } else if (scored.candidate.source == 'new_release') {
      primary = CandidateReason.newReleaseArtist;
    } else if (scored.isExploration) {
      primary = CandidateReason.exploration;
    } else {
      primary = CandidateReason.nativeRecommendation;
    }
    return (primary, secondary);
  }

  /// Profile synthesis from the legacy signal facade — keeps the
  /// provider-facing contract stable while production moves to explicit
  /// profiles. Signals from ALL pools feed penalties (spec #59/#35).
  /// Deterministic.
  static TasteProfile _synthesizeProfile({
    QuickPicksSignalProvider? signalProvider,
    required List<Track> candidates,
    required List<Track> favorites,
    required List<String> searchQueries,
  }) {
    final provider = signalProvider;
    if (provider == null) return TasteProfile.empty();

    final events = <TrackEvent>[];
    for (final track in candidates) {
      final signal = provider.signalFor(track.id);
      if (signal == null) continue;
      events.add(TrackEvent(
        trackId: track.id,
        artistName:
            signal.artistName.isNotEmpty ? signal.artistName : track.artistName,
        completionRate: signal.completionRate,
        playCount: signal.playCount,
        skipCount: signal.skipCount,
        replayCount: signal.replayCount,
        likeCount: 0,
        lastPlayed: DateTime.now(),
      ));
    }
    // Top artists from the long-term model are strong artist evidence.
    final topArtists = provider.topArtists(limit: 10);
    // Trusted genre vocabulary from the signal facade.
    final seedGenres = provider.topGenres(limit: 5);

    return TasteProfile.build(
      events: events,
      favoriteArtists: topArtists,
      searchQueries: searchQueries,
      seedGenres: seedGenres,
      seedGenreWeight: 1.0,
    );
  }

  void _traceLoad({
    required int raw,
    required int validated,
    required int ranked,
    required int finalCount,
    required TasteProfile profile,
  }) {
    if (!kDebugMode) return;
    debugPrint('RECOMMENDATION_LOAD section=quick_picks '
        'candidates=$raw validated=$validated ranked=$ranked final=$finalCount '
        'profileVersion=${profile.profileVersion} rankerVersion=$kRankerVersion '
        'candidateVersion=$kCandidateVersion '
        'personalizationConfidence='
        '${profile.personalizationConfidence.toStringAsFixed(2)}');
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

  /// User's preferred genres (from play signals), strongest first.
  List<String> topGenres({int limit = 5});
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
/// Carries its full feature breakdown + confidence for debugging
/// (spec #69/#70).
class QuickPickCandidate {
  QuickPickCandidate({
    required this.track,
    required this.reason,
    required this.score,
    List<CandidateReason> secondaryReasons = const [],
    this.source,
    this.confidence = 0,
    this.features = const {},
    this.isExploration = false,
    String? trackId,
  })  : secondaryReasons = List.of(secondaryReasons),
        trackId = trackId ?? track.id;

  final Track track;
  final CandidateReason reason;
  double score;
  List<CandidateReason> secondaryReasons;
  final String? source;

  /// Semantic id (may differ from track.id for non-Track candidates).
  final String trackId;
  final double confidence;
  final Map<String, double> features;
  final bool isExploration;

  @override
  String toString() =>
      'QuickPick(${track.trackName} score=${score.toStringAsFixed(2)} '
      'reason=${reason.name} conf=${confidence.toStringAsFixed(2)})';
}
