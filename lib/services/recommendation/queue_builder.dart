import '../../models/track.dart';

/// Builds the station that plays on after a one-off song or auto-fills the queue.
///
/// Direct port of BitChord's [QueueBuilder] architecture.
/// Solves two critical problems:
///  1. Duplicate recordings: YouTube Music watch queues routinely carry both the
///     official audio and music-video uploads under separate IDs with slightly
///     different titles ("Kesariya | Official Video" vs "Kesariya"). Deduplication
///     on normalized title + artist set avoids playing the same track twice.
///  2. Artist balancing: Radio mixes tend to lean heavily on the seed artist.
///     Capping the seed artist at 4 tracks and any other artist at 2 tracks
///     ensures the queue feels diverse, high-taste, and expertly curated.
class QueueBuilder {
  QueueBuilder._();

  /// No more than this many tracks by one artist in a single batch.
  static const int perArtistLimit = 2;

  /// The artist the station was seeded on gets more room, but not the run of it.
  static const int seedArtistLimit = 4;

  static final RegExp _noise = RegExp(
    r'\((?:official|lyric|lyrics|lyrical|audio|video|visuali[sz]er|full song|hd|4k)[^)]*\)'
    r'|\(from[^)]*\)'
    r'|\[[^\]]*\]'
    r'|\b(?:official (?:video|audio|music video)|lyrical video|full video|4k video)\b',
    caseSensitive: false,
  );

  static final RegExp _topic = RegExp(r'\s*-\s*topic\b', caseSensitive: false);
  static final RegExp _punctuation = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _artistSplitter = RegExp(
    r'[,&·•;]|\s+feat\.?\b|\s+ft\.?\b|\s+x\b|\s+with\b',
    caseSensitive: false,
  );

  /// Appends at most [limit] tracks from [candidates] after [existing],
  /// prioritizing catalogue audio cuts over videos, rejecting duplicate recordings,
  /// and enforcing artist diversity caps.
  static List<Track> extend(
    List<Track> existing,
    List<Track> candidates, {
    int limit = 10,
  }) {
    final taken = List<Track>.from(existing);
    final perArtist = <String, int>{};
    final seedArtists = existing.isNotEmpty
        ? artistSet(existing.last.artistName)
        : <String>{};
    final out = <Track>[];

    // Prefer catalogue audio tracks over music video uploads
    final songsOnly = candidates.where((c) => !_isVideoTrack(c)).toList();
    final ordered = songsOnly.isNotEmpty ? songsOnly : candidates;

    for (final candidate in ordered) {
      if (out.length >= limit) break;
      if (taken.any((it) => isSameRecording(it, candidate))) continue;

      final artists = artistSet(candidate.artistName);
      final key = artists.isNotEmpty ? (artists.toList()..sort()).first : null;
      if (key != null) {
        final cap = artists.any((a) => seedArtists.contains(a))
            ? seedArtistLimit
            : perArtistLimit;
        final played = perArtist[key] ?? 0;
        if (played >= cap) continue;
        perArtist[key] = played + 1;
      }

      taken.add(candidate);
      out.add(candidate);
    }

    return out;
  }

  /// Whether two entries represent the same musical recording.
  static bool isSameRecording(Track a, Track b) {
    if (a.id == b.id) return true;

    final normA = normalisedTitle(a.trackName);
    final normB = normalisedTitle(b.trackName);
    if (normA.isEmpty || normA != normB) return false;

    // Shared artist check
    final left = artistSet(a.artistName);
    final right = artistSet(b.artistName);
    return left.isEmpty || right.isEmpty || left.any((it) => right.contains(it));
  }

  /// Normalizes a song title by stripping video labels, noise parentheticals,
  /// and punctuation.
  static String normalisedTitle(String raw) {
    final beforePipe = raw.split(' | ').first;
    return beforePipe
        .toLowerCase()
        .replaceAll(_noise, ' ')
        .replaceAll(_punctuation, ' ')
        .replaceAll(_spaces, ' ')
        .trim();
  }

  /// Extracts the set of individual artists from an artist credit string.
  static Set<String> artistSet(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(_topic, ' ')
        .split(_artistSplitter)
        .map((s) => s.replaceAll(_punctuation, ' ').replaceAll(_spaces, ' ').trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  static bool _isVideoTrack(Track t) {
    final nameLower = t.trackName.toLowerCase();
    if (nameLower.contains('official music video') ||
        nameLower.contains('official video') ||
        nameLower.contains('4k video') ||
        nameLower.contains('full video')) {
      return true;
    }
    // High-res square artwork is catalogue, widescreen indicates video thumbnail
    return false;
  }
}
