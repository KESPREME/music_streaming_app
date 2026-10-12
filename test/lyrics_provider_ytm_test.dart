// YouTube Music Lyrics tab: the `next` -> `browse` flow against REAL captured
// WEB_REMIX responses for videoId R-hYM3BqTbA (responseContext, which carries an
// anonymous visitor id, was blanked in both fixtures).
//
// Nothing here touches the network: every request goes to a MockClient.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/lyrics/youtube_music_provider.dart';

String fixture(String name) =>
    File('test/fixtures/lyrics/$name').readAsStringSync();

http.Response utf8Response(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

Map<String, dynamic> nextWithTabs(List<Map<String, dynamic>> tabs) => {
      'contents': {
        'singleColumnMusicWatchNextResultsRenderer': {
          'tabbedRenderer': {
            'watchNextTabbedResultsRenderer': {
              'tabs': [
                for (final t in tabs) {'tabRenderer': t},
              ],
            },
          },
        },
      },
    };

Map<String, dynamic> lyricsTab(Object title, String browseId,
        {String? params}) =>
    {
      'title': title,
      'endpoint': {
        'browseEndpoint': {
          'browseId': browseId,
          if (params != null) 'params': params,
        },
      },
    };

Map<String, dynamic> shelf(Object description) => {
      'contents': [
        {
          'musicDescriptionShelfRenderer': {'description': description},
        },
      ],
    };

void main() {
  group('Lyrics tab endpoint (real next response)', () {
    final next = jsonDecode(fixture('ytm_next.json'));

    test('is found by its title, with the per-video browse id', () {
      final endpoint = YouTubeMusicLyricsProvider.findLyricsEndpoint(next);
      expect(endpoint, isNotNull);
      // The old code hardcoded the bare prefix "MPLYt_".
      expect(endpoint!.browseId, 'MPLYt_fNSBQgOdyME-1');
      expect(endpoint.browseId.length, greaterThan('MPLYt_'.length));
      expect(endpoint.params, isNull);
    });

    test('the Related tab is not mistaken for it', () {
      final endpoint = YouTubeMusicLyricsProvider.findLyricsEndpoint(next);
      expect(endpoint!.browseId, startsWith('MPLYt_'));
      expect(endpoint.browseId, isNot(startsWith('MPTRt_')));
    });
  });

  group('Lyrics tab endpoint (shapes)', () {
    test('title as runs or simpleText, and params are carried', () {
      final viaRuns = nextWithTabs([
        {'title': 'Up next'},
        lyricsTab({
          'runs': [
            {'text': 'Lyrics'},
          ],
        }, 'MPLYt_abc', params: 'P1'),
      ]);
      final endpoint = YouTubeMusicLyricsProvider.findLyricsEndpoint(viaRuns)!;
      expect(endpoint.browseId, 'MPLYt_abc');
      expect(endpoint.params, 'P1');

      final viaSimple = nextWithTabs([
        lyricsTab({'simpleText': 'LYRICS'}, 'MPLYt_def'),
      ]);
      expect(YouTubeMusicLyricsProvider.findLyricsEndpoint(viaSimple)!.browseId,
          'MPLYt_def');
    });

    test('a localised title is still found by the page type it points at', () {
      final localised = nextWithTabs([
        {'title': 'A seguir'},
        lyricsTab('Letra', 'MPLYt_es'),
        lyricsTab('Relacionado', 'MPTRt_es'),
      ]);
      expect(YouTubeMusicLyricsProvider.findLyricsEndpoint(localised)!.browseId,
          'MPLYt_es');
    });

    test('with no Lyrics tab there is no endpoint - no positional guess', () {
      final none = nextWithTabs([
        {'title': 'Up next'},
        lyricsTab('Related', 'MPTRt_xyz'),
      ]);
      expect(YouTubeMusicLyricsProvider.findLyricsEndpoint(none), isNull);
      expect(YouTubeMusicLyricsProvider.findLyricsEndpoint(<String, dynamic>{}),
          isNull);
      expect(YouTubeMusicLyricsProvider.findLyricsEndpoint(null), isNull);
    });
  });

  group('description shelf (real browse response)', () {
    final page = jsonDecode(fixture('ytm_browse_lyrics.json'));
    final lines = YouTubeMusicLyricsProvider.linesFromBrowse(page)!;
    final texts = lines.map((l) => l.text).toList();

    test('reads runs[].text, which the old simpleText-only parse missed', () {
      expect(lines.length, greaterThan(20));
      expect(texts, contains('I wish that I could lie'));
      expect(texts, contains('Always way too self-aware'));
    });

    test('CRLF breaks become lines, with no blanks or stray CRs', () {
      expect(texts.first, 'Oh');
      expect(texts.every((t) => t.isNotEmpty), isTrue);
      expect(texts.any((t) => t.contains('\r') || t.contains('\n')), isFalse);
    });

    test('plain lines: timeMs 0 and no end', () {
      expect(lines.every((l) => l.timeMs == 0 && l.endMs == null), isTrue);
      expect(lines.every((l) => !l.isWordSynced), isTrue);
    });
  });

  group('description shelf (shapes)', () {
    List<String>? run(Object page) =>
        YouTubeMusicLyricsProvider.linesFromBrowse(page)
            ?.map((l) => l.text)
            .toList();

    test('runs are joined with nothing between them', () {
      expect(
        run(shelf({
          'runs': [
            {'text': 'Hello '},
            {'text': 'world\nSecond'},
          ],
        })),
        ['Hello world', 'Second'],
      );
    });

    test('simpleText is read too', () {
      expect(run(shelf({'simpleText': 'One\n\nTwo'})), ['One', 'Two']);
    });

    test('no shelf or an empty one is a miss', () {
      expect(run({'contents': []}), isNull);
      expect(run(shelf({'runs': []})), isNull);
      expect(run(shelf({'simpleText': '  \n '})), isNull);
    });
  });

  group('end to end with a scripted YouTube Music', () {
    test('POSTs next as WEB_REMIX, then browses the tab it named', () async {
      final calls = <http.Request>[];
      final client = MockClient((request) async {
        calls.add(request);
        if (request.url.path.endsWith('/next')) {
          return utf8Response(fixture('ytm_next.json'));
        }
        if (request.url.path.endsWith('/browse')) {
          return utf8Response(fixture('ytm_browse_lyrics.json'));
        }
        return utf8Response('', 404);
      });
      final provider = YouTubeMusicLyricsProvider(client: client);

      final lines = await provider.getLyrics(videoId: 'R-hYM3BqTbA');

      expect(lines, isNotNull);
      expect(lines!.first.text, 'Oh');
      expect(calls, hasLength(2));

      final next = calls[0];
      expect(next.method, 'POST');
      expect(next.url.host, 'music.youtube.com');
      expect(next.url.path, '/youtubei/v1/next');
      final nextBody = jsonDecode(next.body) as Map<String, dynamic>;
      expect(nextBody['videoId'], 'R-hYM3BqTbA');
      expect(nextBody['context']['client']['clientName'], 'WEB_REMIX');
      expect(nextBody['context']['client']['clientVersion'], isNotEmpty);
      expect(next.headers['Origin'], 'https://music.youtube.com');
      expect(next.headers['Referer'], 'https://music.youtube.com/');
      expect(next.headers['X-YouTube-Client-Name'], '67');
      expect(next.headers['Content-Type'], contains('application/json'));
      // No login material: this must work for a signed-out listener.
      expect(next.headers.containsKey('Cookie'), isFalse);
      expect(next.headers.containsKey('Authorization'), isFalse);

      final browse = calls[1];
      expect(browse.url.path, '/youtubei/v1/browse');
      final browseBody = jsonDecode(browse.body) as Map<String, dynamic>;
      expect(browseBody['browseId'], 'MPLYt_fNSBQgOdyME-1');
      expect(browseBody.containsKey('params'), isFalse);
      expect(browseBody['context']['client']['clientName'], 'WEB_REMIX');
    });

    test('params from the tab are sent on the browse', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        if (request.url.path.endsWith('/next')) {
          return utf8Response(jsonEncode(nextWithTabs([
            lyricsTab('Lyrics', 'MPLYt_p', params: 'ABC=='),
          ])));
        }
        return utf8Response(jsonEncode(shelf({'simpleText': 'Line'})));
      });
      final provider = YouTubeMusicLyricsProvider(client: client);

      expect(await provider.getLyrics(videoId: 'R-hYM3BqTbA'), isNotNull);
      expect(bodies.last['params'], 'ABC==');
      expect(bodies.last['browseId'], 'MPLYt_p');
    });

    test('a video with no Lyrics tab stops after one call', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return utf8Response(jsonEncode(nextWithTabs([
          {'title': 'Up next'},
          lyricsTab('Related', 'MPTRt_x'),
        ])));
      });
      final provider = YouTubeMusicLyricsProvider(client: client);

      expect(await provider.getLyrics(videoId: 'R-hYM3BqTbA'), isNull);
      expect(calls, 1);
    });

    test('anything that is not an 11-character id makes no call at all',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return utf8Response('{}');
      });
      final provider = YouTubeMusicLyricsProvider(client: client);

      for (final bad in [
        null,
        '',
        'short',
        'way-too-long-for-an-id',
        'bad id!!!!!'
      ]) {
        expect(await provider.getLyrics(videoId: bad), isNull);
      }
      expect(calls, 0);
    });

    test('a 429, or a body that is not JSON, is a quiet miss', () async {
      final rateLimited = YouTubeMusicLyricsProvider(
        client: MockClient((_) async => utf8Response('slow down', 429)),
      );
      expect(await rateLimited.getLyrics(videoId: 'R-hYM3BqTbA'), isNull);

      final html = YouTubeMusicLyricsProvider(
        client: MockClient((_) async => utf8Response('<html></html>')),
      );
      expect(await html.getLyrics(videoId: 'R-hYM3BqTbA'), isNull);
    });
  });
}
