// lib/services/lyrics/unison_provider.dart
// Unison - a multi-catalogue mirror answering TTML, LRC or plain text.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';
import 'better_lyrics_provider.dart';
import '../../utils/lyrics_utils.dart';

class UnisonProvider {
  static const String _endpoint = 'https://unison.boidu.dev/lyrics';
  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client = http.Client();

  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
  }) async {
    try {
      final params = <String, String>{'song': title, 'artist': artist};
      if (durationMs != null && durationMs > 0) {
        params['duration'] = '${(durationMs / 1000).round()}';
      }

      final uri = Uri.parse(_endpoint).replace(queryParameters: params);
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'MusicStreamingApp/1.0.0 (lyrics)',
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      return parse(decoded.map((k, v) => MapEntry(k.toString(), v)));
    } catch (e) {
      if (kDebugMode) debugPrint('UnisonProvider: request failed: $e');
      return null;
    }
  }

  /// Parses whichever of the three shapes this host answered with.
  ///
  /// TTML is preferred because it carries the timings; the caller treats a
  /// line-synced answer as a fallback rather than a win.
  static List<LyricsEntry>? parse(Map<String, dynamic> body) {
    final ttml = body['ttml'];
    if (ttml is String && ttml.contains('<tt')) {
      final entries = BetterLyricsProvider.parseTtml(ttml);
      if (entries.isNotEmpty) return entries;
    }

    final synced = body['syncedLyrics'] ?? body['lrc'];
    if (synced is String && synced.trim().isNotEmpty) {
      final entries = parseLrc(synced);
      if (entries.isNotEmpty) return entries;
    }

    final plain = body['lyrics'] ?? body['plainLyrics'];
    if (plain is String && plain.trim().isNotEmpty) {
      return parsePlain(plain);
    }
    return null;
  }

  /// LRC parsing, delegated to [LyricsUtils] rather than re-implemented.
  ///
  /// That class already owns every LRC rule this app follows, including the
  /// word-timing forms. A second parser here would be a second opinion, and two
  /// parsers that disagree is how the same song shows different words depending
  /// on which provider happened to answer.
  static List<LyricsEntry> parseLrc(String lrc) =>
      LyricsUtils.parseLrc(lrc);

  static List<LyricsEntry> parsePlain(String plain) {
    final entries = <LyricsEntry>[];
    var time = 0;
    for (final raw in plain.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      // A leading "[00:12.34]" is a timestamp even in a "plain" body.
      final stamp = RegExp(r'^\[(\d+):(\d+[.:]?\d*)\]').firstMatch(line);
      var text = line;
      if (stamp != null) {
        final m = int.tryParse(stamp.group(1)!) ?? 0;
        final s = double.tryParse(
              (stamp.group(2) ?? '0').replaceAll(':', '.'),
            ) ??
            0;
        // Milliseconds are an int on LyricsEntry; truncating here rather than
        // storing a double keeps the rounding identical to every other parser.
        time = ((m * 60 + s) * 1000).round();
        text = line.substring(stamp.end).trim();
      }
      if (text.isEmpty) continue;
      entries.add(LyricsEntry(timeMs: time, text: text));
      time += 3000;
    }
    return entries;
  }
}