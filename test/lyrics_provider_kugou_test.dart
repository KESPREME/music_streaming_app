// KuGou: the hash route and the keyword route against REAL captured responses
// for Borderline / Tame Impala (237s). The search fixture holds hits at 205,
// 209, 223, 237 (x2), 239, 248 and 437 seconds, so the duration tolerance is
// exercised by real data rather than invented numbers.
//
// Nothing here touches the network: every request goes to a MockClient.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/lyrics/kugou_provider.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_http.dart';

String fixture(String name) =>
    File('test/fixtures/lyrics/$name').readAsStringSync();

http.Response utf8Response(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

// Real hashes from kugou_search.json.
const String borderline = 'efd3f976dd4ad4884aae03f48d43a8b7'; // 237s
const String radioEdit = 'fa04887f262609797285ea0fa4e0f3e9'; // 237s
const String bloodOrange = '1aca15c855514b2cee4f648763868788'; // 437s
const String bitterPill =
    '31d6098feea5ade597393dc4faddd22b'; // 239s, other song

const String noCandidates = '{"status":200,"candidates":[]}';

void main() {
  final searchBody = fixture('kugou_search.json');
  final realLrc = KuGouProvider.decodeDownload(fixture('kugou_download.json'))!;

  group('song search tolerance (real search response)', () {
    test('keeps only cuts within +-8s, nearest first', () {
      expect(KuGouProvider.hashesWithin(searchBody, 237),
          [borderline, radioEdit, bitterPill]);
    });

    test('the 437s remix and the 205-223s tracks are never accepted', () {
      final hashes = KuGouProvider.hashesWithin(searchBody, 237);
      expect(hashes, isNot(contains(bloodOrange)));
      expect(hashes.length, 3);
    });

    test('the window moves with the track', () {
      // 239 is now the nearest, then the two 237s; a 248s hit is exactly 8s
      // away and still in.
      expect(KuGouProvider.hashesWithin(searchBody, 240), [
        bitterPill,
        borderline,
        radioEdit,
        '19a1611a440e61e837745b793a40a36e'
      ]);
    });

    test('exactly 8s away is in, 9s away is out', () {
      const body = '{"data":{"info":['
          '{"hash":"in","duration":108},{"hash":"out","duration":109}]}}';
      expect(KuGouProvider.hashesWithin(body, 100), ['in']);
    });

    test('NEVER falls back to the first hit when none is close enough', () {
      // 600s matches nothing. The old code took infoList.first anyway.
      expect(KuGouProvider.hashesWithin(searchBody, 600), isEmpty);
      expect(KuGouProvider.hashesWithin(searchBody, 100), isEmpty);
    });

    test('a hit with no duration is out of tolerance, not "close enough"', () {
      const body = '{"data":{"info":[{"hash":"nodur"}]}}';
      expect(KuGouProvider.hashesWithin(body, 237), isEmpty);
    });

    test('with no known duration nothing can be ruled out; order is kept', () {
      expect(KuGouProvider.hashesWithin(searchBody, 0).first, borderline);
      expect(KuGouProvider.hashesWithin(searchBody, 0).length, 8);
    });

    test('garbage is empty, not an exception', () {
      expect(KuGouProvider.hashesWithin('<html>', 237), isEmpty);
      expect(KuGouProvider.hashesWithin('{"data":null}', 237), isEmpty);
    });
  });

  group('keyword', () {
    test('"{title} - {artist}" with brackets removed and the album appended',
        () {
      expect(
        KuGouProvider.keyword(
            'Borderline (Live)', 'Tame Impala (Band)', 'The Slow Rush'),
        'Borderline - Tame Impala The Slow Rush',
      );
      expect(KuGouProvider.keyword('Borderline', 'Tame Impala', null),
          'Borderline - Tame Impala');
      expect(KuGouProvider.keyword('Borderline', 'Tame Impala', '  '),
          'Borderline - Tame Impala');
    });

    test('full-width brackets are removed too', () {
      expect(KuGouProvider.stripParenthetical('晴天（Live）'), '晴天');
      expect(
          KuGouProvider.stripParenthetical('Song (a) tail (b)'), 'Song  tail');
    });

    test('a title that is nothing but a bracket is kept whole', () {
      expect(KuGouProvider.stripParenthetical('(Intro)'), '(Intro)');
    });
  });

  group('credit stripping (real downloaded LRC)', () {
    test('the opening title and credit lines are cut', () {
      final lines = KuGouProvider.stripCredits(realLrc).split('\n');
      expect(lines.first, '[00:05.30]Gone a little far');
      expect(lines.any((l) => l.contains('Lyrics by')), isFalse);
      expect(lines.any((l) => l.contains('Composed by')), isFalse);
      // The "Borderline - Tame Impala" banner sits before the credits.
      expect(lines.any((l) => l.contains('Borderline - Tame Impala')), isFalse);
    });

    test('the sung ending and everything between is kept', () {
      final lines = KuGouProvider.stripCredits(realLrc).split('\n');
      expect(lines.last, '[03:43.86]Comes the sun');
      expect(lines, contains('[00:24.52]We\'re on the borderline'));
    });

    test('only stamped lines survive: [ti:], [ar:] and [offset:] are gone', () {
      final stripped = KuGouProvider.stripCredits(realLrc);
      expect(stripped, isNot(contains('[ti:')));
      expect(stripped, isNot(contains('[offset:')));
      expect(stripped.split('\n').every((l) => l.startsWith('[0')), isTrue);
    });

    String stamp(int seconds) =>
        '[${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}.00]';

    test('a trailing credit line is cut', () {
      // Long enough that the first-30 and last-30 windows do not overlap, as
      // in any real song.
      final lrc = [
        for (var i = 0; i < 70; i++) '${stamp(10 + i * 3)}Sung $i',
        '${stamp(232)}Mastered by:Someone Else',
      ].join('\n');
      final lines = KuGouProvider.stripCredits(lrc).split('\n');
      expect(lines.length, 70);
      expect(lines.first, '${stamp(10)}Sung 0');
      expect(lines.last, '${stamp(10 + 69 * 3)}Sung 69');
    });

    test('the tail scan stops at the credit nearest the end (as KuGou.kt does)',
        () {
      // The head scan runs from the far edge of its window inwards and so
      // takes every credit line; the tail scan runs from the last line inwards
      // and cuts only up to the first credit it meets.
      final lrc = [
        for (var i = 0; i < 70; i++) '${stamp(10 + i * 3)}Sung $i',
        '${stamp(230)}Mixed by:Somebody',
        '${stamp(232)}Mastered by:Someone Else',
      ].join('\n');
      final lines = KuGouProvider.stripCredits(lrc).split('\n');
      expect(lines.last, '${stamp(230)}Mixed by:Somebody');
      expect(lines.length, 71);
    });

    test('only the first and last 30 lines are examined', () {
      final body = [
        for (var i = 0; i < 100; i++)
          '[${(i ~/ 60).toString().padLeft(2, '0')}:${(i % 60).toString().padLeft(2, '0')}.00]'
              '${i == 50 ? 'Hey: you there' : 'Line $i'}',
      ].join('\n');
      final stripped = KuGouProvider.stripCredits(body);
      expect(stripped, contains('Hey: you there'));
      expect(stripped.split('\n').length, 100);
    });

    test('no stamped line at all is an empty lyric', () {
      expect(KuGouProvider.stripCredits('[ti:x]\n[ar:y]\nplain'), '');
      expect(KuGouProvider.stripCredits(''), '');
    });

    test('credits that swallow the whole file leave nothing', () {
      expect(KuGouProvider.stripCredits('[00:01.00]Lyrics by:Someone'), '');
    });
  });

  group('download decoding', () {
    test('Base64 UTF-8 content is decoded, BOM dropped', () {
      final content = base64.encode(utf8.encode('\uFEFF[00:01.00]你好 café'));
      expect(KuGouProvider.decodeDownload('{"content":"$content"}'),
          '[00:01.00]你好 café');
    });

    test('a missing, blank or invalid content is null', () {
      expect(KuGouProvider.decodeDownload('{"content":""}'), isNull);
      expect(KuGouProvider.decodeDownload('{}'), isNull);
      expect(KuGouProvider.decodeDownload('{"content":"%%%not base64%%%"}'),
          isNull);
      expect(KuGouProvider.decodeDownload('<html>'), isNull);
    });

    test('the first lyric candidate is taken', () {
      final candidate =
          KuGouProvider.firstCandidate(fixture('kugou_lyrics_search.json'));
      expect(
          candidate,
          const KuGouCandidate(
              '153010526', '444ABA71FA71D873D1667FCCFF565B0D'));
    });

    test('no candidates, or one without an accesskey, is null', () {
      expect(KuGouProvider.firstCandidate(noCandidates), isNull);
      expect(
          KuGouProvider.firstCandidate('{"candidates":[{"id":"1"}]}'), isNull);
      expect(KuGouProvider.firstCandidate('nope'), isNull);
    });
  });

  group('end to end with a scripted KuGou', () {
    /// Routes the three hosts. [lyricsByHash] maps a hash to its lyric-search
    /// body; unlisted hashes are answered with no candidates.
    MockClient scripted(
      List<http.Request> log, {
      Map<String, String> lyricsByHash = const {},
      String keywordBody = noCandidates,
      String? songSearchBody,
    }) {
      return MockClient((request) async {
        log.add(request);
        final url = request.url;
        if (url.host == 'mobileservice.kugou.com') {
          return utf8Response(songSearchBody ?? searchBody);
        }
        if (url.host == 'lyrics.kugou.com' && url.path == '/search') {
          final hash = url.queryParameters['hash'];
          if (hash != null) {
            return utf8Response(lyricsByHash[hash] ?? noCandidates);
          }
          return utf8Response(keywordBody);
        }
        if (url.host == 'lyrics.kugou.com' && url.path == '/download') {
          return utf8Response(fixture('kugou_download.json'));
        }
        return utf8Response('', 404);
      });
    }

    test('hash route: keyword, nearest hash, download, credits stripped',
        () async {
      final log = <http.Request>[];
      final provider = KuGouProvider(
        http: LyricsHttp(
          client: scripted(log, lyricsByHash: {
            borderline: fixture('kugou_lyrics_search.json'),
          }),
        ),
      );

      final lines = await provider.getLyrics(
        title: 'Borderline (Radio Edit)',
        artist: 'Tame Impala',
        durationMs: 237000,
      );

      expect(lines, isNotNull);
      final sung = lines!.where((l) => l.text.isNotEmpty).toList();
      expect(sung.first.text, 'Gone a little far');
      expect(sung.first.timeMs, 5300);
      expect(sung.last.text, 'Comes the sun');
      expect(sung.any((l) => l.text.contains('Lyrics by')), isFalse);

      final song =
          log.firstWhere((r) => r.url.host == 'mobileservice.kugou.com');
      expect(song.url.queryParameters, {
        'version': '9108',
        'plat': '0',
        'pagesize': '8',
        'showtype': '0',
        'keyword': 'Borderline - Tame Impala',
      });

      final download = log.firstWhere((r) => r.url.path == '/download');
      expect(download.url.queryParameters, {
        'fmt': 'lrc',
        'charset': 'utf8',
        'client': 'pc',
        'ver': '1',
        'id': '153010526',
        'accesskey': '444ABA71FA71D873D1667FCCFF565B0D',
      });
    });

    test('a hash outside +-8s is never asked about', () async {
      final log = <http.Request>[];
      final provider = KuGouProvider(
        http: LyricsHttp(
          client: scripted(log, lyricsByHash: {
            borderline: fixture('kugou_lyrics_search.json'),
          }),
        ),
      );

      await provider.getLyrics(
          title: 'Borderline', artist: 'Tame Impala', durationMs: 237000);

      final asked = log
          .where((r) => r.url.queryParameters.containsKey('hash'))
          .map((r) => r.url.queryParameters['hash'])
          .toSet();
      expect(asked, isNotEmpty);
      expect(asked.difference({borderline, radioEdit, bitterPill}), isEmpty);
      expect(asked, isNot(contains(bloodOrange)));
    });

    test('hashes are tried nearest first: a miss on the first uses the next',
        () async {
      final log = <http.Request>[];
      final provider = KuGouProvider(
        http: LyricsHttp(
          client: scripted(log, lyricsByHash: {
            // The two 237s cuts have no lyric; the 239s one does.
            bitterPill: fixture('kugou_lyrics_search.json'),
          }),
        ),
      );

      final lines = await provider.getLyrics(
          title: 'Borderline', artist: 'Tame Impala', durationMs: 237000);

      expect(lines, isNotNull);
      expect(log.any((r) => r.url.path == '/download'), isTrue);
      // The keyword route was not needed.
      expect(
          log.where((r) =>
              r.url.queryParameters.containsKey('keyword') &&
              r.url.host == 'lyrics.kugou.com'),
          isEmpty);
    });

    test('every hash missing falls back to the keyword with duration in ms',
        () async {
      final log = <http.Request>[];
      final provider = KuGouProvider(
        http: LyricsHttp(
          client:
              scripted(log, keywordBody: fixture('kugou_lyrics_search.json')),
        ),
      );

      final lines = await provider.getLyrics(
        title: 'Borderline',
        artist: 'Tame Impala',
        durationMs: 237000,
        album: 'The Slow Rush',
      );

      expect(lines, isNotNull);
      final fallback = log.lastWhere((r) =>
          r.url.host == 'lyrics.kugou.com' &&
          r.url.path == '/search' &&
          r.url.queryParameters.containsKey('keyword'));
      expect(fallback.url.queryParameters['keyword'],
          'Borderline - Tame Impala The Slow Rush');
      expect(fallback.url.queryParameters['duration'], '237000');
      expect(fallback.url.queryParameters.containsKey('hash'), isFalse);
    });

    test('no hit within tolerance skips the hash route entirely', () async {
      final log = <http.Request>[];
      final provider = KuGouProvider(
        http: LyricsHttp(
          client: scripted(log, lyricsByHash: {
            borderline: fixture('kugou_lyrics_search.json'),
          }),
        ),
      );

      // The track is 5 minutes long: nothing in the search is near that.
      final lines = await provider.getLyrics(
          title: 'Borderline', artist: 'Tame Impala', durationMs: 300000);

      expect(lines, isNull);
      expect(
          log.where((r) => r.url.queryParameters.containsKey('hash')), isEmpty);
      expect(log.where((r) => r.url.path == '/download'), isEmpty);
    });

    test('everything refused is a quiet miss', () async {
      final provider = KuGouProvider(
        http: LyricsHttp(
            client: MockClient((_) async => utf8Response('no', 403))),
      );
      expect(
        await provider.getLyrics(
            title: 'Borderline', artist: 'Tame Impala', durationMs: 237000),
        isNull,
      );
    });
  });
}
