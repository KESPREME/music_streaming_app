import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_translation_service.dart';

void main() {
  group('batching', () {
    test('short lyrics go in one batch', () {
      final svc = LyricsTranslationService.instance;
      final batches = svc.batchesForTest(['one', 'two', 'three']);
      expect(batches.length, 1);
      expect(batches.first, ['one', 'two', 'three']);
    });

    test('a long lyric is split under the character cap', () {
      final svc = LyricsTranslationService.instance;
      final lines = List.generate(400, (i) => 'x' * 40);
      final batches = svc.batchesForTest(lines);
      expect(batches.length, greaterThan(1));
      // Every line present exactly once, in order, across all batches.
      expect(batches.expand((b) => b).toList(), lines);
      for (final batch in batches) {
        final joined = batch.join('');
        expect(joined.length, lessThan(LyricsTranslationService.maxBatchChars));
      }
    });

    test('a single line over the cap is sent alone rather than split', () {
      // One over-long line is a bad request; a lyric broken mid-sentence is
      // worse, because the halves read as two separate thoughts.
      final svc = LyricsTranslationService.instance;
      final huge = 'y' * (LyricsTranslationService.maxBatchChars * 2);
      final batches = svc.batchesForTest(['short', huge]);
      expect(batches.length, 2);
      expect(batches[1], [huge]);
    });

    test('no line is lost when the split lands mid-lyric', () {
      final svc = LyricsTranslationService.instance;
      final lines = List.generate(37, (i) => 'line number $i ${'z' * 200}');
      final batches = svc.batchesForTest(lines);
      expect(batches.expand((b) => b).toList(), lines);
    });
  });

  group('reply parsing', () {
    test('reads segments back out in order', () {
      final reply = '[[["translated one","x"],["translated two",null]],null]';
      final out = LyricsTranslationService.parseReplyForTest(reply, 2);
      expect(out, ['translated one', 'translated two']);
    });

    test('a short reply is refused, not padded with the last line', () {
      // Padding repeats one real line across the rest of the song, so the lyric
      // comes back silently wrong. A null sends the caller back to the
      // originals, which is at least visibly true.
      final reply = '[[["only one"]]]';
      expect(LyricsTranslationService.parseReplyForTest(reply, 3), isNull);
    });

    test('a long reply is refused rather than trimmed', () {
      // Trimming keeps the right length but on the wrong lines - segment three
      // would be handed to line three whether or not it ever belonged there.
      final reply = '[[["a"],["b"],["c"],["d"]]]';
      expect(LyricsTranslationService.parseReplyForTest(reply, 2), isNull);
    });

    test('garbage in gives nothing out rather than throwing', () {
      expect(LyricsTranslationService.parseReplyForTest('not json', 2), isNull);
      expect(LyricsTranslationService.parseReplyForTest('{}', 2), isNull);
      expect(LyricsTranslationService.parseReplyForTest('[[[]]]', 2), isNull);
    });

    test('a reply carrying a blank line is refused', () {
      // A gap in the batch means the offsets no longer line up.
      expect(
        LyricsTranslationService.parseReplyForTest(
          '[[["one",null],["",null]]]',
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

    test('a romanization with no transliteration field is refused', () {
      expect(
        LyricsTranslationService.parseRomanizedForTest('[[["そうほん"]]]', 1),
        isNull,
      );
    });

    test('romanization refuses a count that does not match', () {
      expect(
        LyricsTranslationService.parseRomanizedForTest(
          '[[["a",null,null,"A"],["b",null,null,"B"]]]',
          3,
        ),
        isNull,
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
