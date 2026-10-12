// lib/services/lyrics/lyrics_http.dart
// Shared HTTP plumbing for the lyric providers.
//
// WHY ONE CLIENT AND ONE DEADLINE
//
// Every provider is raced against the others, so one that hangs holds up the
// lookup behind it. The deadline is deliberately short: a lyric that arrives
// after the second chorus is of no use to anyone, and the fallbacks behind it
// are the better answer. BitChord uses 6s per call / 3s to connect
// (`LyricsHttp.kt:17-28`), and so does this.
//
// Before this file existed LRCLIB had no timeout at all, LyricsPlus asked six
// mirrors one after another at 8s each, and KuGou chained three 4s requests.
// Because the race consumes answers in priority order, one slow host stalled
// everything ranked below it.
//
// WHAT THIS DOES NOT DO
//
// It does not throw. A lyric host is a volunteer service; a failure is the
// ordinary case and the racing layer moves on. Every method returns null for
// any failure at all, and the caller treats null as a miss.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Thin, never-throwing wrapper over [http.Client] with lyric-sized deadlines.
class LyricsHttp {
  /// Pass a client to test against a recorded response; production uses
  /// [LyricsHttp.shared].
  LyricsHttp({http.Client? client}) : _client = client ?? _defaultClient();

  /// One instance for the app, so the connection pool and DNS cache are common.
  static final LyricsHttp shared = LyricsHttp();

  /// Per-request deadline.
  static const Duration requestTimeout = Duration(seconds: 6);

  /// Connect deadline for the shared client.
  static const Duration connectTimeout = Duration(seconds: 3);

  /// PaxSenix's keyed routes often have to query an upstream catalogue before
  /// answering. Matches its own client timeout so a valid request is not thrown
  /// away while the backend is still resolving the track.
  static const Duration authenticatedTimeout = Duration(seconds: 15);

  /// The app's own identity.
  ///
  /// Our own name rather than another product's: borrowing a different app's
  /// User-Agent is impersonation, and it is not needed. What hosts such as
  /// Genius object to is a *browser-shaped* agent that cannot pass a JavaScript
  /// challenge, not an unknown one.
  static const String agent = 'MineMusic/1.0 (+lyrics; https://github.com/)';

  final http.Client _client;

  static http.Client _defaultClient() {
    final inner = HttpClient()..connectionTimeout = connectTimeout;
    return IOClient(inner);
  }

  /// Body of a successful GET, or null for any failure at all.
  Future<String?> getText(
    String url, {
    Map<String, String>? headers,
    Duration timeout = requestTimeout,
  }) =>
      _send(
        () => _client.get(Uri.parse(url), headers: _merge(headers)),
        timeout,
        url,
      );

  /// A GET carrying a bearer token, without any service-specific browser
  /// headers. For routes that authenticate with a key the listener supplied.
  Future<String?> getBearer(
    String url,
    String bearer, {
    Duration timeout = authenticatedTimeout,
  }) {
    if (bearer.trim().isEmpty) return Future<String?>.value(null);
    return getText(
      url,
      headers: {'Authorization': 'Bearer ${bearer.trim()}'},
      timeout: timeout,
    );
  }

  /// A GET with a bearer token AND the headers Apple's own web player sends
  /// alongside one. `amp-api.music.apple.com` answers a token with no `Origin`
  /// the same way it answers a wrong one - with a 401/403
  /// (`LyricsHttp.kt:73-84`).
  Future<String?> getAppleAuthorized(String url, String bearer) => getText(
        url,
        headers: {
          'Authorization': 'Bearer $bearer',
          'Origin': 'https://music.apple.com',
          'Referer': 'https://music.apple.com/',
        },
      );

  /// Body of a successful form POST, or null for any failure at all.
  Future<String?> postForm(
    String url,
    Map<String, String> fields, {
    Map<String, String>? headers,
    Duration timeout = requestTimeout,
  }) =>
      _send(
        () => _client.post(Uri.parse(url), headers: _merge(headers), body: fields),
        timeout,
        url,
      );

  Map<String, String> _merge(Map<String, String>? extra) => <String, String>{
        'User-Agent': agent,
        'Accept': 'application/json, text/plain, */*',
        ...?extra,
      };

  Future<String?> _send(
    Future<http.Response> Function() request,
    Duration timeout,
    String url,
  ) async {
    try {
      final response = await request().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (response.bodyBytes.isEmpty) return null;
      // Decoded here rather than via `response.body`, which trusts the
      // Content-Type charset and mangles UTF-8 served as latin-1.
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } on TimeoutException {
      if (kDebugMode) debugPrint('LyricsHttp: timeout $url');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsHttp: $url failed: $e');
      return null;
    }
  }

  void close() => _client.close();
}
