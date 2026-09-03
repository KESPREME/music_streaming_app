import 'dart:math' as math;

import 'candidate_metadata.dart';
import 'ranker.dart';

/// One aggregated preference with count, recency and confidence
/// (spec #9). Weights decay over time but never fully erase — a listener
/// can hold a long-term favorite AND a current obsession (#10).
class AffinityEntry {
  AffinityEntry({required this.key})
      : rawWeight = 0,
        count = 0,
        _lastTouched = null;

  final String key;
  double rawWeight;
  int count;
  DateTime? _lastTouched;

  void add(double weight, DateTime at) {
    rawWeight += weight;
    count++;
    // First evidence sets the anchor; later evidence advances it only
    // forward — construction-time "now" must never masquerade as a touch.
    final current = _lastTouched;
    if (current == null || at.isAfter(current)) _lastTouched = at;
  }

  DateTime get lastTouched =>
      _lastTouched ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Exponential half-life decay (spec #10). No evidence yet → 0.
  double decayed(DateTime now, {Duration halfLife = const Duration(days: 45)}) {
    final touched = _lastTouched;
    if (touched == null || rawWeight == 0) return 0;
    final age = now.difference(touched);
    if (age <= Duration.zero) return rawWeight;
    final halfLives = age.inMicroseconds / halfLife.inMicroseconds;
    return rawWeight * math.pow(0.5, halfLives).toDouble();
  }
}

/// One play event feeding the profile (spec #9/#11). Different events
/// carry different intent strength — completion and replay weigh more
/// than a bare play, skips weigh negative (spec #11/#59).
class TrackEvent {
  TrackEvent({
    required this.trackId,
    required this.artistName,
    this.genre,
    this.completionRate = 0,
    this.playCount = 0,
    this.skipCount = 0,
    this.replayCount = 0,
    this.likeCount = 0,
    required this.lastPlayed,
  });

  final String trackId;
  final String artistName;
  final String? genre;
  final double completionRate;
  final int playCount;
  final int skipCount;
  final int replayCount;
  final int likeCount;
  final DateTime lastPlayed;

  /// Intent weight (spec #11): replayed/completed = strong positive,
  /// early-skipped = weak/negative.
  double get intentWeight {
    double w = 0;
    final completion = completionRate.clamp(0.0, 1.0);
    // Completed plays: strong. Minimum evidence floor per spec #58.
    w += completion * 0.6 + (playCount > 0 ? 0.1 : 0);
    if (replayCount > 0) w += (replayCount * 0.25).clamp(0.0, 1.0);
    if (likeCount > 0) w += 0.8;
    // 10-second-then-skip = weak/negative (spec #11).
    if (skipCount > 0 && completion < 0.3)
      w -= (skipCount * 0.3).clamp(0.0, 1.2);
    return w;
  }
}

/// Aggregated user taste (spec #9). Built from local signals only —
/// no fabrication, no network. Long-term horizons use slow decay;
/// the recent window keeps its own fast list for "current obsession".
class TasteProfile {
  TasteProfile._({
    required this.artists,
    required this.genres,
    required this.tracks,
    required this.trackSignals,
    required this.searchQueries,
    required this.eventCount,
    required this.personalizationConfidence,
    required this.recentArtistKeys,
    required this.favoriteArtistKeys,
    required Map<String, String> displayNames,
  }) : _displayNames = displayNames;

  final Map<String, AffinityEntry> artists;
  final Map<String, AffinityEntry> genres;
  final Map<String, AffinityEntry> tracks;

  /// Raw per-track behavior for penalty features (spec #35/#59).
  final Map<String, BehaviorSignal> trackSignals;

  /// Recent search queries, newest last (spec #61). Resolution to
  /// artist/track happens in [searchAffinityFor] (spec #62).
  final List<String> searchQueries;

  final int eventCount;
  final double personalizationConfidence;

  /// Artists touched inside the recent window (#9 recentArtists).
  final Set<String> recentArtistKeys;
  final Set<String> favoriteArtistKeys;

  /// lowercase key → most recent display casing.
  final Map<String, String> _displayNames;

  static const _recentWindow = Duration(days: 14);

  static TasteProfile empty() => TasteProfile._(
        artists: const {},
        genres: const {},
        tracks: const {},
        trackSignals: const {},
        searchQueries: const [],
        eventCount: 0,
        personalizationConfidence: 0,
        recentArtistKeys: const {},
        favoriteArtistKeys: const {},
        displayNames: const {},
      );

  /// Build the profile from track events + explicit favorites (spec #60).
  /// Deterministic: same events → same profile. [seedGenres] injects
  /// trusted genre vocabulary (e.g. from a signal facade) with moderate
  /// weight; [seedGenreWeight] controls that weight.
  factory TasteProfile.build({
    required List<TrackEvent> events,
    List<String> favoriteArtists = const [],
    List<String> searchQueries = const [],
    List<String> seedGenres = const [],
    double seedGenreWeight = 1.0,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final artistEntries = <String, AffinityEntry>{};
    final genreEntries = <String, AffinityEntry>{};
    final trackEntries = <String, AffinityEntry>{};
    final recentArtists = <String>{};
    final displayNames = <String, String>{};
    var strongEvents = 0;
    final artistSet = <String>{};

    for (final event in events) {
      final w = event.intentWeight;
      if (w <= 0 && event.playCount == 0) continue;

      final genre = normalizeGenre(event.genre);
      final artistKey = event.artistName.trim().toLowerCase();
      final lastPlayed = event.lastPlayed;

      if (artistKey.isNotEmpty) {
        artistSet.add(artistKey);
        displayNames[artistKey] = event.artistName.trim();
        (artistEntries[artistKey] ??= AffinityEntry(key: artistKey))
            .add(w, lastPlayed);
        if (clock.difference(lastPlayed) <= _recentWindow) {
          recentArtists.add(artistKey);
        }
      }
      if (genre != null) {
        (genreEntries[genre] ??= AffinityEntry(key: genre)).add(w, lastPlayed);
      }
      (trackEntries[event.trackId] ??= AffinityEntry(key: event.trackId))
          .add(w, lastPlayed);

      if (event.completionRate >= 0.6) strongEvents++;
    }

    for (final artist in favoriteArtists) {
      final key = artist.trim().toLowerCase();
      if (key.isEmpty) continue;
      displayNames.putIfAbsent(key, () => artist.trim());
      // Explicit favorite = strong artist signal (spec #60).
      (artistEntries[key] ??= AffinityEntry(key: key)).add(1.5, clock);
    }

    for (final genre in seedGenres) {
      final key = normalizeGenre(genre);
      if (key == null) continue;
      (genreEntries[key] ??= AffinityEntry(key: key))
          .add(seedGenreWeight, clock);
    }

    // Personalization confidence (spec #57): evidence volume + diversity.
    // Deliberately conservative — one play must NOT define taste (#58).
    final volume = (strongEvents / 25).clamp(0.0, 1.0);
    final diversity = (artistSet.length / 10).clamp(0.0, 1.0);
    final confidence = (volume * 0.7 + diversity * 0.3).clamp(0.0, 1.0);

    return TasteProfile._(
      artists: Map.unmodifiable(artistEntries),
      genres: Map.unmodifiable(genreEntries),
      tracks: Map.unmodifiable(trackEntries),
      trackSignals: Map.unmodifiable({
        for (final event in events)
          event.trackId: BehaviorSignal(
            playCount: event.playCount,
            skipCount: event.skipCount,
            completionRate: event.completionRate,
          ),
      }),
      searchQueries: List.unmodifiable(searchQueries),
      eventCount: events.length,
      personalizationConfidence: confidence,
      recentArtistKeys: Set.unmodifiable(recentArtists),
      favoriteArtistKeys:
          Set.unmodifiable(favoriteArtists.map((a) => a.trim().toLowerCase())),
      displayNames: Map.unmodifiable(displayNames),
    );
  }

  /// Cache/generation version — grows with behavior volume (#67).
  int get profileVersion => (eventCount / 10).floor() + 1;

  List<String> topArtists({int limit = 10}) {
    final ranked = _rankKeys(artists, limit);
    // Preserve display casing from the most recent source event.
    return [
      for (final key in ranked) _displayNames[key] ?? key,
    ];
  }

  List<String> topGenres({int limit = 5}) => _rankKeys(genres, limit);

  List<String> topTracks({int limit = 10}) => _rankKeys(tracks, limit);

  static List<String> _rankKeys(
    Map<String, AffinityEntry> entries,
    int limit,
  ) {
    final now = DateTime.now();
    final ranked = entries.values.toList()
      ..sort((a, b) {
        final cmp = b.decayed(now).compareTo(a.decayed(now));
        if (cmp != 0) return cmp;
        return a.key.compareTo(b.key);
      });
    return ranked.take(limit).map((e) => e.key).toList(growable: false);
  }

  /// Normalized 0-1 artist affinity (spec #27). Absolute saturation
  /// scale w/(w+1.5): monotonic in decayed weight, bounded, and stable
  /// when only one artist exists (max-normalization would make every
  /// single-artist profile exactly 1.0 and comparisons meaningless).
  double artistAffinity(String artistName) {
    final entry = artists[artistName.trim().toLowerCase()];
    if (entry == null) return 0;
    final w = entry.decayed(DateTime.now());
    return w <= 0 ? 0 : (w / (w + 1.5)).clamp(0.0, 1.0);
  }

  double genreAffinity(String genre) {
    final key = normalizeGenre(genre) ?? genre.trim().toLowerCase();
    final entry = genres[key];
    if (entry == null) return 0;
    final w = entry.decayed(DateTime.now());
    return w <= 0 ? 0 : (w / (w + 1.5)).clamp(0.0, 1.0);
  }

  double trackAffinity(String trackId) {
    final entry = tracks[trackId];
    if (entry == null) return 0;
    final w = entry.decayed(DateTime.now());
    return w <= 0 ? 0 : (w / (w + 1.5)).clamp(0.0, 1.0);
  }

  /// Query → item resolution (spec #62): a search matching the
  /// candidate's artist is strong intent; matching the title moderate.
  /// Never fabricates: no query match → 0.
  double searchAffinityFor(RichCandidate candidate) {
    if (searchQueries.isEmpty) return 0;
    var best = 0.0;
    for (final raw in searchQueries) {
      final query = raw.trim().toLowerCase();
      if (query.isEmpty) continue;
      final artistHit =
          candidate.artists.any((a) => a.trim().toLowerCase() == query);
      final titleHit =
          query.length >= 4 && candidate.title.toLowerCase().contains(query);
      final value = artistHit ? 0.6 : (titleHit ? 0.5 : 0.0);
      if (value > best) best = value;
    }
    return best;
  }
}
