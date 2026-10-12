// lib/services/lyrics/lrclib_provider.dart
// LRCLIB - a free, key-less, community lyrics database.
//
// Port of `LrcLib.kt`. Two calls, in order:
//
//   get     exact signature (artist + title + duration)
//   search  fuzzy, when `get` misses - YouTube titles carry noise the exact
//           endpoint will not match
//
// This provider returns SYNCED lyrics or nothing. Plain lyrics are a different
// product (no timings at all), so a record that has only those is a miss here:
// it would otherwise be handed to the synced parser and rendered as if every
// line began at 0:00.
//
// WHAT WAS WRONG BEFORE
//
//   * No timeout: a hung connection held the whole lookup open.
//   * `get` accepted a record with only plain lyrics, and the search fell back
//     to `results.first` - whichever record happened to be first, synced or not,
//     with any duration.
//   * The search picked the closest duration only when a duration was known,
//     and otherwise took the first hit blindly.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'lyrics_http.dart';

/// LRCLIB provider for synced lyrics.
/// API documentation: https://lrclib.net/docs
class LrcLibProvider {
  LrcLibProvider({LyricsHttp? http}) : _http = http ?? LyricsHttp.shared;

  final LyricsHttp _http;

  static const String _baseUrl = 'https://lrclib.net';

  /// Synced (LRC) lyrics for a track, or null when nothing synced is published.
  ///
  /// [album] is accepted for compatibility and deliberately not sent: YouTube's
  /// album name rarely matches LRCLIB's spelling, and `get` treats a mismatch
  /// as a miss. At most two requests are made.
  Future<String?> getLyrics({
    required String title,
    required String artist,
    int? durationSeconds,
    String? album,
  }) async {
    try {
      final wanted = durationSeconds != null && durationSeconds > 0
          ? durationSeconds
          : null;

      final exact = await _exactMatch(title, artist, wanted);
      if (exact != null) return exact;

      return await _bestSearchHit(title, artist, wanted);
    } catch (e) {
      if (kDebugMode) debugPrint('LrcLibProvider: Error getting lyrics: $e');
      return null;
    }
  }

  /// `/api/get`, accepted only if it carries synced lyrics.
  Future<String?> _exactMatch(String title, String artist, int? seconds) async {
    final body = await _http.getText(_url('/api/get', {
      'track_name': title,
      'artist_name': artist,
      if (seconds != null) 'duration': seconds.toString(),
    }));
    if (body == null) return null;
    return syncedFrom(body);
  }

  /// The `syncedLyrics` of a `get` response, or null if blank or absent.
  @visibleForTesting
  static String? syncedFrom(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      return _blankToNull(json['syncedLyrics']);
    } catch (_) {
      return null;
    }
  }

  /// `/api/search`, then the closest-length hit that has synced lyrics.
  Future<String?> _bestSearchHit(
      String title, String artist, int? seconds) async {
    final results = await _search(title: title, artist: artist);
    return pickBest(results, seconds)?.syncedLyrics;
  }

  /// Of [results], only those with non-blank synced lyrics; of those, the one
  /// whose length is nearest [wantedSeconds]; the earliest wins a tie. With no
  /// known length the first synced hit is taken.
  ///
  /// Never a record without synced lyrics, whatever its position.
  @visibleForTesting
  static LrcLibResult? pickBest(
      List<LrcLibResult> results, int? wantedSeconds) {
    LrcLibResult? best;
    var bestDistance = 1 << 30;
    for (final result in results) {
      if (_blankToNull(result.syncedLyrics) == null) continue;
      if (wantedSeconds == null) return result;
      final distance = (result.duration - wantedSeconds).abs();
      if (distance < bestDistance) {
        best = result;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// Search the LRCLIB API.
  Future<List<LrcLibResult>> _search({
    required String title,
    String? artist,
  }) async {
    final body = await _http.getText(_url('/api/search', {
      'track_name': title,
      if (artist != null && artist.isNotEmpty) 'artist_name': artist,
    }));
    if (body == null) return const <LrcLibResult>[];
    return parseSearch(body);
  }

  /// The hits in a `search` response; entries that are not records are skipped.
  @visibleForTesting
  static List<LrcLibResult> parseSearch(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! List) return const <LrcLibResult>[];
      return [
        for (final item in json)
          if (item is Map) LrcLibResult.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      return const <LrcLibResult>[];
    }
  }

  static String? _blankToNull(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  // %20 for a space, as the reference's HTTP client writes it.
  static String _url(String path, Map<String, String> query) {
    final q = query.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$_baseUrl$path?$q';
  }

  /// Nothing to release: requests go through the app-wide [LyricsHttp].
  /// Kept so existing callers need not change.
  void dispose() {}
}

/// Result from the LRCLIB API.
class LrcLibResult {
  final int id;
  final String trackName;
  final String artistName;
  final String? albumName;
  final int duration;
  final String? syncedLyrics;
  final String? plainLyrics;

  const LrcLibResult({
    required this.id,
    required this.trackName,
    required this.artistName,
    this.albumName,
    required this.duration,
    this.syncedLyrics,
    this.plainLyrics,
  });

  factory LrcLibResult.fromJson(Map<String, dynamic> json) {
    return LrcLibResult(
      id: _int(json['id']) ?? 0,
      trackName: _string(json['trackName']) ?? _string(json['name']) ?? '',
      artistName: _string(json['artistName']) ?? '',
      albumName: _string(json['albumName']),
      // LRCLIB reports fractional seconds, and omits the field on some records;
      // a missing one is 0, as the reference reads it.
      duration: _int(json['duration']) ?? 0,
      syncedLyrics: _string(json['syncedLyrics']),
      plainLyrics: _string(json['plainLyrics']),
    );
  }

  static String? _string(Object? v) => v is String ? v : null;

  static int? _int(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) {
      return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt();
    }
    return null;
  }
}
