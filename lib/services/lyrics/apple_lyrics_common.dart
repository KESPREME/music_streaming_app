// lib/services/lyrics/apple_lyrics_common.dart
// Shared helpers for the Apple Music TTML mirrors.
//
// Three providers serve the same catalogue with the same syllable timings -
// lrc.red, BiniLyrics and PaxSenix. They differ only in how the recording is
// identified: by ISRC, by name-and-length, or by Apple catalog id. The timings
// are identical once fetched, so the search and TTML parsing live here and each
// provider contributes only its lookup.

import 'package:flutter/foundation.dart';

import '../../models/lyrics_entry.dart';
import 'better_lyrics_provider.dart';
import 'lyrics_http.dart';

/// How a TTML document is downloaded.
///
/// The lead's lookup passes one that remembers what it has fetched, so lrc.red
/// and Bini - whose `lyricsUrl` points at the very same `lrc.red/s/{ISRC}.ttml`
/// file - do not download it twice. Null means the source's own client.
typedef DocumentFetcher = Future<String?> Function(String url);

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
  AppleLyricsSource({LyricsHttp? http}) : _http = http ?? LyricsHttp.shared;

  final LyricsHttp _http;

  /// The shared client, for subclasses that make requests of their own.
  @protected
  LyricsHttp get lyricsHttp => _http;

  /// Fetches and parses a TTML document, or null when it is unusable.
  ///
  /// [get] replaces the download when supplied, so a caller that already holds
  /// - or is already fetching - the document can hand it over. Parsing is the
  /// same either way.
  Future<List<LyricsEntry>?> fetchTtml(
    String url, {
    DocumentFetcher? get,
  }) async {
    try {
      final body = await (get ?? _download)(url);
      if (body == null) return null;
      return parseTtmlDocument(body);
    } catch (e) {
      // Every one of these mirrors is a volunteer host. A failure here is
      // expected, not exceptional: the racing layer moves on to the next.
      if (kDebugMode) {
        debugPrint('AppleLyricsSource: TTML fetch failed: $e');
      }
      return null;
    }
  }

  Future<String?> _download(String url) => _http.getText(
        url,
        headers: const {'Accept': 'application/xml, text/xml, */*'},
      );

  /// A TTML document parsed, or null when it is not one or holds no lines.
  ///
  /// Pure: no request is made, so it is what a test (or a caller that already
  /// has the body) uses.
  List<LyricsEntry>? parseTtmlDocument(String body) => parseTtmlBody(body);

  /// [parseTtmlDocument] without needing an instance.
  static List<LyricsEntry>? parseTtmlBody(String body) {
    // Served as XML, sometimes with a UTF-8 BOM or a leading comment.
    final text = _stripPreamble(body);
    if (text.trim().isEmpty) return null;
    final entries = BetterLyricsProvider.parseTtml(text);
    return entries.isEmpty ? null : entries;
  }

  /// Removes anything before the root element.
  ///
  /// A document that does not start at `<tt` parses to nothing at all, and a
  /// stray BOM makes the first `<` miss, which looks exactly like an empty
  /// lyric rather than a malformed one.
  static String _stripPreamble(String body) {
    var text = body;
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
  ///
  /// An UNKNOWN duration (on either side, or a non-positive one) cannot veto:
  /// there is nothing to compare, and the reference counts the distance as 0
  /// then (`LrcRed.kt` `best()`). Refusing every candidate for a local file
  /// with no length tag would make this source useless to it.
  static bool durationMatches(int? candidateSec, int? wantedSec) {
    if (candidateSec == null || wantedSec == null || wantedSec <= 0) {
      return true;
    }
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