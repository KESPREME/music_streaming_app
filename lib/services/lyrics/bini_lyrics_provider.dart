// lib/services/lyrics/bini_lyrics_provider.dart
// BiniLyrics - Apple Music syllable timings matched on the recording itself.
//
// The only one of the three Apple mirrors that will answer to a recording
// rather than to a name, and where the ISRC the other mirrors need comes from.
// Sent a name and a length rather than an ISRC, it resolves the recording and
// hands back the catalogue id and the lyrics URL in one call.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';
import 'apple_lyrics_common.dart';

class BiniLyricsProvider extends AppleLyricsSource {
  static const String _base = 'https://lyrics-api.binimum.org/';
  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client = http.Client();

  Future<List<LyricsEntry>?> getLyrics(AppleLyricsQuery query) async {
    final documentUrl = await _resolveDocumentUrl(query);
    if (documentUrl == null) return null;
    return fetchTtml(documentUrl);
  }

  /// Resolves a name to a lyrics document URL.
  Future<String?> _resolveDocumentUrl(AppleLyricsQuery query) async {
    try {
      final params = <String, String>{
        'track': query.title,
        'artist': query.artist,
      };
      final seconds = query.durationSeconds;
      if (seconds != null) params['duration'] = '$seconds';
      final album = query.album;
      if (album != null && album.isNotEmpty) params['album'] = album;
      // Answered by recording when the caller has one.
      final isrc = query.isrc;
      if (isrc != null && isrc.isNotEmpty) params['isrc'] = isrc;

      final uri = Uri.parse(_base).replace(queryParameters: params);
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'MusicStreamingApp/1.0.0 (lyrics)',
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final map = decoded.map((k, v) => MapEntry(k.toString(), v));

      final url = map['lyricsUrl'] ?? map['url'];
      if (url is! String || url.isEmpty) return null;
      return url;
    } catch (e) {
      if (kDebugMode) debugPrint('BiniLyricsProvider: lookup failed: $e');
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