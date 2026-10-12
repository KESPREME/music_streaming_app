// PaxSenix: the keyless Apple route against a REAL captured TTML + catalogue
// search, and the keyed routes against hand-written payloads in the documented
// `content[{timestamp,text:[...]}]` shape (the keyed routes need a paid key, so
// no live capture exists for them).
//
// Nothing here touches the network: every request goes to a MockClient.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/lyrics/apple_lyrics_common.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_http.dart';
import 'package:music_streaming_app/services/lyrics/paxsenix_key_store.dart';
import 'package:music_streaming_app/services/lyrics/paxsenix_provider.dart';

String fixture(String name) =>
    File('test/fixtures/lyrics/$name').readAsStringSync();

http.Response utf8Response(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

// A made-up JWT-shaped string. The real token is scraped at runtime and is
// never stored in the repository.
const String tokenA = 'eyJhbGciOiJFUzI1NiJ9.eyJpc3MiOiJmYWtlLWEifQ.c2lnLWE';
const String tokenB = 'eyJhbGciOiJFUzI1NiJ9.eyJpc3MiOiJmYWtlLWIifQ.c2lnLWI';

const AppleLyricsQuery borderline = AppleLyricsQuery(
  title: 'Borderline',
  artist: 'Tame Impala',
  durationMs: 237800,
);

/// A scripted music.apple.com / amp-api / lyrics.paxsenix.org.
class FakeApple {
  FakeApple({this.tokens = const [tokenA]});

  /// Token served on the Nth scrape (last one repeats).
  final List<String> tokens;
  final List<http.Request> requests = [];

  int homeFetches = 0;
  int scriptFetches = 0;

  /// Tokens the catalogue accepts right now.
  Set<String> accepted = {tokenA, tokenB};

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    final url = request.url;
    if (url.host == 'music.apple.com' && url.path == '/us/new') {
      homeFetches++;
      return utf8Response(
        '<html><head><script type="module" crossorigin '
        'src="/assets/index~abc123def.js"></script></head></html>',
      );
    }
    if (url.host == 'music.apple.com' &&
        url.path == '/assets/index~abc123def.js') {
      scriptFetches++;
      final token = tokens[(scriptFetches - 1).clamp(0, tokens.length - 1)];
      return utf8Response('var x="noise";const t="$token";var y=1;');
    }
    if (url.host == 'amp-api.music.apple.com') {
      final auth = request.headers['Authorization'] ?? '';
      if (!accepted.contains(auth.replaceFirst('Bearer ', ''))) {
        return utf8Response('{"errors":[{"status":"401"}]}', 401);
      }
      if (request.headers['Origin'] == null ||
          request.headers['Referer'] == null) {
        return utf8Response('{"errors":[{"status":"401"}]}', 401);
      }
      return utf8Response(fixture('paxsenix_apple_search.json'));
    }
    if (url.host == 'lyrics.paxsenix.org') {
      return utf8Response(fixture('paxsenix_apple_1497230972.json'));
    }
    return utf8Response('not found', 404);
  });
}

void main() {
  group('PaxSenix keyless Apple route (real captured fixtures)', () {
    test('scrapes the token, searches with Origin+Referer, parses the TTML',
        () async {
      final apple = FakeApple();
      final provider = PaxSenixProvider(http: LyricsHttp(client: apple.client));

      final lines = await provider.getLyrics(borderline);

      expect(lines, isNotNull);
      expect(lines!.length, greaterThan(40));

      final search = apple.requests
          .singleWhere((r) => r.url.host == 'amp-api.music.apple.com');
      expect(search.url.path, '/v1/catalog/us/search');
      expect(search.url.queryParameters['term'], 'Borderline Tame Impala');
      expect(search.url.queryParameters['types'], 'songs');
      expect(search.url.queryParameters['limit'], '10');
      expect(search.url.queryParameters['l'], 'en-US');
      expect(search.headers['Authorization'], 'Bearer $tokenA');
      expect(search.headers['Origin'], 'https://music.apple.com');
      expect(search.headers['Referer'], 'https://music.apple.com/');

      final lyric = apple.requests
          .singleWhere((r) => r.url.host == 'lyrics.paxsenix.org');
      expect(lyric.url.path, '/apple-music/lyrics');
      // The first of two identically-scored "Borderline" rows is kept, and the
      // id is the STRING Apple sent.
      expect(lyric.url.queryParameters['id'], '1497230972');
      expect(lyric.url.queryParameters['ttml'], 'true');
      // The lyric proxy is not Apple and must not be handed Apple's token.
      expect(lyric.headers.containsKey('Authorization'), isFalse);

      final first = lines.firstWhere((l) => l.text.trim().isNotEmpty);
      expect(first.text, 'Gone a little far');
      expect(first.isWordSynced, isTrue);
      expect(first.timeMs, inInclusiveRange(5100, 5300));

      // "some" + "thing" carry no space between them in the TTML: one word,
      // two syllables.
      final something = lines
          .expand((l) => l.timedWords)
          .firstWhere((w) => w.text == 'something');
      expect(something.syllables.length, 2);
    });

    test('the token is scraped once and reused', () async {
      final apple = FakeApple();
      final provider = PaxSenixProvider(http: LyricsHttp(client: apple.client));

      expect(await provider.getLyrics(borderline), isNotNull);
      expect(await provider.getLyrics(borderline), isNotNull);

      expect(apple.homeFetches, 1);
      expect(apple.scriptFetches, 1);
    });

    test('concurrent first lookups share one in-flight scrape', () async {
      final apple = FakeApple();
      final provider = PaxSenixProvider(http: LyricsHttp(client: apple.client));

      final results = await Future.wait([
        provider.getLyrics(borderline),
        provider.getLyrics(borderline),
        provider.getLyrics(borderline),
      ]);

      expect(results.every((r) => r != null), isTrue);
      expect(apple.homeFetches, 1);
    });

    test('a cached token that Apple now refuses is dropped and re-scraped',
        () async {
      final apple = FakeApple(tokens: [tokenA, tokenB]);
      final provider = PaxSenixProvider(http: LyricsHttp(client: apple.client));

      expect(await provider.getLyrics(borderline), isNotNull);
      expect(apple.scriptFetches, 1);

      apple.accepted = {tokenB}; // Apple rotated it.
      expect(await provider.getLyrics(borderline), isNotNull);

      expect(apple.scriptFetches, 2);
      final searches = apple.requests
          .where((r) => r.url.host == 'amp-api.music.apple.com')
          .toList();
      expect(searches.map((r) => r.headers['Authorization']).toList(), [
        'Bearer $tokenA',
        'Bearer $tokenA',
        'Bearer $tokenB',
      ]);
    });

    test('a token that was only just scraped and refused is not retried',
        () async {
      final apple = FakeApple()..accepted = {};
      final provider = PaxSenixProvider(http: LyricsHttp(client: apple.client));

      expect(await provider.getLyrics(borderline), isNull);

      expect(apple.scriptFetches, 1);
      expect(
        apple.requests.where((r) => r.url.host == 'amp-api.music.apple.com'),
        hasLength(1),
      );
    });

    test('a caller-supplied Apple id skips the catalogue search entirely',
        () async {
      final apple = FakeApple();
      final provider = PaxSenixProvider(http: LyricsHttp(client: apple.client));

      final lines = await provider.getLyrics(const AppleLyricsQuery(
        title: 'Borderline',
        artist: 'Tame Impala',
        appleId: '1497230972',
      ));

      expect(lines, isNotNull);
      expect(apple.homeFetches, 0);
      expect(
        apple.requests.where((r) => r.url.host == 'amp-api.music.apple.com'),
        isEmpty,
      );
    });
  });

  group('PaxSenix candidate scoring (real Apple search fixture)', () {
    final root = jsonDecode(fixture('paxsenix_apple_search.json'));

    test('song ids are strings and are accepted as such', () {
      final best =
          PaxSenixProvider.bestCandidate(root, 'Borderline', 'Tame Impala', 0);
      expect(best, isNotNull);
      expect(best!.id, isA<String>());
      expect(best.id, '1497230972');
    });

    test('an exact title beats a remix that merely contains it', () {
      final best = PaxSenixProvider.bestCandidate(
          root, 'Borderline', 'Tame Impala', 237800);
      expect(best!.title, 'Borderline');
      expect(best.durationMs, 237800);
    });

    test('duration breaks a tie between same-titled rows', () {
      final doc = {
        'results': {
          'songs': {
            'data': [
              {
                'id': '1',
                'attributes': {
                  'name': 'Song',
                  'artistName': 'Band',
                  'durationInMillis': 300000,
                },
              },
              {
                'id': '2',
                'attributes': {
                  'name': 'Song',
                  'artistName': 'Band',
                  'durationInMillis': 200500,
                },
              },
            ],
          },
        },
      };
      expect(
          PaxSenixProvider.bestCandidate(doc, 'Song', 'Band', 200000)!.id, '2');
    });

    test('nothing scoring at least 10 is not a match', () {
      expect(
        PaxSenixProvider.bestCandidate(
            root, 'Completely Unrelated', 'Nobody', 0),
        isNull,
      );
    });
  });

  group('PaxSenix timed JSON (hand-written, documented shape)', () {
    const timed = '''
{"type":"Syllable","content":[
  {"timestamp":1000,"text":[
    {"text":"Long","timestamp":1000,"endtime":1400,"part":false},
    {"text":"e","timestamp":1400,"endtime":1600,"part":true},
    {"text":"nough","timestamp":1600,"endtime":2200,"part":false}]},
  {"timestamp":"3000","text":[
    {"text":"Next","timestamp":"3000"},
    {"text":"line","timestamp":3500}]}
]}''';

    test('`part` joins a syllable to the next with no space', () {
      final lines = PaxSenixProvider.parseTimedApple(timed)!;

      expect(lines.length, 2);
      expect(lines[0].text, 'Long enough');
      final words = lines[0].lyricWords!;
      expect(words.map((w) => w.text).toList(), ['Long', 'enough']);
      expect(words[1].syllables.length, 2);
      expect(words[1].startMs, 1400);
      expect(words[1].endMs, 2200);
    });

    test('a line is sung until the next line starts', () {
      final lines = PaxSenixProvider.parseTimedApple(timed)!;
      expect(lines[0].endMs, 3000);
    });

    test('a missing endtime falls back: next syllable, then start+800ms', () {
      final lines = PaxSenixProvider.parseTimedApple(timed)!;
      final words = lines[1].lyricWords!;
      expect(lines[1].timeMs, 3000); // numeric string accepted
      expect(words[0].endMs, 3500); // next syllable's timestamp
      expect(words[1].endMs, 4300); // no successor at all: +800ms
      expect(lines[1].endMs, 4300); // last line closes with its last word
    });

    test('a missing endtime on the last syllable takes the next line first',
        () {
      const doc = '''
{"content":[
  {"timestamp":0,"text":[{"text":"One","timestamp":0}]},
  {"timestamp":2500,"text":[{"text":"Two","timestamp":2500}]}]}''';
      final lines = PaxSenixProvider.parseTimedApple(doc)!;
      expect(lines[0].lyricWords!.single.endMs, 2500);
    });

    test('content nested inside a wrapper object is still found', () {
      final wrapped = '{"data":{"result":$timed}}';
      expect(PaxSenixProvider.parseTimedApple(wrapped), isNotNull);
    });

    test('TTML inside a JSON envelope is parsed', () {
      final lines = PaxSenixProvider.parseResponse(
          fixture('paxsenix_apple_1497230972.json'));
      expect(lines, isNotNull);
      expect(lines!.length, greaterThan(40));
    });

    test('an error envelope is a miss, not a lyric', () {
      expect(
          PaxSenixProvider.parseResponse('{"error":"quota exceeded"}'), isNull);
      expect(PaxSenixProvider.parseResponse('not json at all, just a page'),
          isNotNull); // plain text is accepted as unsynced lines
      expect(
          PaxSenixProvider.parseResponse('<html>Bad gateway</html>'), isNull);
    });
  });

  group('PaxSenix keyed routes', () {
    test('a blank key makes ZERO network calls on both routes', () async {
      final calls = <http.Request>[];
      final client = MockClient((request) async {
        calls.add(request);
        return utf8Response('{}');
      });
      final provider = PaxSenixProvider(http: LyricsHttp(client: client));

      for (final blank in ['', '   ', 'Bearer', 'Bearer   ', '\n']) {
        expect(
          await provider.getSpotifyLyrics(
              title: 'Borderline', artist: 'Tame Impala', apiKey: blank),
          isNull,
        );
        expect(
          await provider.getMusixmatchLyrics(
              title: 'Borderline', artist: 'Tame Impala', apiKey: blank),
          isNull,
        );
      }

      expect(calls, isEmpty);
    });

    test('Musixmatch route sends the bearer key and t/a/d, and parses',
        () async {
      final calls = <http.Request>[];
      final client = MockClient((request) async {
        calls.add(request);
        return utf8Response('''
{"content":[
  {"timestamp":1000,"text":[{"text":"Hel","timestamp":1000,"part":true},
                            {"text":"lo","timestamp":1300}]},
  {"timestamp":4000,"text":[{"text":"World","timestamp":4000}]}]}''');
      });
      final provider = PaxSenixProvider(http: LyricsHttp(client: client));

      final lines = await provider.getMusixmatchLyrics(
        title: 'Borderline',
        artist: 'Tame Impala',
        durationMs: 237800,
        apiKey: 'Bearer  secret-key ',
      );

      expect(lines, isNotNull);
      expect(lines!.first.text, 'Hello');
      expect(calls, hasLength(1));
      expect(calls.single.url.host, 'api.paxsenix.org');
      expect(calls.single.url.path, '/lyrics/musixmatch');
      expect(calls.single.url.queryParameters,
          {'t': 'Borderline', 'a': 'Tame Impala', 'd': '237'});
      // "Bearer " pasted from the dashboard is not doubled.
      expect(calls.single.headers['Authorization'], 'Bearer secret-key');
    });

    test('Spotify route searches, then fetches the best id', () async {
      final calls = <http.Request>[];
      final client = MockClient((request) async {
        calls.add(request);
        if (request.url.path == '/spotify/search') {
          return utf8Response('''
{"tracks":{"items":[
  {"id":"sp-wrong","name":"Borderline (Live)","artists":[{"name":"Someone Else"}],"duration_ms":120000},
  {"id":"sp-right","name":"Borderline","artists":[{"name":"Tame Impala"}],"duration_ms":237800}]}}''');
        }
        if (request.url.path == '/lyrics/spotify') {
          return utf8Response(
              '{"content":[{"timestamp":500,"text":[{"text":"Hi","timestamp":500}]}]}');
        }
        return utf8Response('', 404);
      });
      final provider = PaxSenixProvider(http: LyricsHttp(client: client));

      final lines = await provider.getSpotifyLyrics(
        title: 'Borderline',
        artist: 'Tame Impala',
        durationMs: 237800,
        apiKey: 'k',
      );

      expect(lines!.single.text, 'Hi');
      expect(calls.map((c) => c.url.path).toList(),
          ['/spotify/search', '/lyrics/spotify']);
      expect(calls[0].url.queryParameters['q'], 'Borderline Tame Impala');
      expect(calls[1].url.queryParameters['id'], 'sp-right');
      expect(
          calls.every((c) => c.headers['Authorization'] == 'Bearer k'), isTrue);
    });

    test('both fall back to lrcget, choosing ONE recording by metadata',
        () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path == '/lyrics/lrcget') {
          return utf8Response(jsonEncode({
            'lyrics': [
              {
                'trackName': 'Some Other Song',
                'artistName': 'Other Artist',
                'duration': 200,
                'syncedLyrics': '[00:01.00]Wrong one\n[00:05.00]Wrong two',
              },
              {
                'trackName': 'Borderline',
                'artistName': 'Tame Impala',
                'duration': 237,
                'syncedLyrics': '[00:02.00]Right one\n[00:06.00]Right two',
              },
            ],
          }));
        }
        return utf8Response('', 404);
      });
      final provider = PaxSenixProvider(http: LyricsHttp(client: client));

      final spotify = await provider.getSpotifyLyrics(
          title: 'Borderline',
          artist: 'Tame Impala',
          durationMs: 237000,
          apiKey: 'k');
      final musixmatch = await provider.getMusixmatchLyrics(
          title: 'Borderline',
          artist: 'Tame Impala',
          durationMs: 237000,
          apiKey: 'k');

      for (final lines in [spotify, musixmatch]) {
        final texts =
            lines!.map((l) => l.text).where((t) => t.isNotEmpty).toList();
        expect(texts, ['Right one', 'Right two']);
      }
      expect(calls, contains('/lyrics/lrcget'));
    });

    test('parseLrcGet breaks a metadata tie by length, not by list order', () {
      final raw = jsonEncode({
        'lyrics': [
          {
            'trackName': 'Borderline',
            'artistName': 'Tame Impala',
            'syncedLyrics': '[00:01.00]Short\n[01:00.00]Short end',
          },
          {
            'trackName': 'Borderline',
            'artistName': 'Tame Impala',
            'syncedLyrics': '[00:01.00]Full\n[03:55.00]Full end',
          },
        ],
      });
      final lines = PaxSenixProvider.parseLrcGet(
          raw, 'Borderline', 'Tame Impala', 237000)!;
      expect(lines.map((l) => l.text), contains('Full end'));
    });
  });

  group('PaxSenixKeyStore', () {
    test('normalize trims and strips a leading Bearer, any case', () {
      expect(PaxSenixKeyStore.normalize('  abc  '), 'abc');
      expect(PaxSenixKeyStore.normalize('Bearer abc'), 'abc');
      expect(PaxSenixKeyStore.normalize('bearer   abc '), 'abc');
      expect(PaxSenixKeyStore.normalize('BEARER abc'), 'abc');
      expect(PaxSenixKeyStore.normalize('Bearer'), '');
      expect(PaxSenixKeyStore.normalize('   '), '');
      // Not a prefix: a key that merely starts with the letters is untouched.
      expect(PaxSenixKeyStore.normalize('Bearerabc'), 'Bearerabc');
    });

    test('write, read and clear round-trip and drive hasKey', () async {
      final storage = _MemoryStorage();
      final store = PaxSenixKeyStore(storage: storage);
      var notifications = 0;
      store.hasKey.addListener(() => notifications++);

      expect(await store.read(), '');
      expect(store.hasKey.value, isFalse);

      await store.write('Bearer my-key ');
      expect(storage.values[PaxSenixKeyStore.storageKey], 'my-key');
      expect(store.hasKey.value, isTrue);
      expect(await store.read(), 'my-key');

      await store.clear();
      expect(storage.values.containsKey(PaxSenixKeyStore.storageKey), isFalse);
      expect(store.hasKey.value, isFalse);
      expect(notifications, 2);
    });

    test('writing a blank key clears rather than storing an empty string',
        () async {
      final storage = _MemoryStorage();
      final store = PaxSenixKeyStore(storage: storage);
      await store.write('abc');
      await store.write('  ');
      expect(storage.values, isEmpty);
      expect(store.hasKey.value, isFalse);
    });

    test('an unusable keystore reads as no key instead of throwing', () async {
      final store = PaxSenixKeyStore(storage: _ThrowingStorage());
      expect(await store.read(), '');
      await store.write('abc'); // must not throw
      await store.clear();
      expect(store.hasKey.value, isFalse);
    });

    test('the storage key name is the one the settings screen will use', () {
      expect(PaxSenixKeyStore.storageKey, 'paxsenix_api_key');
    });
  });
}

class _MemoryStorage implements PaxSenixSecretStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _ThrowingStorage implements PaxSenixSecretStorage {
  @override
  Future<String?> read(String key) async => throw StateError('keystore');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('keystore');

  @override
  Future<void> delete(String key) async => throw StateError('keystore');
}
