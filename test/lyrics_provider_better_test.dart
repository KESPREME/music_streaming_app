import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/lyrics/better_lyrics_provider.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_http.dart';

import 'support/lyrics_fixtures.dart';

/// A line-timed answer: the downgrade the album parameter sometimes causes.
final String _lineTimed = jsonEncode({
  'ttml': '<tt xmlns="http://www.w3.org/ns/ttml"><body><div>'
      '<p begin="1.000" end="3.000">First line</p>'
      '<p begin="3.500" end="5.000">Second line</p>'
      '</div></body></tt>',
});

class _Host {
  _Host(this.respond);

  /// Answers one request; receives the decoded query.
  final http.Response Function(Uri url) respond;
  final List<Uri> requests = [];

  BetterLyricsProvider get provider => BetterLyricsProvider(
        http: LyricsHttp(client: MockClient((request) async {
          requests.add(request.url);
          return respond(request.url);
        })),
      );
}

void main() {
  group('BetterLyricsProvider.getLyrics against the captured response', () {
    test('Borderline: word timed, and the album is NOT sent when not needed', () async {
      final host = _Host((_) => okBody(fixture('betterlyrics_borderline.json')));
      final lines = await host.provider.getLyrics(
        title: 'Borderline',
        artist: 'Tame Impala',
        durationMs: 237000,
        album: 'The Slow Rush', // sending this made the live host downgrade it
      );

      // One request, and exactly the parameters BitChord sends sans `al`.
      expect(host.requests, hasLength(1));
      expect(host.requests.single.origin, 'https://lyrics-api.boidu.dev');
      expect(host.requests.single.path, '/getLyrics');
      expect(host.requests.single.queryParameters,
          {'s': 'Borderline', 'a': 'Tame Impala', 'd': '237'});

      expect(lines, isNotNull);
      expect(lines, isNotEmpty);
      expect(wordSyncedShare(lines!), greaterThan(0.9));
      expect(isMonotonic(lines), isTrue);
      expect(lines.first.text, 'Gone a little far');
      expect(lines.first.timeMs, 5195);
      expect(lines.first.lyricWords!.map((w) => w.text), ['Gone', 'a', 'little', 'far']);
    });

    test('a line-timed answer gets a second chance with the album', () async {
      // Self Aware's live behaviour: plain query -> Line, with `al` -> Word.
      final host = _Host((url) => url.queryParameters.containsKey('al')
          ? okBody(fixture('betterlyrics_borderline.json'))
          : okBody(_lineTimed));
      final lines = await host.provider.getLyrics(
        title: 'Self Aware',
        artist: 'Temper City',
        durationMs: 180000,
        album: 'Self Aware - Single',
      );

      expect(host.requests, hasLength(2));
      expect(host.requests[0].queryParameters.containsKey('al'), isFalse);
      expect(host.requests[1].queryParameters['al'], 'Self Aware - Single');
      expect(wordSyncedShare(lines!), greaterThan(0.9));
    });

    test('when the album does not help, the plain answer is kept', () async {
      final host = _Host((_) => okBody(_lineTimed));
      final lines = await host.provider.getLyrics(
        title: 'T',
        artist: 'A',
        durationMs: 200000,
        album: 'Album',
      );
      expect(host.requests, hasLength(2));
      expect(lines!.map((l) => l.text), ['First line', 'Second line']);
      expect(lines.any((l) => l.isWordSynced), isFalse);
    });

    test('a line-timed answer with no album to try costs one request', () async {
      final host = _Host((_) => okBody(_lineTimed));
      for (final album in [null, '', '   ']) {
        host.requests.clear();
        final lines = await host.provider.getLyrics(
          title: 'T',
          artist: 'A',
          durationMs: 200000,
          album: album,
        );
        expect(host.requests, hasLength(1), reason: 'album=$album');
        expect(lines, hasLength(2));
      }
    });

    test('a miss on the plain query can still be found with the album', () async {
      final host = _Host((url) => url.queryParameters.containsKey('al')
          ? okBody(_lineTimed)
          : status(404));
      final lines = await host.provider.getLyrics(
        title: 'T',
        artist: 'A',
        durationMs: 200000,
        album: 'Album',
      );
      expect(host.requests, hasLength(2));
      expect(lines, hasLength(2));
    });

    test('an unknown duration sends no d; credits are cleaned from the query', () async {
      final host = _Host((_) => status(404));
      await host.provider.getLyrics(title: 'Dracula (feat. JENNIE)', artist: 'Tame Impala');
      expect(host.requests.single.queryParameters, {'s': 'Dracula', 'a': 'Tame Impala'});
    });

    test('failures are misses, never exceptions', () async {
      for (final response in <http.Response>[
        status(401),
        status(500),
        okBody('<!DOCTYPE html><html><body>Just a moment...</body></html>'),
        okBody('{"isError":true,"ttml":"<tt xmlns=\\"http://www.w3.org/ns/ttml\\"></tt>"}'),
        okBody('{}'),
      ]) {
        final host = _Host((_) => response);
        expect(
          await host.provider.getLyrics(title: 'T', artist: 'A', durationMs: 1000),
          isNull,
        );
      }
    });
  });

  group('BetterLyricsProvider.getPortato (QQ/QRC) against the captured response', () {
    test('uses /qq/getLyrics and never sends the album', () async {
      final host = _Host((_) => okBody(fixture('portato_borderline.json')));
      final lines = await host.provider.getPortato(
        title: 'Borderline',
        artist: 'Tame Impala',
        durationMs: 237000,
        album: 'The Slow Rush', // the live route answers any `al=` with a 401
      );

      expect(BetterLyricsProvider.portatoUrl, 'https://lyrics-api.boidu.dev/qq/getLyrics');
      expect(host.requests.single.path, '/qq/getLyrics');
      expect(host.requests.single.queryParameters,
          {'s': 'Borderline', 'a': 'Tame Impala', 'd': '237'});

      expect(lines, isNotNull);
      expect(wordSyncedShare(lines!), greaterThan(0.9));
      expect(isMonotonic(lines), isTrue);
      expect(lines.first.text, 'Borderline - Tame Impala');
      final gone = lines.firstWhere((l) => l.text == 'Gone a little far');
      expect(gone.timeMs, 5308);
      expect(gone.lyricWords!.map((w) => w.text), ['Gone', 'a', 'little', 'far']);
    });

    test('a 401 is a miss', () async {
      final host = _Host((_) => status(401));
      expect(
        await host.provider.getPortato(title: 'T', artist: 'A', durationMs: 1000),
        isNull,
      );
    });
  });

  group('BetterLyricsProvider.parseTtml stays public and static', () {
    test('parses a one-line document', () {
      final lines = BetterLyricsProvider.parseTtml(
        '<tt xmlns="http://www.w3.org/ns/ttml"><body><div>'
        '<p begin="1.0" end="2.0"><span begin="1.0" end="1.5">Hi</span> '
        '<span begin="1.5" end="2.0">you</span></p></div></body></tt>',
      );
      expect(lines.single.text, 'Hi you');
    });
  });
}
