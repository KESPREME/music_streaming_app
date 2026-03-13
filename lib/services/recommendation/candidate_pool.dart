// lib/services/recommendation/candidate_pool.dart
// Multi-source candidate generation for Spotify-level recommendations

import '../../models/track.dart';
import '../recommendation_service.dart';
import 'taste_vector.dart';
import 'intent_detector.dart';

/// Represents the source category of a candidate track
enum CandidateSource {
  favoriteArtist,   // From top artists, not recently played
  similarArtist,    // Genre cluster overlap
  rediscovery,      // High engagement + lastPlayed > 30 days
  exploration,      // Never-heard artists matching genre profile
  trending,         // From trending tracks
  intentBased,      // Matching current listening intent
}

/// A candidate track with metadata about why it was selected
class ScoredCandidate {
  final Track track;
  final CandidateSource source;
  final double relevanceScore;
  final String? reason; // e.g. "Because you love Arctic Monkeys"
  
  ScoredCandidate({
    required this.track,
    required this.source,
    required this.relevanceScore,
    this.reason,
  });
}

/// Row metadata for the multi-row For You feed
class ForYouRow {
  final String title;
  final String? badge;       // emoji badge
  final List<Track> tracks;
  final ForYouRowType type;
  final String? contextArtist; // For "Because you love X" rows
  
  const ForYouRow({
    required this.title,
    this.badge,
    required this.tracks,
    required this.type,
    this.contextArtist,
  });
}

enum ForYouRowType {
  becauseYouLove,
  recentlyInspired,
  trending,
  rediscover,
  discoverNew,
  moodBased,
  genreMix,
}

/// Generates a pool of candidate tracks from multiple sources
class CandidatePool {
  /// Build candidate pool from all available sources
  static List<ScoredCandidate> buildPool({
    required Map<String, TrackSignal> signalCache,
    required TasteVector tasteVector,
    required ListeningIntent intent,
    required List<Track> trendingTracks,
    required List<Track> recentlyPlayed,
    required List<String> topArtists,
    required Set<String> recentlyPlayedIds,
  }) {
    final pool = <ScoredCandidate>[];
    final seenIds = <String>{};
    final now = DateTime.now();
    
    // Source 1: Favorite Artists — tracks not recently played
    for (final signal in signalCache.values) {
      if (topArtists.contains(signal.artistName) && 
          !recentlyPlayedIds.contains(signal.trackId)) {
        if (!seenIds.contains(signal.trackId)) {
          seenIds.add(signal.trackId);
          pool.add(ScoredCandidate(
            track: Track(
              id: signal.trackId,
              trackName: '', // Will be enriched later
              artistName: signal.artistName,
              albumName: '',
              albumArtUrl: '',
              previewUrl: '',
              source: 'cached_signal',
              duration: null,
            ),
            source: CandidateSource.favoriteArtist,
            relevanceScore: signal.engagementScore,
            reason: 'From your favorite: ${signal.artistName}',
          ));
        }
      }
    }
    
    // Source 2: Rediscovery — loved tracks not played in 30+ days
    for (final signal in signalCache.values) {
      final daysSince = now.difference(signal.lastPlayed).inDays;
      if (daysSince >= 30 && signal.engagementScore > 0.6 && !seenIds.contains(signal.trackId)) {
        seenIds.add(signal.trackId);
        pool.add(ScoredCandidate(
          track: Track(
            id: signal.trackId,
            trackName: '',
            artistName: signal.artistName,
            albumName: '',
            albumArtUrl: '',
            previewUrl: '',
            source: 'cached_signal',
            duration: null,
          ),
          source: CandidateSource.rediscovery,
          relevanceScore: signal.engagementScore * 0.8 + (daysSince / 365.0).clamp(0, 0.2),
          reason: 'Rediscover this gem',
        ));
      }
    }
    
    // Source 3: Trending — boost trending tracks matching user taste
    for (final track in trendingTracks) {
      if (!seenIds.contains(track.id)) {
        seenIds.add(track.id);
        final genreAffinity = tasteVector.genreAffinityFor(track.artistName, trackName: track.trackName);
        pool.add(ScoredCandidate(
          track: track,
          source: CandidateSource.trending,
          relevanceScore: 0.5 + genreAffinity * 0.3,
          reason: '🔥 Trending',
        ));
      }
    }
    
    // Source 4: Exploration — new artists from trending matching genre profile
    for (final track in trendingTracks) {
      final isKnown = signalCache.values.any((s) => s.artistName == track.artistName);
      if (!isKnown && !seenIds.contains(track.id)) {
        final genreAffinity = tasteVector.genreAffinityFor(track.artistName, trackName: track.trackName);
        if (genreAffinity > 0.3) {
          seenIds.add(track.id);
          pool.add(ScoredCandidate(
            track: track,
            source: CandidateSource.exploration,
            relevanceScore: genreAffinity * 0.7,
            reason: '✨ New for you',
          ));
        }
      }
    }
    
    return pool;
  }
  
  /// Build contextual rows for the multi-row For You feed
  static List<ForYouRow> buildForYouRows({
    required List<Track> allCandidates,
    required List<Track> trendingTracks,
    required List<Track> recentlyPlayed,
    required Map<String, TrackSignal> signalCache,
    required TasteVector tasteVector,
    required ListeningIntent intent,
    required List<String> topArtists,
    int tracksPerRow = 10,
  }) {
    final rows = <ForYouRow>[];
    final usedIds = <String>{};
    final now = DateTime.now();
    
    // Row 1: "Because you love {topArtist}" — tracks from/related to top artist
    if (topArtists.isNotEmpty) {
      final topArtist = topArtists.first;
      final artistTracks = allCandidates.where(
        (t) => t.artistName.toLowerCase() == topArtist.toLowerCase() && !usedIds.contains(t.id)
      ).take(tracksPerRow).toList();
      
      // Also add tracks from similar genre
      if (artistTracks.length < tracksPerRow) {
        final artistGenres = GenreMapper.inferGenres(topArtist);
        for (final track in allCandidates) {
          if (artistTracks.length >= tracksPerRow) break;
          if (usedIds.contains(track.id) || artistTracks.any((t) => t.id == track.id)) continue;
          final trackGenres = GenreMapper.inferGenres(track.artistName);
          final overlap = artistGenres.keys.any((g) => trackGenres.containsKey(g));
          if (overlap) artistTracks.add(track);
        }
      }
      
      if (artistTracks.isNotEmpty) {
        for (final t in artistTracks) { usedIds.add(t.id); }
        rows.add(ForYouRow(
          title: 'Because you love $topArtist',
          badge: '❤️',
          tracks: artistTracks.take(tracksPerRow).toList(),
          type: ForYouRowType.becauseYouLove,
          contextArtist: topArtist,
        ));
      }
    }
    
    // Row 2: "Inspired by your recent listening" — intent-based
    final intentTracks = <Track>[];
    for (final track in allCandidates) {
      if (usedIds.contains(track.id)) continue;
      if (intent.dominantGenre != null) {
        final genres = GenreMapper.inferGenres(track.artistName);
        if (genres.containsKey(intent.dominantGenre)) {
          intentTracks.add(track);
          usedIds.add(track.id);
          if (intentTracks.length >= tracksPerRow) break;
        }
      }
    }
    // Fill remaining with top-scoring candidates
    if (intentTracks.length < tracksPerRow) {
      for (final track in allCandidates) {
        if (usedIds.contains(track.id)) continue;
        intentTracks.add(track);
        usedIds.add(track.id);
        if (intentTracks.length >= tracksPerRow) break;
      }
    }
    if (intentTracks.isNotEmpty) {
      rows.add(ForYouRow(
        title: 'Inspired by your recent listening',
        badge: '🎧',
        tracks: intentTracks,
        type: ForYouRowType.recentlyInspired,
      ));
    }
    
    // Row 3: "Trending Now" — from trendingTracks
    final trendingRow = trendingTracks
        .where((t) => !usedIds.contains(t.id))
        .take(tracksPerRow)
        .toList();
    if (trendingRow.isNotEmpty) {
      for (final t in trendingRow) { usedIds.add(t.id); }
      rows.add(ForYouRow(
        title: 'Trending Now',
        badge: '🔥',
        tracks: trendingRow,
        type: ForYouRowType.trending,
      ));
    }
    
    // Row 4: "Rediscover Your Favorites" — old loved tracks
    final rediscoverTracks = <Track>[];
    for (final track in allCandidates) {
      if (usedIds.contains(track.id)) continue;
      final signal = signalCache[track.id];
      if (signal != null) {
        final daysSince = now.difference(signal.lastPlayed).inDays;
        if (daysSince >= 14 && signal.engagementScore > 0.5) {
          rediscoverTracks.add(track);
          usedIds.add(track.id);
          if (rediscoverTracks.length >= tracksPerRow) break;
        }
      }
    }
    if (rediscoverTracks.isNotEmpty) {
      rows.add(ForYouRow(
        title: 'Rediscover Your Favorites',
        badge: '🔁',
        tracks: rediscoverTracks,
        type: ForYouRowType.rediscover,
      ));
    }
    
    // Row 5: "Discover Something New" — exploration candidates
    final explorationTracks = allCandidates
        .where((t) => !usedIds.contains(t.id) && 
            !signalCache.containsKey(t.id)) // Never heard before
        .take(tracksPerRow)
        .toList();
    if (explorationTracks.isNotEmpty) {
      for (final t in explorationTracks) { usedIds.add(t.id); }
      rows.add(ForYouRow(
        title: 'Discover Something New',
        badge: '✨',
        tracks: explorationTracks,
        type: ForYouRowType.discoverNew,
      ));
    }
    
    return rows;
  }
}
