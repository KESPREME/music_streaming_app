import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';

/// Line-synced community LRC scraped from Megalobiz.
///
/// Whole lines only, and it is a scraper of somebody's HTML — so it is the last
/// resort before Genius and the reason both are `isLazy`. It still earns its
/// place: it is a catalogue the licensed sources do not carry.
class MegalobizProvider {
  static const String _base = 'https://www.megalobiz.com';
  static const Duration _timeout = Duration(seconds: 6);

  /// The download link out of a search page.
  static final RegExp _lrcLink = RegExp(
    r'''href=["'](/lrc/maker/download/[^"']+)["']''',
    caseSensitive: false,
  );

  /// The lyric body out of the download page.
  static final RegExp _lrcBody = RegExp(
    r'''id=["']lrc_[^"']*_details["'][^>]*>(.*?)</span>''',
    caseSensitive: true,
    dotAll: true,
  );

  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
  }) async {
    try {
      final search = await _get(
        '$_base/searchall?qry=${Uri.encodeQueryComponent('$artist $title'.trim())}',
      );
      if (search == null) return null;

      final link = _lrcLink.firstMatch(search);
      if (link == null) return null;

      // The search page HTML-escapes the query in its own href, so an
      // unescaped link is a 404 rather than a lyric.
      final page = await _get('$_base${link.group(1)!.replaceAll('&amp;', '&')}');
      if (page == null) return null;

      final raw = _lrcBody.firstMatch(page)?.group(1);
      if (raw == null || raw.trim().isEmpty) return null;

      final lrc = raw
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), '');
      final entries = LyricsUtils.parseLrc(lrc);
      if (entries.isEmpty || !entries.any((e) => e.text.trim().isNotEmpty)) {
        return null;
      }
      return entries;
    } catch (e) {
      if (kDebugMode) debugPrint('Megalobiz: lookup failed: $e');
      return null;
    }
  }

  Future<String?> _get(String url) async {
    final response = await http
        .get(
          Uri.parse(url),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        )
        .timeout(_timeout);
    if (response.statusCode != 200) return null;
    return response.body;
  }

  /// Exposed for tests: the body is JSON-shaped enough to be worth one unit.
  @visibleForTesting
  static List<LyricsEntry>? parseForTest(String page) {
    final raw = _lrcBody.firstMatch(page)?.group(1);
    if (raw == null) return null;
    final lrc = raw
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    final entries = LyricsUtils.parseLrc(lrc);
    return entries.isEmpty ? null : entries;
  }
}