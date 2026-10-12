// Nothing here touches the network: every request goes to a MockClient, and the
// responses are REAL captures (test/fixtures/lyrics/translate_*, inputtools_*)
// so the parser is tested against what the endpoint actually sends - sentence
// segments, a marker as a segment of its own, native digits inside a marker -
// rather than against what someone remembered it sending.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_translation_service.dart';

import 'support/lyrics_fixtures.dart';

const String _start = '\uE000';
const String _end = '\uE001';

/// The marker before line [n] (the first line has none).
String marker(int n) => '$_start${n.toString().padLeft(4, '0')}$_end';

// The sources the captured fixtures were made from.
const List<String> japanese = ['ねこが 好き', 'これは テスト です'];
const List<String> hindiUnchanged = [
  'tera hone laga hoon',
  'main tujhse pyar karta hoon',
];
const List<String> hindiFour = [
  'dil mera tujhe dhoondhta hai',
  'raat bhar tere khayal aate hain',
  'main tujhse pyar karta hoon',
  'tu hi meri zindagi hai',
];

/// A scripted Google: records every request and answers with [onTranslate] and
/// [onInputTools].
class Endpoint {
  Endpoint({this.onTranslate, this.onInputTools, this.latency = Duration.zero});

  final http.Response Function(Map<String, String> fields)? onTranslate;
  final http.Response Function(Map<String, String> fields)? onInputTools;
  final Duration latency;

  final List<http.Request> requests = [];
  final List<Map<String, String>> translate = [];
  final List<Map<String, String>> inputTools = [];
  int _inFlight = 0;
  int maxInFlight = 0;

  late final MockClient client = MockClient((request) async {
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      if (latency > Duration.zero) await Future<void>.delayed(latency);
      requests.add(request);
      final fields = request.bodyFields;
      if (request.url.host == 'translate.googleapis.com') {
        translate.add(fields);
        return (onTranslate ?? (_) => status(500))(fields);
      }
      if (request.url.host == 'inputtools.google.com') {
        inputTools.add(fields);
        return (onInputTools ?? (_) => status(500))(fields);
      }
      return status(404);
    } finally {
      _inFlight--;
    }
  });
}

LyricsTranslationService service(
  Endpoint endpoint, {
  Directory? cache,
}) =>
    LyricsTranslationService(
      client: endpoint.client,
      // Memory only unless a test gives it a directory: the default asks the
      // platform, and a unit test has no platform.
      cacheDirectory: () async => cache,
    );

/// A response shaped like the real one, for a body the test computes.
///
/// Sentence-sized segments with the newline kept on the end, the markers coming
/// back as segments of their own - the shape the captured fixtures have.
http.Response reply(
  String text, {
  String detected = 'ja',
  bool romanized = false,
}) {
  final pieces = text.split('\n');
  final segments = <Object?>[
    for (var i = 0; i < pieces.length; i++)
      () {
        final piece = i < pieces.length - 1 ? '${pieces[i]}\n' : pieces[i];
        return romanized
            ? <Object?>[null, null, null, piece]
            : <Object?>[piece, piece, null, null, 3];
      }(),
  ];
  return okBody(jsonEncode([segments, null, detected]));
}

final RegExp _markerLine = RegExp('^\uE000[^\uE001]*\uE001\$');

/// Applies [change] to every line of [payload] except the markers, which the
/// real endpoint hands back untouched.
String mapPayload(String payload, String Function(String line) change) => payload
    .split('\n')
    .map((line) => _markerLine.hasMatch(line) ? line : change(line))
    .join('\n');

Future<LyricsTransformResult> run(
  LyricsTranslationService svc,
  List<String> lines, {
  LyricsTransform kind = LyricsTransform.translate,
  String target = 'en',
  String track = 'track-1',
  LyricsCancelToken? cancel,
}) =>
    svc.transform(
      trackId: track,
      lines: lines,
      kind: kind,
      targetLanguage: target,
      cancel: cancel,
    );

LyricsTransformReady ready(LyricsTransformResult result) {
  expect(result, isA<LyricsTransformReady>(), reason: 'got $result');
  return result as LyricsTransformReady;
}

void main() {
  late LyricsTranslationService plain;
  setUp(() => plain = service(Endpoint()));

  group('batching', () {
    test('short lyrics go in one batch', () {
      final batches = plain.batchesForTest(['one', 'two', 'three']);
      expect(batches.length, 1);
      expect(batches.first, ['one', 'two', 'three']);
    });

    test('a long lyric is split under the character cap', () {
      final lines = List.generate(400, (i) => 'x' * 40);
      final batches = plain.batchesForTest(lines);
      expect(batches.length, greaterThan(1));
      // Every line present exactly once, in order, across all batches.
      expect(batches.expand((b) => b).toList(), lines);
    });

    test('the cap holds for the payload actually sent, markers included', () {
      // Counting the text alone lets a batch of short lines run 8 characters a
      // line past the cap, which is how a "3500 character" batch became 4500.
      final lines = List.generate(400, (i) => 'x' * 40);
      for (final payload in plain.payloadsForTest(lines)) {
        expect(payload.length, lessThanOrEqualTo(
          LyricsTranslationService.maxBatchChars,
        ));
      }
    });

    test('the boundary is exact: 3500 stays together, 3501 splits', () {
      // 1000 + 8 (newline, marker, newline) + 2492 = 3500.
      final fits = ['a' * 1000, 'b' * 2492];
      expect(plain.payloadsForTest(fits).single.length, 3500);
      final spills = ['a' * 1000, 'b' * 2493];
      expect(plain.batchesForTest(spills).length, 2);
    });

    test('a single line over the cap is sent alone rather than split', () {
      // One over-long line is a bad request; a lyric broken mid-sentence is
      // worse, because the halves read as two separate thoughts.
      final huge = 'y' * (LyricsTranslationService.maxBatchChars * 2);
      final batches = plain.batchesForTest(['short', huge]);
      expect(batches.length, 2);
      expect(batches[1], [huge]);
    });

    test('no line is lost when the split lands mid-lyric', () {
      final lines = List.generate(37, (i) => 'line number $i ${'z' * 200}');
      final batches = plain.batchesForTest(lines);
      expect(batches.length, greaterThan(1));
      expect(batches.expand((b) => b).toList(), lines);
    });

    test('lines are joined by numbered markers, the first having none', () {
      final payload = plain.payloadsForTest(['one', 'two', 'three']).single;
      expect(
        payload,
        'one\n${marker(1)}\ntwo\n${marker(2)}\nthree',
        reason: '\\n U+E000 NNNN U+E001 \\n, counting from 0001 before line two',
      );
    });

    test('the marker counter restarts in each batch', () {
      // It indexes the line within ITS batch, so a lost marker is attributable.
      final lines = ['a' * 3000, 'b' * 600, 'c' * 600];
      final payloads = plain.payloadsForTest(lines);
      expect(payloads.length, 2);
      expect(payloads[0], 'a' * 3000);
      expect(payloads[1], '${'b' * 600}\n${marker(1)}\n${'c' * 600}');
    });

    test('blank lines are not sent, and section headers lose their brackets',
        () {
      final payload =
          plain.payloadsForTest(['[Chorus]', '', 'hello', '  ', 'world']).single;
      expect(payload, 'Chorus\n${marker(1)}\nhello\n${marker(2)}\nworld');
    });
  });

  group('reply parsing', () {
    // The captured shapes: segments are SENTENCES, and each marker is a segment
    // of its own, so a four-line lyric comes back as seven segments.
    test('a real response is split on its markers, not on its segments', () {
      final body = fixture('translate_hindi_latin_pass1.json');
      final answer = LyricsTranslationService.parseBatchReply(
        body,
        kind: LyricsTransform.translate,
        expectedSlots: 4,
        weight: 120,
      );
      expect(answer, isNotNull);
      expect(answer!.texts, [
        'my heart searches for you',
        'I am thinking of you at night.',
        'I love you most of the time',
        'you are my life',
      ]);
      expect(answer.sourceLanguage, 'hi', reason: 'read from root[2]');
      expect(answer.weight, 120);
    });

    test('the old one-segment-per-line reading fails on a real response', () {
      // The regression this group exists for: counting segments (7) against
      // lines (4) refused every real response, so every batch "failed".
      final decoded = jsonDecode(fixture('translate_hindi_latin_pass1.json'))
          as List<dynamic>;
      expect((decoded.first as List).length, 7);
    });

    test('native digits inside a marker still split', () {
      // Input Tools rewrites 0001 as ०००१; only the wrapper survives.
      final answer = LyricsTranslationService.parseBatchReply(
        fixture('translate_hindi_native_retry.json'),
        kind: LyricsTransform.translate,
        expectedSlots: 4,
      );
      expect(answer?.texts, [
        'my heart searches for you',
        'I think about you all night long',
        'i love you',
        'you are my life',
      ]);
    });

    test('reads a translation from root[0][*][0] and the language from root[2]',
        () {
      final answer = LyricsTranslationService.parseBatchReply(
        fixture('translate_japanese_to_english.json'),
        kind: LyricsTransform.translate,
        expectedSlots: 2,
      )!;
      expect(answer.texts, ['I like cats', 'this is a test']);
      expect(answer.sourceLanguage, 'ja');
    });

    test('a lost marker is refused: two lines merged is not a translation', () {
      // Handing back one part for two lines would put each line's text on its
      // neighbour, silently, with nothing left to detect it by.
      final body = fixture('translate_japanese_to_english.json')
          .replaceAll('${marker(1)}\\n', '');
      expect(
        LyricsTranslationService.parseBatchReply(
          body,
          kind: LyricsTransform.translate,
          expectedSlots: 2,
        ),
        isNull,
      );
    });

    test('a short reply is refused, not padded with the last line', () {
      final reply = '[[["only one"]]]';
      expect(LyricsTranslationService.parseReplyForTest(reply, 3), isNull);
    });

    test('a long reply is refused rather than trimmed', () {
      // Trimming keeps the right length but on the wrong lines.
      final reply = '[[["a${marker(1)}b${marker(2)}c${marker(3)}d"]]]';
      expect(LyricsTranslationService.parseReplyForTest(reply, 2), isNull);
      expect(
        LyricsTranslationService.parseReplyForTest(reply, 4),
        ['a', 'b', 'c', 'd'],
      );
    });

    test('garbage in gives nothing out rather than throwing', () {
      expect(LyricsTranslationService.parseReplyForTest('not json', 2), isNull);
      expect(LyricsTranslationService.parseReplyForTest('{}', 2), isNull);
      expect(LyricsTranslationService.parseReplyForTest('[[[]]]', 2), isNull);
      expect(LyricsTranslationService.parseReplyForTest('[]', 1), isNull);
      expect(LyricsTranslationService.parseReplyForTest('[1,2]', 1), isNull);
    });

    test('a reply carrying a blank line is refused', () {
      // A gap in the batch means the offsets no longer line up.
      expect(
        LyricsTranslationService.parseReplyForTest(
          '[[["one${marker(1)}"]]]',
          2,
        ),
        isNull,
      );
    });
  });

  group('romanization reads a different field', () {
    // A segment is [translated, source, phonetic, transliterated, ...]. A
    // romanization request asks for dt=rm and its answer is the TRANSLITERATED
    // field. Reading the translated one returns text that was never romanized -
    // a failure that looks like success because the line count still lines up.
    test('a romanized reply comes from the transliteration field', () {
      final body = '[[["そうほん","ja",null,"sohuhon"]],null,"ja"]';
      expect(
        LyricsTranslationService.parseRomanizedForTest(body, 1),
        ['sohuhon'],
      );
    });

    test('the same body read as a translation gives the other field', () {
      final body = '[[["そうほん","ja",null,"sohuhon"]],null,"ja"]';
      expect(
        LyricsTranslationService.parseReplyForTest(body, 1),
        ['そうほん'],
      );
    });

    test('the captured romanization is ONE segment holding every line', () {
      // Unlike a translation, dt=rm answers with a single segment whose null
      // translated field is why reading field 0 yields nothing at all.
      final body = fixture('translate_romanize_japanese.json');
      expect(
        LyricsTranslationService.parseReplyForTest(body, 2),
        isNull,
        reason: 'field 0 is null in a romanization response',
      );
      final answer = LyricsTranslationService.parseBatchReply(
        body,
        kind: LyricsTransform.romanize,
        expectedSlots: 2,
      )!;
      expect(answer.texts, ['Neko ga suki', 'kore wa tesutodesu']);
      expect(answer.sourceLanguage, 'ja');
    });

    test('a romanization with no transliteration field is refused', () {
      expect(
        LyricsTranslationService.parseRomanizedForTest('[[["そうほん"]]]', 1),
        isNull,
      );
    });

    test('a romanization with no detected language is refused', () {
      expect(
        LyricsTranslationService.parseRomanizedForTest(
          '[[[null,null,null,"sohuhon"]]]',
          1,
        ),
        isNull,
      );
    });

    test('romanization refuses a count that does not match', () {
      expect(
        LyricsTranslationService.parseRomanizedForTest(
          '[[["a",null,null,"A"],["b",null,null,"B"]],null,"ja"]',
          3,
        ),
        isNull,
      );
    });
  });

  group('Input Tools reply', () {
    test('reads root[1][0][1][0] when root[0] is SUCCESS', () {
      final native = LyricsTranslationService.parseNativeScriptReply(
        fixture('inputtools_hindi_latin_unchanged.json'),
      );
      expect(native, contains('तेरा होने लगा हूँ'));
      expect(native, contains('$_start०००१$_end'),
          reason: 'the markers come back, with native digits');
    });

    test('anything but SUCCESS is nothing', () {
      expect(
        LyricsTranslationService.parseNativeScriptReply('["FAILED_TO_PARSE_REQUEST_BODY"]'),
        isNull,
      );
      expect(LyricsTranslationService.parseNativeScriptReply('nope'), isNull);
      expect(
        LyricsTranslationService.parseNativeScriptReply('["SUCCESS",[]]'),
        isNull,
      );
      expect(
        LyricsTranslationService.parseNativeScriptReply('["SUCCESS",[["a",[""]]]]'),
        isNull,
        reason: 'a blank candidate is not a rendering',
      );
    });
  });

  group('Latin script detection', () {
    test('English and numerals count as Latin', () {
      expect(LyricsTranslationService.isLatinScript('Hello there, 42'), isTrue);
      expect(LyricsTranslationService.isLatinScript(''), isTrue);
      expect(LyricsTranslationService.isLatinScript('naïve café'), isTrue);
    });

    test('Japanese, Korean and Chinese do not', () {
      expect(LyricsTranslationService.isLatinScript('君は僕'), isFalse);
      expect(LyricsTranslationService.isLatinScript('안녕하세요'), isFalse);
      expect(LyricsTranslationService.isLatinScript('我很好'), isFalse);
      expect(LyricsTranslationService.isLatinScript('привет'), isFalse);
    });

    test('only LETTERS decide: curly quotes, dashes, notes and emoji do not', () {
      // The first version called anything at or above U+0250 non-Latin, so the
      // curly apostrophe in "don’t" - in a great many English lyrics - made the
      // globe offer a romanization that could only echo the text back.
      expect(LyricsTranslationService.isLatinScript('don’t stop – ever…'), isTrue);
      expect(LyricsTranslationService.isLatinScript('♪ la la la ♪ 😀'), isTrue);
      expect(LyricsTranslationService.isLatinScript('“quoted” ‘single’'), isTrue);
    });

    test('Vietnamese, fullwidth Latin and modifier letters are still Latin', () {
      expect(LyricsTranslationService.isLatinScript('Ở đâu có em'), isTrue);
      expect(LyricsTranslationService.isLatinScript('ＡＢＣ ａｂｃ'), isTrue);
      expect(LyricsTranslationService.isLatinScript('Hawaiʻi oʼzbek'), isTrue,
          reason: 'the okina and the modifier apostrophe sit inside Latin words');
    });

    test('one non-Latin letter makes a line non-Latin', () {
      expect(LyricsTranslationService.isLatinScript('hello мир'), isFalse);
      expect(LyricsTranslationService.isLatinScript('Ελλάδα'), isFalse);
    });

    test('a lyric is judged as a whole, and the answer is remembered per list',
        () {
      final english = [
        LyricsEntry(timeMs: 0, text: 'The only answer'),
        LyricsEntry(timeMs: 1, text: 'don’t stop'),
      ];
      final mixed = [...english, LyricsEntry(timeMs: 2, text: 'ねこ')];
      expect(LyricsTranslationService.entriesAreLatin(english), isTrue);
      expect(LyricsTranslationService.entriesAreLatin(mixed), isFalse,
          reason: 'one Japanese line among English still needs the globe');
      // Asked again for the same list: the remembered answer.
      expect(LyricsTranslationService.entriesAreLatin(english), isTrue);
      expect(LyricsTranslationService.entriesAreLatin(const []), isFalse,
          reason: 'nothing to romanize is not "already romanized"');
    });

    test('predominantly Latin means at least four Latin letters to one other',
        () {
      // 8 Latin letters (hiragana excluded) against 2 kana: exactly 4x.
      expect(
        LyricsTranslationService.predominantlyLatinForTest(['abcdefgh ねこ']),
        isTrue,
      );
      expect(
        LyricsTranslationService.predominantlyLatinForTest(['abcdefg ねこ']),
        isFalse,
      );
      expect(LyricsTranslationService.predominantlyLatinForTest(['ねこ']), isFalse);
      expect(LyricsTranslationService.predominantlyLatinForTest(['123 !?']), isFalse,
          reason: 'no letters at all is not Latin');
    });
  });

  group('language rules', () {
    test('the base subtag is compared, not the whole tag', () {
      expect(LyricsTranslationService.sameLanguage('en-US', 'en_GB'), isTrue);
      expect(LyricsTranslationService.sameLanguage('pt-BR', 'pt'), isTrue);
      expect(LyricsTranslationService.sameLanguage('ja', 'en'), isFalse);
    });

    test('the legacy codes are folded: iw -> he, in -> id, ji -> yi', () {
      expect(LyricsTranslationService.sameLanguage('iw', 'he'), isTrue);
      expect(LyricsTranslationService.sameLanguage('he', 'iw'), isTrue);
      expect(LyricsTranslationService.sameLanguage('in', 'id'), isTrue);
      expect(LyricsTranslationService.sameLanguage('ji', 'yi'), isTrue);
      expect(LyricsTranslationService.canonicalLanguage('IW_IL'), 'he');
      expect(LyricsTranslationService.canonicalLanguage('in-ID'), 'id');
    });

    test('two blanks are not "the same language"', () {
      expect(LyricsTranslationService.sameLanguage('', ''), isFalse);
    });

    test('names cover the common lyric languages', () {
      const names = {
        'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
        'it': 'Italian', 'pt': 'Portuguese', 'ru': 'Russian', 'ja': 'Japanese',
        'ko': 'Korean', 'zh': 'Chinese', 'hi': 'Hindi', 'ar': 'Arabic',
        'tr': 'Turkish', 'pl': 'Polish', 'nl': 'Dutch', 'sv': 'Swedish',
        'th': 'Thai', 'vi': 'Vietnamese', 'id': 'Indonesian', 'ms': 'Malay',
        'bn': 'Bengali', 'ta': 'Tamil', 'te': 'Telugu', 'ur': 'Urdu',
        'pa': 'Punjabi', 'fa': 'Persian', 'he': 'Hebrew', 'el': 'Greek',
        'uk': 'Ukrainian', 'cs': 'Czech', 'hu': 'Hungarian', 'ro': 'Romanian',
        'fi': 'Finnish', 'da': 'Danish', 'no': 'Norwegian', 'fil': 'Filipino',
        'sw': 'Swahili', 'af': 'Afrikaans', 'mr': 'Marathi', 'gu': 'Gujarati',
        'kn': 'Kannada', 'ml': 'Malayalam',
      };
      for (final entry in names.entries) {
        expect(LyricsTranslationService.languageName(entry.key), entry.value,
            reason: entry.key);
      }
    });

    test('a name is looked up by base subtag, whatever the case or separator',
        () {
      expect(LyricsTranslationService.languageName('pt-BR'), 'Portuguese');
      expect(LyricsTranslationService.languageName('pt_br'), 'Portuguese');
      expect(LyricsTranslationService.languageName('JA'), 'Japanese');
      expect(LyricsTranslationService.languageName(' en_US '), 'English');
    });

    test('legacy codes name the language they stand for', () {
      expect(LyricsTranslationService.languageName('iw'), 'Hebrew');
      expect(LyricsTranslationService.languageName('in'), 'Indonesian');
      expect(LyricsTranslationService.languageName('ji'), 'Yiddish');
    });

    test('Chinese keeps its script', () {
      expect(LyricsTranslationService.languageName('zh'), 'Chinese');
      expect(LyricsTranslationService.languageName('zh-CN'), 'Chinese (Simplified)');
      expect(LyricsTranslationService.languageName('zh-Hans'), 'Chinese (Simplified)');
      expect(LyricsTranslationService.languageName('zh-TW'), 'Chinese (Traditional)');
      expect(LyricsTranslationService.languageName('zh_HK'), 'Chinese (Traditional)');
      expect(LyricsTranslationService.languageName('zh-Hant'), 'Chinese (Traditional)');
    });

    test('an unknown code comes back upper-cased, never guessed at', () {
      expect(LyricsTranslationService.languageName('xx'), 'XX');
      expect(LyricsTranslationService.languageName('xx-yy'), 'XX-YY');
      expect(LyricsTranslationService.languageName(''), '');
    });
  });

  group('the target language', () {
    test('the setting wins, exactly as typed', () {
      expect(
        LyricsTranslationService.resolveTargetLanguage(
          setting: 'ja',
          localeName: 'en_US',
        ),
        'ja',
      );
      // zh-TW and zh-CN are different targets: narrowing either to zh asks for
      // the wrong script.
      expect(
        LyricsTranslationService.resolveTargetLanguage(
          setting: ' zh-TW ',
          localeName: 'en_US',
        ),
        'zh-TW',
      );
    });

    test('blank means follow the app, reduced to a BASE language', () {
      // Platform.localeName is "en_US". Sent as tl=en_US was the bug.
      for (final entry in {
        'en_US': 'en',
        'en-US': 'en',
        'pt_BR': 'pt',
        'zh_Hans_CN': 'zh',
        'de_DE.UTF-8': 'de',
        'fr_FR@euro': 'fr',
        'FIL': 'fil',
        'iw_IL': 'he',
      }.entries) {
        expect(
          LyricsTranslationService.resolveTargetLanguage(
            setting: '',
            localeName: entry.key,
          ),
          entry.value,
          reason: entry.key,
        );
      }
      expect(
        LyricsTranslationService.resolveTargetLanguage(
          setting: '   ',
          localeName: 'es_MX',
        ),
        'es',
      );
    });

    test('en when nothing usable is left', () {
      for (final locale in [null, '', 'C', 'POSIX', '1', 'e']) {
        expect(
          LyricsTranslationService.resolveTargetLanguage(localeName: locale),
          'en',
          reason: '$locale',
        );
      }
    });

    test('the stored setting is read on each call', () async {
      // Through the real store, as the settings screen writes it.
      final svc = service(Endpoint());
      final stored = LyricsTranslationService(
        client: Endpoint().client,
        cacheDirectory: () async => null,
      );
      addTearDown(svc.close);
      addTearDown(stored.close);

      SharedPreferences.setMockInitialValues({'translation_language': 'fr'});
      expect(await stored.targetLanguage(localeName: 'en_US'), 'fr');

      SharedPreferences.setMockInitialValues({});
      expect(await stored.targetLanguage(localeName: 'es_MX'), 'es');

      SharedPreferences.setMockInitialValues({'translation_language': ''});
      expect(await stored.targetLanguage(localeName: 'de_DE'), 'de');

      expect(LyricsTranslationService.translationLanguagePrefKey,
          'translation_language');
    });

    test('an injected reader replaces the store', () async {
      var setting = 'ko';
      final svc = LyricsTranslationService(
        client: Endpoint().client,
        cacheDirectory: () async => null,
        settingReader: () async => setting,
      );
      addTearDown(svc.close);
      expect(await svc.targetLanguage(localeName: 'en_US'), 'ko');
      setting = '';
      expect(await svc.targetLanguage(localeName: 'en_US'), 'en');
    });

    test('the device language is the fallback when no locale is passed',
        () async {
      SharedPreferences.setMockInitialValues({});
      final svc = LyricsTranslationService(
        client: Endpoint().client,
        cacheDirectory: () async => null,
      );
      addTearDown(svc.close);
      final language = await svc.targetLanguage();
      expect(language, matches(RegExp(r'^[a-z]{2,3}$')),
          reason: 'a base language, never en_US');
    });
  });

  group('translate', () {
    test('posts the form the reference sends, and reads the answer', () async {
      final endpoint = Endpoint(
        onTranslate: (_) => okBody(fixture('translate_japanese_to_english.json')),
      );
      final result = ready(await run(service(endpoint), japanese));

      expect(endpoint.requests.length, 1);
      final request = endpoint.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://translate.googleapis.com/translate_a/single',
      );
      expect(request.headers['Content-Type'], contains('x-www-form-urlencoded'));

      final fields = endpoint.translate.single;
      expect(fields, {
        'client': 'dict-chrome-ex',
        'sl': 'auto',
        'tl': 'en',
        'dt': 't',
        'q': '${japanese[0]}\n${marker(1)}\n${japanese[1]}',
      });

      expect(result.lines, ['I like cats', 'this is a test']);
      expect(result.sourceLanguage, 'ja');
      expect(result.fromCache, isFalse);
    });

    test('the target is sent as given, not reduced to a base language',
        () async {
      final endpoint = Endpoint(
        onTranslate: (f) => reply(f['q']!, detected: 'ja'),
      );
      await run(service(endpoint), japanese, target: 'zh-TW');
      expect(endpoint.translate.single['tl'], 'zh-TW');
    });

    test('blank lines stay blank and a section header keeps its brackets',
        () async {
      final endpoint = Endpoint(
        onTranslate: (f) => reply(
          mapPayload(f['q']!, (line) => line.toUpperCase()),
          detected: 'es',
        ),
      );
      final lines = ['[Estribillo]', 'hola mundo', '', 'adiós'];
      final result = ready(await run(service(endpoint), lines));

      expect(endpoint.translate.single['q'],
          'Estribillo\n${marker(1)}\nhola mundo\n${marker(2)}\nadiós');
      expect(result.lines, ['[ESTRIBILLO]', 'HOLA MUNDO', '', 'ADIÓS']);
    });

    test('a batch boundary in the middle of a lyric loses and reorders nothing',
        () async {
      final endpoint = Endpoint(
        onTranslate: (f) => reply(
          mapPayload(f['q']!, (line) => 'T:$line'),
          detected: 'es',
        ),
      );
      final lines = List.generate(40, (i) => 'line $i ${'z' * 200}');
      final result = ready(await run(service(endpoint), lines));

      expect(endpoint.translate.length, greaterThan(1));
      for (final fields in endpoint.translate) {
        expect(fields['q']!.length,
            lessThanOrEqualTo(LyricsTranslationService.maxBatchChars));
      }
      expect(result.lines, [for (final l in lines) 'T:$l']);
    });

    test('at most two requests are in flight at once', () async {
      final endpoint = Endpoint(
        latency: const Duration(milliseconds: 15),
        onTranslate: (f) => reply(
          mapPayload(f['q']!, (line) => 'T:${line.substring(0, 5)}'),
          detected: 'es',
        ),
      );
      // Six lines of 2000 characters: each is a batch of its own.
      final lines = List.generate(6, (i) => '$i' * 2000);
      final result = ready(await run(service(endpoint), lines));

      expect(endpoint.translate.length, 6);
      expect(endpoint.maxInFlight, 2);
      expect(result.lines, [for (var i = 0; i < 6; i++) 'T:${'$i' * 5}']);
    });

    test('any batch failing makes the whole thing unavailable', () async {
      final lines = [for (var i = 0; i < 3; i++) '$i' * 2000];
      final endpoint = Endpoint(
        onTranslate: (f) => f['q']!.startsWith('1')
            ? status(503)
            : reply(f['q']!, detected: 'es'),
      );
      expect(await run(service(endpoint), lines),
          isA<LyricsTransformUnavailable>());
    });

    test('a lost marker in the answer makes it unavailable', () async {
      // The endpoint sometimes drops a marker; the two lines it joined cannot be
      // told apart afterwards, so the answer is refused rather than guessed.
      final endpoint = Endpoint(
        onTranslate: (f) => reply(
          f['q']!.replaceAll(RegExp('\uE000[^\uE001]*\uE001'), ''),
          detected: 'es',
        ),
      );
      expect(await run(service(endpoint), ['uno', 'dos']),
          isA<LyricsTransformUnavailable>());
    });

    test('a non-success status, a timeout and garbage are all unavailable',
        () async {
      for (final response in [
        status(500),
        status(429),
        okBody('not json'),
        okBody('[]'),
      ]) {
        final endpoint = Endpoint(onTranslate: (_) => response);
        expect(await run(service(endpoint), ['uno']),
            isA<LyricsTransformUnavailable>());
      }

      final slow = LyricsTranslationService(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return okBody('[]');
        }),
        cacheDirectory: () async => null,
        timeout: const Duration(milliseconds: 20),
      );
      expect(await run(slow, ['uno']), isA<LyricsTransformUnavailable>());
    });

    test('an empty or blank-only lyric is unavailable without a request',
        () async {
      final endpoint = Endpoint(onTranslate: (f) => reply(f['q']!));
      expect(await run(service(endpoint), const []),
          isA<LyricsTransformUnavailable>());
      expect(await run(service(endpoint), ['', '  ']),
          isA<LyricsTransformUnavailable>());
      expect(await run(service(endpoint), ['uno'], target: ' '),
          isA<LyricsTransformUnavailable>());
      expect(endpoint.requests, isEmpty);
    });

    test('the source language is the PAYLOAD-weighted majority', () async {
      // Two 600-character batches say "ko", two 3000-character batches say "ja".
      // By batch count it is a tie that "ko" wins by arriving first; by payload
      // it is 6000 against 1200.
      final lines = ['b' * 600, 'a' * 3000, 'd' * 600, 'c' * 3000];
      final endpoint = Endpoint(
        onTranslate: (f) => reply(
          mapPayload(f['q']!, (line) => 'T${line.length}'),
          detected: f['q']!.length > 1000 ? 'ja' : 'ko',
        ),
      );
      final result = ready(await run(service(endpoint), lines));
      expect(endpoint.translate.length, 4);
      expect(result.sourceLanguage, 'ja');
    });

    test('a missing detected language is unavailable', () async {
      final endpoint = Endpoint(
        onTranslate: (f) => okBody(jsonEncode([
          [
            [f['q'], f['q']]
          ],
          null,
          null,
        ])),
      );
      expect(await run(service(endpoint), ['uno']),
          isA<LyricsTransformUnavailable>());
    });

    test('a cancelled call returns unavailable and caches nothing', () async {
      final token = LyricsCancelToken();
      final lines = [for (var i = 0; i < 4; i++) '$i' * 2000];
      final endpoint = Endpoint(
        onTranslate: (f) {
          token.cancel();
          return reply(f['q']!, detected: 'es');
        },
      );
      final svc = service(endpoint);
      expect(await run(svc, lines, cancel: token),
          isA<LyricsTransformUnavailable>());
      expect(svc.memoryKeysForTest, isEmpty,
          reason: 'nobody wanted the answer, so it must not be remembered');
    });
  });

  group('same language', () {
    test('a lyric already in the target language is SameLanguage', () async {
      final endpoint = Endpoint(
        onTranslate: (f) => reply(f['q']!, detected: 'ja'),
      );
      final result = await run(service(endpoint), japanese, target: 'ja');
      expect(result, isA<LyricsTransformSameLanguage>());
      expect((result as LyricsTransformSameLanguage).language, 'ja');
    });

    test('base subtags decide, so ja-JP is ja', () async {
      final endpoint = Endpoint(
        onTranslate: (f) => reply(f['q']!, detected: 'ja'),
      );
      expect(
        await run(service(endpoint), japanese, target: 'ja-JP'),
        isA<LyricsTransformSameLanguage>(),
      );
    });

    test('iw is he, in is id, ji is yi - even when the endpoint says the old one',
        () async {
      for (final pair in [('iw', 'he'), ('in', 'id'), ('ji', 'yi')]) {
        final endpoint = Endpoint(
          onTranslate: (f) => reply(f['q']!, detected: pair.$1),
        );
        expect(
          await run(service(endpoint), ['שלום'], target: pair.$2),
          isA<LyricsTransformSameLanguage>(),
          reason: '${pair.$1} vs ${pair.$2}',
        );
      }
    });

    test('the answer is cached too: the second tap costs no request', () async {
      final endpoint = Endpoint(
        onTranslate: (f) => reply(f['q']!, detected: 'ja'),
      );
      final svc = service(endpoint);
      expect(await run(svc, japanese, target: 'ja'),
          isA<LyricsTransformSameLanguage>());
      expect(await run(svc, japanese, target: 'ja'),
          isA<LyricsTransformSameLanguage>());
      expect(endpoint.translate.length, 1);
    });

    test('and it survives a restart: it is on disk', () async {
      final dir = Directory.systemTemp.createTempSync('lyrics_same_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final first = Endpoint(onTranslate: (f) => reply(f['q']!, detected: 'ja'));
      await run(service(first, cache: dir), japanese, target: 'ja');

      final second = Endpoint();
      final result =
          await run(service(second, cache: dir), japanese, target: 'ja');
      expect(result, isA<LyricsTransformSameLanguage>());
      expect(second.requests, isEmpty);
    });
  });

  group('romanize', () {
    test('posts dt=rm and reads root[0][*][3]', () async {
      final endpoint = Endpoint(
        onTranslate: (_) => okBody(fixture('translate_romanize_japanese.json')),
      );
      final result = ready(await run(
        service(endpoint),
        japanese,
        kind: LyricsTransform.romanize,
      ));

      expect(endpoint.translate.single, {
        'client': 'dict-chrome-ex',
        'sl': 'auto',
        'tl': 'en',
        'dt': 'rm',
        'q': '${japanese[0]}\n${marker(1)}\n${japanese[1]}',
      });
      expect(result.lines, ['Neko ga suki', 'kore wa tesutodesu']);
      expect(result.sourceLanguage, 'ja');
    });

    test('a lyric with no non-Latin letter is AlreadyRomanized, with no request',
        () async {
      final endpoint = Endpoint(onTranslate: (f) => reply(f['q']!));
      final svc = service(endpoint);
      for (final lines in [
        ['The only answer', 'This high came rushing'],
        ['don’t stop – ever…', '♪ la la ♪'],
        ['Ở đâu có em', 'Café'],
      ]) {
        final result = await run(svc, lines, kind: LyricsTransform.romanize);
        expect(result, isA<LyricsTransformSameLanguage>(), reason: '$lines');
      }
      expect(endpoint.requests, isEmpty);
    });

    test('one non-Latin line among English is still romanized', () async {
      final endpoint = Endpoint(
        onTranslate: (f) => reply(
          mapPayload(f['q']!, (line) => line == 'ねこ' ? 'neko' : line),
          detected: 'ja',
          romanized: true,
        ),
      );
      final result = ready(await run(
        service(endpoint),
        ['hello there', 'ねこ'],
        kind: LyricsTransform.romanize,
      ));
      expect(result.lines, ['hello there', 'neko']);
    });

    test('an unchanged answer for non-Latin input is unavailable, not Ready',
        () async {
      // The endpoint echoing Japanese back means it could not romanize it. That
      // is a fault, not "already Latin": the lyric is NOT in Latin script.
      final endpoint = Endpoint(
        onTranslate: (f) => reply(f['q']!, detected: 'ja', romanized: true),
      );
      expect(
        await run(service(endpoint), japanese, kind: LyricsTransform.romanize),
        isA<LyricsTransformUnavailable>(),
      );
    });

    test('the target language changes the request but not the cache', () async {
      final endpoint = Endpoint(
        onTranslate: (_) => okBody(fixture('translate_romanize_japanese.json')),
      );
      final svc = service(endpoint);

      await run(svc, japanese, kind: LyricsTransform.romanize, target: 'en');
      final again = ready(await run(
        svc,
        japanese,
        kind: LyricsTransform.romanize,
        target: 'fr',
      ));

      expect(endpoint.translate.length, 1,
          reason: 'how a language is pronounced does not depend on the language '
              'the reader translates INTO');
      expect(again.fromCache, isTrue);
      expect(again.lines, ['Neko ga suki', 'kore wa tesutodesu']);
    });

    test('a blank target is sent as en', () async {
      final endpoint = Endpoint(
        onTranslate: (_) => okBody(fixture('translate_romanize_japanese.json')),
      );
      await run(service(endpoint), japanese,
          kind: LyricsTransform.romanize, target: '  ');
      expect(endpoint.translate.single['tl'], 'en');
    });
  });

  group('cache keys', () {
    String key(
      LyricsTransform kind, {
      String track = 't1',
      String target = 'en',
      List<String> lines = japanese,
    }) =>
        LyricsTranslationService.cacheKeyForTest(
          kind: kind,
          trackId: track,
          targetLanguage: target,
          lines: lines,
        );

    test('a key is a SHA-256 hex digest, safe to use as a filename', () {
      expect(key(LyricsTransform.translate), matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('a translate key includes the target language', () {
      expect(
        key(LyricsTransform.translate, target: 'en'),
        isNot(key(LyricsTransform.translate, target: 'fr')),
      );
      expect(
        key(LyricsTransform.translate, target: 'zh-CN'),
        isNot(key(LyricsTransform.translate, target: 'zh-TW')),
      );
    });

    test('a romanize key EXCLUDES it', () {
      expect(
        key(LyricsTransform.romanize, target: 'en'),
        key(LyricsTransform.romanize, target: 'fr'),
      );
    });

    test('translate and romanize never share a key', () {
      expect(
        key(LyricsTransform.romanize),
        isNot(key(LyricsTransform.translate, target: 'romanize')),
        reason: 'a translation target that happened to be spelled "romanize" '
            'would otherwise be served a romanization from the cache',
      );
      expect(
        key(LyricsTransform.romanize),
        isNot(key(LyricsTransform.translate, target: '')),
      );
    });

    test('the track and the words are part of every key', () {
      for (final kind in LyricsTransform.values) {
        expect(key(kind, track: 'a'), isNot(key(kind, track: 'b')));
        expect(
          key(kind, lines: ['one', 'two']),
          isNot(key(kind, lines: ['one', 'too'])),
          reason: "a different provider's words must not get this answer",
        );
      }
    });

    test('blank lines do not change a key', () {
      expect(
        key(LyricsTransform.translate, lines: ['a', '', 'b']),
        key(LyricsTransform.translate, lines: ['a', 'b']),
      );
    });
  });

  group('the inputtools retry', () {
    // Pass one leaves "tera hone laga hoon" untouched (19 of 46 characters, over a
    // third); Input Tools restores the Devanagari; translating THAT works.
    Endpoint hindi({
      http.Response Function(Map<String, String>)? inputTools,
      http.Response Function(Map<String, String>)? retry,
      String firstPass = 'translate_hindi_latin_unchanged_pass1.json',
    }) =>
        Endpoint(
          onTranslate: (f) => f['sl'] == 'auto'
              ? okBody(fixture(firstPass))
              : (retry ??
                  (_) => okBody(
                      fixture('translate_hindi_native_unchanged_retry.json')))(f),
          onInputTools: inputTools ??
              (_) => okBody(fixture('inputtools_hindi_latin_unchanged.json')),
        );

    test('a Latin Hindi lyric that came back unchanged is retried and KEPT',
        () async {
      final endpoint = hindi();
      final result = ready(await run(service(endpoint), hindiUnchanged));

      // The first pass left "tera hone laga hoon" alone; the retry translated it.
      expect(result.lines, ['I am becoming yours', 'i love you']);
      expect(result.sourceLanguage, 'hi');

      expect(endpoint.translate.length, 2);
      expect(endpoint.translate[0]['sl'], 'auto');
      expect(endpoint.translate[1]['sl'], 'hi',
          reason: 'the retry says which language it is, rather than asking the '
              'endpoint to re-detect it');
      expect(endpoint.translate[1]['q'], contains('तेरा होने लगा हूँ'),
          reason: 'what is retranslated is the NATIVE script');
    });

    test('the Input Tools request carries the documented form', () async {
      final endpoint = hindi();
      await run(service(endpoint), hindiUnchanged);

      final request = endpoint.requests.firstWhere(
        (r) => r.url.host == 'inputtools.google.com',
      );
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://inputtools.google.com/request');
      expect(endpoint.inputTools.single, {
        'text': '${hindiUnchanged[0]}\n${marker(1)}\n${hindiUnchanged[1]}',
        'itc': 'hi-t-i0-und',
        'num': '1',
        'cp': '0',
        'cs': '1',
        'ie': 'utf-8',
        'oe': 'utf-8',
      });
    });

    test('a four-line lyric survives the round trip, native digits and all',
        () async {
      // Three of four lines untouched on pass one; the retry fixtures are the
      // captured Input Tools and translate answers for the same four lines.
      final endpoint = Endpoint(
        onTranslate: (f) => f['sl'] == 'auto'
            ? reply(
                mapPayload(f['q']!, (line) => line == hindiFour[3] ? 'you are my life' : line),
                detected: 'hi',
              )
            : okBody(fixture('translate_hindi_native_retry.json')),
        onInputTools: (_) => okBody(fixture('inputtools_hindi_latin.json')),
      );
      final result = ready(await run(service(endpoint), hindiFour));

      expect(result.lines, [
        'my heart searches for you',
        'I think about you all night long',
        'i love you',
        'you are my life',
      ]);
    });

    test('the retry is DISCARDED when it leaves no less text unchanged',
        () async {
      // The retry answers with the very same unchanged text, so there is nothing
      // to prefer it for. Bilingual lyrics and names must not get worse merely
      // because they contain Latin text.
      final endpoint = hindi(
        retry: (_) => okBody(fixture('translate_hindi_latin_unchanged_pass1.json')),
      );
      final result = ready(await run(service(endpoint), hindiUnchanged));

      expect(endpoint.translate.length, 2, reason: 'it WAS tried');
      expect(result.lines, ['tera hone laga hoon', 'I love you most of the time']);
    });

    test('and when Input Tools fails, pass one stands', () async {
      for (final response in [
        status(500),
        okBody('["FAILED_TO_PARSE_REQUEST_BODY"]'),
        okBody('garbage'),
      ]) {
        final endpoint = hindi(inputTools: (_) => response);
        final result = ready(await run(service(endpoint), hindiUnchanged));
        expect(result.lines, ['tera hone laga hoon', 'I love you most of the time']);
        expect(endpoint.translate.length, 1,
            reason: 'with no native script there is nothing to retranslate');
      }
    });

    test('and when the retranslation fails, pass one stands', () async {
      final endpoint = hindi(retry: (_) => status(500));
      final result = ready(await run(service(endpoint), hindiUnchanged));
      expect(result.lines, ['tera hone laga hoon', 'I love you most of the time']);
    });

    test('nothing unchanged, nothing retried', () async {
      final endpoint = hindi(firstPass: 'translate_hindi_latin_pass1.json');
      final result = ready(await run(service(endpoint), hindiFour));
      expect(result.lines.first, 'my heart searches for you');
      expect(endpoint.inputTools, isEmpty);
      expect(endpoint.translate.length, 1);
    });

    test('less than a third unchanged is not enough to retry', () async {
      // 19 unchanged of 19 + 26 + 100 = 145: under a third.
      final lines = ['tera hone laga hoon', 'main tujhse pyar karta hoon', 'x' * 100];
      final endpoint = Endpoint(
        onTranslate: (f) => reply(
          mapPayload(f['q']!, (l) => l == lines[0] ? l : 'T:$l'),
          detected: 'hi',
        ),
        onInputTools: (_) => okBody(fixture('inputtools_hindi_latin.json')),
      );
      ready(await run(service(endpoint), lines));
      expect(endpoint.inputTools, isEmpty);
    });

    test('exactly a third unchanged does retry', () async {
      // 3 unchanged characters of 9: three times the unchanged weight IS the total.
      final lines = ['abc', 'defghi'];
      final endpoint = Endpoint(
        onTranslate: (f) => reply(
          mapPayload(f['q']!, (l) => l == 'abc' ? l : 'T:$l'),
          detected: 'hi',
        ),
        onInputTools: (_) => status(500),
      );
      ready(await run(service(endpoint), lines));
      expect(endpoint.inputTools.length, 1);
    });

    test('an English source is never retried', () async {
      final endpoint = Endpoint(
        onTranslate: (f) => reply(f['q']!, detected: 'en'),
        onInputTools: (_) => okBody(fixture('inputtools_hindi_latin.json')),
      );
      ready(await run(service(endpoint), hindiUnchanged, target: 'fr'));
      expect(endpoint.inputTools, isEmpty);
    });

    test('a lyric that is not predominantly Latin is never retried', () async {
      // Japanese is already in its own script: there is no native form to restore.
      final endpoint = Endpoint(
        onTranslate: (f) => reply(f['q']!, detected: 'ja'),
        onInputTools: (_) => okBody(fixture('inputtools_hindi_latin.json')),
      );
      ready(await run(service(endpoint), japanese));
      expect(endpoint.inputTools, isEmpty);
    });

    test('a lyric already in the target language is never retried', () async {
      final endpoint = Endpoint(
        onTranslate: (f) => reply(f['q']!, detected: 'hi'),
        onInputTools: (_) => okBody(fixture('inputtools_hindi_latin.json')),
      );
      final result = await run(service(endpoint), hindiUnchanged, target: 'hi');
      expect(result, isA<LyricsTransformSameLanguage>());
      expect(endpoint.inputTools, isEmpty);
    });
  });

  group('the cache', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('lyrics_cache_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Endpoint japanese2English() => Endpoint(
          onTranslate: (_) =>
              okBody(fixture('translate_japanese_to_english.json')),
        );

    File only() {
      final folder = Directory('${dir.path}/lyrics_translation_v3');
      return folder.listSync().whereType<File>().single;
    }

    test('lives at <cache>/lyrics_translation_v3/<sha256>.json.gz, gzipped',
        () async {
      await run(service(japanese2English(), cache: dir), japanese);

      final file = only();
      final name = file.uri.pathSegments.last;
      expect(name, matches(RegExp(r'^[0-9a-f]{64}\.json\.gz$')));
      expect(
        name,
        '${LyricsTranslationService.cacheKeyForTest(kind: LyricsTransform.translate, trackId: 'track-1', targetLanguage: 'en', lines: japanese)}.json.gz',
      );

      final bytes = file.readAsBytesSync();
      expect(bytes.take(2), [0x1f, 0x8b], reason: 'gzip magic');
      final stored = jsonDecode(utf8.decode(gzip.decode(bytes))) as Map;
      expect(stored['version'], 3);
      expect(stored['sourceLanguage'], 'ja');
      expect(stored['targetLanguage'], 'en');
      expect(stored['texts'], ['I like cats', 'this is a test']);
    });

    test('is read back by a fresh service with no request', () async {
      await run(service(japanese2English(), cache: dir), japanese);

      final offline = Endpoint();
      final result = ready(await run(service(offline, cache: dir), japanese));
      expect(offline.requests, isEmpty);
      expect(result.fromCache, isTrue);
      expect(result.lines, ['I like cats', 'this is a test']);
      expect(result.sourceLanguage, 'ja');
    });

    test('is keyed on the track: another song re-asks', () async {
      await run(service(japanese2English(), cache: dir), japanese);
      final other = japanese2English();
      await run(service(other, cache: dir), japanese, track: 'track-2');
      expect(other.translate.length, 1);
    });

    test('an entry of another version is ignored, not misread', () async {
      final key = LyricsTranslationService.cacheKeyForTest(
        kind: LyricsTransform.translate,
        trackId: 'track-1',
        targetLanguage: 'en',
        lines: japanese,
      );
      final folder = Directory('${dir.path}/lyrics_translation_v3')
        ..createSync(recursive: true);
      File('${folder.path}/$key.json.gz').writeAsBytesSync(gzip.encode(utf8.encode(
        jsonEncode({
          'version': 2,
          'sourceLanguage': 'ja',
          'targetLanguage': 'en',
          'texts': ['stale', 'stale'],
        }),
      )));

      final endpoint = japanese2English();
      final result = ready(await run(service(endpoint, cache: dir), japanese));
      expect(endpoint.translate.length, 1);
      expect(result.lines, ['I like cats', 'this is a test']);
    });

    test('a corrupt or short entry is a miss', () async {
      final key = LyricsTranslationService.cacheKeyForTest(
        kind: LyricsTransform.translate,
        trackId: 'track-1',
        targetLanguage: 'en',
        lines: japanese,
      );
      final folder = Directory('${dir.path}/lyrics_translation_v3')
        ..createSync(recursive: true);
      final file = File('${folder.path}/$key.json.gz');

      file.writeAsBytesSync([1, 2, 3]);
      var endpoint = japanese2English();
      ready(await run(service(endpoint, cache: dir), japanese));
      expect(endpoint.translate.length, 1);

      file.writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode({
        'version': 3,
        'sourceLanguage': 'ja',
        'targetLanguage': 'en',
        'texts': ['only one'],
      }))));
      endpoint = japanese2English();
      ready(await run(service(endpoint, cache: dir), japanese));
      expect(endpoint.translate.length, 1,
          reason: 'one text for two lines is not an answer');
    });

    test('a romanization is shared across target languages on disk too',
        () async {
      final endpoint = Endpoint(
        onTranslate: (_) => okBody(fixture('translate_romanize_japanese.json')),
      );
      await run(service(endpoint, cache: dir), japanese,
          kind: LyricsTransform.romanize, target: 'en');

      final offline = Endpoint();
      final result = ready(await run(
        service(offline, cache: dir),
        japanese,
        kind: LyricsTransform.romanize,
        target: 'de',
      ));
      expect(offline.requests, isEmpty);
      expect(result.lines, ['Neko ga suki', 'kore wa tesutodesu']);
    });

    test('stays under 2MB by deleting the OLDEST entries first', () async {
      final folder = Directory('${dir.path}/lyrics_translation_v3')
        ..createSync(recursive: true);
      final now = DateTime.now();
      // Three 900KB entries, newest to oldest. Two fit under 2MB with the new
      // one; the third does not.
      final files = <File>[];
      for (var i = 0; i < 3; i++) {
        final file = File('${folder.path}/${'$i' * 64}.json.gz')
          ..writeAsBytesSync(List<int>.filled(900 * 1024, 7));
        file.setLastModifiedSync(now.subtract(Duration(hours: i + 1)));
        files.add(file);
      }

      await run(service(japanese2English(), cache: dir), japanese);

      expect(files[0].existsSync(), isTrue, reason: 'newest old entry kept');
      expect(files[1].existsSync(), isTrue);
      expect(files[2].existsSync(), isFalse, reason: 'the oldest goes first');
      expect(
        folder.listSync().whereType<File>().length,
        3,
        reason: 'two survivors plus the entry just written',
      );
      final total = folder
          .listSync()
          .whereType<File>()
          .fold<int>(0, (sum, f) => sum + f.lengthSync());
      expect(total, lessThanOrEqualTo(LyricsTranslationService.maxDiskBytes));
    });

    test('the entry just written survives an old one that alone breaks the budget',
        () async {
      // Newest first: what the reader is looking at is kept. Deleting the
      // LARGEST first (as this once did) throws away the current song whenever
      // it happens to be long, and keeps a stale huge one.
      final folder = Directory('${dir.path}/lyrics_translation_v3')
        ..createSync(recursive: true);
      final old = File('${folder.path}/${'a' * 64}.json.gz')
        ..writeAsBytesSync(List<int>.filled(2100 * 1024, 7));
      old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 1)));

      await run(service(japanese2English(), cache: dir), japanese);

      expect(old.existsSync(), isFalse);
      expect(folder.listSync().whereType<File>().length, 1);
    });

    test('without a cache directory it still works, from memory', () async {
      final endpoint = japanese2English();
      final svc = service(endpoint);
      await run(svc, japanese);
      await run(svc, japanese);
      expect(endpoint.translate.length, 1);
    });

    test('clear() forgets memory and disk', () async {
      final endpoint = japanese2English();
      final svc = service(endpoint, cache: dir);
      await run(svc, japanese);
      await svc.clear();
      expect(svc.memoryKeysForTest, isEmpty);
      await run(svc, japanese);
      expect(endpoint.translate.length, 2);
    });
  });

  group('the memory cache', () {
    Endpoint fresh() => Endpoint(
          onTranslate: (f) => reply(
            mapPayload(f['q']!, (l) => 'T:$l'),
            detected: 'es',
          ),
        );

    test('holds 12 entries, least recently USED out first', () async {
      final endpoint = fresh();
      final svc = service(endpoint);
      for (var i = 1; i <= 12; i++) {
        await run(svc, ['uno'], track: 't$i');
      }
      expect(svc.memoryKeysForTest.length, 12);
      expect(endpoint.translate.length, 12);

      // Use t1 again, so t2 is now the oldest.
      await run(svc, ['uno'], track: 't1');
      expect(endpoint.translate.length, 12, reason: 'a hit');

      await run(svc, ['uno'], track: 't13');
      expect(svc.memoryKeysForTest.length, 12);
      expect(endpoint.translate.length, 13);

      await run(svc, ['uno'], track: 't1');
      expect(endpoint.translate.length, 13,
          reason: 'recently used, so it stayed');
      await run(svc, ['uno'], track: 't2');
      expect(endpoint.translate.length, 14, reason: 't2 was the one evicted');
    });
  });

  group('applying a transform', () {
    final original = [
      LyricsEntry(timeMs: 0, endMs: 1000, text: 'one'),
      LyricsEntry(timeMs: 1000, endMs: 2000, text: 'two'),
    ];

    test('timestamps survive the swap', () {
      final out =
          LyricsTranslationService.applyText(original, ['un', 'deux']);
      expect(out[0].timeMs, 0);
      expect(out[1].timeMs, 1000);
      expect(out[0].endMs, 1000);
      expect(out.map((e) => e.text).toList(), ['un', 'deux']);
    });

    test('word timings are dropped, because their spans no longer apply', () {
      // A syllable span indexes into the ORIGINAL characters. Keeping it
      // against translated text would clip the wrong letters entirely.
      final withWords = [
        LyricsEntry(
          timeMs: 0,
          endMs: 1000,
          text: 'hello',
          words: const [WordTiming(timeMs: 0, durationMs: 500, text: 'hello')],
        ),
      ];
      final out =
          LyricsTranslationService.applyText(withWords, ['bonjour']);
      expect(out.first.text, 'bonjour');
      expect(out.first.timedWords, isEmpty);
      expect(out.first.timeMs, 0);
    });

    test('a length mismatch is refused rather than applied', () {
      final out = LyricsTranslationService.applyText(original, ['only one']);
      expect(out.length, 2);
      expect(out[0].text, 'one');
      expect(out[1].text, 'two');
    });

    test('an empty translated line keeps the original', () {
      final out = LyricsTranslationService.applyText(original, ['', 'deux']);
      expect(out[0].text, 'one');
      expect(out[1].text, 'deux');
    });
  });
}
