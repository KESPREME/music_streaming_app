// lib/services/lyrics/lyrics_plus_provider.dart
// YouLy+ community mirrors - the finest timing of the lot, the least reliable
// hosting.
//
// Port of `LyricsPlus.kt`.
//
// The mirrors are volunteer-run and, at any moment, most are rate-limited, out
// of credit or simply gone. So ALL of them are asked at once and the first
// NON-EMPTY answer wins; the winner is remembered so the next track goes
// straight to a host that was up a minute ago.
//
// This used to ask them one after another at 8s each, so a dead host at the
// front of the list cost its whole timeout before the next was even tried -
// six mirrors, four of them down, was a half-minute wait for the one that was
// up.
//
// "Abandoned" below means only that nobody awaits the slower requests any more.
// package:http cannot cancel a request in flight, so they run to their own
// deadline and their results are dropped on arrival.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/lyrics_entry.dart';
import 'lyric_words.dart';
import 'lyrics_http.dart';
import 'lyrics_url.dart';

class LyricsPlusProvider {
  LyricsPlusProvider({LyricsHttp? http}) : _http = http ?? LyricsHttp.shared;

  /// Volunteer mirrors. They come and go, so all stay listed whatever their
  /// state at the time of writing (2026-10-12: prjktla.my.id and binimum.org
  /// answer; atomix has an SSL fault; workers.dev 404s; both vercel mirrors
  /// answer 402).
  static const List<String> mirrors = [
    'https://lyricsplus.prjktla.my.id',
    'https://lyricsplus.atomix.one',
    'https://lyricsplus.binimum.org',
    'https://lyricsplus.prjktla.workers.dev',
    'https://lyricsplus-seven.vercel.app',
    'https://lyrics-plus-backend.vercel.app',
  ];

  /// The mirror that last answered with lyrics, tried first next time.
  ///
  /// Static so every lookup in the app shares it, and NOT persisted: a host that
  /// is up now may be gone tomorrow, and a stale preference would put a dead
  /// host ahead of a race that would have found a live one. Assignable so a test
  /// can reset it.
  static String? lastGood;

  final LyricsHttp _http;

  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
    String? isrc,
  }) async {
    final preferred = lastGood;
    final hosts = preferred == null
        ? mirrors
        : <String>[preferred, ...mirrors.where((m) => m != preferred)];

    final answer = Completer<({String host, List<LyricsEntry> lines})?>();
    var outstanding = hosts.length;

    for (final host in hosts) {
      unawaited(
        _fetch(host, title, artist, durationMs, album, isrc).then<void>(
          (lines) {
            // A late answer, after the race is decided, is simply dropped: it
            // must not move [lastGood] or complete anything twice.
            if (answer.isCompleted) return;
            if (lines != null && lines.isNotEmpty) {
              answer.complete((host: host, lines: lines));
            } else if (--outstanding == 0) {
              answer.complete(null);
            }
          },
          // [_fetch] does not throw, but an error escaping a future nobody is
          // awaiting any more would be reported as unhandled.
          onError: (Object _) {
            if (!answer.isCompleted && --outstanding == 0) {
              answer.complete(null);
            }
          },
        ),
      );
    }

    final winner = await answer.future;
    if (winner == null) return null;
    lastGood = winner.host;
    if (kDebugMode) {
      debugPrint(
        'LyricsPlusProvider: answered by ${winner.host} '
        '(${winner.lines.length} lines)',
      );
    }
    return winner.lines;
  }

  /// One mirror's answer. Never throws and never returns an empty list.
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
      if (durationMs != null) {
        final seconds = (durationMs / 1000).round();
        if (seconds > 0) params['duration'] = '$seconds';
      }
      if (album != null && album.trim().isNotEmpty) params['album'] = album;
      // Sent alongside the name rather than instead of it: this backend
      // aggregates several catalogues, and the ones with no ISRC index still
      // need something to match on.
      if (isrc != null && isrc.trim().isNotEmpty) params['isrc'] = isrc.trim();

      final body = await _http.getText(
        buildLyricsUrl('$host/v2/lyrics/get', params),
      );
      if (body == null) return null;
      return parseBody(body);
    } catch (e) {
      // Expected: mirrors fail often, and the race has others.
      if (kDebugMode) debugPrint('LyricsPlusProvider: $host failed: $e');
      return null;
    }
  }

  /// Parses a raw response body, or null for anything unusable.
  static List<LyricsEntry>? parseBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      // A mirror that answers 200 with an error envelope is a miss.
      final error = decoded['error'];
      if (decoded['isError'] == true ||
          decoded['ok'] == false ||
          (error != null && error != false && error != '')) {
        return null;
      }
      return parse(decoded.map((k, v) => MapEntry(k.toString(), v)));
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsPlusProvider: unreadable answer: $e');
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
          timeMs: math.min(timeMs, words.first.startMs),
          endMs: words.last.endMs,
          text: words.map((w) => w.text).join(' '),
          lyricWords: words,
        ));
        continue;
      }

      // Some sources are only line-synced; still worth showing. The line's
      // duration is the only end it gets, and without it an interlude cannot be
      // told from a slowly sung line.
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
