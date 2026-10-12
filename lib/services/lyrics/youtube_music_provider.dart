// lib/services/lyrics/youtube_music_provider.dart
// YouTube Music's Lyrics tab, for the exact video that is playing.
//
// Port of `YouTubeLyrics.kt`. Two InnerTube calls as the WEB_REMIX client:
//
//   next    {videoId}   -> the watch panel's tabs; the one titled "Lyrics" holds
//                          a browseEndpoint (browseId "MPLYt_...", sometimes
//                          with params)
//   browse  {browseId}  -> musicDescriptionShelfRenderer.description, the text
//
// WHY THE PREVIOUS VERSION NEVER ANSWERED
//
// It scraped youtube.com/watch, which is answered 429 with no lyrics tab at all;
// guessed the browse id as a constant `MPLYt_` (the real one is per video); and
// read only `simpleText`, where lyrics come as `runs[].text`.
//
// The only source here keyed on the video rather than on a name, so it cannot
// return the wrong recording the way a title search can. It carries no timings,
// which is why it sits near the bottom of the order and cannot word-sync.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';
import 'lyrics_http.dart';

class YouTubeMusicLyricsProvider {
  /// Takes a raw [http.Client] rather than a [LyricsHttp]: these are JSON POSTs,
  /// which [LyricsHttp] (GET and form POST only) does not offer. The deadline is
  /// the same [LyricsHttp.requestTimeout], and like it this never throws.
  YouTubeMusicLyricsProvider({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const String _apiUrl = 'https://music.youtube.com/youtubei/v1';
  static const String _origin = 'https://music.youtube.com';

  // Kept in step with InnerTubeService's WEB_REMIX pin (its constants are
  // private, and that file is not this provider's to change).
  static const String _clientVersion = '1.20260707.12.00';
  static const String _clientId = '67';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0';

  static final RegExp _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Fetches the Lyrics tab for [videoId].
  ///
  /// Null unless [videoId] looks like a YouTube id: the difference between "we
  /// asked YouTube about this video" and "we asked about some other video that
  /// happens to share a title".
  Future<List<LyricsEntry>?> getLyrics({required String? videoId}) async {
    if (videoId == null || !_videoId.hasMatch(videoId)) return null;
    try {
      // `isAudioOnly` and no playlist: the radio the reference also names
      // returns the same tabs in a response twenty times the size.
      final next = await _post('next', <String, dynamic>{
        'videoId': videoId,
        'isAudioOnly': true,
      });
      if (next == null) return null;

      final endpoint = findLyricsEndpoint(next);
      if (endpoint == null) return null;

      final page = await _post('browse', <String, dynamic>{
        'browseId': endpoint.browseId,
        if (endpoint.params != null) 'params': endpoint.params,
      });
      if (page == null) return null;

      return linesFromBrowse(page);
    } catch (e) {
      if (kDebugMode) debugPrint('YouTubeMusicLyrics: lookup failed: $e');
      return null;
    }
  }

  /// The Lyrics tab's browse endpoint, found by name rather than by position.
  ///
  /// A positional read of the tab list is a guess about an ordered structure,
  /// and the guess is wrong the moment YouTube adds a tab. A video with no
  /// lyrics has no such tab, and that is a miss - it is not answered with some
  /// other tab's page.
  @visibleForTesting
  static ({String browseId, String? params})? findLyricsEndpoint(Object? next) {
    final tabs = <Map>[];
    _collectNamed(next, 'tabRenderer', tabs);

    Map? endpointOf(Map tab) {
      final found = <Map>[];
      _collectNamed(tab, 'browseEndpoint', found);
      return found.isEmpty ? null : found.first;
    }

    Map? chosen;
    // 1. The tab titled "Lyrics".
    for (final tab in tabs) {
      if (_strings(tab['title'])
          .any((t) => t.trim().toLowerCase() == 'lyrics')) {
        chosen = endpointOf(tab);
        if (chosen != null) break;
      }
    }
    // 2. A title in another language: the endpoint says what it is.
    if (chosen == null) {
      for (final tab in tabs) {
        final endpoint = endpointOf(tab);
        if (endpoint == null) continue;
        final id = endpoint['browseId'];
        final isLyricsPage = (id is String && id.startsWith('MPLYt_')) ||
            _containsString(endpoint, 'MUSIC_PAGE_TYPE_TRACK_LYRICS');
        if (isLyricsPage) {
          chosen = endpoint;
          break;
        }
      }
    }
    if (chosen == null) return null;

    final browseId = chosen['browseId'];
    if (browseId is! String || browseId.isEmpty) return null;
    final params = chosen['params'];
    return (
      browseId: browseId,
      params: params is String && params.isNotEmpty ? params : null,
    );
  }

  /// Plain lines out of a browse response's description shelf.
  ///
  /// Joins `runs[].text` (and `simpleText`) with nothing between them, then
  /// splits on the line breaks the text itself carries. No timings: every line
  /// is at `timeMs: 0`.
  @visibleForTesting
  static List<LyricsEntry>? linesFromBrowse(Object? page) {
    final shelves = <Map>[];
    _collectNamed(page, 'musicDescriptionShelfRenderer', shelves);
    if (shelves.isEmpty) return null;

    final text = _strings(shelves.first['description']).join().trim();
    if (text.isEmpty) return null;

    final lines = <LyricsEntry>[
      for (final raw in text.split(RegExp(r'\r\n|\r|\n')))
        if (raw.trim().isNotEmpty) LyricsEntry(timeMs: 0, text: raw.trim()),
    ];
    return lines.isEmpty ? null : lines;
  }

  Future<Object?> _post(String method, Map<String, dynamic> body) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_apiUrl/$method?prettyPrint=false'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Accept-Language': 'en-US,en;q=0.9',
              'X-YouTube-Client-Name': _clientId,
              'X-YouTube-Client-Version': _clientVersion,
              'X-Origin': _origin,
              'Origin': _origin,
              'Referer': '$_origin/',
              'User-Agent': _userAgent,
            },
            body: jsonEncode(<String, dynamic>{
              'context': <String, dynamic>{
                'client': <String, dynamic>{
                  'clientName': 'WEB_REMIX',
                  'clientVersion': _clientVersion,
                  'hl': 'en',
                  'gl': 'US',
                  'platform': 'DESKTOP',
                },
                'request': <String, dynamic>{'useSsl': true},
              },
              ...body,
            }),
          )
          .timeout(LyricsHttp.requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on TimeoutException {
      if (kDebugMode) debugPrint('YouTubeMusicLyrics: $method timed out');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('YouTubeMusicLyrics: $method failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // JSON walking
  // ---------------------------------------------------------------------------

  /// Every object stored under the key [name], anywhere in [node].
  static void _collectNamed(Object? node, String name, List<Map> out) {
    if (node is Map) {
      node.forEach((key, value) {
        if (key == name && value is Map) out.add(value);
        _collectNamed(value, name, out);
      });
    } else if (node is List) {
      for (final value in node) {
        _collectNamed(value, name, out);
      }
    }
  }

  /// All the text in [node]: a bare string, a list of them, `{simpleText}`, or
  /// `{runs:[{text}]}`. In document order.
  static List<String> _strings(Object? node) {
    if (node is String) return <String>[node];
    if (node is List) return <String>[for (final e in node) ..._strings(e)];
    if (node is Map) {
      final direct = node['text'] ?? node['simpleText'];
      if (direct is String) return <String>[direct];
      return <String>[for (final v in node.values) ..._strings(v)];
    }
    return const <String>[];
  }

  static bool _containsString(Object? node, String needle) {
    if (node is String) return node == needle;
    if (node is List) return node.any((e) => _containsString(e, needle));
    if (node is Map) return node.values.any((v) => _containsString(v, needle));
    return false;
  }

  void dispose() => _client.close();
}
