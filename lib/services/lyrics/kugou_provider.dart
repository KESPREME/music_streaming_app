import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';

/// Provider for KuGou — massive international line-synced lyrics catalog.
class KuGouProvider {
  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
  }) async {
    try {
      final keyword = '$artist $title'.trim();
      final seconds = durationMs != null && durationMs > 0 ? durationMs ~/ 1000 : 0;

      // 1. Search song to obtain audio hash
      final searchUrl = Uri.parse(
        'https://mobileservice.kugou.com/api/v3/search/song?version=9108&plat=0&pagesize=8&showtype=0&keyword=${Uri.encodeComponent(keyword)}',
      );
      final searchRes = await http
          .get(searchUrl, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 4));

      if (searchRes.statusCode != 200) return null;
      final searchJson = jsonDecode(searchRes.body);
      if (searchJson is! Map<String, dynamic>) return null;

      final infoList = searchJson['data']?['info'] as List<dynamic>?;
      if (infoList == null || infoList.isEmpty) return null;

      // Find closest duration candidate
      String? bestHash;
      int minDiff = 999999;
      for (final item in infoList) {
        if (item is! Map<String, dynamic>) continue;
        final d = (item['duration'] as num?)?.toInt() ?? 0;
        final diff = (d - seconds).abs();
        if (seconds == 0 || diff <= 8) {
          if (diff < minDiff) {
            minDiff = diff;
            bestHash = item['hash'] as String?;
          }
        }
      }

      bestHash ??= infoList.first['hash'] as String?;
      if (bestHash == null || bestHash.isEmpty) return null;

      // 2. Search lyrics with hash
      final lyricsSearchUrl = Uri.parse(
        'https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&hash=$bestHash',
      );
      final lrcSearchRes = await http
          .get(lyricsSearchUrl, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 4));

      if (lrcSearchRes.statusCode != 200) return null;
      final lrcJson = jsonDecode(lrcSearchRes.body);
      final candidates = lrcJson['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;

      final candidate = candidates.first as Map<String, dynamic>;
      final id = candidate['id']?.toString();
      final accesskey = candidate['accesskey']?.toString();
      if (id == null || accesskey == null) return null;

      // 3. Download lyrics
      final downloadUrl = Uri.parse(
        'https://lyrics.kugou.com/download?fmt=lrc&charset=utf8&client=pc&ver=1&id=$id&accesskey=$accesskey',
      );
      final downloadRes = await http
          .get(downloadUrl, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 4));

      if (downloadRes.statusCode != 200) return null;
      final downloadJson = jsonDecode(downloadRes.body);
      final base64Content = downloadJson['content'] as String?;
      if (base64Content == null || base64Content.isEmpty) return null;

      final lrcString = utf8.decode(base64.decode(base64Content));
      return LyricsUtils.parseLrc(lrcString);
    } catch (e) {
      if (kDebugMode) debugPrint('KuGouProvider: lookup failed: $e');
      return null;
    }
  }
}
