import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_http.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_plus_provider.dart';

import 'support/lyrics_fixtures.dart';

const _prjktla = 'https://lyricsplus.prjktla.my.id';
const _atomix = 'https://lyricsplus.atomix.one';
const _binimum = 'https://lyricsplus.binimum.org';
const _workers = 'https://lyricsplus.prjktla.workers.dev';
const _vercelA = 'https://lyricsplus-seven.vercel.app';
const _vercelB = 'https://lyrics-plus-backend.vercel.app';

typedef _Behaviour = Future<http.Response> Function(Uri url);

/// Six mirrors, each with its own behaviour, recording who was asked and when.
class _Mirrors {
  _Mirrors(this.behaviours);

  final Map<String, _Behaviour> behaviours;
  final List<Uri> requests = [];

  List<String> get hostsAsked => [for (final u in requests) u.origin];

  LyricsPlusProvider get provider => LyricsPlusProvider(
        http: LyricsHttp(client: MockClient((request) async {
          requests.add(request.url);
          final behaviour = behaviours[request.url.origin];
          if (behaviour == null) return status(404);
          return behaviour(request.url);
        })),
      );
}

_Behaviour _answers(String body, {int delayMs = 0}) => (_) async {
      if (delayMs > 0) await Future<void>.delayed(Duration(milliseconds: delayMs));
      return okBody(body);
    };

_Behaviour _fails({int delayMs = 0}) => (_) async {
      if (delayMs > 0) await Future<void>.delayed(Duration(milliseconds: delayMs));
      throw http.ClientException('SSL connection could not be established');
    };

_Behaviour _statusCode(int code, {int delayMs = 0}) => (_) async {
      if (delayMs > 0) await Future<void>.delayed(Duration(milliseconds: delayMs));
      return status(code);
    };

/// Mirror state as probed on 2026-10-12.
Map<String, _Behaviour> _liveStatus({
  _Behaviour? prjktla,
  _Behaviour? binimum,
}) =>
    {
      _prjktla: prjktla ?? _answers(fixture('lyricsplus_borderline.json')),
      _atomix: _fails(),
      _binimum: binimum ?? _answers(fixture('lyricsplus_binimum_borderline.json')),
      _workers: _statusCode(404),
      _vercelA: _statusCode(402),
      _vercelB: _statusCode(402),
    };

void main() {
  setUp(() => LyricsPlusProvider.lastGood = null);
  tearDown(() => LyricsPlusProvider.lastGood = null);

  group('LyricsPlusProvider against the captured response', () {
    test('Borderline: syllable timed, monotonic, first lines as served', () async {
      final mirrors = _Mirrors(_liveStatus());
      final lines = await mirrors.provider.getLyrics(
        title: 'Borderline',
        artist: 'Tame Impala',
        durationMs: 237000,
      );

      expect(lines, isNotNull);
      expect(lines, isNotEmpty);
      expect(wordSyncedShare(lines!), greaterThan(0.9));
      expect(isMonotonic(lines), isTrue);
      // The service's first line is the songwriter credit; the sung lyric
      // follows it, with its trailing-space word boundaries honoured.
      expect(lines.first.text, 'Kevin Parker');
      expect(lines.first.timeMs, 2768);
      final gone = lines.firstWhere((l) => l.text == 'Gone a little far');
      expect(gone.timeMs, 5308);
      expect(gone.lyricWords!.map((w) => w.text), ['Gone', 'a', 'little', 'far']);
    });

    test('every mirror is asked, with the reference parameters', () async {
      final mirrors = _Mirrors(_liveStatus());
      await mirrors.provider.getLyrics(
        title: 'Borderline',
        artist: 'Tame Impala',
        durationMs: 237000,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mirrors.hostsAsked.toSet(),
          {_prjktla, _atomix, _binimum, _workers, _vercelA, _vercelB});
      for (final url in mirrors.requests) {
        expect(url.path, '/v2/lyrics/get');
        expect(url.queryParameters,
            {'title': 'Borderline', 'artist': 'Tame Impala', 'duration': '237'});
      }
    });

    test('album and isrc are sent alongside the name when given', () async {
      final mirrors = _Mirrors(_liveStatus());
      await mirrors.provider.getLyrics(
        title: 'Borderline',
        artist: 'Tame Impala',
        durationMs: 237000,
        album: 'The Slow Rush',
        isrc: 'AUUM71900956',
      );
      expect(mirrors.requests.first.queryParameters, {
        'title': 'Borderline',
        'artist': 'Tame Impala',
        'duration': '237',
        'album': 'The Slow Rush',
        'isrc': 'AUUM71900956',
      });
      // ...and left off when blank or unknown.
      mirrors.requests.clear();
      await mirrors.provider.getLyrics(title: 'T', artist: 'A', album: ' ', isrc: '');
      expect(mirrors.requests.first.queryParameters, {'title': 'T', 'artist': 'A'});
    });
  });

  group('LyricsPlusProvider races its mirrors', () {
    test('the first NON-EMPTY answer wins without waiting for the slow ones', () async {
      final mirrors = _Mirrors({
        _prjktla: _answers(fixture('lyricsplus_borderline.json'), delayMs: 500), // slow
        _atomix: _fails(delayMs: 500), // slow failure
        _binimum: _answers(fixture('lyricsplus_binimum_borderline.json'), delayMs: 20),
        _workers: _statusCode(404),
        _vercelA: _statusCode(402, delayMs: 500),
        _vercelB: _statusCode(402),
      });

      final watch = Stopwatch()..start();
      final lines = await mirrors.provider.getLyrics(
        title: 'Borderline',
        artist: 'Tame Impala',
        durationMs: 237000,
      );
      watch.stop();

      expect(lines, isNotEmpty);
      expect(watch.elapsedMilliseconds, lessThan(300),
          reason: 'one fast mirror answered; nobody should wait out the 500ms ones');
      expect(LyricsPlusProvider.lastGood, _binimum);

      // The slow mirror that answers later must not steal the preference.
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(LyricsPlusProvider.lastGood, _binimum);
    });

    test('a fast answer with no lyrics does not win the race', () async {
      final mirrors = _Mirrors({
        _prjktla: _answers('{"type":"Line","lyrics":[]}'),
        _atomix: _answers('{"error":"track not found"}'),
        _binimum: _answers(fixture('lyricsplus_binimum_borderline.json'), delayMs: 80),
      });
      final lines = await mirrors.provider.getLyrics(title: 'T', artist: 'A');
      expect(lines, isNotEmpty);
      expect(LyricsPlusProvider.lastGood, _binimum);
    });

    test('the winning host is asked first next time', () async {
      final mirrors = _Mirrors(_liveStatus(
        prjktla: _statusCode(404),
        binimum: _answers(fixture('lyricsplus_binimum_borderline.json')),
      ));
      await mirrors.provider.getLyrics(title: 'Borderline', artist: 'Tame Impala');
      expect(LyricsPlusProvider.lastGood, _binimum);

      // First round asked in list order; this one must lead with the winner.
      mirrors.requests.clear();
      await mirrors.provider.getLyrics(title: 'Borderline', artist: 'Tame Impala');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(mirrors.hostsAsked.first, _binimum);
      expect(mirrors.hostsAsked, hasLength(6), reason: 'the rest are still raced');
    });

    test('nobody answering is a miss, not a hang, and keeps the old preference', () async {
      LyricsPlusProvider.lastGood = _binimum;
      final mirrors = _Mirrors({
        _prjktla: _statusCode(500),
        _atomix: _fails(),
        _binimum: _answers('{"lyrics":[]}'),
        _workers: _statusCode(404),
        _vercelA: _statusCode(402),
        _vercelB: _statusCode(402),
      });
      expect(await mirrors.provider.getLyrics(title: 'T', artist: 'A'), isNull);
      expect(LyricsPlusProvider.lastGood, _binimum);
    });

    test('late failures after the winner never surface as unhandled errors', () async {
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        final mirrors = _Mirrors({
          _prjktla: _answers(fixture('lyricsplus_borderline.json')),
          _atomix: _fails(delayMs: 80),
          _binimum: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 80));
            throw StateError('late and broken');
          },
          _workers: _statusCode(500, delayMs: 80),
          _vercelA: _answers('not json', delayMs: 80),
          _vercelB: _answers('{"lyrics":"wrong type"}', delayMs: 80),
        });
        final lines = await mirrors.provider.getLyrics(title: 'Borderline', artist: 'Tame Impala');
        expect(lines, isNotEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }, (error, stack) => uncaught.add(error));
      expect(uncaught, isEmpty);
    });
  });

  group('LyricsPlusProvider.parse', () {
    String body(List<Map<String, Object?>> lines) => jsonEncode({'type': 'Word', 'lyrics': lines});

    test('a trailing space ends a word; syllables without one glue together', () {
      final lines = LyricsPlusProvider.parseBody(body([
        {
          'time': 1000,
          'duration': 900,
          'text': 'enough already',
          'syllabus': [
            {'time': 1000, 'duration': 300, 'text': 'e'},
            {'time': 1300, 'duration': 300, 'text': 'nough '},
            {'time': 1600, 'duration': 300, 'text': 'already'},
          ],
        },
      ]))!;
      expect(lines.single.lyricWords!.map((w) => w.text), ['enough', 'already']);
      expect(lines.single.lyricWords!.first.syllables, hasLength(2));
      expect(lines.single.text, 'enough already');
    });

    test('line-only entries get an end time of time + duration', () {
      final lines = LyricsPlusProvider.parseBody(body([
        {'time': 4000, 'duration': 2500, 'text': ' Second '},
        {'time': 1000, 'duration': 0, 'text': 'First'},
        {'time': 8000, 'text': ''},
        {'text': 'no time'},
      ]))!;
      expect(lines.map((l) => l.text), ['First', 'Second']);
      expect(lines[0].endMs, isNull, reason: 'a zero duration is no end at all');
      expect(lines[1].endMs, 6500);
      expect(lines.any((l) => l.isWordSynced), isFalse);
    });

    test('envelope errors and the wrong shape are misses', () {
      expect(LyricsPlusProvider.parseBody('[]'), isNull);
      expect(LyricsPlusProvider.parseBody('{"lyrics":[]}'), isNull);
      expect(LyricsPlusProvider.parseBody('{"error":"nope","lyrics":[{"time":1,"text":"a"}]}'), isNull);
      expect(LyricsPlusProvider.parseBody('{"isError":true}'), isNull);
    });

    test('the mirror list is complete and in order', () {
      expect(LyricsPlusProvider.mirrors, [
        _prjktla,
        _atomix,
        _binimum,
        _workers,
        _vercelA,
        _vercelB,
      ]);
    });
  });
}
