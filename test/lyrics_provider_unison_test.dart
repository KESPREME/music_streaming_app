import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_http.dart';
import 'package:music_streaming_app/services/lyrics/unison_provider.dart';

import 'support/lyrics_fixtures.dart';

/// A Unison answer around a hand-written entry. Only TTML has a captured real
/// answer (Unison's catalogue of those is what the live probe found); the LRC
/// and plain shapes are written to the field list in `Unison.kt`.
String _entry(Map<String, Object?> data) =>
    jsonEncode({'success': true, 'data': data});

UnisonProvider _providerAnswering(http.Response response, [List<Uri>? log]) =>
    UnisonProvider(
      http: LyricsHttp(client: MockClient((request) async {
        log?.add(request.url);
        return response;
      })),
    );

void main() {
  group('UnisonProvider against the captured response', () {
    test('Self Aware: the TTML in data.lyrics is parsed, word timed', () async {
      final requests = <Uri>[];
      final lines = await _providerAnswering(
        okBody(fixture('unison_self_aware.json')),
        requests,
      ).getLyrics(
        title: 'Self Aware',
        artist: 'Temper City',
        durationMs: 180000,
        album: 'Self Aware - Single',
      );

      expect(requests, hasLength(1));
      expect(requests.single.origin, 'https://unison.boidu.dev');
      expect(requests.single.path, '/lyrics');
      expect(requests.single.queryParameters, {
        'song': 'Self Aware',
        'artist': 'Temper City',
        'album': 'Self Aware - Single',
        'duration': '180',
      });

      expect(lines, isNotNull);
      expect(lines, isNotEmpty);
      expect(wordSyncedShare(lines!), greaterThan(0.8));
      expect(isMonotonic(lines), isTrue);
      expect(sung(lines).first.text, isNotEmpty);
    });

    test('the first sung line is the first <p> of the document', () {
      final lines = UnisonProvider.parseBody(fixture('unison_self_aware.json'))!;
      expect(lines.first.text, 'No smoke with no fire');
      expect(lines[1].text, "No silence if there's no sound");
      expect(lines.first.timeMs, lessThan(lines[1].timeMs));
    });

    test('album is left off when absent, duration when unknown', () async {
      final requests = <Uri>[];
      await _providerAnswering(status(404), requests)
          .getLyrics(title: 'T', artist: 'A');
      expect(requests.single.queryParameters, {'song': 'T', 'artist': 'A'});
    });

    test('a 404 (the usual miss) is null', () async {
      expect(
        await _providerAnswering(status(404)).getLyrics(title: 'T', artist: 'A', durationMs: 1000),
        isNull,
      );
    });
  });

  group('UnisonProvider shapes', () {
    List<dynamic>? parse(Map<String, Object?> data) {
      return UnisonProvider.parseBody(_entry(data));
    }

    test('success must be true', () {
      expect(UnisonProvider.parseBody('{"success":false,"data":{"lyrics":"a","format":"lrc"}}'), isNull);
      expect(UnisonProvider.parseBody('{"data":{"lyrics":"[00:01.00]a","format":"lrc"}}'), isNull);
      expect(UnisonProvider.parseBody('{"success":true}'), isNull);
      expect(UnisonProvider.parseBody('{"success":true,"data":{"lyrics":"  "}}'), isNull);
      expect(UnisonProvider.parseBody('nonsense'), isNull);
    });

    test('the old top-level shapes are no longer read', () {
      expect(UnisonProvider.parseBody('{"ttml":"<tt></tt>","lyrics":"x"}'), isNull);
    });

    test('lrc: line-synced text keeps its stamps', () {
      final lines = parse({
        'lyrics': '[00:01.00]First line\n[00:05.50]Second line',
        'format': 'lrc',
        'syncType': 'linesync',
      })!;
      final real = sung(lines.cast());
      expect(real.map((l) => l.text), ['First line', 'Second line']);
      expect(real.map((l) => l.timeMs), [1000, 5500]);
    });

    test('lrc: word stamps are kept', () {
      final lines = parse({
        'lyrics': '[00:01.00]<00:01.00>Hello <00:01.40>there',
        'format': 'lrc',
        'syncType': 'wordsync',
      })!;
      expect(sung(lines.cast()).single.isWordSynced, isTrue);
    });

    test('plain: every line is stamped 0, never stepped', () {
      final lines = parse({
        'lyrics': 'one\n\ntwo\nthree',
        'format': 'lrc',
        'syncType': 'plain',
      })!;
      final real = sung(lines.cast());
      expect(real.map((l) => l.text), ['one', 'two', 'three']);
      expect(real.map((l) => l.timeMs), [0, 0, 0]);
    });

    test('format is read case-insensitively; ttml wins over syncType', () {
      const ttml = '<tt xmlns="http://www.w3.org/ns/ttml"><body><div>'
          '<p begin="1.0" end="2.0">Hello</p></div></body></tt>';
      final lines = parse({'lyrics': ttml, 'format': 'TTML', 'syncType': 'plain'})!;
      expect(lines.single.timeMs, 1000);
    });

    test('an lrc entry with nothing parseable is a miss', () {
      expect(parse({'lyrics': 'no stamps here', 'format': 'lrc', 'syncType': 'linesync'}), isNull);
    });
  });
}
