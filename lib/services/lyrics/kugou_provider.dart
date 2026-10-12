// lib/services/lyrics/kugou_provider.dart
// KuGou - line-synced lyrics from its public mobile/lyrics endpoints.
//
// Port of `KuGou.kt`. A Chinese catalogue that also carries a great many
// English and Hindi tracks the other sources do not have. Three unauthenticated
// calls, chained:
//
//   1. search the song for its audio fingerprint (`hash`), keeping only cuts
//      within [durationToleranceSeconds] of the track being played;
//   2. search lyric candidates against each such hash;
//   3. download the winning candidate (Base64 LRC).
//
// A search by keyword alone is the fallback that catches what the hash route
// misses.
//
// WHAT WAS WRONG BEFORE
//
// The song search asked for "{artist} {title}" with no cleanup, and when no hit
// was within tolerance it fell back to `infoList.first` - the first result for
// a common title is as likely to be a cover or a remix as the right recording,
// so the lyric of a different cut was returned with confident timestamps.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';
import 'lyrics_http.dart';

class KuGouProvider {
  KuGouProvider({LyricsHttp? http}) : _http = http ?? LyricsHttp.shared;

  final LyricsHttp _http;

  /// A cut further than this from the playing track is another recording.
  static const int durationToleranceSeconds = 8;

  static const String _songSearch =
      'https://mobileservice.kugou.com/api/v3/search/song';
  static const String _lyricsSearch = 'https://lyrics.kugou.com/search';
  static const String _lyricsDownload = 'https://lyrics.kugou.com/download';

  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) async {
    try {
      final query = keyword(title, artist, album);
      final seconds =
          durationMs != null && durationMs > 0 ? durationMs ~/ 1000 : 0;

      final candidate = await _findCandidate(query, seconds);
      if (candidate == null) return null;

      final lrc = await _download(candidate);
      if (lrc == null || lrc.isEmpty) return null;

      final parsed = LyricsUtils.parseLrc(lrc);
      return parsed.any((e) => e.text.trim().isNotEmpty) ? parsed : null;
    } catch (e) {
      if (kDebugMode) debugPrint('KuGouProvider: lookup failed: $e');
      return null;
    }
  }

  /// The first lyric candidate: by hash, nearest cut first, else by keyword.
  Future<KuGouCandidate?> _findCandidate(String keyword, int seconds) async {
    final hashes = await _searchSongs(keyword, seconds);
    if (hashes.isNotEmpty) {
      // Asked together rather than one after another: a lyric lookup that
      // arrives late is of no use, and the answers are read in closeness order
      // regardless of which came back first.
      final results = await Future.wait(hashes.map(_candidateForHash));
      for (final candidate in results) {
        if (candidate != null) return candidate;
      }
    }
    return _candidateForKeyword(keyword, seconds);
  }

  // ---------------------------------------------------------------------------
  // Step 1: the song
  // ---------------------------------------------------------------------------

  /// Song hashes worth trying: only cuts within [durationToleranceSeconds] of
  /// [seconds] - otherwise the first result for a common title is as likely to
  /// be a cover or a remix as the right recording - closest match first.
  ///
  /// Empty, never "whatever came first", when nothing is close enough.
  Future<List<String>> _searchSongs(String keyword, int seconds) async {
    final body = await _http.getText(_url(_songSearch, {
      'version': '9108',
      'plat': '0',
      'pagesize': '8',
      'showtype': '0',
      'keyword': keyword,
    }));
    return body == null ? const <String>[] : hashesWithin(body, seconds);
  }

  /// The hashes in a song-search response that are within tolerance of
  /// [seconds], nearest first. When [seconds] is unknown (<= 0) nothing can be
  /// ruled out and the response order is kept.
  @visibleForTesting
  static List<String> hashesWithin(String searchBody, int seconds) {
    final Object? root;
    try {
      root = jsonDecode(searchBody);
    } catch (_) {
      return const <String>[];
    }
    final data = root is Map ? root['data'] : null;
    final info = data is Map ? data['info'] : null;
    if (info is! List) return const <String>[];

    final rows = <({String hash, int diff, int order})>[];
    for (var i = 0; i < info.length; i++) {
      final item = info[i];
      if (item is! Map) continue;
      final hash = item['hash'];
      if (hash is! String || hash.isEmpty) continue;
      final rawDuration = item['duration'];
      final duration = rawDuration is num
          ? rawDuration.toInt()
          : int.tryParse('$rawDuration') ?? -1;
      final diff = (duration - seconds).abs();
      if (seconds > 0 && diff > durationToleranceSeconds) continue;
      rows.add((hash: hash, diff: seconds > 0 ? diff : 0, order: i));
    }
    rows.sort((a, b) {
      final byDiff = a.diff.compareTo(b.diff);
      return byDiff != 0 ? byDiff : a.order.compareTo(b.order);
    });
    return [for (final r in rows) r.hash];
  }

  // ---------------------------------------------------------------------------
  // Step 2: the lyric candidate
  // ---------------------------------------------------------------------------

  Future<KuGouCandidate?> _candidateForHash(String hash) async {
    final body = await _http.getText(_url(_lyricsSearch, {
      'ver': '1',
      'man': 'yes',
      'client': 'pc',
      'hash': hash,
    }));
    return body == null ? null : firstCandidate(body);
  }

  Future<KuGouCandidate?> _candidateForKeyword(
      String keyword, int seconds) async {
    final body = await _http.getText(_url(_lyricsSearch, {
      'ver': '1',
      'man': 'yes',
      'client': 'pc',
      'keyword': keyword,
      if (seconds > 0) 'duration': (seconds * 1000).toString(),
    }));
    return body == null ? null : firstCandidate(body);
  }

  /// The first `{id, accesskey}` in a lyric-search response.
  @visibleForTesting
  static KuGouCandidate? firstCandidate(String body) {
    try {
      final root = jsonDecode(body);
      final candidates = root is Map ? root['candidates'] : null;
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map) return null;
      final id = first['id'];
      final accessKey = first['accesskey'];
      if (id == null || accessKey is! String || accessKey.isEmpty) return null;
      final idText = id.toString();
      return idText.isEmpty ? null : KuGouCandidate(idText, accessKey);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Step 3: the lyric
  // ---------------------------------------------------------------------------

  Future<String?> _download(KuGouCandidate candidate) async {
    final body = await _http.getText(_url(_lyricsDownload, {
      'fmt': 'lrc',
      'charset': 'utf8',
      'client': 'pc',
      'ver': '1',
      'id': candidate.id,
      'accesskey': candidate.accessKey,
    }));
    if (body == null) return null;
    final lrc = decodeDownload(body);
    return lrc == null ? null : stripCredits(lrc);
  }

  /// The LRC text out of a download response: JSON `content` is Base64 UTF-8.
  @visibleForTesting
  static String? decodeDownload(String body) {
    try {
      final root = jsonDecode(body);
      final content = root is Map ? root['content'] : null;
      if (content is! String || content.trim().isEmpty) return null;
      final text = utf8.decode(
        base64.decode(base64.normalize(content.trim())),
        allowMalformed: true,
      );
      return text.replaceAll('\uFEFF', '');
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Query building and credit stripping
  // ---------------------------------------------------------------------------

  /// `"{title} - {artist}"`, each stripped of bracketed qualifiers, then the
  /// album when there is one.
  @visibleForTesting
  static String keyword(String title, String artist, String? album) {
    final buffer = StringBuffer()
      ..write(stripParenthetical(title))
      ..write(' - ')
      ..write(stripParenthetical(artist));
    if (album != null && album.trim().isNotEmpty) {
      buffer
        ..write(' ')
        ..write(album);
    }
    return buffer.toString();
  }

  static final RegExp _parenthetical = RegExp(r'[(（].*?[)）]');

  /// [text] without anything in ASCII or full-width parentheses, or [text]
  /// itself if that would leave nothing.
  @visibleForTesting
  static String stripParenthetical(String text) {
    final stripped = text.replaceAll(_parenthetical, '').trim();
    return stripped.isEmpty ? text : stripped;
  }

  static final RegExp _stamped = RegExp(r'^\[\d{2}:\d{2}\.\d{2,3}\].*$');
  static final RegExp _credit = RegExp(r'^.+\][^\[]+[:：].+$');

  /// KuGou's lyric files open and close with uncredited lines - songwriter,
  /// composer, arranger - that carry a real timestamp and would otherwise be
  /// sung as the first and last lines of the song.
  ///
  /// Keeps only stamped lines, then cuts from either end up to the nearest
  /// "label: value" line, looking only within the first and last 30 lines so a
  /// legitimate lyric that happens to contain a colon deep in the song is left
  /// alone.
  @visibleForTesting
  static String stripCredits(String lrc) {
    final lines = lrc
        .split(RegExp(r'\r\n|\r|\n'))
        .where((line) => _stamped.hasMatch(line))
        .toList();
    if (lines.isEmpty) return '';

    final headLimit = min(30, lines.length - 1);
    var headCut = 0;
    for (var i = headLimit; i >= 0; i--) {
      if (_credit.hasMatch(lines[i])) {
        headCut = i + 1;
        break;
      }
    }
    final body = lines.sublist(headCut);

    final tailLimit = min(30, body.length - 1);
    var tailCut = 0;
    for (var i = 0; i <= tailLimit; i++) {
      if (_credit.hasMatch(body[body.length - 1 - i])) {
        tailCut = i + 1;
        break;
      }
    }
    return body.sublist(0, body.length - tailCut).join('\n');
  }

  /// Query values percent-encoded with a space as `%20`.
  static String _url(String base, Map<String, String> query) {
    final q = query.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$base?$q';
  }
}

/// A KuGou lyric file: its id and the key that unlocks the download.
@immutable
class KuGouCandidate {
  const KuGouCandidate(this.id, this.accessKey);

  final String id;
  final String accessKey;

  @override
  bool operator ==(Object other) =>
      other is KuGouCandidate && other.id == id && other.accessKey == accessKey;

  @override
  int get hashCode => Object.hash(id, accessKey);
}
