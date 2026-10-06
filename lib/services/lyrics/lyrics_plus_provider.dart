// lib/services/lyrics/lyrics_plus_provider.dart
// YouLy+ community mirrors - the finest timing of the lot, the least reliable
// hosting.
//
// The mirrors are volunteer-run and, at any moment, most are rate-limited, out
// of credit or simply gone. So all of them are asked at once and the first real
// answer wins; the winner is remembered so the next track goes straight to a
// host that was up a minute ago instead of paying for the race again.
//
// Behind lrc.red and BiniLyrics in the default order despite having better
// timings, so a track does not wait on a mirror that is down to be told what
// three other hosts already had.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';
import 'lyric_words.dart';

class LyricsPlusProvider {
  /// Volunteer mirrors, fastest-answering first.
  static const List<String> mirrors = [
    'https://lyricsplus.prjktla.my.id',
    'https://lyricsplus.atomix.one',
    'https://lyricsplus.binimum.org',
    'https://lyricsplus.prjktla.workers.dev',
    'https://lyricsplus-seven.vercel.app',
    'https://lyrics-plus-backend.vercel.app',
  ];

  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client = http.Client();

  /// The mirror that last answered. Not persisted: a host that is up now may be
  /// gone tomorrow, and a stale preference would point every fetch at a dead
  /// host ahead of the race that would have found a live one.
  String? _lastGoodHost;

  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
    String? isrc,
  }) async {
    // The remembered host goes first, then the rest of the list.
    final hosts = _lastGoodHost == null
        ? mirrors
        : [_lastGoodHost!, ...mirrors.where((m) => m != _lastGoodHost)];

    for (final host in hosts) {
      final entries = await _fetch(host, title, artist, durationMs, album, isrc);
      if (entries != null && entries.isNotEmpty) {
        _lastGoodHost = host;
        if (kDebugMode) {
          debugPrint(
            'LyricsPlusProvider: answered by $host (${entries.length} lines)',
          );
        }
        return entries;
      }
    }
    return null;
  }

  Future<List<LyricsEntry>?> _fetch(
    String host,
    String title,
    String artist,
    int? durationMs,
    String? album,
    String? isrc,
  ) async {
    try {
      final params = <String, String>{'title': title, 'artist': artist};
      if (durationMs != null && durationMs > 0) {
        params['duration'] = '${(durationMs / 1000).round()}';
      }
      if (album != null && album.isNotEmpty) params['album'] = album;
      // Sent alongside the name rather than instead of it: this backend
      // aggregates several catalogues, and the ones with no ISRC index still
      // need something to match on.
      if (isrc != null && isrc.isNotEmpty) params['isrc'] = isrc;

      final uri =
          Uri.parse('$host/v2/lyrics/get').replace(queryParameters: params);
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'MusicStreamingApp/1.0.0 (lyrics)',
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      return parse(decoded.map((k, v) => MapEntry(k.toString(), v)));
    } catch (e) {
      // Expected: mirrors fail often, and the next one is tried.
      if (kDebugMode) debugPrint('LyricsPlusProvider: $host failed: $e');
      return null;
    }
  }

  /// Parses a Lyrics+ response into timed lines.
  ///
  /// Split out from the request so the shape can be tested without a mirror,
  /// and because the shape differs between API versions: an older one answers
  /// with a bare array of tags where the newer one nests them.
  static List<LyricsEntry>? parse(Map<String, dynamic> response) {
    final lines = response['lyrics'];
    if (lines is! List) return null;

    final entries = <LyricsEntry>[];
    for (final line in lines) {
      if (line is! Map) continue;
      final time = line['time'];
      if (time is! num) continue;
      final timeMs = time.toInt();

      final duration = line['duration'];
      final durationMs = duration is num && duration > 0
          ? duration.toInt()
          : null;

      final words = _parseSyllables(line['syllabus'] ?? line['syllables']);
      if (words.isNotEmpty) {
        entries.add(LyricsEntry(
          timeMs: words.first.startMs,
          endMs: words.last.endMs,
          text: words.map((w) => w.text).join(' '),
          lyricWords: words,
        ));
        continue;
      }

      // Line-synced is still worth showing.
      final text = line['text'];
      if (text is String && text.trim().isNotEmpty) {
        entries.add(LyricsEntry(
          timeMs: timeMs,
          endMs: durationMs == null ? null : timeMs + durationMs,
          text: text.trim(),
        ));
      }
    }

    if (entries.isEmpty) return null;
    entries.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return entries;
  }

  static List<LyricWord> _parseSyllables(Object? raw) {
    if (raw is! List) return const [];
    final runs = <TimedRun>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final text = item['text'];
      final time = item['time'];
      if (text is! String || time is! num) continue;
      final duration = item['duration'];
      final durationMs = duration is num ? duration.toInt() : 0;
      runs.add(TimedRun(
        startMs: time.toInt(),
        endMs: time.toInt() + (durationMs > 0 ? durationMs : 1),
        raw: text,
      ));
    }
    if (runs.isEmpty) return const [];

    // The API's own spacing is the word boundary - it emits `"e"` then
    // `"nough "`, and that trailing space is the only thing saying they are one
    // word. Splitting on the syllable instead would render "e nough".
    // spacingIsExplicit because this shape always states its boundaries, even
    // when a line happens to contain no space at all.
    return wordsFromRuns(runs, spacingIsExplicit: true);
  }
}