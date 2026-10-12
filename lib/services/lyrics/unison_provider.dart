// lib/services/lyrics/unison_provider.dart
// Unison - a community-submitted lyrics database answering TTML, LRC or plain
// text.
//
// Port of `Unison.kt`.
//
// Every other source here is a window onto somebody's catalogue; this one
// carries what people have uploaded, so it occasionally has a track none of the
// others do and its coverage is thin everywhere else. Entries are voted on and
// the response says so (`confidence`, `voteCount`); none of it is acted on - a
// fresh submission is `confidence: "low"` with no votes at all, so refusing
// those would refuse nearly the whole database, and the alternative to a
// lightly-voted entry is usually no lyrics rather than better ones.
//
// WIRE SHAPE
//
//   GET https://unison.boidu.dev/lyrics?song=&artist=&album=&duration=<s>
//   {"success":true,"data":{"lyrics":"<tt ...>","format":"ttml"|"lrc",
//     "syncType":"richsync"|"wordsync"|"linesync"|"plain", ...}}
//
// The previous version looked for a top-level `ttml` / `syncedLyrics` /
// `lyrics`, none of which this host sends, and invented 3-second steps for
// unsynced text. Plain text is now stamped 0 like every other unsynced source,
// which is how the panel knows to scroll it by hand rather than follow it.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';
import 'better_lyrics_provider.dart';
import 'lyrics_http.dart';
import 'lyrics_url.dart';

class UnisonProvider {
  UnisonProvider({LyricsHttp? http}) : _http = http ?? LyricsHttp.shared;

  static const String _endpoint = 'https://unison.boidu.dev/lyrics';

  final LyricsHttp _http;

  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) async {
    final params = <String, String>{'song': title, 'artist': artist};
    if (album != null && album.trim().isNotEmpty) params['album'] = album;
    if (durationMs != null) {
      final seconds = (durationMs / 1000).round();
      if (seconds > 0) params['duration'] = '$seconds';
    }

    final body = await _http.getText(buildLyricsUrl(_endpoint, params));
    if (body == null) return null;
    return parseBody(body);
  }

  /// Lyrics in a raw response body, or null for anything unusable.
  static List<LyricsEntry>? parseBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return parse(decoded.map((k, v) => MapEntry(k.toString(), v)));
    } catch (e) {
      if (kDebugMode) debugPrint('UnisonProvider: answer unreadable: $e');
      return null;
    }
  }

  /// Lyrics in a decoded response: `{"success":true,"data":{...}}`.
  static List<LyricsEntry>? parse(Map<String, dynamic> body) {
    if (body['success'] != true) return null;
    final data = body['data'];
    if (data is! Map) return null;
    return linesOf(data.map((k, v) => MapEntry(k.toString(), v)));
  }

  /// The three shapes, told apart by what the entry says it is.
  static List<LyricsEntry>? linesOf(Map<String, dynamic> data) {
    final text = data['lyrics'];
    if (text is! String || text.trim().isEmpty) return null;
    final format = data['format'];
    final syncType = data['syncType'];

    final List<LyricsEntry> lines;
    if (format is String && format.toLowerCase() == 'ttml') {
      lines = BetterLyricsProvider.parseTtml(text);
    } else if (syncType is String && syncType.toLowerCase() == 'plain') {
      lines = parsePlain(text);
    } else {
      // Word stamps and line stamps are both "lrc" here; LyricsUtils reads
      // either, and an enhanced file is still one.
      lines = parseLrc(text);
    }
    return lines.any((l) => l.text.trim().isNotEmpty) ? lines : null;
  }

  /// LRC parsing, delegated to [LyricsUtils] rather than re-implemented.
  ///
  /// That class already owns every LRC rule this app follows, including the
  /// word-timing forms. A second parser here would be a second opinion, and two
  /// parsers that disagree is how the same song shows different words depending
  /// on which provider happened to answer.
  static List<LyricsEntry> parseLrc(String lrc) => LyricsUtils.parseLrc(lrc);

  /// Lyrics with no timing: one line each, all stamped 0.
  ///
  /// Nothing is invented. A fixed step per line would pass for timing, and the
  /// panel would follow it - scrolling to the wrong line every time.
  static List<LyricsEntry> parsePlain(String plain) => <LyricsEntry>[
        for (final raw in const LineSplitter().convert(plain))
          if (raw.trim().isNotEmpty) LyricsEntry(timeMs: 0, text: raw.trim()),
      ];
}
