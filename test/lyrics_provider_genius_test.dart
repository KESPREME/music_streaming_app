// Genius: search selection and page extraction against a REAL captured search
// response and a trimmed REAL song page (see test/fixtures/lyrics/genius_song.html
// - header, three lyric containers and the ad slot between them are verbatim;
// only the verses after the first Post-Chorus lines, the page chrome outside the
// lyrics root, and SVG path data were removed).
//
// Nothing here touches the network: every request goes to a MockClient.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/lyrics/genius_provider.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_http.dart';

String fixture(String name) =>
    File('test/fixtures/lyrics/$name').readAsStringSync();

http.Response utf8Response(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

const String songUrl = 'https://genius.com/Tame-impala-borderline-lyrics';

void main() {
  group('search selection (real captured search response)', () {
    final search = fixture('genius_search.json');

    test('picks the song itself, not a translation or another version', () {
      expect(GeniusProvider.bestMatchUrl(search, 'Borderline', 'Tame Impala'),
          songUrl);
    });

    test('a title-only query could not tell the hits apart; artist decides',
        () {
      // "Borderline (Single Version)" also contains the title, but the exact
      // title and artist outrank it.
      final url =
          GeniusProvider.bestMatchUrl(search, 'Borderline', 'Tame Impala');
      expect(url, isNot(contains('single-version')));
      expect(url, isNot(contains('turkce')));
    });

    test('an unrelated query matches nothing rather than the first hit', () {
      expect(
        GeniusProvider.bestMatchUrl(search, 'Zzzz Qqqq', 'Nobody At All'),
        isNull,
      );
    });

    test('garbage is a miss, not an exception', () {
      expect(GeniusProvider.bestMatchUrl('<html>403</html>', 'a', 'b'), isNull);
      expect(GeniusProvider.bestMatchUrl('{"response":{}}', 'a', 'b'), isNull);
    });

    test('a translation page is penalised unless one was asked for', () {
      const body = '''
{"response":{"sections":[{"type":"song","hits":[
  {"result":{"title":"Song","artist_names":"Band","url":"https://genius.com/translated","path":"/Genius-translations-band-song-english-translation-lyrics"}},
  {"result":{"title":"Song (Remix)","artist_names":"Band","url":"https://genius.com/remix","path":"/Band-song-remix-lyrics"}}
]}]}}''';
      // The translation scores 90-30=60; the remix 25+40=65.
      expect(GeniusProvider.bestMatchUrl(body, 'Song', 'Band'),
          'https://genius.com/remix');
    });
  });

  group('page extraction (real song page)', () {
    final html = fixture('genius_song.html');
    final lines = GeniusProvider.parseHtml(html)!;
    final texts = lines.map((l) => l.text).toList();

    test('keeps every verse of every container, in order', () {
      expect(texts, [
        '[Verse 1]',
        'Gone a little far',
        'Gone a little far this time with something',
        'How was I to know?',
        'How was I to know this high came rushing?',
        '[Chorus]',
        'We\'re on the borderline',
        'Dangerously fine and unforgiving',
        'Possibly a sign',
        'I\'m gonna have the strangest night on Sunday',
        '[Verse 2]',
        'Here I go',
        'Quite a show for a loner in L.A.',
        'I wonder how I managed to end up in this place',
        'Where I couldn\'t get away',
        '[Verse 3]',
        'Gone a little far',
        'Gone a little far this time with something',
        'Rudi said it\'s fine',
        'They used to do this all the time in college (If you and I get comfortable)',
        '[Chorus]',
        'And we\'re on the borderline (Ooh)',
        'Caught between the tides of pain and rapture',
        'Then I saw the time',
        'Watched it speedin\' by like a train',
        '[Post-Chorus]',
        'Will I be known and loved?',
        'Is there one that I trust?',
        'Starting to sober up',
      ]);
    });

    test('verse 1 and verse 2 survive the nested-div header (the old bug)', () {
      // The first container opens with a header of nested divs. A regex that
      // stops at the first </div> ends inside it and loses everything below.
      expect(texts, contains('[Verse 1]'));
      expect(texts, contains('How was I to know this high came rushing?'));
      expect(texts, contains('[Verse 2]'));
      expect(texts, contains('Where I couldn\'t get away'));
    });

    test('the excluded header and its contributors/translation chrome are gone',
        () {
      final all = texts.join('\n');
      expect(all, isNot(contains('Contributors')));
      expect(all, isNot(contains('Translations')));
      expect(all, isNot(contains('Read More')));
      expect(all, isNot(contains('Borderline Lyrics')));
      expect(all, isNot(contains('reworked')));
      expect(all, isNot(contains('Embed')));
      expect(all, isNot(contains('<')));
    });

    test('<br> is a line break and entities are decoded', () {
      expect(texts, contains('We\'re on the borderline'));
      expect(
          texts.any((t) => t.contains('&#x27;') || t.contains('&')), isFalse);
    });

    test('text inside annotation links is kept', () {
      expect(texts, contains('Will I be known and loved?'));
    });

    test('Genius\'s odd Unicode spaces become ordinary ones', () {
      // The real page writes U+2005 between words and U+200B at line ends.
      expect(texts, contains('How was I to know this high came rushing?'));
      expect(texts.join(), isNot(contains('\u2005')));
      expect(texts.join(), isNot(contains('\u200B')));
    });

    test('lines are plain: timeMs 0, no end, no invented step', () {
      expect(lines.every((l) => l.timeMs == 0), isTrue);
      expect(lines.every((l) => l.endMs == null), isTrue);
      expect(lines.every((l) => !l.isWordSynced), isTrue);
    });

    test('section headers are kept and recognised', () {
      final headers = texts.where(isGeniusSectionHeader).toList();
      expect(headers, [
        '[Verse 1]',
        '[Chorus]',
        '[Verse 2]',
        '[Verse 3]',
        '[Chorus]',
        '[Post-Chorus]',
      ]);
    });
  });

  group('extraction edge cases', () {
    List<String>? run(String html) =>
        GeniusProvider.parseHtml(html)?.map((l) => l.text).toList();

    test('deeply nested divs inside a container do not end it early', () {
      expect(
        run('<div data-lyrics-container="true">'
            'one<br/><div><div>two</div></div><br/>three'
            '</div><div>not lyrics</div>'),
        ['one', 'two', 'three'],
      );
    });

    test('closing tags inside comments, scripts and attributes are ignored',
        () {
      expect(
        run('<div data-lyrics-container="true">'
            'a<!-- </div> --><br/>'
            '<script>var s = "</div>";</script>b<br/>'
            '<span title="</div>">c</span></div>'),
        ['a', 'b', 'c'],
      );
    });

    test('unclosed inline tags and stray end tags do not swallow the lyric',
        () {
      expect(
        run('<div data-lyrics-container="true">'
            '<span>one<br/></b>two<br/><i>three</div>trailing'),
        ['one', 'two', 'three'],
      );
    });

    test('data-exclude-from-selection and button blocks are dropped, wherever',
        () {
      expect(
        run('<div data-lyrics-container="true">'
            '<div data-exclude-from-selection="true"><div>ad<div>x</div></div></div>'
            'keep<br/><button>Share</button>this</div>'),
        ['keep', 'this'],
      );
    });

    test('<p> blocks start on their own line', () {
      expect(
        run('<div data-lyrics-container="true"><p>one<br/>two</p><p>three</p></div>'),
        ['one', 'two', 'three'],
      );
    });

    test('an older page with div.lyrics is read', () {
      expect(
        run('<div class="lyrics foo"><p>old<br/>page</p></div>'),
        ['old', 'page'],
      );
    });

    test('a page with no lyric container is a miss', () {
      expect(run('<html><body><div>nothing here</div></body></html>'), isNull);
      expect(run(''), isNull);
    });

    test('numeric and named entities are decoded', () {
      expect(
        run('<div data-lyrics-container="true">caf&eacute; &amp; cr&#232;me '
            '&#x2019;&nbsp;ok</div>'),
        ['café & crème ’ ok'],
      );
    });

    test('stripArtifacts removes recommendation inserts and the glued Embed',
        () {
      expect(
        GeniusProvider.stripArtifacts(
            'line one\u00A0two\n12You might also like\n'
            'last line123Embed'),
        'line one two\n\nlast line',
      );
    });

    test('a lyric that merely ends in the word "embed" is not truncated', () {
      final lines =
          GeniusProvider.textToEntries('We will embed\n42Embed\nEmbed');
      expect(lines.map((l) => l.text).toList(), ['We will embed']);
    });

    test('isGeniusSectionHeader enforces the 3..60 bracket rule', () {
      expect(isGeniusSectionHeader('[Chorus]'), isTrue);
      expect(isGeniusSectionHeader('  [Verse 1]  '), isTrue);
      expect(isGeniusSectionHeader('[]'), isFalse);
      expect(isGeniusSectionHeader('[x'), isFalse);
      expect(isGeniusSectionHeader('Chorus]'), isFalse);
      expect(isGeniusSectionHeader('[${'a' * 59}]'), isFalse); // 61 chars
      expect(isGeniusSectionHeader('[${'a' * 58}]'), isTrue); // 60 chars
    });
  });

  group('query building', () {
    test('the first search is "{artist} {title}"', () {
      final attempts =
          GeniusProvider.searchAttempts('Borderline', 'Tame Impala');
      expect(attempts.first.query, 'Tame Impala Borderline');
      expect(attempts.first.title, 'Borderline');
      expect(attempts.first.artist, 'Tame Impala');
    });

    test('"Artist - Title" uploads are split, and attempts do not repeat', () {
      final attempts = GeniusProvider.searchAttempts(
          'Tame Impala - Borderline (Official Video)', 'Tame Impala');
      expect(attempts.first.query, 'Tame Impala Borderline');
      expect(attempts.map((a) => a.query).toSet().length, attempts.length);
    });

    test('credits and packaging do not reach the query', () {
      final attempts = GeniusProvider.searchAttempts(
          'Dracula (feat. JENNIE) [Official Audio]', 'Tame Impala');
      expect(attempts.first.query, 'Tame Impala Dracula');
    });
  });

  group('end to end with a scripted Genius', () {
    test('searches "{artist} {title}", fetches the matched page, parses it',
        () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/search/multi') {
          return utf8Response(fixture('genius_search.json'));
        }
        if (request.url.toString() == songUrl) {
          return utf8Response(fixture('genius_song.html'));
        }
        return utf8Response('', 404);
      });
      final provider = GeniusProvider(http: LyricsHttp(client: client));

      final lines =
          await provider.getLyrics(title: 'Borderline', artist: 'Tame Impala');

      expect(lines, isNotNull);
      expect(lines!.map((l) => l.text), contains('Where I couldn\'t get away'));
      expect(requests, hasLength(2));
      expect(requests[0].url.queryParameters['q'], 'Tame Impala Borderline');
      expect(requests[1].url.toString(), songUrl);
    });

    test('identifies as the app, never as a browser', () async {
      final agents = <String>[];
      final client = MockClient((request) async {
        agents.add(request.headers['User-Agent'] ?? '');
        // Genius's CDN answers a browser-shaped agent with a bot challenge.
        if ((request.headers['User-Agent'] ?? '').contains('Mozilla')) {
          return utf8Response('<html>Just a moment...</html>', 403);
        }
        if (request.url.path == '/api/search/multi') {
          return utf8Response(fixture('genius_search.json'));
        }
        return utf8Response(fixture('genius_song.html'));
      });
      final provider = GeniusProvider(http: LyricsHttp(client: client));

      final lines =
          await provider.getLyrics(title: 'Borderline', artist: 'Tame Impala');

      expect(lines, isNotNull);
      expect(agents, isNotEmpty);
      expect(agents.every((a) => a == LyricsHttp.agent), isTrue);
      expect(agents.any((a) => a.contains('Mozilla') || a.contains('Chrome')),
          isFalse);
    });

    test('falls through to the next search when the first finds no song',
        () async {
      final queries = <String>[];
      final client = MockClient((request) async {
        if (request.url.path == '/api/search/multi') {
          queries.add(request.url.queryParameters['q']!);
          return queries.length == 1
              ? utf8Response('{"response":{"sections":[]}}')
              : utf8Response(fixture('genius_search.json'));
        }
        return utf8Response(fixture('genius_song.html'));
      });
      final provider = GeniusProvider(http: LyricsHttp(client: client));

      final lines = await provider.getLyrics(
          title: 'Borderline (Official Video)', artist: 'Tame Impala');

      expect(lines, isNotNull);
      expect(queries.length, 2);
      expect(queries.first, 'Tame Impala Borderline');
    });

    test('a 403 or an unmatched search is a miss', () async {
      final blocked = GeniusProvider(
        http: LyricsHttp(
            client: MockClient((_) async => utf8Response('blocked', 403))),
      );
      expect(
        await blocked.getLyrics(title: 'Borderline', artist: 'Tame Impala'),
        isNull,
      );

      final empty = GeniusProvider(
        http: LyricsHttp(
            client: MockClient(
                (_) async => utf8Response('{"response":{"sections":[]}}'))),
      );
      expect(
        await empty.getLyrics(title: 'Borderline', artist: 'Tame Impala'),
        isNull,
      );
    });
  });
}
