import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';

/// Provider for BetterLyrics — Apple Music TTML word and syllable-timed lyrics.
class BetterLyricsProvider {
  static const String _baseUrl = 'https://lyrics-api.boidu.dev/getLyrics';

  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) async {
    try {
      final cleanTitle = _cleanQuery(title);
      final cleanArtist = _cleanQuery(artist);
      if (cleanTitle.isEmpty || cleanArtist.isEmpty) return null;

      final queryParams = <String, String>{
        's': cleanTitle,
        'a': cleanArtist,
      };
      if (durationMs != null && durationMs > 0) {
        queryParams['d'] = (durationMs ~/ 1000).toString();
      }
      if (album != null && album.isNotEmpty) {
        queryParams['al'] = album;
      }

      final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);
      final response = await http
          .get(uri, headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          })
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;

      final ttml = json['ttml'] as String?;
      if (ttml == null || ttml.isEmpty) return null;

      return parseTtml(ttml);
    } catch (e) {
      if (kDebugMode) debugPrint('BetterLyricsProvider: lookup failed: $e');
      return null;
    }
  }

  /// Parses Apple Music TTML with per-syllable / per-word timings into [LyricsEntry]
  static List<LyricsEntry> parseTtml(String ttml) {
    final entries = <LyricsEntry>[];
    // Find all <p begin="..." end="..."> ... </p> elements
    final pRegex = RegExp(
      r'<p\b[^>]*\bbegin="([^"]+)"(?:\s+[^>]*\bend="([^"]+)")?[^>]*>(.*?)<\/p>',
      dotAll: true,
      caseSensitive: false,
    );

    final spanRegex = RegExp(
      r'<span\b[^>]*\bbegin="([^"]+)"(?:\s+[^>]*\bend="([^"]+)")?[^>]*>(.*?)<\/span>',
      dotAll: true,
      caseSensitive: false,
    );

    for (final pMatch in pRegex.allMatches(ttml)) {
      final lineBeginStr = pMatch.group(1);
      final lineEndStr = pMatch.group(2);
      final lineContent = pMatch.group(3) ?? '';

      final lineTimeMs = _parseTimestampMs(lineBeginStr);
      if (lineTimeMs == null) continue;
      final lineEndMs = _parseTimestampMs(lineEndStr);

      final words = <WordTiming>[];
      final rawTextBuffer = StringBuffer();

      // Check if line contains per-syllable / word spans
      final spanMatches = spanRegex.allMatches(lineContent).toList();
      if (spanMatches.isNotEmpty) {
        for (final sMatch in spanMatches) {
          final sBeginStr = sMatch.group(1);
          final sEndStr = sMatch.group(2);
          var sText = sMatch.group(3) ?? '';
          sText = _stripXmlTags(sText);

          final sTimeMs = _parseTimestampMs(sBeginStr) ?? lineTimeMs;
          final sEnd = _parseTimestampMs(sEndStr) ?? (sTimeMs + 400);
          final duration = (sEnd - sTimeMs).clamp(50, 8000);

          rawTextBuffer.write(sText);
          final trimmedWord = sText.trim();
          if (trimmedWord.isNotEmpty) {
            words.add(WordTiming(
              timeMs: sTimeMs,
              durationMs: duration,
              text: trimmedWord,
            ));
          }
        }
      } else {
        // Plain text inside <p>
        rawTextBuffer.write(_stripXmlTags(lineContent));
      }

      final fullLineText = rawTextBuffer.toString().trim();
      if (fullLineText.isNotEmpty) {
        entries.add(LyricsEntry(
          timeMs: lineTimeMs,
          endMs: lineEndMs,
          text: fullLineText,
          words: words.isNotEmpty ? words : null,
        ));
      }
    }

    entries.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return entries;
  }

  static String _stripXmlTags(String raw) {
    return raw.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  static int? _parseTimestampMs(String? raw) {
    if (raw == null) return null;
    raw = raw.trim();
    if (raw.isEmpty) return null;

    if (raw.contains(':')) {
      final parts = raw.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s = double.tryParse(parts[1]) ?? 0.0;
        return (m * 60 * 1000 + s * 1000).round();
      } else if (parts.length == 3) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final s = double.tryParse(parts[2]) ?? 0.0;
        return (h * 3600 * 1000 + m * 60 * 1000 + s * 1000).round();
      }
    }
    final sec = double.tryParse(raw);
    if (sec != null) return (sec * 1000).round();
    return null;
  }

  static String _cleanQuery(String raw) {
    return raw
        .replaceAll(
            RegExp(
              r'(\s*[\(\[](?:feat\.?|ft\.?|official|video|remastered|bonus track|audio|lyrics)[^\)\]]*[\)\]])',
              caseSensitive: false,
            ),
            '')
        .trim();
  }
}
