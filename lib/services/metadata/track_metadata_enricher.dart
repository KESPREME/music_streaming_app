import '../../models/track.dart';

/// Service responsible for sanitizing and enriching track metadata.
///
/// In streaming responses (especially YouTube Music and third-party APIs),
/// subtitle or byline fields often arrive concatenated or misattributed:
///  - "The Weeknd, After Hours" (Artist field containing both Artist and Album)
///  - "The Weeknd • After Hours" or "After Hours - The Weeknd"
///  - "Blinding Lights, The Weeknd" (Song title leaking into Artist field)
///  - "Album - After Hours" or "Single - Starboy" (Type prefixes in Album)
///  - "After Hours by The Weeknd" (Artist leaking into Album)
///  - "Artist - Topic" (YouTube auto-generated channel suffix)
///
/// This enricher separates and normalizes these fields cleanly to ensure
/// BitChord-grade metadata accuracy.
class TrackMetadataEnricher {
  TrackMetadataEnricher._();

  static final RegExp _topicRegex = RegExp(r'\s*-\s*topic\b', caseSensitive: false);
  static final RegExp _typePrefixRegex = RegExp(r'^(album|single|ep|song|video)\s*[-:•·]\s*', caseSensitive: false);
  static final RegExp _byArtistRegex = RegExp(r'\s+(?:by|from)\s+.*$', caseSensitive: false);
  static final RegExp _durationRegex = RegExp(r'^\d{1,3}:\d{2}(:\d{2})?$');
  static final RegExp _tallyRegex = RegExp(
    r'^[\d,.]+\s*[KMB]?\s*(plays?|views?|streams?|listeners?|likes?)$',
    caseSensitive: false,
  );
  static final RegExp _yearRegex = RegExp(r'^(19|20)\d{2}$');
  static final RegExp _explicitTitleRegex = RegExp(r'\s*[\(\[]\s*explicit\s*[\)\]]', caseSensitive: false);

  /// Sanitizes title, artist, and album components and returns clean values.
  static ({String title, String artist, String album}) sanitize({
    required String title,
    required String artist,
    required String album,
  }) {
    var cleanTitle = title.replaceAll(_explicitTitleRegex, '').trim();
    var cleanArtist = artist.trim();
    var cleanAlbum = album.trim();

    // 1. Strip "- Topic" suffix from artist
    cleanArtist = cleanArtist.replaceAll(_topicRegex, '').trim();

    // 2. Strip noise prefixes from album ("Album - ", "Single - ", etc.)
    cleanAlbum = cleanAlbum.replaceAll(_typePrefixRegex, '').trim();

    // 3. Remove "by Artist" from album name if present (e.g. "After Hours by The Weeknd")
    if (cleanArtist.isNotEmpty) {
      final byThisArtist = RegExp(r'\s+(?:by|from)\s+' + RegExp.escape(cleanArtist) + r'$', caseSensitive: false);
      cleanAlbum = cleanAlbum.replaceAll(byThisArtist, '').trim();
    }
    cleanAlbum = cleanAlbum.replaceAll(_byArtistRegex, '').trim();

    // 4. Handle multi-segment artist (e.g. "The Weeknd • After Hours", "Blinding Lights, The Weeknd", "Song • The Weeknd")
    final hasBylineDelimiter = cleanArtist.contains(' • ') ||
        cleanArtist.contains(' · ') ||
        cleanArtist.contains(' | ') ||
        cleanArtist.contains(' - ');

    final artistSegments = _splitCandidateSegments(cleanArtist);
    if (artistSegments.length >= 2) {
      final seg0 = artistSegments[0].trim();
      final seg1 = artistSegments[1].trim();

      if (_isTypeLabel(seg0)) {
        // "Song • The Weeknd"
        cleanArtist = seg1;
      } else if (hasBylineDelimiter &&
          (cleanAlbum.isEmpty || cleanAlbum.toLowerCase() == 'unknown album')) {
        // "The Weeknd • Starboy" or "The Weeknd - After Hours"
        if (!_isMetadataSegment(seg1)) {
          cleanArtist = seg0;
          cleanAlbum = seg1;
        }
      } else if (_areIdentical(seg0, cleanTitle)) {
        // Song title leaked into first segment: "Blinding Lights, The Weeknd"
        cleanArtist = seg1;
      } else if (_areIdentical(seg1, cleanTitle)) {
        // Song title leaked into second segment: "The Weeknd, Blinding Lights"
        cleanArtist = seg0;
      } else {
        // Filter out segments that duplicate album or title
        final filteredSegments = artistSegments.where((s) {
          final segLower = s.trim().toLowerCase();
          final albumLower = cleanAlbum.toLowerCase();
          final titleLower = cleanTitle.toLowerCase();
          return (cleanAlbum.isEmpty || segLower != albumLower) &&
              (cleanTitle.isEmpty || segLower != titleLower) &&
              !_isMetadataSegment(s.trim());
        }).toList();

        if (filteredSegments.isNotEmpty) {
          cleanArtist = filteredSegments.join(', ');
        }
      }
    } else if (cleanTitle.isNotEmpty && cleanArtist.isNotEmpty) {
      cleanArtist = _stripSongTitleFromArtist(cleanArtist, cleanTitle);
    }

    // 6. Handle Case: Album contains Artist (e.g. "The Weeknd - After Hours" or "The Weeknd, After Hours")
    if (cleanAlbum.isNotEmpty && cleanArtist.isNotEmpty) {
      final albumSegments = _splitCandidateSegments(cleanAlbum);
      if (albumSegments.length >= 2) {
        final nonArtistSegments = albumSegments.where((s) {
          final seg = s.trim().toLowerCase();
          final art = cleanArtist.toLowerCase();
          return seg != art && !_areIdentical(s, cleanArtist) && !_isMetadataSegment(s);
        }).toList();

        if (nonArtistSegments.isNotEmpty && nonArtistSegments.length < albumSegments.length) {
          cleanAlbum = nonArtistSegments.join(' - ');
        }
      }
    }

    // 7. Handle Case: Album is identical to Title (single track release where album was set to song name)
    // Keep it if it's genuinely a self-titled single/album, but strip if formatted as "Title - Artist"
    if (cleanAlbum.contains(' - ') && cleanArtist.isNotEmpty) {
      final parts = cleanAlbum.split(' - ');
      if (parts.length == 2) {
        if (_areIdentical(parts[0], cleanArtist)) {
          cleanAlbum = parts[1].trim();
        } else if (_areIdentical(parts[1], cleanArtist)) {
          cleanAlbum = parts[0].trim();
        }
      }
    }

    // 8. Fallbacks for empty states
    if (cleanArtist.isEmpty) cleanArtist = 'Unknown Artist';
    if (cleanTitle.isEmpty) cleanTitle = 'Unknown Track';

    return (
      title: cleanTitle,
      artist: cleanArtist,
      album: cleanAlbum,
    );
  }

  /// Sanitizes a [Track] instance and returns an updated copy.
  static Track sanitizeTrack(Track track) {
    final hasExplicitTag = track.trackName.contains(_explicitTitleRegex);
    final isExplicit = track.isExplicit || hasExplicitTag;

    final cleaned = sanitize(
      title: track.trackName,
      artist: track.artistName,
      album: track.albumName,
    );

    if (cleaned.title == track.trackName &&
        cleaned.artist == track.artistName &&
        cleaned.album == track.albumName &&
        isExplicit == track.isExplicit) {
      return track;
    }

    return track.copyWith(
      trackName: cleaned.title,
      artistName: cleaned.artist,
      albumName: cleaned.album,
      isExplicit: isExplicit,
    );
  }

  static String _stripSongTitleFromArtist(String rawArtist, String rawTitle) {
    final titleLower = rawTitle.trim().toLowerCase();
    final segments = _splitCandidateSegments(rawArtist);

    if (segments.length <= 1) {
      return rawArtist;
    }

    final filtered = segments.where((s) {
      final segLower = s.trim().toLowerCase();
      return segLower != titleLower &&
          !_areIdentical(segLower, titleLower) &&
          segLower != 'song' &&
          segLower != 'video' &&
          !_isMetadataSegment(s);
    }).toList();

    if (filtered.isNotEmpty) {
      return filtered.join(', ').trim();
    }
    return rawArtist;
  }

  static List<String> _splitCandidateSegments(String text) {
    // Splits on ' • ', ' · ', ' | ', or ', ' (only when not inside parentheses)
    if (text.contains(' • ')) {
      return text.split(' • ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    if (text.contains(' · ')) {
      return text.split(' · ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    if (text.contains(' | ')) {
      return text.split(' | ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    if (text.contains(' - ')) {
      return text.split(' - ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    if (text.contains(', ')) {
      return text.split(', ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return [text.trim()];
  }

  static bool _isMetadataSegment(String seg) {
    final s = seg.trim();
    if (_durationRegex.hasMatch(s)) return true;
    if (_tallyRegex.hasMatch(s)) return true;
    if (_yearRegex.hasMatch(s)) return true;
    final lower = s.toLowerCase();
    if (lower == 'song' || lower == 'video' || lower == 'official video') return true;
    return false;
  }

  static bool _isTypeLabel(String text) {
    final lower = text.trim().toLowerCase();
    return lower == 'song' ||
        lower == 'video' ||
        lower == 'official video' ||
        lower == 'album' ||
        lower == 'single' ||
        lower == 'ep';
  }

  static bool _areIdentical(String a, String b) {
    final normA = a.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '').trim();
    final normB = b.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '').trim();
    return normA.isNotEmpty && normA == normB;
  }
}
