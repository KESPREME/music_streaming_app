// lib/services/lyrics/genius_provider.dart
// Genius - plain-text lyrics scraped, and only as a last resort.
//
// No timings at all. Every provider above this one can sing along; this one
// only prints the words.
//
// It exists so a song with no synced coverage anywhere is not simply blank,
// and it is deliberately the final entry in the default order. Starting it
// eagerly would spend a scrape and a rate-limit budget on every track before
// the providers that can actually synchronise have answered.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';

class GeniusProvider {
  static const String _searchUrl = 'https://genius.com/api/search/multi';
  static const Duration _timeout = Duration(seconds: 8);

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  final http.Client _client = http.Client();

  /// Plain-text lyrics, or null when nothing matched.
  ///
  /// Returned without any timings, so the line-level fallback renders it: the
  /// whole line lights at its stamp and stays lit. The caller is expected to
  /// treat this as a fallback rather than a result worth showing a wipe on.
  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
  }) async {
    try {
      final uri = Uri.parse(_searchUrl).replace(queryParameters: {'q': title});
      final response = await _client.get(uri, headers: const {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode != 200) return null;
      final hits = parseSearch(response.body);
      final page = await _firstPageUrl(hits, title, artist);
      if (page == null) return null;

      final body = await _client
          .get(Uri.parse(page), headers: const {'User-Agent': _userAgent})
          .timeout(_timeout);
      if (body.statusCode != 200) return null;

      final text = extractLyrics(body.body);
      if (text == null) return null;
      return plainToEntries(text);
    } catch (e) {
      if (kDebugMode) debugPrint('GeniusProvider: failed: $e');
      return null;
    }
  }

  /// Candidate song URLs from the search body.
  static List<String> parseSearch(String body) {
    final urls = <String>[];
    try {
      final decoded = _decode(body);
      final sections = decoded['response']['sections'];
      if (sections is! List) return urls;
      for (final section in sections) {
        if (section is! Map) continue;
        final hits = section['hits'];
        if (hits is! List) continue;
        for (final hit in hits) {
          if (hit is! Map) continue;
          final result = hit['result'];
          if (result is! Map) continue;
          final url = result['url'];
          if (url is String && url.isNotEmpty) urls.add(url);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('GeniusProvider: bad search body: $e');
    }
    return urls;
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      // jsonDecode hands back Map<dynamic, dynamic>; retyping the keys is what
      // lets the rest of this file read a typed shape.
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Pulls the lyric text out of a Genius song page.
  ///
  /// The page carries the lyrics twice: once as readable containers, and once
  /// inside a script tag for crawlers. The script copy is preferred because it
  /// is not broken up by the page's own navigation and annotation markup.
  static String? extractLyrics(String html) {
    // The crawler payload is plain text between fixed markers.
    final scriptMatch = RegExp(
      r'Lyrics\[\s*LyricHtml\s*\]\s*=\s*\[\s*"((?:[^"\\]|\\.)*)"',
      dotAll: true,
    ).firstMatch(html);
    if (scriptMatch != null) {
      try {
        final decoded = jsonDecode('"${scriptMatch.group(1)}"');
        if (decoded is String && decoded.trim().isNotEmpty) {
          return stripHtml(decoded);
        }
      } catch (_) {
        // Fall through to the container copy below.
      }
    }

    // Otherwise the readable containers.
    final containers = RegExp(
      r'<div[^>]*data-lyrics-container="true"[^>]*>(.*?)</div>',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(html).toList();
    if (containers.isEmpty) return null;

    final parts = containers.map((m) => stripHtml(m.group(1) ?? ''));
    final text = parts
        .where((p) => p.trim().isNotEmpty)
        .join('\n')
        .trim();
    return text.isEmpty ? null : text;
  }

  /// Removes markup, turning `<br>` into the line break it stands for.
  static String stripHtml(String html) {
    var out = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '');
    // Genius annotates words with bracket markers that are editorial, not
    // lyric. Leaving them in makes a line that cannot be sung look wrong.
    out = out.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    out = out.replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#x27;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    out = out.replaceAll(RegExp(r'[ \t]+'), ' ');
    return out
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n')
        .trim();
  }

  /// Splits plain text into unsynced lines.
  ///
  /// Evenly spaced by [secondsPerLine] rather than left at a shared timestamp:
  /// an unsynced list where every line starts at the same millisecond cannot be
  /// scrolled sensibly and reads as broken rather than as unsynced.
  static List<LyricsEntry> plainToEntries(
    String text, {
    int secondsPerLine = 4,
  }) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];

    final step = secondsPerLine * 1000;
    return [
      for (var i = 0; i < lines.length; i++)
        LyricsEntry(
          timeMs: i * step,
          endMs: (i + 1) * step,
          text: lines[i],
        ),
    ];
  }

  Future<String?> _firstPageUrl(
    List<String> urls,
    String title,
    String artist,
  ) async {
    for (final url in urls) {
      final slug = url.toLowerCase();
      final wantTitle = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (wantTitle.isNotEmpty && slug.contains(wantTitle)) return url;
    }
    return urls.isEmpty ? null : urls.first;
  }
}