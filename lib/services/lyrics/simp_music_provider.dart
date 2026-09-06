import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';

/// Provider for SimpMusic — YouTube video-ID keyed community lyrics.
///
/// Because it is keyed directly on the YouTube video ID, it never returns
/// the wrong recording, edit, or remix.
class SimpMusicProvider {
  static const String _baseUrl = 'https://api-lyrics.simpmusic.org/v1/';

  Future<List<LyricsEntry>?> getLyrics({
    required String videoId,
    int? durationMs,
  }) async {
    if (videoId.isEmpty) return null;

    try {
      final uri = Uri.parse('$_baseUrl$videoId');
      final response = await http
          .get(uri, headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          })
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic> || json['success'] != true) return null;

      final data = json['data'] as List<dynamic>?;
      if (data == null || data.isEmpty) return null;

      final seconds = durationMs != null && durationMs > 0 ? durationMs ~/ 1000 : 0;

      // Find closest duration track
      Map<String, dynamic>? bestTrack;
      int minDiff = 999999;
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final d = (item['duration'] as num?)?.toInt() ?? 0;
        final diff = (d - seconds).abs();
        if (seconds == 0 || diff <= 10) {
          if (diff < minDiff) {
            minDiff = diff;
            bestTrack = item;
          }
        }
      }

      bestTrack ??= data.first as Map<String, dynamic>?;
      if (bestTrack == null) return null;

      // 1. Rich sync (word/syllable-level timing)
      final richSync = bestTrack['richSyncLyrics'] as String?;
      if (richSync != null && richSync.trim().isNotEmpty) {
        final parsed = LyricsUtils.parseLrc(richSync);
        if (parsed.isNotEmpty) return parsed;
      }

      // 2. Standard line-synced lyrics
      final synced = bestTrack['syncedLyrics'] as String?;
      if (synced != null && synced.trim().isNotEmpty) {
        final parsed = LyricsUtils.parseLrc(synced);
        if (parsed.isNotEmpty) return parsed;
      }

      // 3. Plain text lyrics
      final plain = bestTrack['plainLyrics'] as String?;
      if (plain != null && plain.trim().isNotEmpty) {
        return LyricsUtils.parsePlainText(plain);
      }

      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('SimpMusicProvider: lookup failed: $e');
      return null;
    }
  }
}
