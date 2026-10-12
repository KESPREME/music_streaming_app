import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/lyrics/apple_lyrics_common.dart';
import 'package:music_streaming_app/services/lyrics/lrc_red_provider.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_http.dart';

import 'support/lyrics_fixtures.dart';

/// lrc.red as the captured fixtures describe it, recording what is asked.
class _FakeLrcRed {
  _FakeLrcRed({this.missingDocuments = const {}});

  final Set<String> missingDocuments;
  final List<Uri> requests = [];

  late final MockClient client = MockClient((request) async {
    requests.add(request.url);
    if (request.url.host != 'lrc.red') return status(404);
    final path = request.url.path;
    if (path == '/search.json') {
      final q = request.url.queryParameters['q'] ?? '';
      if (q.contains('Self Aware')) return okBody(fixture('lrcred_search_selfaware.json'));
      if (q.contains('Borderline')) return okBody(fixture('lrcred_search_borderline.json'));
      return okBody('{"hits":[],"next":null}');
    }
    final isrc = RegExp(r'^/s/([A-Z0-9]+)\.ttml$').firstMatch(path)?.group(1);
    if (isrc == null || missingDocuments.contains(isrc)) return status(404);
    if (isrc == 'AUUM71900956') return okBody(fixture('lrcred_AUUM71900956.ttml'));
    if (isrc == 'QZHN52696246') return okBody(fixture('lrcred_QZHN52696246.ttml'));
    return status(404);
  });

  LrcRedProvider get provider => LrcRedProvider(http: LyricsHttp(client: client));
}

LrcRedHit _hit(
  String isrc,
  String title,
  String artist, {
  double? duration = 237.0,
}) =>
    LrcRedHit(isrc: isrc, title: title, artist: artist, duration: duration);

void main() {
  group('LrcRedProvider against the captured lrc.red responses', () {
    test('Borderline: searches by "title artist", then fetches s/{ISRC}.ttml', () async {
      final fake = _FakeLrcRed();
      String? learned;
      final lines = await fake.provider.getLyrics(
        const AppleLyricsQuery(title: 'Borderline', artist: 'Tame Impala', durationMs: 237000),
        onIsrc: (isrc) => learned = isrc,
      );

      // Exactly the two requests BitChord makes, in order.
      expect(fake.requests, hasLength(2));
      expect(fake.requests[0].origin, 'https://lrc.red');
      expect(fake.requests[0].path, '/search.json');
      expect(fake.requests[0].queryParameters, {'q': 'Borderline Tame Impala'});
      expect(fake.requests[1].toString(), 'https://lrc.red/s/AUUM71900956.ttml');
      expect(learned, 'AUUM71900956');

      expect(lines, isNotNull);
      expect(lines, isNotEmpty);
      expect(wordSyncedShare(lines!), greaterThan(0.9));
      expect(isMonotonic(lines), isTrue);
      expect(lines.first.text, 'Gone a little far');
      expect(lines.first.timeMs, 5195);
    });

    test('Self Aware picks the Temper City recording, not the namesakes', () async {
      final fake = _FakeLrcRed();
      String? learned;
      final lines = await fake.provider.getLyrics(
        const AppleLyricsQuery(title: 'Self Aware', artist: 'Temper City', durationMs: 180000),
        onIsrc: (isrc) => learned = isrc,
      );
      expect(learned, 'QZHN52696246');
      expect(fake.requests.last.path, '/s/QZHN52696246.ttml');
      expect(lines, isNotEmpty);
      expect(wordSyncedShare(lines!), greaterThan(0.8));
      expect(isMonotonic(lines), isTrue);
    });

    test('a known ISRC costs one request and no search', () async {
      final fake = _FakeLrcRed();
      var told = false;
      final lines = await fake.provider.getLyrics(
        const AppleLyricsQuery(
          title: 'whatever it is called here',
          artist: 'x',
          isrc: ' auum71900956 ', // trimmed and upper-cased before use
        ),
        onIsrc: (_) => told = true,
      );
      expect(fake.requests.map((u) => u.toString()), ['https://lrc.red/s/AUUM71900956.ttml']);
      expect(lines, isNotEmpty);
      expect(told, isFalse, reason: 'the caller already knew it');
    });

    test('a malformed known ISRC is never put in a path; search is used', () async {
      final fake = _FakeLrcRed();
      final lines = await fake.provider.getLyrics(
        const AppleLyricsQuery(
          title: 'Borderline',
          artist: 'Tame Impala',
          durationMs: 237000,
          isrc: '../../etc/passwd',
        ),
      );
      expect(fake.requests.first.path, '/search.json');
      expect(lines, isNotEmpty);
    });

    test('a known recording lrc.red lacks falls through to search', () async {
      final fake = _FakeLrcRed(missingDocuments: {'AUUM71900573'});
      final lines = await fake.provider.getLyrics(
        const AppleLyricsQuery(
          title: 'Borderline',
          artist: 'Tame Impala',
          durationMs: 237000,
          isrc: 'AUUM71900573', // the "Radio Edit" code: not in the catalogue
        ),
      );
      expect(fake.requests.map((u) => u.path), [
        '/s/AUUM71900573.ttml',
        '/search.json',
        '/s/AUUM71900956.ttml',
      ]);
      expect(lines, isNotEmpty);
    });

    test('a document whose URL equals the known one is not fetched twice', () async {
      final fake = _FakeLrcRed(missingDocuments: {'AUUM71900956'});
      final lines = await fake.provider.getLyrics(
        const AppleLyricsQuery(
          title: 'Borderline',
          artist: 'Tame Impala',
          durationMs: 237000,
          isrc: 'AUUM71900956',
        ),
      );
      expect(lines, isNull);
      expect(
        fake.requests.where((u) => u.path == '/s/AUUM71900956.ttml'),
        hasLength(1),
      );
    });

    test('a supplied DocumentFetcher replaces the download', () async {
      final fake = _FakeLrcRed();
      final fetched = <String>[];
      final lines = await fake.provider.getLyrics(
        const AppleLyricsQuery(title: 'Borderline', artist: 'Tame Impala', durationMs: 237000),
        get: (url) async {
          fetched.add(url);
          return fixture('lrcred_AUUM71900956.ttml');
        },
      );
      expect(fetched, ['https://lrc.red/s/AUUM71900956.ttml']);
      // Only the search went to the client; the document came from [get].
      expect(fake.requests.map((u) => u.path), ['/search.json']);
      expect(lines, isNotEmpty);
    });

    test('ISRC is reported even when the document then fails to download', () async {
      final fake = _FakeLrcRed(missingDocuments: {'AUUM71900956'});
      String? learned;
      final lines = await fake.provider.getLyrics(
        const AppleLyricsQuery(title: 'Borderline', artist: 'Tame Impala', durationMs: 237000),
        onIsrc: (isrc) => learned = isrc,
      );
      expect(lines, isNull);
      expect(learned, 'AUUM71900956');
    });

    test('a search failure, an empty search and junk are all misses', () async {
      for (final response in <http.Response>[
        status(500),
        okBody('{"hits":[],"next":null}'),
        okBody('not json'),
        okBody('{"hits":"nope"}'),
      ]) {
        final provider = LrcRedProvider(
          http: LyricsHttp(client: MockClient((_) async => response)),
        );
        expect(
          await provider.getLyrics(
            const AppleLyricsQuery(title: 'Borderline', artist: 'Tame Impala'),
          ),
          isNull,
        );
      }
    });

    test('parseSearch reads the real answer shape', () {
      final hits = LrcRedProvider.parseSearch(fixture('lrcred_search_borderline.json'));
      expect(hits, hasLength(7));
      expect(hits.first.isrc, 'AUUM71900956');
      expect(hits.first.title, 'Borderline');
      expect(hits.first.duration, closeTo(237.8, 1e-9));
      expect(hits.first.year, 2019);
    });
  });

  group('LrcRedProvider.best', () {
    const wantedMs = 237000;

    test('the real Borderline search settles on the studio recording', () {
      final hits = LrcRedProvider.parseSearch(fixture('lrcred_search_borderline.json'));
      final best = LrcRedProvider.best(hits, 'Borderline', 'Tame Impala', wantedMs);
      expect(best?.isrc, 'AUUM71900956');
    });

    test('a live cut is not the studio recording, and vice versa', () {
      final studio = _hit('USAAA1234567', 'Song', 'Band');
      final live = _hit('USAAA7654321', 'Song (Live)', 'Band');
      expect(LrcRedProvider.best([live], 'Song', 'Band', wantedMs), isNull);
      expect(LrcRedProvider.best([studio], 'Song (Live)', 'Band', wantedMs), isNull);
      // Both present: each side gets its own.
      expect(LrcRedProvider.best([live, studio], 'Song', 'Band', wantedMs), same(studio));
      expect(LrcRedProvider.best([studio, live], 'Song (Live)', 'Band', wantedMs), same(live));
    });

    test('version words are found in a " - " suffix too, labels are ignored', () {
      final remix = _hit('USAAA1234567', 'Song - Club Remix', 'Band');
      expect(LrcRedProvider.best([remix], 'Song', 'Band', wantedMs), isNull);
      // "Remastered" and an album credit name no different recording.
      final remaster = _hit('USAAA1234567', 'Song - 2011 Remaster', 'Band');
      expect(LrcRedProvider.best([remaster], 'Song', 'Band', wantedMs), same(remaster));
      final film = _hit('USAAA1234567', "Song (From 'Some Film')", 'Band');
      expect(LrcRedProvider.best([film], 'Song', 'Band', wantedMs), same(film));
    });

    test('a hit more than 3 seconds away is rejected; exactly 3 is not', () {
      expect(LrcRedProvider.best([_hit('USAAA1234567', 'Song', 'Band', duration: 240.5)],
          'Song', 'Band', wantedMs), isNull);
      expect(LrcRedProvider.best([_hit('USAAA1234567', 'Song', 'Band', duration: 233.5)],
          'Song', 'Band', wantedMs), isNull);
      expect(LrcRedProvider.best([_hit('USAAA1234567', 'Song', 'Band', duration: 240.0)],
          'Song', 'Band', wantedMs), isNotNull);
    });

    test('an unknown duration cannot veto, on either side', () {
      final far = _hit('USAAA1234567', 'Song', 'Band', duration: 999);
      expect(LrcRedProvider.best([far], 'Song', 'Band', null), same(far));
      expect(LrcRedProvider.best([far], 'Song', 'Band', 0), same(far));
      final unknown = _hit('USAAA1234567', 'Song', 'Band', duration: null);
      expect(LrcRedProvider.best([unknown], 'Song', 'Band', wantedMs), same(unknown));
    });

    test('at least one shared artist is required', () {
      final other = _hit('USAAA1234567', 'Song', 'Somebody Else');
      expect(LrcRedProvider.best([other], 'Song', 'Band', wantedMs), isNull);
      final shared = _hit('USAAA1234567', 'Song', 'Other Guy & Band');
      expect(LrcRedProvider.best([shared], 'Song', 'Band', wantedMs), same(shared));
      final featuring = _hit('USAAA1234567', 'Song', 'Band feat. Other Guy');
      expect(LrcRedProvider.best([featuring], 'Song', 'Band', wantedMs), same(featuring));
      // No wanted artist at all: nothing to disagree with.
      expect(LrcRedProvider.best([other], 'Song', '', wantedMs), same(other));
    });

    test('accents and punctuation do not make a title or artist differ', () {
      final hit = _hit('USAAA1234567', 'Beyoncé: Halo!', 'ROSÉ');
      expect(LrcRedProvider.best([hit], 'beyonce halo', 'Rose', wantedMs), same(hit));
    });

    test('a hit without a well-formed ISRC is never chosen', () {
      for (final bad in ['', 'short', 'US-AAA-12-34567', 'USAAA12345678', null]) {
        final hit = LrcRedHit(isrc: bad, title: 'Song', artist: 'Band', duration: 237);
        expect(LrcRedProvider.best([hit], 'Song', 'Band', wantedMs), isNull, reason: '$bad');
      }
      // Lower case is tolerated: it is normalised the way the reference does.
      final lower = _hit('usaaa1234567', 'Song', 'Band');
      expect(LrcRedProvider.best([lower], 'Song', 'Band', wantedMs), same(lower));
    });

    test('closest length wins; a tie keeps the search order', () {
      final a = _hit('USAAA0000001', 'Song', 'Band', duration: 238.5);
      final b = _hit('USAAA0000002', 'Song', 'Band', duration: 237.2);
      final c = _hit('USAAA0000003', 'Song', 'Band', duration: 236.8); // same distance as b
      expect(LrcRedProvider.best([a, b, c], 'Song', 'Band', wantedMs), same(b));
      expect(LrcRedProvider.best([c, b, a], 'Song', 'Band', wantedMs), same(c));
    });
  });

  group('AppleLyricsSource', () {
    test('durationMatches: unknown cannot veto, 3 seconds is the line', () {
      expect(AppleLyricsSource.durationMatches(200, null), isTrue);
      expect(AppleLyricsSource.durationMatches(200, 0), isTrue);
      expect(AppleLyricsSource.durationMatches(null, 200), isTrue);
      expect(AppleLyricsSource.durationMatches(203, 200), isTrue);
      expect(AppleLyricsSource.durationMatches(204, 200), isFalse);
      expect(AppleLyricsSource.durationMatches(196, 200), isFalse);
    });

    test('parseTtmlDocument strips a BOM/preamble and rejects non-TTML', () {
      final source = LrcRedProvider(http: LyricsHttp(client: MockClient((_) async => status(404))));
      final doc = fixture('lrcred_AUUM71900956.ttml');
      expect(source.parseTtmlDocument('\uFEFF<?xml version="1.0"?>\n<!-- c -->$doc'), isNotEmpty);
      expect(source.parseTtmlDocument('<html>nope</html>'), isNull);
      expect(source.parseTtmlDocument('   '), isNull);
    });

    test('fetchTtml survives a throwing DocumentFetcher', () async {
      final source = LrcRedProvider(http: LyricsHttp(client: MockClient((_) async => status(404))));
      expect(await source.fetchTtml('https://x', get: (_) async => throw StateError('boom')), isNull);
    });
  });

  group('LrcRedProvider ISRC helpers', () {
    test('documentUrl validates', () {
      expect(LrcRedProvider.documentUrl('AUUM71900956'), 'https://lrc.red/s/AUUM71900956.ttml');
      expect(LrcRedProvider.documentUrl(' auum71900956\n'), 'https://lrc.red/s/AUUM71900956.ttml');
      expect(LrcRedProvider.documentUrl('AUUM7190095'), isNull);
      expect(LrcRedProvider.documentUrl(null), isNull);
    });
  });
}
