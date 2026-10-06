import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/services/lyrics/lyric_growth.dart';
import 'package:music_streaming_app/services/lyrics/lyric_words.dart';

LyricWord word(String text, int startMs, int endMs) =>
    LyricWord(startMs: startMs, endMs: endMs, text: text);

/// Long enough that the word has earned close to the full treatment.
GrowingWord grown(String text, {int heldMs = 3000, int startMs = 0}) =>
    GrowingWord(0, word(text, startMs, startMs + heldMs));

void main() {
  group('qualifying', () {
    test('a long-held short word qualifies', () {
      expect(canGrow(word('oh', 0, 2000)), isTrue);
      expect(canGrow(word('golden', 0, 3000)), isTrue);
    });

    test('a word merely being sung does not', () {
      // The whole point of the steep thresholds: a word sung at an ordinary pace
      // has nothing to show, and animating it anyway makes the whole lyric twitch.
      expect(canGrow(word('oh', 0, 400)), isFalse);
      expect(canGrow(word('golden', 0, 900)), isFalse);
    });

    test('a long word held a second is still just being sung', () {
      expect(canGrow(word('wonderful', 0, 1000)), isFalse);
    });

    test('an empty word never qualifies', () {
      expect(canGrow(word('   ', 0, 3000)), isFalse);
    });

    test('past seven letters it reads as a ripple', () {
      expect(canGrow(word('extraordinarily', 0, 5000)), isFalse);
    });

    test('a hyphenated word would break at the hyphen', () {
      // Really two words; growing one letter would tear it at the joint.
      expect(canGrow(word('half-slow', 0, 3000)), isFalse);
    });

    test('block scripts are left alone', () {
      // Kana draw as blocks, so moving one letter would come apart.
      expect(canGrow(word('ねこ', 0, 3000)), isFalse);
      expect(canGrow(word('我很好', 0, 3000)), isFalse);
      expect(canGrow(word('안녕', 0, 3000)), isFalse);
    });

    test('joined scripts are left alone', () {
      // Arabic letters join, so they are not independent boxes to move.
      expect(canGrow(word('سلام', 0, 3000)), isFalse);
    });

    test('Latin with an accent still qualifies', () {
      expect(canGrow(word('naïve', 0, 3000)), isTrue);
    });

    test('short words are held to a stricter bar than length alone suggests', () {
      // Two letters must clear the flat short-word bar; seven must clear a
      // per-letter ramp, so the same second is a held note for one and an
      // ordinary pace for the other.
      expect(canGrow(word('no', 0, 1000)), isFalse);
      expect(canGrow(word('no', 0, 1400)), isTrue);
      expect(canGrow(word('tonight', 0, 1000)), isFalse);
      // 200ms per letter, so seven letters need 1400ms.
      expect(canGrow(word('tonight', 0, 1400)), isTrue);
    });

    test('a long word needs time proportional to its letters', () {
      expect(canGrow(word('tonight', 0, 1399)), isFalse);
      expect(canGrow(word('tonight', 0, 1400)), isTrue);
    });
  });

  group('letter list', () {
    test('is indexed the same way the renderer measures', () {
      // The renderer walks the caret per code unit, so the letter list must be
      // too or the swell lands a character away from its glyph.
      final w = grown('abc');
      expect(w.length, 3);
      expect(canGrow(word('abc', 0, 3000)), isTrue);
    });

    test('ignores surrounding whitespace when measuring', () {
      expect(grown(' oh ', heldMs: 2000).length, 2);
    });
  });

  group('the three beats', () {
    final w = grown('golden', heldMs: 3000);
    final sample = CharGrowth();

    test('starts at rest, unswollen', () {
      w.sampleInto(0, w.startMs - 1, sample);
      expect(sample.scale, 1.0);
      expect(sample.bloom, 0.0);
    });

    test('swells up partway through the hold', () {
      // First letter, a quarter of the way through its own move.
      final span = (w.endMs - w.startMs).toDouble();
      w.sampleInto(0, w.startMs + (span * growSpan * 0.5).round(), sample);
      expect(sample.scale, greaterThan(1.0));
      expect(sample.bloom, greaterThan(0.0));
    });

    test('holds at its peak rather than oscillating', () {
      final span = (w.endMs - w.startMs).toDouble();
      final first = CharGrowth();
      final second = CharGrowth();
      // Either side of the middle of the hold window.
      w.sampleInto(0, w.startMs + (span * growSpan * 0.26).round(), first);
      w.sampleInto(0, w.startMs + (span * growSpan * 0.29).round(), second);
      expect(first.scale, second.scale);
    });

    test('settles back to the ordinary sung-word lift', () {
      // Long past the move: back to scale 1 and the plain lift, not to nothing.
      w.sampleInto(0, w.restsAtMs + 5000, sample);
      expect(sample.scale, 1.0);
      expect(sample.rise, growRest);
      expect(sample.bloom, 0.0);
      expect(sample.shift, 0.0);
    });

    test('scale never dips below the laid-out size mid-move', () {
      // A swell that shrank past 1 would read as the letter deflating.
      final span = (w.endMs - w.startMs).toDouble();
      for (var t = 0.0; t <= 1.0; t += 0.02) {
        w.sampleInto(
          0,
          w.startMs + (span * growSpan * t).round(),
          sample,
        );
        expect(sample.scale, greaterThanOrEqualTo(1.0));
      }
    });

    test('bloom stays within its own range', () {
      final span = (w.endMs - w.startMs).toDouble();
      for (var t = 0.0; t <= 1.0; t += 0.02) {
        w.sampleInto(
          2,
          w.startMs + (span * growSpan * t).round(),
          sample,
        );
        expect(sample.bloom, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('the stagger', () {
    test('later letters start later, so movement travels along the word', () {
      final w = grown('golden', heldMs: 3000);
      final span = (w.endMs - w.startMs).toDouble();
      // A point where the first letter is moving but the last has not begun.
      final at = w.startMs + (span * growSpan * 0.30).round();
      final first = CharGrowth();
      final last = CharGrowth();
      w.sampleInto(0, at, first);
      w.sampleInto(w.length - 1, at, last);
      expect(first.scale, greaterThan(last.scale));
    });

    test('the word is still animating right up to its rest', () {
      final w = grown('golden', heldMs: 3000);
      expect(w.isAnimatingAt(w.startMs), isTrue);
      expect(w.isAnimatingAt(w.restsAtMs), isTrue);
      expect(w.isAnimatingAt(w.restsAtMs + 1), isFalse);
      expect(w.isAnimatingAt(w.startMs - 1), isFalse);
    });
  });

  group('how much each word has earned', () {
    test('a word held barely long enough barely moves', () {
      // The ramp is cubed so that under a second is nearly nothing. Getting this
      // wrong is what makes every word twitch.
      final brief = grown('golden', heldMs: 900);
      final long = grown('golden', heldMs: 3000);
      final a = CharGrowth();
      final b = CharGrowth();
      brief.sampleInto(0, brief.startMs + (900 * growSpan * 0.3).round(), a);
      long.sampleInto(0, long.startMs + (3000 * growSpan * 0.3).round(), b);
      expect(a.scale, lessThan(b.scale));
    });

    test('a long word damps its tail', () {
      // Otherwise the last letters are still swelling after the singer moved on.
      final w = grown('golden', heldMs: 9000);
      final span = (w.endMs - w.startMs).toDouble();
      final first = CharGrowth();
      final last = CharGrowth();
      final at = w.startMs + (span * growSpan * 0.29).round();
      w.sampleInto(0, at, first);
      w.sampleInto(w.length - 1, at, last);
      expect(last.scale, lessThan(first.scale));
    });

    test('a short word swells a little more than a long one', () {
      // Fewer letters to do it with, so each carries more.
      final short = grown('oh', heldMs: 3000);
      final long = grown('golden', heldMs: 3000);
      final a = CharGrowth();
      final b = CharGrowth();
      short.sampleInto(0, (short.startMs + 3000 * growSpan * 0.29).round(), a);
      long.sampleInto(0, (long.startMs + 3000 * growSpan * 0.29).round(), b);
      expect(a.scale, greaterThan(b.scale));
    });
  });

  group('the lean', () {
    test('letters lean away from the middle', () {
      // So the word opens outwards rather than every letter sliding one way.
      //
      // Each letter is sampled at ITS OWN peak. Sampling them all at one instant
      // would measure the stagger instead of the lean: late letters have not
      // started yet by then, and their shift would read as zero.
      final w = grown('golden', heldMs: 3000);
      final span = (w.endMs - w.startMs).toDouble();
      final peakPhase = (growIn + growHold) / 2;
      int at(int charIndex) => w.startMs +
          (span * charIndex * growStagger + span * growSpan * peakPhase)
              .round();

      final first = CharGrowth();
      final mid = CharGrowth();
      final last = CharGrowth();
      w.sampleInto(0, at(0), first);
      w.sampleInto(3, at(3), mid);
      w.sampleInto(w.length - 1, at(w.length - 1), last);
      expect(first.shift, lessThan(0));
      expect(last.shift, greaterThan(0));
      expect(mid.shift.abs(), lessThan(first.shift.abs()));
    });
  });

  group('collecting the held words on a line', () {
    test('finds only the ones that earned it', () {
      final words = [
        word('quick', 0, 300), // sung fast, no treatment
        word('golden', 400, 3400), // held
        word('hour', 3500, 3900), // too short to qualify
      ];
      final growing = growingWordsOf(words);
      expect(growing.length, 1);
      expect(growing.first.index, 1);
      expect(growing.first.text, 'golden');
    });

    test('a line with none costs nothing', () {
      final words = [word('a', 0, 100), word('b', 200, 400)];
      expect(growingWordsOf(words), isEmpty);
      expect(isGrowingAt(growingWordsOf(words), 300), isFalse);
    });

    test('reports whether anything on the line is mid-flight', () {
      final words = [word('golden', 0, 3000)];
      final growing = growingWordsOf(words);
      expect(isGrowingAt(growing, 1500), isTrue);
      expect(isGrowingAt(growing, 10000), isFalse);
    });
  });

  group('defensive', () {
    test('an out-of-range letter is ignored rather than throwing', () {
      // Per-frame sampling computes indices from timings; a source that disagrees
      // with its own text must not crash the lyric.
      final w = grown('abc');
      final sample = CharGrowth();
      expect(() => w.sampleInto(99, 1500, sample), returnsNormally);
      expect(() => w.sampleInto(-1, 1500, sample), returnsNormally);
      expect(sample.scale, 1.0);
    });

    test('a zero-length word cannot produce a NaN', () {
      final w = GrowingWord(0, word('ab', 500, 500));
      final sample = CharGrowth();
      expect(() => w.sampleInto(0, 500, sample), returnsNormally);
      expect(sample.scale.isNaN, isFalse);
      expect(sample.rise.isNaN, isFalse);
    });
  });
}