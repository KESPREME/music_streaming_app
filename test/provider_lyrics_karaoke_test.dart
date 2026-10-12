import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/lyrics/provider_lyrics.dart';

import 'support/lyrics_fixtures.dart';

void main() {
  group('KaraokeLrc on the real Portato (QQ/QRC) response', () {
    late String body;
    setUp(() => body = fixture('portato_borderline.json'));

    test('the JSON envelope is unwrapped and recognised as karaoke', () {
      final inner = ProviderLyrics.unwrap(body)!;
      expect(inner, contains('<QrcInfos>'));
      expect(KaraokeLrc.looksLike(inner), isTrue);
    });

    test('parses to word-timed, monotonic lines', () {
      final lines = ProviderLyrics.parse(body)!;
      expect(lines, isNotEmpty);
      expect(isMonotonic(lines), isTrue);
      expect(wordSyncedShare(lines), greaterThan(0.9));
      // QQ opens with a title card before the first sung line; it is kept, as
      // the reference keeps it.
      expect(lines.first.text, 'Borderline - Tame Impala');
    });

    test('a sung line has its words, spacing and sung-until', () {
      final lines = ProviderLyrics.parse(body)!;
      final line = lines.firstWhere((l) => l.text == 'Gone a little far');
      expect(line.timeMs, 5308);
      // [5308,2497]: the line header's own duration is how long it is sung.
      expect(line.endMs, 5308 + 2497);
      expect(line.lyricWords!.map((w) => w.text), ['Gone', 'a', 'little', 'far']);
      expect(line.lyricWords!.first.startMs, 5308);
      expect(line.lyricWords!.last.startMs, 6270);
      // The flat list is filled too, for consumers that still read it.
      expect(line.words!.length, 4);
    });

    test('a hyphen stamped as its own run does not glue to its neighbours', () {
      final lines = ProviderLyrics.parse(body)!;
      expect(lines.first.lyricWords!.map((w) => w.text),
          ['Borderline', '-', 'Tame', 'Impala']);
    });
  });

  group('KaraokeLrc stamp placement', () {
    test('QRC: the stamp follows its text', () {
      final lines = KaraokeLrc.parse('[1000,900]Gone (1000,300)a (1300,200)lot(1500,400)');
      expect(lines, hasLength(1));
      expect(lines.single.lyricWords!.map((w) => w.text), ['Gone', 'a', 'lot']);
      expect(lines.single.lyricWords!.last.startMs, 1500);
    });

    test('YRC: the stamp precedes its text, and that reading wins', () {
      final lines =
          KaraokeLrc.parse('[1000,900](1000,300,0)Gone (1300,200,0)a (1500,400,0)lot');
      expect(lines, hasLength(1));
      expect(lines.single.lyricWords!.map((w) => w.text), ['Gone', 'a', 'lot']);
      expect(lines.single.lyricWords!.first.startMs, 1000);
      expect(lines.single.text, 'Gone a lot');
    });

    test('syllables of one word glue back together', () {
      final lines = KaraokeLrc.parse('[0,900]e(0,300)nough (300,600)');
      final word = lines.single.lyricWords!.single;
      expect(word.text, 'enough');
      expect(word.syllables, hasLength(2));
    });

    test('a zero line duration leaves the end open', () {
      final lines = KaraokeLrc.parse('[500,0]Hi(500,200)');
      expect(lines.single.endMs, isNull);
    });

    test('entities in the text are decoded', () {
      final lines = KaraokeLrc.parse('[0,500]I&#x27;m (0,250)here&apos;s(250,250)');
      expect(lines.single.text, contains("I'm"));
      expect(lines.single.text, contains("here's"));
    });

    test('lines come back sorted by start time', () {
      final lines = KaraokeLrc.parse('[2000,500]Two(2000,500)\n[1000,500]One(1000,500)');
      expect(lines.map((l) => l.text), ['One', 'Two']);
    });

    test('the QRC XML wrapper is read via its LyricContent attribute', () {
      const wrapped = '<QrcInfos><Lyric_1 LyricContent="[ti:x]\n'
          '[0,500]Hi(0,250) there(250,250)\n"/></QrcInfos>';
      expect(KaraokeLrc.looksLike(wrapped), isTrue);
      expect(KaraokeLrc.parse(wrapped).single.text, 'Hi there');
    });
  });

  group('ProviderLyrics envelopes', () {
    const lrc = '[00:01.00]Hello world\n[00:03.00]Second line';

    test('finds the lyric under any of the content keys', () {
      for (final key in ProviderLyrics.contentKeys) {
        final out = ProviderLyrics.parse(jsonEncode({key: lrc}));
        expect(out, isNotNull, reason: key);
        expect(sung(out!).first.text, 'Hello world', reason: key);
      }
    });

    test('unwraps nested envelopes, and a string that is itself JSON', () {
      expect(
        sung(ProviderLyrics.parse(jsonEncode({'data': {'result': {'lyrics': lrc}}}))!)
            .first
            .text,
        'Hello world',
      );
      expect(
        sung(ProviderLyrics.parse(jsonEncode({'data': jsonEncode({'lrc': lrc})}))!)
            .first
            .text,
        'Hello world',
      );
    });

    test('an envelope that says it is an error is a miss', () {
      expect(ProviderLyrics.parse(jsonEncode({'isError': true, 'lyrics': lrc})), isNull);
      expect(ProviderLyrics.parse(jsonEncode({'ok': false, 'lyrics': lrc})), isNull);
      expect(ProviderLyrics.parse(jsonEncode({'error': 'boom', 'lyrics': lrc})), isNull);
      // ...but the all-clear spellings of "error" are not errors.
      expect(ProviderLyrics.parse(jsonEncode({'error': false, 'lyrics': lrc})), isNotNull);
      expect(ProviderLyrics.parse(jsonEncode({'error': '', 'lyrics': lrc})), isNotNull);
      expect(ProviderLyrics.parse(jsonEncode({'error': null, 'lyrics': lrc})), isNotNull);
    });

    test('a blank value does not shadow a later key', () {
      expect(
        ProviderLyrics.parse(jsonEncode({'ttml': '', 'lyrics': lrc})),
        isNotNull,
      );
    });

    test('a markdown code fence and a BOM are peeled', () {
      expect(ProviderLyrics.parse('\uFEFF```\n$lrc\n```'), isNotNull);
    });

    test('TTML served HTML-escaped is un-escaped and parsed', () {
      const ttml = '<tt xmlns="http://www.w3.org/ns/ttml"><body><div>'
          '<p begin="1.0" end="2.0"><span begin="1.0" end="1.5">Hi</span> '
          '<span begin="1.5" end="2.0">you</span></p></div></body></tt>';
      final escaped = ttml.replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
      final out = ProviderLyrics.parse(jsonEncode({'lyrics': escaped}))!;
      expect(out.single.text, 'Hi you');
      expect(out.single.isWordSynced, isTrue);
    });

    test('the real BetterLyrics TTML envelope parses, word timed', () {
      final out = ProviderLyrics.parse(fixture('betterlyrics_borderline.json'))!;
      expect(out.length, greaterThan(30));
      expect(wordSyncedShare(out), greaterThan(0.9));
    });

    test('enhanced LRC keeps its word stamps', () {
      final out = ProviderLyrics.parse(
        '[00:01.00]<00:01.00>Hello <00:01.50>world\n[00:03.00]<00:03.00>Bye',
      )!;
      expect(sung(out).first.text, 'Hello world');
      expect(sung(out).first.isWordSynced, isTrue);
    });

    test('plain text is stamped 0, minus [tag:value] lines, with no invented steps', () {
      final out = ProviderLyrics.parse('[ar:Someone]\nfirst line\n\nsecond line')!;
      expect(out.map((l) => l.text), ['first line', 'second line']);
      expect(out.map((l) => l.timeMs), [0, 0]);
    });

    test('"lyrics not found" style bodies, and HTML pages, are misses', () {
      expect(ProviderLyrics.parse('Lyrics not found'), isNull);
      expect(ProviderLyrics.parse('Something went wrong: error 5'), isNull);
      expect(ProviderLyrics.parse('<html><body>502 Bad Gateway</body></html>'), isNull);
      expect(ProviderLyrics.parse(''), isNull);
      expect(ProviderLyrics.parse('{"lyrics":null}'), isNull);
      expect(ProviderLyrics.parse('42'), isNull);
    });
  });
}
