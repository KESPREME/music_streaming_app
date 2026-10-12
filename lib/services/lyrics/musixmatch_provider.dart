// lib/services/lyrics/musixmatch_provider.dart
// Musixmatch - rich-sync word timings from the mobile API.
//
// Port of `Musixmatch.kt`. Every request to apic.musixmatch.com is signed:
//
//   signature = base64( HMAC-SHA256( secret, url + UTC yyyyMMdd ) )
//
// and the secret is not a constant. The web client ships it, base64 and
// reversed, inside its `_app-*.js` chunk, so it is scraped from the public
// search page and cached. A fallback secret covers the page being briefly
// unavailable. A user token minted by `token.get` is then cached too; either
// moving credential going stale is reported INSIDE a successful HTTP response
// (`message.header.status_code` 401/402), so both are cleared and the request
// retried once.
//
// WHY THE PREVIOUS VERSION NEVER ANSWERED
//
// It asked for a bearer token from a `web-desktop-app-v1.0` endpoint and then
// read lyrics out of a response shape that endpoint does not produce.
//
// An unobtainable token is not an error. It returns null and the racing layer
// moves on.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';
import 'lyric_words.dart';
import 'lyrics_http.dart';

class MusixmatchProvider {
  /// [clock] is injectable so a signature can be checked against a fixed date.
  MusixmatchProvider(
      {LyricsHttp? http, DateTime Function()? clock, String? guid})
      : _http = http ?? LyricsHttp.shared,
        _clock = clock ?? DateTime.now,
        _guid = guid ?? _newGuid();

  final LyricsHttp _http;
  final DateTime Function() _clock;
  final String _guid;

  static const String _base = 'https://apic.musixmatch.com/ws/1.1';
  static const String _appId = 'mobile-app-v1.0';
  static const String _searchPage = 'https://www.musixmatch.com/search';
  static const Duration _timeout = Duration(seconds: 8);

  static const String _browserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// Used only if the public page serving the rotating key is unavailable.
  static const String fallbackSigningSecret =
      'f09016176ba43a1cfd1031fbd6b3d26c';

  static final RegExp _appScript = RegExp(
    r'''src=["']([^"']*/_next/static/chunks/pages/_app-[^"']+\.js)["']''',
    caseSensitive: false,
  );
  static final RegExp _encodedSecret =
      RegExp(r'''from\(\s*["']([^"']+)["']\s*\.split''');

  String? _cachedSecret;
  Future<String>? _secretInFlight;
  String? _cachedToken;
  Future<String?>? _tokenInFlight;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
  }) async {
    try {
      final seconds = (durationMs ?? 0) ~/ 1000;
      final track = await _bestTrack(title, artist, seconds);
      if (track == null) return null;

      // The subtitle endpoint is line-timed by design. Prefer the separate
      // rich-sync tier so a track that has syllable data is not flattened.
      // `!= 0` rather than `== 1`: an absent flag is "ask and see".
      if (track.hasRichSync != 0) {
        final body = await _fetchRichSync(track.trackId);
        final rich = body == null ? null : parseRichSyncBody(body);
        if (rich != null && rich.any((l) => l.isWordSynced)) return rich;
      }

      if (track.hasSubtitles == 0) return null;
      final subtitle = await _fetchSubtitle(track.trackId);
      final lrc = subtitle == null ? '' : subtitleToLrc(subtitle);
      if (lrc.isEmpty) return null;
      final parsed = LyricsUtils.parseLrc(lrc);
      return parsed.any((e) => e.text.trim().isNotEmpty) ? parsed : null;
    } catch (e) {
      if (kDebugMode) debugPrint('MusixmatchProvider: lookup failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  Future<MusixmatchTrack?> _bestTrack(
    String title,
    String artist,
    int seconds,
  ) async {
    final tracks = await _searchTrack(title, artist);
    if (tracks == null || tracks.isEmpty) return null;
    return bestTrack(tracks, title, artist, seconds);
  }

  /// The highest-scoring track; the earliest wins a tie.
  @visibleForTesting
  static MusixmatchTrack? bestTrack(
    List<MusixmatchTrack> tracks,
    String title,
    String artist,
    int seconds,
  ) {
    MusixmatchTrack? best;
    var bestScore = -double.maxFinite;
    for (final track in tracks) {
      final s = score(track, title, artist, seconds);
      if (s > bestScore) {
        best = track;
        bestScore = s;
      }
    }
    return best;
  }

  /// Title +80 exact / +40 contains, artist +40 contains, length +30 within 2s,
  /// +15 within 5s, +5 within 10s and -20 beyond.
  @visibleForTesting
  static double score(
    MusixmatchTrack track,
    String title,
    String artist,
    int seconds,
  ) {
    var total = 0.0;
    final name = track.trackName.trim().toLowerCase();
    final targetTitle = title.trim().toLowerCase();
    if (name == targetTitle) {
      total += 80;
    } else if (name.contains(targetTitle) || targetTitle.contains(name)) {
      total += 40;
    }
    if (track.artistName
        .trim()
        .toLowerCase()
        .contains(artist.trim().toLowerCase())) {
      total += 40;
    }
    final length = track.trackLength;
    if (length != null) {
      final diff = (length - seconds).abs();
      if (diff <= 2) {
        total += 30;
      } else if (diff <= 5) {
        total += 15;
      } else if (diff <= 10) {
        total += 5;
      } else {
        total -= 20;
      }
    }
    return total;
  }

  Future<List<MusixmatchTrack>?> _searchTrack(
      String title, String artist) async {
    final response = await _signedGet((token) => _url('track.search', {
          'app_id': _appId,
          'format': 'json',
          'q_track': title,
          'q_artist': artist,
          'f_has_lyrics': '1',
          's_track_rating': 'desc',
          'quorum_factor': '1',
          'page_size': '10',
          'page': '1',
          'usertoken': token,
        }));
    if (response == null) return null;
    return parseTrackSearch(response);
  }

  /// `message.body.track_list[].track`, tolerating the empty-result `[]` body.
  @visibleForTesting
  static List<MusixmatchTrack>? parseTrackSearch(String response) {
    final body = _messageBody(response);
    if (body is! Map) return null;
    final list = body['track_list'];
    if (list is! List) return const <MusixmatchTrack>[];
    return [
      for (final item in list)
        if (item is Map && item['track'] is Map)
          if (MusixmatchTrack.tryParse(item['track'] as Map) case final t?) t,
    ];
  }

  Future<String?> _fetchSubtitle(int trackId) async {
    final response = await _signedGet((token) => _url('track.subtitle.get', {
          'app_id': _appId,
          'format': 'json',
          'track_id': trackId.toString(),
          'subtitle_format': 'mxm',
          'usertoken': token,
        }));
    if (response == null) return null;
    final body = _messageBody(response);
    if (body is! Map) return null;
    final subtitle = body['subtitle'];
    return subtitle is Map ? subtitle['subtitle_body'] as String? : null;
  }

  Future<String?> _fetchRichSync(int trackId) async {
    final response = await _signedGet((token) => _url('track.richsync.get', {
          'app_id': _appId,
          'format': 'json',
          'track_id': trackId.toString(),
          'usertoken': token,
        }));
    if (response == null) return null;
    return richSyncBodyFromResponse(response);
  }

  /// `message.body.richsync.richsync_body` out of a `track.richsync.get` reply.
  @visibleForTesting
  static String? richSyncBodyFromResponse(String response) {
    final body = _messageBody(response);
    if (body is! Map) return null;
    final richsync = body['richsync'];
    if (richsync is! Map) return null;
    final text = richsync['richsync_body'];
    return text is String ? text : null;
  }

  // ---------------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------------

  /// Decodes rich-sync offsets without flattening them through line LRC.
  ///
  /// The body is `[{ts, te, l:[{c, o}], x}]`: a line starts at `ts` seconds,
  /// each fragment `c` starts `o` seconds after it, and `x` is the whole line.
  /// Source order is kept because punctuation and syllable fragments can share
  /// a stamp.
  @visibleForTesting
  static List<LyricsEntry> parseRichSyncBody(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const <LyricsEntry>[];
    }
    if (decoded is! List) return const <LyricsEntry>[];

    final out = <LyricsEntry>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final startSeconds = _asDouble(item['ts']);
      final endSeconds = _asDouble(item['te']);
      if (startSeconds == null || endSeconds == null) continue;

      final lineStart = _secondsToMs(startSeconds);
      final lineEnd = max(lineStart, _secondsToMs(endSeconds));

      final fragments = <({String text, double offset})>[
        for (final f in (item['l'] is List ? item['l'] as List : const []))
          if (f is Map && f['c'] is String && _asDouble(f['o']) != null)
            (text: f['c'] as String, offset: _asDouble(f['o'])!),
      ];

      var previousStart = lineStart;
      // Fragments carry their own spacing, so a fragment with no space after it
      // is a syllable of a word that carries on - see [wordsFromRuns].
      final runs = <TimedRun>[];
      for (var index = 0; index < fragments.length; index++) {
        final fragment = fragments[index];
        if (fragment.text.isEmpty) continue;
        final start = max(
          max(lineStart, previousStart),
          _secondsToMs(startSeconds + fragment.offset),
        );
        final next = index + 1 < fragments.length
            ? _secondsToMs(startSeconds + fragments[index + 1].offset)
            : lineEnd;
        previousStart = start;
        runs.add(TimedRun(
          startMs: start,
          endMs: max(start, min(lineEnd, next)),
          raw: fragment.text,
        ));
      }
      final words = wordsFromRuns(runs, spacingIsExplicit: true);

      final x = item['x'] is String ? (item['x'] as String).trim() : '';
      final text = x.isNotEmpty ? x : words.map((w) => w.text).join(' ');
      if (text.isEmpty) continue;

      out.add(LyricsEntry(
        timeMs: words.isNotEmpty && words.first.startMs < lineStart
            ? words.first.startMs
            : lineStart,
        text: text,
        endMs: lineEnd > lineStart ? lineEnd : null,
        lyricWords: words.isEmpty ? null : words,
      ));
    }

    // Stable by construction: ties keep source order.
    final indexed = out.asMap().entries.toList()
      ..sort((a, b) {
        final byTime = a.value.timeMs.compareTo(b.value.timeMs);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });
    return [for (final e in indexed) e.value];
  }

  /// Musixmatch's `mxm` subtitle JSON `[{text, time:{total}}]`, as stamped LRC.
  /// Used only for the line-sync fallback.
  @visibleForTesting
  static String subtitleToLrc(String subtitleBody) {
    final Object? decoded;
    try {
      decoded = jsonDecode(subtitleBody);
    } catch (_) {
      return '';
    }
    if (decoded is! List) return '';

    final buffer = StringBuffer();
    for (final line in decoded) {
      if (line is! Map) continue;
      final text = line['text'];
      final time = line['time'];
      if (text is! String || text.trim().isEmpty || time is! Map) continue;
      final total = _asDouble(time['total']);
      if (total == null) continue;
      final totalMs = _secondsToMs(total);
      final minutes = totalMs ~/ 1000 ~/ 60;
      final seconds = (totalMs ~/ 1000) % 60;
      final millis = totalMs % 1000;
      buffer.writeln('[${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}.'
          '${millis.toString().padLeft(3, '0')}]$text');
    }
    return buffer.toString().trim();
  }

  static int _secondsToMs(double seconds) => (seconds * 1000.0).toInt();

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  /// The `message.body` of an API envelope, or null if it is not one.
  static Object? _messageBody(String response) {
    try {
      final root = jsonDecode(response);
      if (root is! Map) return null;
      final message = root['message'];
      if (message is! Map) return null;
      return message['body'];
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Signed requests
  // ---------------------------------------------------------------------------

  /// Signs and issues [buildUrl]; an auth failure refreshes both moving
  /// credentials once.
  Future<String?> _signedGet(String Function(String token) buildUrl) async {
    final secret = await _secret();
    final token = await _token(secret);
    if (token == null) return null;

    final first = await _apiGet(sign(buildUrl(token), secret, _clock()));
    if (first != null && !looksUnauthorized(first)) return first;

    _cachedToken = null;
    _cachedSecret = null;
    final freshSecret = await _secret();
    final freshToken = await _token(freshSecret);
    if (freshToken == null) return null;
    return _apiGet(sign(buildUrl(freshToken), freshSecret, _clock()));
  }

  /// Musixmatch reports an expired token inside a successful HTTP response.
  @visibleForTesting
  static bool looksUnauthorized(String body) {
    try {
      final root = jsonDecode(body);
      if (root is! Map) return false;
      final message = root['message'];
      if (message is! Map) return false;
      final header = message['header'];
      if (header is! Map) return false;
      final code = header['status_code'];
      final status = code is num ? code.toInt() : int.tryParse('$code');
      return status == 401 || status == 402;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _token(String secret) {
    final cached = _cachedToken;
    if (cached != null) return Future<String?>.value(cached);
    return _tokenInFlight ??= _fetchToken(secret).then((token) {
      _cachedToken = token;
      return token;
    }).whenComplete(() {
      _tokenInFlight = null;
    });
  }

  Future<String?> _fetchToken(String secret) async {
    final url = _url('token.get', {
      'app_id': _appId,
      'guid': _guid,
      'format': 'json',
    });
    final body = await _apiGet(sign(url, secret, _clock()));
    if (body == null) return null;
    final data = _messageBody(body);
    if (data is! Map) return null;
    final token = data['user_token'];
    return token is String && token.isNotEmpty ? token : null;
  }

  /// Reads the rotating signing key from the JavaScript the current web client
  /// links, falling back to a known one if the page is unavailable.
  Future<String> _secret() {
    final cached = _cachedSecret;
    if (cached != null) return Future<String>.value(cached);
    return _secretInFlight ??= _scrapeSecret().then((secret) {
      _cachedSecret = secret;
      return secret;
    }).whenComplete(() {
      _secretInFlight = null;
    });
  }

  Future<String> _scrapeSecret() async {
    try {
      final page =
          await _browserGet(_searchPage, 'text/html,application/xhtml+xml');
      if (page == null) return fallbackSigningSecret;
      final script = _appScript.firstMatch(page)?.group(1);
      if (script == null) return fallbackSigningSecret;
      final scriptUrl = Uri.parse(_searchPage).resolve(script).toString();
      final javascript = await _browserGet(scriptUrl, '*/*');
      if (javascript == null) return fallbackSigningSecret;
      final encoded = _encodedSecret.firstMatch(javascript)?.group(1);
      if (encoded == null) return fallbackSigningSecret;
      return decodeSecret(encoded) ?? fallbackSigningSecret;
    } catch (_) {
      return fallbackSigningSecret;
    }
  }

  /// The web client stores the key reversed and base64-encoded.
  @visibleForTesting
  static String? decodeSecret(String encoded) {
    try {
      final reversed = String.fromCharCodes(encoded.runes.toList().reversed);
      final decoded = utf8.decode(base64.decode(base64.normalize(reversed)));
      return decoded.trim().isEmpty ? null : decoded;
    } catch (_) {
      return null;
    }
  }

  /// Signs `<url><UTC yyyyMMdd>` with HMAC-SHA256, matching the web client.
  ///
  /// Spaces become `+` BEFORE signing, so the signature covers exactly the URL
  /// that is sent.
  @visibleForTesting
  static String sign(String url, String secret, DateTime now) {
    final normalized = url.replaceAll('%20', '+').replaceAll(' ', '+');
    final utc = now.toUtc();
    final date = '${utc.year.toString().padLeft(4, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}';
    final mac = Hmac(sha256, utf8.encode(secret));
    final digest = mac.convert(utf8.encode('$normalized$date'));
    final signature = base64.encode(digest.bytes);
    return '$normalized&signature=${Uri.encodeQueryComponent(signature)}'
        '&signature_protocol=sha256';
  }

  Future<String?> _apiGet(String url) => _http.getText(
        url,
        headers: const {
          'User-Agent': _browserAgent,
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'en-US,en;q=0.9',
        },
        timeout: _timeout,
      );

  Future<String?> _browserGet(String url, String accept) => _http.getText(
        url,
        headers: {
          'User-Agent': _browserAgent,
          'Accept': accept,
          'Accept-Language': 'en-US,en;q=0.9',
          'Cookie': 'mxm_bab=AB',
        },
        timeout: _timeout,
      );

  // ---------------------------------------------------------------------------
  // URLs and ids
  // ---------------------------------------------------------------------------

  /// Query values percent-encoded the way OkHttp does, which is what the
  /// signature was designed against: everything but letters, digits and
  /// `- . _ *` is escaped, and a space becomes `%20` (then `+` in [sign]).
  static String _url(String method, Map<String, String> query) {
    final q = query.entries
        .map((e) => '${_encode(e.key)}=${_encode(e.value)}')
        .join('&');
    return '$_base/$method?$q';
  }

  static String _encode(String value) {
    final out = StringBuffer();
    for (final byte in utf8.encode(value)) {
      final isUnreserved = (byte >= 0x30 && byte <= 0x39) ||
          (byte >= 0x41 && byte <= 0x5A) ||
          (byte >= 0x61 && byte <= 0x7A) ||
          byte == 0x2D || // -
          byte == 0x2E || // .
          byte == 0x5F || // _
          byte == 0x2A; // *
      if (isUnreserved) {
        out.writeCharCode(byte);
      } else {
        out
          ..write('%')
          ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return out.toString();
  }

  /// A random v4 UUID, identifying this process to Musixmatch.
  static String _newGuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // RFC 4122 variant
    String hex(int from, int to) => bytes
        .sublist(from, to)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}

/// One row of `track.search`.
@immutable
class MusixmatchTrack {
  const MusixmatchTrack({
    required this.trackId,
    required this.trackName,
    required this.artistName,
    this.trackLength,
    this.hasSubtitles,
    this.hasRichSync,
  });

  final int trackId;
  final String trackName;
  final String artistName;
  final int? trackLength;
  final int? hasSubtitles;
  final int? hasRichSync;

  static MusixmatchTrack? tryParse(Map json) {
    final id = _int(json['track_id']);
    final name = json['track_name'];
    if (id == null || name is! String) return null;
    return MusixmatchTrack(
      trackId: id,
      trackName: name,
      artistName:
          json['artist_name'] is String ? json['artist_name'] as String : '',
      trackLength: _int(json['track_length']),
      hasSubtitles: _int(json['has_subtitles']),
      hasRichSync: _int(json['has_richsync']),
    );
  }

  static int? _int(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
