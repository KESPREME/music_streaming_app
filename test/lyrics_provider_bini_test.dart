import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/lyrics/apple_lyrics_common.dart';
import 'package:music_streaming_app/services/lyrics/bini_lyrics_provider.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_http.dart';

import 'support/lyrics_fixtures.dart';

/// The Bini search host plus the lrc.red document host it points at.
class _FakeBini {
  _FakeBini({this.searchStatus = 200, String? searchBody})
      : searchBody = searchBody ?? fixture('bini_borderline.json');

  final int searchStatus;
  final String searchBody;
  final List<Uri> requests = [];

  late final MockClient client = MockClient((request) async {
    requests.add(request.url);
    if (request.url.host == 'lyrics-api.binimum.org') {
      return searchStatus == 200 ? okBody(searchBody) : status(searchStatus);
    }
    if (request.url.toString() == 'https://lrc.red/s/AUUM71900956.ttml') {
      return okBody(fixture('lrcred_AUUM71900956.ttml'));
    }
    return status(404);
  });

  BiniLyricsProvider get provider =>
      BiniLyricsProvider(http: LyricsHttp(client: client));
}

void main() {
  group('BiniLyricsProvider.identify sends what BitChord sends', () {
    test('by name: track, artist and duration in whole seconds', () async {
      final fake = _FakeBini();
      final hit = await fake.provider.identify(
        const AppleLyricsQuery(title: 'Borderline', artist: 'Tame Impala', durationMs: 237000),
      );

      expect(fake.requests, hasLength(1));
      final url = fake.requests.single;
      expect(url.origin, 'https://lyrics-api.binimum.org');
      expect(url.path, '/');
      expect(url.queryParameters,
          {'track': 'Borderline', 'artist': 'Tame Impala', 'duration': '237'});

      expect(hit, isNotNull);
      expect(hit!.isrc, 'AUUM71900956');
      expect(hit.lyricsUrl, 'https://lrc.red/s/AUUM71900956.ttml');
      expect(hit.timingType, 'word');
    });

    test('album is sent when present and not blank, duration only if > 0', () async {
      final fake = _FakeBini();
      await fake.provider.identify(
        const AppleLyricsQuery(title: 'T', artist: 'A', album: 'The Slow Rush', durationMs: 237000),
      );
      expect(fake.requests.last.queryParameters['album'], 'The Slow Rush');

      await fake.provider.identify(const AppleLyricsQuery(title: 'T', artist: 'A', album: '  '));
      expect(fake.requests.last.queryParameters, {'track': 'T', 'artist': 'A'});

      await fake.provider.identify(const AppleLyricsQuery(title: 'T', artist: 'A', durationMs: 0));
      expect(fake.requests.last.queryParameters.containsKey('duration'), isFalse);
    });

    test('WITH an ISRC only isrc= is sent', () async {
      final fake = _FakeBini();
      await fake.provider.identify(
        const AppleLyricsQuery(
          title: 'Borderline',
          artist: 'Tame Impala',
          album: 'The Slow Rush',
          durationMs: 237000,
          isrc: 'AUUM71900956',
        ),
      );
      expect(fake.requests.single.queryParameters, {'isrc': 'AUUM71900956'});
    });

    test('a 404 is a miss', () async {
      final fake = _FakeBini(searchStatus: 404);
      expect(
        await fake.provider.identify(const AppleLyricsQuery(title: 'Nope', artist: 'Nobody')),
        isNull,
      );
    });

    test('unreadable, empty and URL-less answers are misses', () async {
      for (final body in [
        'not json',
        '[]',
        '{"results":[]}',
        '{"results":["x"]}',
        '{"results":[{"isrc":"AUUM71900956"}]}', // nothing to fetch
        '{"lyricsUrl":"https://lrc.red/s/AUUM71900956.ttml"}', // the OLD shape
      ]) {
        final fake = _FakeBini(searchBody: body);
        expect(
          await fake.provider.identify(const AppleLyricsQuery(title: 'T', artist: 'A')),
          isNull,
          reason: body,
        );
      }
    });

    test('takes results.first, as the reference does', () {
      final hit = BiniLyricsProvider.parseHit(fixture('bini_borderline.json'))!;
      // The second result is the Radio Edit; it is not preferred.
      expect(hit.isrc, 'AUUM71900956');
    });
  });

  group('BiniLyricsProvider lyrics', () {
    test('getLyrics: identify, then fetch and parse the document', () async {
      final fake = _FakeBini();
      String? learned;
      final lines = await fake.provider.getLyrics(
        const AppleLyricsQuery(title: 'Borderline', artist: 'Tame Impala', durationMs: 237000),
        onIsrc: (isrc) => learned = isrc,
      );

      expect(fake.requests.map((u) => u.host), ['lyrics-api.binimum.org', 'lrc.red']);
      expect(learned, 'AUUM71900956');
      expect(lines, isNotEmpty);
      expect(wordSyncedShare(lines!), greaterThan(0.9));
      expect(isMonotonic(lines), isTrue);
      expect(lines.first.text, 'Gone a little far');
    });

    test('a hit passed in skips the search and is not re-announced', () async {
      final fake = _FakeBini();
      var told = false;
      final lines = await fake.provider.getLyrics(
        const AppleLyricsQuery(title: 'ignored', artist: 'ignored'),
        hit: const BiniHit(
          isrc: 'AUUM71900956',
          lyricsUrl: 'https://lrc.red/s/AUUM71900956.ttml',
        ),
        onIsrc: (_) => told = true,
      );
      expect(fake.requests.map((u) => u.host), ['lrc.red']);
      expect(told, isFalse);
      expect(lines, isNotEmpty);
    });

    test('a supplied DocumentFetcher shares the download', () async {
      final fake = _FakeBini();
      final provider = fake.provider;
      final hit = await provider.identify(
        const AppleLyricsQuery(title: 'Borderline', artist: 'Tame Impala', durationMs: 237000),
      );
      final fetched = <String>[];
      final lines = await provider.lyricsForHit(hit!, get: (url) async {
        fetched.add(url);
        return fixture('lrcred_AUUM71900956.ttml');
      });
      expect(fetched, ['https://lrc.red/s/AUUM71900956.ttml']);
      expect(fake.requests.where((u) => u.host == 'lrc.red'), isEmpty);
      expect(lines, isNotEmpty);
    });

    test('a hit with no URL, or a document that will not download, is a miss', () async {
      final fake = _FakeBini();
      expect(
        await fake.provider.lyricsForHit(const BiniHit(isrc: 'X', lyricsUrl: '  ')),
        isNull,
      );
      expect(
        await fake.provider.lyricsForHit(
          const BiniHit(isrc: 'X', lyricsUrl: 'https://lrc.red/s/USAAA0000000.ttml'),
        ),
        isNull,
      );
    });
  });
}
