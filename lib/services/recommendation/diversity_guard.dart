// lib/services/recommendation/diversity_guard.dart
// Post-ranking filter to prevent repetitive recommendations

import '../../models/track.dart';
import 'taste_vector.dart';

/// Enforces diversity constraints on ranked track lists
class DiversityGuard {
  /// Maximum tracks per artist in a single row
  static const int maxPerArtist = 2;
  
  /// Maximum tracks per genre in a single row
  static const int maxPerGenre = 4;
  
  /// Minimum unique genres required in top 10
  static const int minGenresInTop10 = 2;
  
  /// Apply diversity filtering to a ranked list
  static List<Track> apply(List<Track> ranked, {int? limit}) {
    if (ranked.isEmpty) return ranked;
    
    final result = <Track>[];
    final artistCount = <String, int>{};
    final genreCount = <String, int>{};
    final skipped = <Track>[];
    
    for (final track in ranked) {
      final artist = track.artistName.toLowerCase();
      final currentArtistCount = artistCount[artist] ?? 0;
      
      // Check artist limit
      if (currentArtistCount >= maxPerArtist) {
        skipped.add(track);
        continue;
      }
      
      // Check genre limit
      final genres = GenreMapper.inferGenres(track.artistName);
      bool genreBlocked = false;
      for (final genre in genres.keys) {
        if ((genreCount[genre] ?? 0) >= maxPerGenre) {
          genreBlocked = true;
          break;
        }
      }
      
      if (genreBlocked) {
        skipped.add(track);
        continue;
      }
      
      // Accept track
      result.add(track);
      artistCount[artist] = currentArtistCount + 1;
      for (final genre in genres.keys) {
        genreCount[genre] = (genreCount[genre] ?? 0) + 1;
      }
      
      if (limit != null && result.length >= limit) break;
    }
    
    // If we need more tracks, add from skipped
    if (limit != null && result.length < limit) {
      for (final track in skipped) {
        result.add(track);
        if (result.length >= limit) break;
      }
    }
    
    // Ensure minimum genre diversity in top 10
    if (result.length >= 10) {
      final top10Genres = <String>{};
      for (final track in result.take(10)) {
        top10Genres.addAll(GenreMapper.inferGenres(track.artistName).keys);
      }
      
      if (top10Genres.length < minGenresInTop10 && skipped.isNotEmpty) {
        // Try to swap in a different-genre track
        for (final track in skipped) {
          final trackGenres = GenreMapper.inferGenres(track.artistName);
          final newGenres = trackGenres.keys.where((g) => !top10Genres.contains(g));
          if (newGenres.isNotEmpty && result.length > 8) {
            // Swap with last track in top 10
            result.insert(8, track);
            if (limit != null && result.length > limit) {
              result.removeLast();
            }
            break;
          }
        }
      }
    }
    
    return result;
  }
  
  /// Apply diversity to a ForYouRow — stricter per-row limits
  static List<Track> applyToRow(List<Track> tracks, {int maxTracks = 12}) {
    return apply(tracks, limit: maxTracks);
  }
}
