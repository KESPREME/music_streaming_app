import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';

/// Plain lyrics from the Lyrics tab of the exact playing video.
///
/// The only source here that is keyed on the video rather than on a name, so it
/// cannot return the wrong recording the way a title search can. It carries no
/// timings at all, which is why it sits near the bottom of the order and is
/// `canWordSync == false`.
class YouTubeMusicLyricsProvider {
  static const Duration _timeout = Duration(seconds: 6);

  /// Fetches the Lyrics tab for [videoId].
  ///
  /// Returns null unless [videoId] looks like a YouTube id. Guessing a shape
  /// check is the difference between "we asked YouTube about this video" and
  /// "we asked YouTube about some other video that happens to share a title".
  Future<List<LyricsEntry>?> getLyrics({required String? videoId}) async {
    if (videoId == null || !_looksLikeYouTubeId(videoId)) return null;
    try {
      // The description shelf is reached through a browse of the Lyrics tab, and
      // the tab's browse id has to come from the video's own watch response.
      // Without that step there is nothing to ask for, so a missing watch page
      // is a miss rather than an error.
      final watch = await _get('https://www.youtube.com/watch?v=$videoId');
      if (watch == null) return null;

      final params = _lyricsBrowseParams(watch);
      if (params == null) return null;

      final browse = await _get(
        'https://music.youtube.com/youtubei/v1/browse',
        // Typed maps, not bare braces: `'key' => { ... }` is parsed as a SET
        // literal, which fails at compile time rather than quietly.
        body: <String, dynamic>{
          'context': <String, dynamic>{
            'client': <String, dynamic>{
              'clientName': 'WEB_REMIX',
              'clientVersion': '1.20240101.01.00',
            },
          },
          'browseId': 'MPLYt_',
          'params': params,
        },
      );
      if (browse == null) return null;

      final text = _descriptionText(browse);
      if (text == null || text.trim().isEmpty) return null;

      // No timings: every line starts at 0, which is how a plain-text source
      // says so rather than pretending to be synced.
      final lines = text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isEmpty) return null;
      return [
        for (final line in lines)
          LyricsEntry(timeMs: 0, endMs: 0, text: line),
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('YouTubeMusicLyrics: lookup failed: $e');
      return null;
    }
  }

  /// 11-character ids only. Anything else is not this provider's business.
  static bool _looksLikeYouTubeId(String id) =>
      RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);

  Future<String?> _get(String url, {Map<String, dynamic>? body}) async {
    final response = body == null
        ? await http.get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Accept-Language': 'en-US,en;q=0.9',
            },
          ).timeout(_timeout)
        : await http
            .post(
              Uri.parse(url),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Content-Type': 'application/json',
                'Accept-Language': 'en-US,en;q=0.9',
              },
              body: jsonEncode(body),
            )
            .timeout(_timeout);
    if (response.statusCode != 200) return null;
    return response.body;
  }

  /// The Lyrics tab's browse params, found by name rather than by position.
  ///
  /// A positional read of the tab list is a guess about an unordered structure,
  /// and the guess is wrong the moment YouTube adds a tab.
  static String? _lyricsBrowseParams(String watchHtml) {
    for (final match in RegExp(
      r'"tabRenderer"\s*:\s*\{.*?"title"\s*:\s*\{\s*"simpleText"\s*:\s*"(Lyrics|lyrics)"',
      dotAll: true,
    ).allMatches(watchHtml)) {
      final after = watchHtml.substring(match.end);
      final params = RegExp(r'"params"\s*:\s*"([^"]+)"').firstMatch(after);
      if (params != null) return params.group(1);
    }
    return null;
  }

  /// The description text out of a musicDescriptionShelfRenderer.
  static String? _descriptionText(String body) {
    final shelf = RegExp(
      r'"musicDescriptionShelfRenderer"\s*:\s*\{(.*?)(?:"\w+Renderer"|\}\s*\})',
      dotAll: true,
    ).firstMatch(body);
    final scope = shelf?.group(1) ?? body;
    final parts = RegExp(r'"simpleText"\s*:\s*"((?:[^"\\]|\\.)*)"')
        .allMatches(scope)
        .map((m) => _unescape(m.group(1)!))
        .toList();
    if (parts.isEmpty) return null;
    return parts.join('');
  }

  static String _unescape(String raw) => jsonDecode('"$raw"') is String
      ? jsonDecode('"$raw"') as String
      : raw;
}