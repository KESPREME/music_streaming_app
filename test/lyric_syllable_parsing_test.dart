import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/services/lyrics/better_lyrics_provider.dart';
import 'package:music_streaming_app/services/lyrics/lyric_sweep.dart';
import 'package:music_streaming_app/utils/lyrics_utils.dart';

/// Apple Music TTML: one <p> per line, one <span> per syllable, spacing left
/// out between the spans of the same word.
const String _ttmlTwoSyllableWord = '''
<?xml version="1.0" encoding="UTF-8"?>
<tt xmlns="http://www.w3.org/ns/ttml">
 <body>
  <div>
   <p begin="00:00.500" end="00:03.000">
    <span begin="00:00.500" end="00:00.900">e</span><span begin="00:00.900" end="00:01.800">nough </span><span begin="00:01.800" end="00:03.000">I </span><span begin="00:03.000" end="00:04.000">wait</span>
   </p>
  </div>
 </body>
</tt>
''';

void main() {
  group('TTML spans glue into words', () {
    final entries = BetterLyricsProvider.parseTtml(_ttmlTwoSyllableWord);

    test('the line parses', () {
      expect(entries.length, 1);
      expect(entries.first.text.trim(), 'enough I wait');
    });

    test('spans without a space between them become ONE word', () {
      // "e" + "nough " is the word "enough" sung over two syllables. Treating
      // each span as a word splits it and lights up at the wrong times.
      final words = entries.first.timedWords;
      expect(words.map((w) => w.text).toList(), ['enough', 'I', 'wait']);
    });

    test('the glued word keeps both syllables', () {
      final enough = entries.first.timedWords.first;
      expect(enough.text, 'enough');
      expect(enough.syllables.length, 2);
      expect(enough.startMs, 500);
      expect(enough.endMs, 1800);
      expect(enough.syllables[0].start, 0);
      expect(enough.syllables[1].start, 1);
      expect(enough.syllables[1].end, 6);
    });

    test('the line reports itself as syllable synced', () {
      expect(entries.first.isSyllableSynced, isTrue);
      expect(entries.first.isWordSynced, isTrue);
    });

    test('the wipe draws across the glued word rather than snapping', () {
      final entry = entries.first;
      // Mid-way through the second syllable of "enough" the wipe must be inside
      // the word, not parked on its first letter.
      final mid = revealedChars(entry, 1350);
      expect(mid, greaterThan(1.0));
      expect(mid, lessThan(6.0));
      // When the word ends the wipe has crossed all six of its letters. By the
      // time the next word's stamp arrives the following space has filled too,
      // which is the gap creep - so it sits at the start of "I", not inside
      // "enough".
      expect(revealedChars(entry, 1799), closeTo(6.0, 0.05));
      expect(revealedChars(entry, 1800), closeTo(7.0, 0.05));
    });

    test('a line with no spans is line-synced only', () {
      const plain = '''
<tt><body><div>
 <p begin="00:02.000" end="00:04.000">just a plain line</p>
</div></body></tt>
''';
      final plainEntries = BetterLyricsProvider.parseTtml(plain);
      expect(plainEntries.length, 1);
      expect(plainEntries.first.text, 'just a plain line');
      expect(plainEntries.first.timedWords, isEmpty);
      // Still fully revealed once its stamp passes - the line-level fallback.
      expect(revealedChars(plainEntries.first, 1000), 0);
      expect(
        revealedChars(plainEntries.first, 2500),
        'just a plain line'.length.toDouble(),
      );
    });
  });

  group('enhanced LRC word tags', () {
    test('word timestamps become interpolatable words', () {
      const lrc =
          '[00:00.00]<00:00.00>hello <00:00.50>world\n[00:05.00]second line';
      final entries = LyricsUtils.parseLrc(lrc);
      expect(entries.length, greaterThanOrEqualTo(2));

      final first = entries.firstWhere(
        (e) => e.text.contains('hello'),
      );
      expect(first.timedWords.map((w) => w.text).toList(),
          ['hello', 'world']);
      expect(first.timedWords.first.startMs, 0);
      expect(first.timedWords.last.startMs, 500);
      // Interpolating across "hello" rather than arriving whole at 0.
      final mid = revealedChars(first, 250);
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(5.0));
    });
  });

  group('plain LRC heuristic', () {
    test('derived words carry their own span so they interpolate', () {
      const lrc = '[00:00.00]one two three four\n[00:10.00]next line';
      final entries = LyricsUtils.parseLrc(lrc);
      final sung = entries.firstWhere((e) => e.text.contains('one'));
      expect(sung.timedWords.length, 4);
      // Every derived word has a non-degenerate span, which is what stops the
      // wipe snapping word to word on guessed timings.
      for (final w in sung.timedWords) {
        expect(w.endMs, greaterThan(w.startMs));
        expect(w.syllables, isNotEmpty);
      }
      // And it moves gradually rather than in four steps.
      final samples = [
        for (var i = 0; i <= 10; i++)
          revealedChars(sung, sung.timeMs + i * 300),
      ];
      final distinct = samples.toSet().length;
      expect(distinct, greaterThan(3),
          reason: 'a guessed-but-interpolated wipe still has steps');
    });
  });
}