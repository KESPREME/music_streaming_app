// lib/services/lyrics/musixmatch_provider.dart
// Musixmatch - rich-sync word timings, via the public web token.
//
// The most fragile provider in the list: its API requires a bearer token that
// the web player mints at runtime and that expires. It is kept late in the
// default order for exactly that reason - every provider ahead of it answers
// without a rotating secret, and this one only matters when they all miss.
//
// A token that cannot be obtained is not an error. It returns null and the
// racing layer moves on.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';
import 'lyric_words.dart';

class MusixmatchProvider {
  static const String _searchUrl =
      'https://www.musixmatch.com/search';
  static const String _apiBase = 'https://apic.musixmatch.com/ws/1.1/';
  static const Duration _timeout = Duration(seconds: 8);

  /// A desktop browser UA. This endpoint rejects anything that looks like a
  /// bot, and it is not asking permission.
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  final http.Client _client = http.Client();

  String? _token;
  DateTime? _tokenFetchedAt;

  /// How long a minted token is assumed good before it is re-minted.
  static const Duration _tokenLifetime = Duration(hours: 2);

  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
  }) async {
    final token = await _ensureToken();
    if (token == null) return null;

    final trackId = await _findTrack(title, artist);
    if (trackId == null) return null;

    final body = await _getJson(
      '${_apiBase}matcher.lyrics.get?track_id=$trackId&format=json'
      '&subtitle_format=__SYLLABIC__',
      token: token,
    );
    if (body == null) return null;

    // The body shape is a list of tracks, not a map, which is why this endpoint
    // is fetched separately from the token endpoints.
    return _parseLyricsBody(body);
  }

  /// Parses a matcher response.
  ///
  /// Not async: it reads an already-fetched body, and marking it `Future` while
  /// it returns a plain value made every `return null` inside it a type error.
  List<LyricsEntry>? _parseLyricsBody(dynamic decoded) {
    if (decoded is! List || decoded.isEmpty) return null;
    final message = decoded.first;
    if (message is! Map) return null;
    final body = message['body'];
    if (body is! Map) return null;

    final lyrics = body['lyrics'];
    if (lyrics is! Map) return null;

    final subtitle = lyrics['subtitle'];
    if (subtitle is! Map) return null;
    final lines = subtitle['lines'];
    if (lines is! List) return null;

    final entries = <LyricsEntry>[];
    for (final line in lines) {
      if (line is! Map) continue;
      final start = line['startTimeMs'];
      final end = line['endTimeMs'];
      if (start is! num || end is! num) continue;

      final words = _parseWords(line['words']);
      final text = words.isNotEmpty
          ? words.map((w) => w.text).join(' ')
          : (line['lyric'] is String ? (line['lyric'] as String).trim() : '');
      if (text.isEmpty) continue;

      entries.add(LyricsEntry(
        timeMs: start.toInt(),
        endMs: end.toInt(),
        text: text,
        lyricWords: words.isEmpty ? null : words,
      ));
    }

    if (entries.isEmpty) return null;
    entries.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return entries;
  }

  static List<LyricWord> _parseWords(Object? raw) {
    if (raw is! List) return const [];
    final runs = <TimedRun>[];
    for (final item in raw) {
      if (item is! Map) return const [];
      final text = item['word'];
      final start = item['startTimeMs'];
      final end = item['endTimeMs'];
      if (text is! String || start is! num || end is! num) return const [];
      // Musixmatch appends the separating space to each word, which is exactly
      // the boundary signal wordsFromRuns needs.
      runs.add(TimedRun(
        startMs: start.toInt(),
        endMs: end.toInt(),
        raw: text,
      ));
    }
    if (runs.isEmpty) return const [];
    return wordsFromRuns(runs, spacingIsExplicit: true);
  }

  Future<String?> _ensureToken() async {
    final fetchedAt = _tokenFetchedAt;
    final token = _token;
    if (token != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _tokenLifetime) {
      return token;
    }

    try {
      final uri = Uri.parse('${_apiBase}token.get').replace(queryParameters: {
        'app_id': 'web-desktop-app-v1.0',
      });
      final response = await _client.get(uri, headers: const {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      }).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) return null;
      final message = decoded.first;
      if (message is! Map) return null;
      final body = message['message'];
      if (body is! Map) return null;
      final value = body['token'];
      if (value is! String || value.isEmpty) return null;
      _token = value;
      _tokenFetchedAt = DateTime.now();
      return value;
    } catch (e) {
      // No token is a normal outcome, not a failure worth logging loudly.
      if (kDebugMode) debugPrint('MusixmatchProvider: no token: $e');
      return null;
    }
  }

  Future<int?> _findTrack(String title, String artist) async {
    try {
      final uri = Uri.parse(_searchUrl).replace(queryParameters: {
        'q': '$title $artist',
        'f': 'songs',
      });
      final response = await _client.get(uri, headers: const {
        'User-Agent': _userAgent,
        'Accept': 'text/html',
      }).timeout(_timeout);
      if (response.statusCode != 200) return null;

      // The search page is HTML. The track id is pulled out of the JSON blob it
      // embeds, rather than parsing the markup.
      final match =
          RegExp(r'"track_id"\s*:\s*(\d+)').firstMatch(response.body);
      if (match == null) return null;
      return int.tryParse(match.group(1)!);
    } catch (e) {
      if (kDebugMode) debugPrint('MusixmatchProvider: search failed: $e');
      return null;
    }
  }

  /// Fetches a JSON body of any shape.
  ///
  /// `dynamic`, not a map: this API answers some endpoints with a bare list
  /// wrapped in an envelope and others with an object, and a narrower return
  /// type here would force a silent cast at the call site.
  Future<dynamic> _getJson(String url, {required String token}) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: {
            'User-Agent': _userAgent,
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          })
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body);
    } catch (e) {
      if (kDebugMode) debugPrint('MusixmatchProvider: request failed: $e');
      return null;
    }
  }
}