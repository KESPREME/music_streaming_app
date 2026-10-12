// LRCLIB: `get` / `search` selection against REAL captured responses for
// Borderline / Tame Impala. lrclib_get.json is verbatim. lrclib_search.json is
// the real 20-hit response with `plainLyrics` and `lyricsfile` removed and each
// hit's `syncedLyrics` cut to its first 8 lines (the full response was 213 KB);
// ids, names, albums and durations - the fields selection reads - are untouched.
//
// Nothing here touches the network: every request goes to a MockClient.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/lyrics/lrclib_provider.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_http.dart';

String fixture(String name) =>
    File('test/fixtures/lyrics/$name').readAsStringSync();

http.Response utf8Response(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

/// Routes get/search, logging each request.
MockClient scripted(
  List<http.Request> log, {
  http.Response? get,
  String? search,
}) {
  return MockClient((request) async {
    log.add(request);
    if (request.url.path == '/api/get') {
      return get ??
          utf8Response('{"statusCode":404,"name":"TrackNotFound"}', 404);
    }
    if (request.url.path == '/api/search') {
      return utf8Response(search ?? '[]');
    }
    return utf8Response('', 404);
  });
}

LrcLibProvider providerFor(MockClient client) =>
    LrcLibProvider(http: LyricsHttp(client: client));

void main() {
  final getBody = fixture('lrclib_get.json');
  final getJson = jsonDecode(getBody) as Map<String, dynamic>;
  final searchBody = fixture('lrclib_search.json');
  final hits = (jsonDecode(searchBody) as List).cast<Map<String, dynamic>>();

  /// The real search hit with this id.
  Map<String, dynamic> hit(int id) => hits.firstWhere((h) => h['id'] == id);

  group('get (real response)', () {
    test('synced lyrics from get are returned, in one request', () async {
      final log = <http.Request>[];
      final provider = providerFor(scripted(log, get: utf8Response(getBody)));

      final lrc = await provider.getLyrics(
          title: 'Borderline', artist: 'Tame Impala', durationSeconds: 237);

      expect(lrc, getJson['syncedLyrics']);
      expect(lrc!.trimLeft(), startsWith('['));
      expect(log, hasLength(1));

      final request = log.single;
      expect(request.url.host, 'lrclib.net');
      expect(request.url.path, '/api/get');
      expect(request.url.queryParameters, {
        'track_name': 'Borderline',
        'artist_name': 'Tame Impala',
        'duration': '237'
      });
      // The album is not sent: a spelling mismatch would turn a hit into a 404.
      expect(request.url.queryParameters.containsKey('album_name'), isFalse);
      expect(request.headers['User-Agent'], LyricsHttp.agent);
    });

    test('a record with ONLY plain lyrics is not accepted from get', () async {
      for (final synced in [null, '', '   \n']) {
        final log = <http.Request>[];
        final plainOnly = Map<String, dynamic>.of(getJson)
          ..['syncedLyrics'] = synced;
        final provider = providerFor(scripted(log,
            get: utf8Response(jsonEncode(plainOnly)), search: '[]'));

        final lrc = await provider.getLyrics(
            title: 'Borderline', artist: 'Tame Impala', durationSeconds: 237);

        expect(lrc, isNull, reason: 'syncedLyrics: ${jsonEncode(synced)}');
        // It went on to search instead of settling for the plain text.
        expect(
            log.map((r) => r.url.path).toList(), ['/api/get', '/api/search']);
      }
    });

    test('plain lyrics are never returned, even when nothing else exists',
        () async {
      final plainOnly = Map<String, dynamic>.of(getJson)
        ..['syncedLyrics'] = null;
      final provider = providerFor(scripted(
        <http.Request>[],
        get: utf8Response(jsonEncode(plainOnly)),
        search: jsonEncode([plainOnly]),
      ));

      expect(
        await provider.getLyrics(
            title: 'Borderline', artist: 'Tame Impala', durationSeconds: 237),
        isNull,
      );
    });

    test('an unknown duration omits the parameter rather than sending 0',
        () async {
      final log = <http.Request>[];
      final provider = providerFor(scripted(log, get: utf8Response(getBody)));

      await provider.getLyrics(title: 'Borderline', artist: 'Tame Impala');

      expect(log.single.url.queryParameters.containsKey('duration'), isFalse);
    });
  });

  group('search (real response)', () {
    test('after a 404 from get, search runs once and no more', () async {
      final log = <http.Request>[];
      final provider = providerFor(scripted(log, search: searchBody));

      final lrc = await provider.getLyrics(
          title: 'Borderline', artist: 'Tame Impala', durationSeconds: 237);

      expect(lrc, isNotNull);
      expect(log.map((r) => r.url.path).toList(), ['/api/get', '/api/search']);
      expect(log.last.url.queryParameters,
          {'track_name': 'Borderline', 'artist_name': 'Tame Impala'});
    });

    test('picks the hit whose length is closest to the wanted one', () async {
      Future<String?> ask(int seconds) => providerFor(scripted(
            <http.Request>[],
            search: searchBody,
          )).getLyrics(
              title: 'Borderline',
              artist: 'Tame Impala',
              durationSeconds: seconds);

      // Exact: two hits are 237s; the earlier one wins.
      expect(await ask(237), hit(34705429)['syncedLyrics']);
      // 164s exists only as the 36863443 record.
      expect(await ask(164), hit(36863443)['syncedLyrics']);
      // 289s exists only as the Coachella record.
      expect(await ask(289), hit(34773950)['syncedLyrics']);
      // 300s is nearest to 289 (11s), ahead of 437 (137s).
      expect(await ask(300), hit(34773950)['syncedLyrics']);
    });

    test('with no wanted length the first synced hit is taken', () async {
      final provider =
          providerFor(scripted(<http.Request>[], search: searchBody));
      final lrc =
          await provider.getLyrics(title: 'Borderline', artist: 'Tame Impala');
      expect(lrc, hits.first['syncedLyrics']);
    });

    test('a hit without synced lyrics is skipped however close it is',
        () async {
      final mutated = [
        for (final h in hits)
          if (h['id'] == 34705429)
            (Map<String, dynamic>.of(h)..['syncedLyrics'] = null)
          else
            h,
      ];
      final provider =
          providerFor(scripted(<http.Request>[], search: jsonEncode(mutated)));

      final lrc = await provider.getLyrics(
          title: 'Borderline', artist: 'Tame Impala', durationSeconds: 237);

      // The other 237s record (the Blood Orange single) takes over.
      expect(lrc, hit(34366391)['syncedLyrics']);
    });

    test('it never takes results.first blindly', () async {
      final list = [
        {
          'id': 1,
          'trackName': 'x',
          'artistName': 'y',
          'duration': 237,
          'syncedLyrics': null,
          'plainLyrics': 'plain'
        },
        {
          'id': 2,
          'trackName': 'x',
          'artistName': 'y',
          'duration': 237,
          'syncedLyrics': '',
          'plainLyrics': 'plain'
        },
        {
          'id': 3,
          'trackName': 'x',
          'artistName': 'y',
          'duration': 500,
          'syncedLyrics': '[00:01.00]real'
        },
      ];
      final provider =
          providerFor(scripted(<http.Request>[], search: jsonEncode(list)));

      expect(
        await provider.getLyrics(title: 'x', artist: 'y', durationSeconds: 237),
        '[00:01.00]real',
      );
      expect(
          await provider.getLyrics(title: 'x', artist: 'y'), '[00:01.00]real');
    });

    test('a double duration (the live bug) and a missing one are both read',
        () {
      final results = LrcLibProvider.parseSearch(jsonEncode([
        {
          'id': 1,
          'trackName': 'a',
          'artistName': 'b',
          'duration': 237.6,
          'syncedLyrics': '[0]'
        },
        {'id': 2, 'trackName': 'a', 'artistName': 'b', 'syncedLyrics': '[0]'},
        {
          'id': 3,
          'trackName': 'a',
          'artistName': 'b',
          'duration': '240',
          'syncedLyrics': '[0]'
        },
      ]));
      expect(results.map((r) => r.duration).toList(), [237, 0, 240]);
    });

    test('hits that are not records, or a non-list body, are ignored', () {
      expect(LrcLibProvider.parseSearch('[1, "x", null, {"id": 5}]').length, 1);
      expect(LrcLibProvider.parseSearch('{"error":"x"}'), isEmpty);
      expect(LrcLibProvider.parseSearch('<html>'), isEmpty);
    });

    test('nothing found anywhere is null', () async {
      final provider = providerFor(scripted(<http.Request>[], search: '[]'));
      expect(
        await provider.getLyrics(
            title: 'Nonexistent', artist: 'Nobody', durationSeconds: 100),
        isNull,
      );
    });
  });

  group('failure and timeout', () {
    test('a server error or garbage body is a miss, not an exception',
        () async {
      final broken =
          providerFor(MockClient((_) async => utf8Response('oops', 500)));
      expect(
        await broken.getLyrics(
            title: 'Borderline', artist: 'Tame Impala', durationSeconds: 237),
        isNull,
      );

      final garbage = providerFor(
          MockClient((_) async => utf8Response('<html>not json</html>')));
      expect(
        await garbage.getLyrics(
            title: 'Borderline', artist: 'Tame Impala', durationSeconds: 237),
        isNull,
      );
    });

    testWidgets('a hung server is abandoned at the lyric deadline',
        (tester) async {
      var calls = 0;
      final never = Completer<http.Response>();
      final provider = providerFor(MockClient((_) {
        calls++;
        return never.future;
      }));

      final result = provider.getLyrics(
          title: 'Borderline', artist: 'Tame Impala', durationSeconds: 237);

      // `get` hangs, is given up on at 6s, and the search is then tried - and
      // is given up on in turn. Without a timeout this never finishes.
      await tester.pump(LyricsHttp.requestTimeout + const Duration(seconds: 1));
      await tester.pump(LyricsHttp.requestTimeout + const Duration(seconds: 1));

      expect(await result, isNull);
      expect(calls, 2);
    });
  });
}
