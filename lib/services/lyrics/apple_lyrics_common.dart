// lib/services/lyrics/apple_lyrics_common.dart
// Shared helpers for the Apple Music TTML mirrors.
//
// Three providers serve the same catalogue with the same syllable timings -
// lrc.red, BiniLyrics and PaxSenix. They differ only in how the recording is
// identified: by ISRC, by name-and-length, or by Apple catalog id. The timings
// are identical once fetched, so the search and TTML parsing live here and each
// provider contributes only its lookup.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';
import 'better_lyrics_provider.dart';

/// A track being looked up in an Apple-style lyrics mirror.
class AppleLyricsQuery {
  const AppleLyricsQuery({
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
    this.isrc,
    this.appleId,
  });

  final String title;
  final String artist;
  final String? album;
  final int? durationMs;

  /// International Standard Recording Code. The most reliable key when present:
  /// it identifies the recording itself rather than a name spelling.
  final String? isrc;

  /// Apple Music catalog id, when the caller already has one.
  final String? appleId;

  /// Seconds, which is what these mirrors accept.
  int? get durationSeconds {
    final ms = durationMs;
    if (ms == null || ms <= 0) return null;
    return (ms / 1000).round();
  }
}

/// Shared HTTP + TTML plumbing for the Apple mirrors.
abstract class AppleLyricsSource {
  static const Duration _timeout = Duration(seconds: 8);
  static const String _userAgent =
      'MusicStreamingApp/1.0.0 (lyrics; +https://github.com/)';

  final http.Client _client = http.Client();

  /// Fetches and parses a TTML document, or null when it is unusable.
  Future<List<LyricsEntry>?> fetchTtml(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      if (response.bodyBytes.isEmpty) return null;

      // Served as XML, sometimes with a UTF-8 BOM or a leading comment.
      final body = _stripPreamble(response.bodyBytes);
      if (body.trim().isEmpty) return null;

      final entries = BetterLyricsProvider.parseTtml(body);
      return entries.isEmpty ? null : entries;
    } catch (e) {
      // Every one of these mirrors is a volunteer host. A failure here is
      // expected, not exceptional: the racing layer moves on to the next.
      if (kDebugMode) {
        debugPrint('AppleLyricsSource: TTML fetch failed: $e');
      }
      return null;
    }
  }

  Map<String, String> get _headers => const {
        'User-Agent': _userAgent,
        'Accept': 'application/xml, text/xml, */*',
      };

  /// Decodes bytes as UTF-8 and removes anything before the root element.
  ///
  /// A document that does not start at `<tt` parses to nothing at all, and a
  /// stray BOM makes the first `<` miss, which looks exactly like an empty
  /// lyric rather than a malformed one.
  static String _stripPreamble(List<int> bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    final rootIndex = text.indexOf('<tt');
    if (rootIndex > 0) {
      text = text.substring(rootIndex);
    } else if (rootIndex < 0) {
      // Not TTML at all. Some mirrors answer a lyric request with an HTML error
      // page, and handing that to the parser would produce one garbage line.
      return '';
    }
    return text;
  }

  /// Whether a duration is close enough to call it the same recording.
  ///
  /// Three seconds, matching the reference. A cover running twenty seconds
  /// longer is a different recording and must not borrow these timings - that is
  /// how a song ends up with the right words at the wrong moments.
  static bool durationMatches(int? candidateSec, int? wantedSec) {
    if (candidateSec == null || wantedSec == null) return false;
    return (candidateSec - wantedSec).abs() <= durationToleranceSeconds;
  }

  static const int durationToleranceSeconds = 3;

  /// Normalises a title for comparison: lower case, punctuation dropped, and the
  /// bracketed qualifiers removed that catalogues disagree about.
  static String normaliseTitle(String title) {
    var t = title.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'[\(\[\-–—].*?[\)\]]'), ' ');
    t = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String normaliseArtist(String artist) =>
      artist
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  /// Whether a candidate's title and artist are the same recording.
  ///
  /// Both have to agree loosely. Title alone matches covers and remixes; artist
  /// alone matches every song by an artist that anyone has ever uploaded.
  static bool titlesMatch(String candidate, String wanted) {
    final a = normaliseTitle(candidate);
    final b = normaliseTitle(wanted);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    // A featured credit on either side should not fail the match.
    return a.contains(b) || b.contains(a);
  }
}