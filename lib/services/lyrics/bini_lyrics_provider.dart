// lib/services/lyrics/bini_lyrics_provider.dart
// BiniLyrics - Apple Music syllable timings matched on the recording itself.
//
// Port of `BiniLyrics.kt`.
//
// The only one of the Apple mirrors that will answer to a recording rather than
// to a name, and where the ISRC the other mirrors need comes from. Its search is
// small (a couple of hundred bytes) and returns a URL rather than the document,
// so a lookup is two steps and they are exposed as two methods:
//
//   [identify]     which recording is this?            (the search)
//   [lyricsForHit] fetch and parse that recording's words  (the document)
//
// Splitting them lets the caller run [identify] on its own, ahead of everyone
// else, and hand the ISRC it finds to every source that can use one. Today the
// document it points at is lrc.red's `s/{ISRC}.ttml`, the same file
// [LrcRedProvider] fetches, so a `get:` that shares the download between the two
// saves a request.
//
// WHAT THIS REPLACES
//
// The previous version read a top-level `lyricsUrl`/`url`. The real answer is
// `{"total","source","results":[{...,"isrc","timing_type","lyricsUrl"}]}`, so
// it never found a URL. It also sent an ISRC alongside the name; the reference
// sends the ISRC ALONE - a name next to it can only disagree with it.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';
import 'apple_lyrics_common.dart';
import 'lyrics_url.dart';

/// What a Bini search settled on: the recording, and where its words are.
class BiniHit {
  const BiniHit({
    required this.isrc,
    required this.lyricsUrl,
    this.timingType,
  });

  /// The recording's ISRC, or empty when the hit did not carry one.
  final String isrc;

  /// The TTML document for this recording.
  final String lyricsUrl;

  /// `word`, `line` or `none`. Informational: the document is the authority.
  final String? timingType;

  @override
  String toString() => 'BiniHit($isrc, $timingType, $lyricsUrl)';
}

class BiniLyricsProvider extends AppleLyricsSource {
  BiniLyricsProvider({super.http});

  static const String _base = 'https://lyrics-api.binimum.org/';

  /// Which recording [query] is, without fetching its words.
  ///
  /// WITH an ISRC only `isrc=` is sent: the recording is named, and a title
  /// alongside it could only ever disagree with it. Otherwise `track=`,
  /// `artist=`, an optional `album=` and `duration=` in whole seconds.
  ///
  /// A miss is a 404 from this host rather than an empty result set; the shared
  /// client already turns that into null.
  Future<BiniHit?> identify(AppleLyricsQuery query) async {
    final params = <String, String>{};
    final isrc = query.isrc?.trim();
    if (isrc != null && isrc.isNotEmpty) {
      params['isrc'] = isrc;
    } else {
      params['track'] = query.title;
      params['artist'] = query.artist;
      final album = query.album;
      if (album != null && album.trim().isNotEmpty) params['album'] = album;
      final seconds = query.durationSeconds;
      if (seconds != null && seconds > 0) params['duration'] = '$seconds';
    }

    final body = await lyricsHttp.getText(buildLyricsUrl(_base, params));
    if (body == null) return null;
    return parseHit(body);
  }

  /// The document [hit] points at, fetched and parsed.
  ///
  /// [get] replaces the download (see [DocumentFetcher]).
  Future<List<LyricsEntry>?> lyricsForHit(
    BiniHit hit, {
    DocumentFetcher? get,
  }) {
    if (hit.lyricsUrl.trim().isEmpty) return Future<List<LyricsEntry>?>.value();
    return fetchTtml(hit.lyricsUrl, get: get);
  }

  /// Lyrics for [query]: [identify] then [lyricsForHit].
  ///
  /// Pass [hit] when [identify] has already been run, so the search is not made
  /// twice. [onIsrc] is told the ISRC of a hit this call found itself; it is
  /// not called for a [hit] the caller already had, who knows it.
  Future<List<LyricsEntry>?> getLyrics(
    AppleLyricsQuery query, {
    BiniHit? hit,
    DocumentFetcher? get,
    void Function(String isrc)? onIsrc,
  }) async {
    var found = hit;
    if (found == null) {
      found = await identify(query);
      if (found == null) return null;
      if (found.isrc.isNotEmpty) onIsrc?.call(found.isrc);
    }
    return lyricsForHit(found, get: get);
  }

  /// The first result in a search answer, or null when there is none worth
  /// following (no `lyricsUrl`).
  static BiniHit? parseHit(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final results = decoded['results'];
      if (results is! List || results.isEmpty) return null;
      final first = results.first;
      if (first is! Map) return null;

      final url = first['lyricsUrl'];
      if (url is! String || url.trim().isEmpty) return null;
      final isrc = first['isrc'];
      final timing = first['timing_type'];
      return BiniHit(
        isrc: isrc is String ? isrc.trim() : '',
        lyricsUrl: url.trim(),
        timingType: timing is String ? timing : null,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('BiniLyricsProvider: answer unreadable: $e');
      return null;
    }
  }
}

/// PaxSenix - Apple Music catalog search, then the same TTML.
///
/// Falls back to Apple's own catalog API rather than a third-party mirror, so it
/// answers when the volunteer hosts are down. It costs a search request per
/// track and returns no ISRC, which is why it sits behind the two mirrors that
/// do.
class PaxSenixProvider extends AppleLyricsSource {
  static const String _catalogSearch =
      'https://amp-api.music.apple.com/v1/catalog/us/search';
  static const String _country = 'us';
  static const Duration _timeout = Duration(seconds: 8);

  /// Apple's public web token. Not a secret: it ships inside every Apple Music
  /// client and is scoped to the catalogue endpoint.
  static const String _mediaApiToken =
      'eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJkc3Nfa2V5Ijoi'
      'MC4yLjcuMTQwIiwiZHR0IjpudWxsLCJjb2RlIjoxMDB9.'
      'BOJUmOr7CRQOOFHq7WCsMSjF0B3UOxNOjHzNWPPmS0M';

  final http.Client _client = http.Client();

  Future<List<LyricsEntry>?> getLyrics(AppleLyricsQuery query) async {
    final id = query.appleId ?? await _searchCatalogId(query);
    if (id == null) return null;

    // Apple's lyric asset path, which is the same TTML the mirrors serve.
    final url = 'https://amp-api.music.apple.com/v1/catalog/$_country/'
        'songs/$id?include=lyrics,artwork';
    final body = await _getJson(url);
    if (body == null) return null;

    final data = body['data'];
    if (data is! List || data.isEmpty) return null;
    final song = data.first;
    if (song is! Map) return null;

    final attributes = song['attributes'];
    if (attributes is! Map) return null;
    final relationships = song['relationships'];
    final lyricsRel = relationships is Map ? relationships['lyrics'] : null;
    final lyricData = lyricsRel is Map ? lyricsRel['data'] : null;
    if (lyricData is! List || lyricData.isEmpty) return null;

    final lyricId = lyricData.first;
    if (lyricId is! Map) return null;
    final lyricAttrs = lyricId['attributes'];
    final ttmlUrl = lyricAttrs is Map ? lyricAttrs['ttml'] : null;
    if (ttmlUrl is! String || ttmlUrl.isEmpty) return null;

    return fetchTtml(ttmlUrl);
  }

  Future<Map<String, dynamic>?> _getJson(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: {
            'User-Agent': 'MusicStreamingApp/1.0.0 (lyrics)',
            'Authorization': 'Bearer $_mediaApiToken',
            'Accept': 'application/json',
          })
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      // jsonDecode hands back Map<dynamic, dynamic>, which is not assignable
      // to the typed shape everything downstream reads.
      if (decoded is! Map) return null;
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    } catch (e) {
      if (kDebugMode) debugPrint('PaxSenixProvider: request failed: $e');
      return null;
    }
  }

  Future<int?> _searchCatalogId(AppleLyricsQuery query) async {
    final body = await _getJson(
      Uri.parse(_catalogSearch).replace(queryParameters: {
        'term': '${query.title} ${query.artist}',
        'types': 'songs',
        'limit': '5',
        'country': _country,
        'media': 'music',
      }).toString(),
    );
    if (body == null) return null;

    final results = body['results'];
    if (results is! Map) return null;
    final songs = results['songs'];
    if (songs is! Map) return null;
    final data = songs['data'];
    if (data is! List || data.isEmpty) return null;

    for (final item in data) {
      if (item is! Map) continue;
      final attributes = item['attributes'];
      final id = item['id'];
      if (attributes is! Map || id is! num) continue;
      final title = attributes['name'];
      if (title is! String) continue;
      if (!AppleLyricsSource.titlesMatch(title, query.title)) continue;

      final durationMs = attributes['durationInMillis'];
      if (durationMs is num &&
          !AppleLyricsSource.durationMatches(
            (durationMs / 1000).round(),
            query.durationSeconds,
          )) {
        continue;
      }
      return id.toInt();
    }
    return null;
  }
}