// Musixmatch: signing, secret scraping, token handling and the rich-sync
// parser.
//
// UNVERIFIABLE LIVE: from the machine this was written on, `token.get` on
// apic.musixmatch.com answers an nginx 403 (three header variants, scraped and
// fallback secrets), so NO Musixmatch response here was captured. The signing
// vectors were computed with an independent HMAC implementation (PowerShell);
// the rich-sync fixture and the search/subtitle payloads are HAND-WRITTEN to
// match the RichSyncEntry / SubtitleLine shapes in Musixmatch.kt.
//
// Nothing here touches the network: every request goes to a MockClient.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_http.dart';
import 'package:music_streaming_app/services/lyrics/musixmatch_provider.dart';

String fixture(String name) =>
    File('test/fixtures/lyrics/$name').readAsStringSync();

http.Response utf8Response(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

String ok(Object body) => jsonEncode({
      'message': {
        'header': {'status_code': 200},
        'body': body,
      },
    });

const String unauthorized =
    '{"message":{"header":{"status_code":401,"hint":"renew"},"body":[]}}';

void main() {
  const fallback = MusixmatchProvider.fallbackSigningSecret;

  group('signature (vectors from an independent HMAC implementation)', () {
    test('token.get at a fixed date and secret', () {
      final signed = MusixmatchProvider.sign(
        'https://apic.musixmatch.com/ws/1.1/token.get?app_id=mobile-app-v1.0'
        '&guid=11111111-2222-4333-8444-555555555555&format=json',
        fallback,
        DateTime.utc(2026, 10, 12, 8, 30),
      );
      expect(
        signed,
        'https://apic.musixmatch.com/ws/1.1/token.get?app_id=mobile-app-v1.0'
        '&guid=11111111-2222-4333-8444-555555555555&format=json'
        '&signature=w0KiqbPt1f1QwQgJ7u%2B%2FCf7xttnGPYL0FwQZGHQ8vFU%3D'
        '&signature_protocol=sha256',
      );
    });

    test('spaces are normalised to + BEFORE signing', () {
      final signed = MusixmatchProvider.sign(
        'https://apic.musixmatch.com/ws/1.1/track.search?app_id=mobile-app-v1.0'
        '&format=json&q_track=Don%27t%20Stop&q_artist=Tame%20Impala'
        '&usertoken=abc123',
        fallback,
        DateTime.utc(2026, 10, 12),
      );
      expect(
        signed,
        'https://apic.musixmatch.com/ws/1.1/track.search?app_id=mobile-app-v1.0'
        '&format=json&q_track=Don%27t+Stop&q_artist=Tame+Impala'
        '&usertoken=abc123'
        '&signature=mZ9T96VaXD8WW6NIRrNsG9OuNrrykZdhKpFvWuj1zj4%3D'
        '&signature_protocol=sha256',
      );
    });

    test('a different secret and date give a different signature', () {
      final signed = MusixmatchProvider.sign(
        'https://apic.musixmatch.com/ws/1.1/token.get?app_id=mobile-app-v1.0'
            '&guid=11111111-2222-4333-8444-555555555555&format=json',
        'another-secret-value',
        DateTime.utc(2026, 12, 31),
      );
      expect(
        signed,
        endsWith(
            '&signature=NLyQK0dncL%2Bi0iR3mMx%2BMC%2B7kOmVsSSC%2BaEQydMdyPI%3D'
            '&signature_protocol=sha256'),
      );
    });

    test('the date is the UTC date, not the local one', () {
      const url = 'https://apic.musixmatch.com/ws/1.1/token.get?app_id=x';
      // 23:59 at UTC-5 is already the 13th in UTC.
      final localEvening = DateTime.parse('2026-10-12T23:59:59-05:00');
      expect(
        MusixmatchProvider.sign(url, fallback, localEvening),
        MusixmatchProvider.sign(url, fallback, DateTime.utc(2026, 10, 13)),
      );
      expect(
        MusixmatchProvider.sign(url, fallback, localEvening),
        isNot(
            MusixmatchProvider.sign(url, fallback, DateTime.utc(2026, 10, 12))),
      );
    });

    test('the secret is stored reversed and base64-encoded', () {
      const secret = 'test-secret-key-0123456789abcdef';
      final stored = String.fromCharCodes(
          base64.encode(utf8.encode(secret)).runes.toList().reversed);
      expect(MusixmatchProvider.decodeSecret(stored), secret);
      expect(MusixmatchProvider.decodeSecret('!!!not base64!!!'), isNull);
      expect(MusixmatchProvider.decodeSecret(''), isNull);
    });
  });

  group('rich-sync parser (hand-written fixture)', () {
    final body = MusixmatchProvider.richSyncBodyFromResponse(
        fixture('musixmatch_richsync_sample.json'))!;
    final lines = MusixmatchProvider.parseRichSyncBody(body);

    test('lines come out in order with their sung-until time', () {
      expect(lines.map((l) => l.text).toList(),
          ['We\'re on the borderline', '(instrumental)', 'Out of order']);
      expect(lines.map((l) => l.timeMs).toList(), [12000, 18000, 20250]);
      expect(lines[0].endMs, 16000);
      // te == ts: no sung span.
      expect(lines[1].endMs, isNull);
    });

    test('fragment start is ts+o and end is the next start, capped at te', () {
      final words = lines[0].lyricWords!;
      expect(words.map((w) => w.text).toList(),
          ['We\'re', 'on', 'the', 'borderline']);
      expect(words[0].startMs, 12000);
      expect(words[0].endMs, 12375);
      expect(words[1].startMs, 12500);
      expect(words[3].startMs, 13250);
      expect(words[3].endMs, 16000); // last fragment ends at te
    });

    test('fragments with no space between them are syllables of one word', () {
      final borderline = lines[0].lyricWords!.last;
      expect(borderline.syllables.length, 2);
      expect(borderline.syllables[0].startMs, 13250);
      expect(borderline.syllables[0].endMs, 13750);
      expect(borderline.syllables[1].startMs, 13750);
      expect(borderline.isSyllableSynced, isTrue);
    });

    test('a fragment stamped earlier than its predecessor is clamped forward',
        () {
      final words = lines[2].lyricWords!;
      expect(words.map((w) => w.text).toList(), ['Out', 'of', 'order']);
      // "of" claims offset 0.25 but follows "Out" at 0.5 and a space at 0.75.
      expect(words[1].startMs, greaterThanOrEqualTo(words[0].startMs));
      expect(words[1].startMs, 21000);
      for (var i = 1; i < words.length; i++) {
        expect(words[i].startMs, greaterThanOrEqualTo(words[i - 1].startMs));
      }
    });

    test('a line with no fragments keeps its text but has no words', () {
      expect(lines[1].lyricWords, isNull);
      expect(lines[1].isWordSynced, isFalse);
    });

    test('garbage is an empty result, not an exception', () {
      expect(MusixmatchProvider.parseRichSyncBody('not json'), isEmpty);
      expect(MusixmatchProvider.parseRichSyncBody('{"a":1}'), isEmpty);
      expect(MusixmatchProvider.parseRichSyncBody('[1,2,{"ts":"x"}]'), isEmpty);
    });
  });

  group('subtitle conversion and scoring', () {
    test('mxm subtitle JSON becomes [mm:ss.mmm] LRC and drops blank lines', () {
      final lrc = MusixmatchProvider.subtitleToLrc(jsonEncode([
        {
          'text': 'Hello',
          'time': {'total': 5.25, 'minutes': 0}
        },
        {
          'text': ' ',
          'time': {'total': 7.0}
        },
        {
          'text': 'World',
          'time': {'total': 65.0625}
        },
      ]));
      // 65.0625s is 65062.5ms; the conversion truncates, as the reference does.
      expect(lrc, '[00:05.250]Hello\n[01:05.062]World');
    });

    test('score: title, artist and length rules', () {
      const exact = MusixmatchTrack(
          trackId: 1,
          trackName: 'Borderline',
          artistName: 'Tame Impala',
          trackLength: 238);
      // 80 title + 40 artist + 30 (within 2s)
      expect(MusixmatchProvider.score(exact, 'Borderline', 'Tame Impala', 237),
          150);
      expect(MusixmatchProvider.score(exact, 'borderline', 'tame impala', 233),
          135);
      expect(MusixmatchProvider.score(exact, 'Borderline', 'Tame Impala', 229),
          125);
      expect(MusixmatchProvider.score(exact, 'Borderline', 'Tame Impala', 100),
          100);

      const partial = MusixmatchTrack(
          trackId: 2, trackName: 'Borderline (Live)', artistName: 'X');
      expect(MusixmatchProvider.score(partial, 'Borderline', 'Y', 0), 40);
    });

    test('the best track wins, the earliest breaks a tie', () {
      const a = MusixmatchTrack(
          trackId: 1, trackName: 'Song', artistName: 'Band', trackLength: 200);
      const b = MusixmatchTrack(
          trackId: 2, trackName: 'Song', artistName: 'Band', trackLength: 200);
      const c = MusixmatchTrack(
          trackId: 3, trackName: 'Song', artistName: 'Band', trackLength: 400);
      expect(
          MusixmatchProvider.bestTrack([c, a, b], 'Song', 'Band', 200)!.trackId,
          1);
    });

    test('track.search tolerates the empty-result [] body', () {
      expect(MusixmatchProvider.parseTrackSearch(ok(<dynamic>[])), isNull);
      expect(
          MusixmatchProvider.parseTrackSearch(ok({'track_list': []})), isEmpty);
    });
  });

  group('end to end with a scripted Musixmatch', () {
    const secret = 'test-secret-key-0123456789abcdef';
    final reversedB64 = String.fromCharCodes(
        base64.encode(utf8.encode(secret)).runes.toList().reversed);

    final searchBody = ok({
      'track_list': [
        {
          'track': {
            'track_id': 111,
            'track_name': 'Borderline (Live)',
            'artist_name': 'Tame Impala',
            'track_length': 300,
            'has_subtitles': 1,
            'has_richsync': 0,
          },
        },
        {
          'track': {
            'track_id': 222,
            'track_name': 'Borderline',
            'artist_name': 'Tame Impala',
            'track_length': 238,
            'has_subtitles': 1,
            'has_richsync': 1,
          },
        },
      ],
    });

    final fixedNow = DateTime.utc(2026, 10, 12, 9);

    /// Verifies the signature on [url] by recomputing it independently.
    void expectValidSignature(Uri url, String forSecret) {
      final signature = url.queryParameters['signature']!;
      expect(url.queryParameters['signature_protocol'], 'sha256');
      final raw = url.toString();
      final unsigned = raw.substring(0, raw.indexOf('&signature='));
      final mac = Hmac(sha256, utf8.encode(forSecret))
          .convert(utf8.encode('${unsigned}20261012'));
      expect(signature, base64.encode(mac.bytes));
    }

    test(
        'scrapes the secret, mints a token once, signs every call, and '
        'prefers rich sync', () async {
      final requests = <http.Request>[];
      var tokenCalls = 0;
      final client = MockClient((request) async {
        requests.add(request);
        final url = request.url;
        if (url.host == 'www.musixmatch.com' && url.path == '/search') {
          return utf8Response('<html><script defer src="https://s.mxmcdn.net/'
              'mxm-com/prod/1.41.9/_next/static/chunks/pages/_app-abc123.js">'
              '</script></html>');
        }
        if (url.host == 's.mxmcdn.net') {
          return utf8Response(
              'x=Buffer.from("$reversedB64".split("").reverse().join(""),"base64");');
        }
        if (url.path.endsWith('/token.get')) {
          tokenCalls++;
          return utf8Response(ok({'user_token': 'tok-$tokenCalls'}));
        }
        if (url.path.endsWith('/track.search')) return utf8Response(searchBody);
        if (url.path.endsWith('/track.richsync.get')) {
          return utf8Response(fixture('musixmatch_richsync_sample.json'));
        }
        return utf8Response('', 404);
      });
      final provider = MusixmatchProvider(
        http: LyricsHttp(client: client),
        clock: () => fixedNow,
        guid: 'fixed-guid',
      );

      final first = await provider.getLyrics(
          title: 'Borderline', artist: 'Tame Impala', durationMs: 237800);
      final second = await provider.getLyrics(
          title: 'Borderline', artist: 'Tame Impala', durationMs: 237800);

      expect(first, isNotNull);
      expect(first!.first.text, 'We\'re on the borderline');
      expect(first.first.isSyllableSynced, isTrue);
      expect(second, isNotNull);
      expect(tokenCalls, 1, reason: 'the token is cached');

      // The page fetches carry the cookie; API calls do not.
      final page =
          requests.firstWhere((r) => r.url.host == 'www.musixmatch.com');
      expect(page.headers['Cookie'], 'mxm_bab=AB');
      expect(page.headers['User-Agent'], contains('Chrome/131'));
      expect(page.headers['Accept-Language'], 'en-US,en;q=0.9');
      // Scraped once for both lookups.
      expect(requests.where((r) => r.url.host == 'www.musixmatch.com'),
          hasLength(1));

      final api =
          requests.where((r) => r.url.host == 'apic.musixmatch.com').toList();
      expect(api.first.url.path, '/ws/1.1/token.get');
      expect(api.first.url.queryParameters['guid'], 'fixed-guid');
      expect(api.first.url.queryParameters['app_id'], 'mobile-app-v1.0');
      expect(api.first.headers.containsKey('Cookie'), isFalse);
      for (final r in api) {
        expectValidSignature(r.url, secret);
      }

      final search =
          api.firstWhere((r) => r.url.path.endsWith('/track.search'));
      expect(search.url.queryParameters, containsPair('q_track', 'Borderline'));
      expect(
          search.url.queryParameters, containsPair('q_artist', 'Tame Impala'));
      expect(search.url.queryParameters, containsPair('f_has_lyrics', '1'));
      expect(
          search.url.queryParameters, containsPair('s_track_rating', 'desc'));
      expect(search.url.queryParameters, containsPair('quorum_factor', '1'));
      expect(search.url.queryParameters, containsPair('page_size', '10'));
      expect(search.url.queryParameters, containsPair('usertoken', 'tok-1'));
      // The spaced artist went out with '+', as it was signed.
      expect(search.url.toString(), contains('q_artist=Tame+Impala'));

      final rich =
          api.firstWhere((r) => r.url.path.endsWith('/track.richsync.get'));
      // 238s is within 2s of 237.8s: track 222 outranks the 300s live cut.
      expect(rich.url.queryParameters['track_id'], '222');
    });

    test('an unreachable search page falls back to the built-in secret',
        () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final url = request.url;
        if (url.host == 'www.musixmatch.com') return utf8Response('down', 503);
        if (url.path.endsWith('/token.get')) {
          return utf8Response(ok({'user_token': 'tok'}));
        }
        if (url.path.endsWith('/track.search')) return utf8Response(searchBody);
        return utf8Response(fixture('musixmatch_richsync_sample.json'));
      });
      final provider = MusixmatchProvider(
        http: LyricsHttp(client: client),
        clock: () => fixedNow,
      );

      expect(
        await provider.getLyrics(
            title: 'Borderline', artist: 'Tame Impala', durationMs: 238000),
        isNotNull,
      );
      for (final r
          in requests.where((r) => r.url.host == 'apic.musixmatch.com')) {
        expectValidSignature(r.url, fallback);
      }
    });

    test('a 401 inside a 200 clears token AND secret and retries once',
        () async {
      var tokenCalls = 0;
      var searchCalls = 0;
      var pageCalls = 0;
      final client = MockClient((request) async {
        final url = request.url;
        if (url.host == 'www.musixmatch.com' && url.path == '/search') {
          pageCalls++;
          return utf8Response(
              '<script src="/_next/static/chunks/pages/_app-1.js">'
              '</script>');
        }
        if (url.path.endsWith('_app-1.js')) {
          return utf8Response('from("$reversedB64".split(""))');
        }
        if (url.path.endsWith('/token.get')) {
          tokenCalls++;
          return utf8Response(ok({'user_token': 'tok-$tokenCalls'}));
        }
        if (url.path.endsWith('/track.search')) {
          searchCalls++;
          // Stale on the first attempt, fine after a refresh.
          return utf8Response(searchCalls == 1 ? unauthorized : searchBody);
        }
        return utf8Response(fixture('musixmatch_richsync_sample.json'));
      });
      final provider = MusixmatchProvider(
        http: LyricsHttp(client: client),
        clock: () => fixedNow,
      );

      final lines = await provider.getLyrics(
          title: 'Borderline', artist: 'Tame Impala', durationMs: 238000);

      expect(lines, isNotNull);
      expect(searchCalls, 2);
      expect(tokenCalls, 2, reason: 'token re-minted');
      expect(pageCalls, 2, reason: 'secret re-scraped');
    });

    test('a persistent 401 retries ONCE and then gives up', () async {
      var searchCalls = 0;
      final client = MockClient((request) async {
        final url = request.url;
        if (url.host == 'www.musixmatch.com') return utf8Response('', 500);
        if (url.path.endsWith('/token.get')) {
          return utf8Response(ok({'user_token': 'tok'}));
        }
        if (url.path.endsWith('/track.search')) {
          searchCalls++;
          return utf8Response(unauthorized);
        }
        return utf8Response('', 404);
      });
      final provider = MusixmatchProvider(
        http: LyricsHttp(client: client),
        clock: () => fixedNow,
      );

      expect(
        await provider.getLyrics(
            title: 'Borderline', artist: 'Tame Impala', durationMs: 238000),
        isNull,
      );
      expect(searchCalls, 2);
    });

    test('with no rich sync it asks for the mxm subtitle and converts it',
        () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final url = request.url;
        if (url.host == 'www.musixmatch.com') return utf8Response('', 500);
        if (url.path.endsWith('/token.get')) {
          return utf8Response(ok({'user_token': 'tok'}));
        }
        if (url.path.endsWith('/track.search')) {
          return utf8Response(ok({
            'track_list': [
              {
                'track': {
                  'track_id': 7,
                  'track_name': 'Borderline',
                  'artist_name': 'Tame Impala',
                  'track_length': 238,
                  'has_subtitles': 1,
                  'has_richsync': 0,
                },
              },
            ],
          }));
        }
        if (url.path.endsWith('/track.subtitle.get')) {
          return utf8Response(ok({
            'subtitle': {
              'subtitle_body': jsonEncode([
                {
                  'text': 'Gone a little far',
                  'time': {'total': 5.25}
                },
                {
                  'text': 'How was I to know',
                  'time': {'total': 15.5}
                },
              ]),
            },
          }));
        }
        return utf8Response('', 404);
      });
      final provider = MusixmatchProvider(
        http: LyricsHttp(client: client),
        clock: () => fixedNow,
      );

      final lines = await provider.getLyrics(
          title: 'Borderline', artist: 'Tame Impala', durationMs: 238000);

      final sung = lines!.where((l) => l.text.isNotEmpty).toList();
      expect(sung.map((l) => l.text).toList(),
          ['Gone a little far', 'How was I to know']);
      expect(sung.map((l) => l.timeMs).toList(), [5250, 15500]);
      expect(requests.any((r) => r.url.path.endsWith('/track.richsync.get')),
          isFalse);
      final sub = requests
          .firstWhere((r) => r.url.path.endsWith('/track.subtitle.get'));
      expect(sub.url.queryParameters['subtitle_format'], 'mxm');
      expect(sub.url.queryParameters['track_id'], '7');
    });

    test('rich sync with no word timing falls through to the subtitle',
        () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final url = request.url;
        if (url.host == 'www.musixmatch.com') return utf8Response('', 500);
        if (url.path.endsWith('/token.get')) {
          return utf8Response(ok({'user_token': 'tok'}));
        }
        if (url.path.endsWith('/track.search')) return utf8Response(searchBody);
        if (url.path.endsWith('/track.richsync.get')) {
          // Lines but no fragments: not word-synced.
          return utf8Response(ok({
            'richsync': {
              'richsync_body': jsonEncode([
                {'ts': 1.0, 'te': 2.0, 'l': [], 'x': 'Plain line'},
              ]),
            },
          }));
        }
        if (url.path.endsWith('/track.subtitle.get')) {
          return utf8Response(ok({
            'subtitle': {
              'subtitle_body': jsonEncode([
                {
                  'text': 'Subtitle line',
                  'time': {'total': 3.0}
                },
              ]),
            },
          }));
        }
        return utf8Response('', 404);
      });
      final provider = MusixmatchProvider(
        http: LyricsHttp(client: client),
        clock: () => fixedNow,
      );

      final lines = await provider.getLyrics(
          title: 'Borderline', artist: 'Tame Impala', durationMs: 238000);

      expect(lines!.map((l) => l.text), contains('Subtitle line'));
    });

    test('token.get answered with a 403 is a quiet miss with no further calls',
        () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.host == 'www.musixmatch.com') {
          return utf8Response('', 500);
        }
        return utf8Response(
          '<html><head><title>403 Forbidden</title></head></html>',
          403,
        );
      });
      final provider = MusixmatchProvider(
        http: LyricsHttp(client: client),
        clock: () => fixedNow,
      );

      expect(
        await provider.getLyrics(
            title: 'Borderline', artist: 'Tame Impala', durationMs: 238000),
        isNull,
      );
      expect(paths.where((p) => p.endsWith('/token.get')), hasLength(1));
      expect(paths.any((p) => p.endsWith('/track.search')), isFalse);
    });
  });
}
