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

  // The swell is ONE wave riding the voice: the letter being sung rises as it is
  // sung, the crest is just behind the voice, and the letters behind it fall away
  // slowly. These sample it by "voice": how many letters of the word are sung.
  group('the wave', () {
    // Six letters held three seconds.
    GrowingWord golden() => grown('golden');

    CharGrowth at(GrowingWord w, int letter, double voice) {
      final s = CharGrowth();
      w.sampleInto(letter, w.startMs + 1, s, voice: voice);
      return s;
    }

    test('a letter is untouched until the voice reaches it', () {
      final w = golden();
      for (var i = 0; i < w.length; i++) {
        final s = at(w, i, i.toDouble());
        expect(s.scale, 1);
        expect(s.rise, 0);
        expect(s.bloom, 0);
        expect(s.shift, 0);
      }
    });

    test('the letter under the voice RISES as it is sung', () {
      final w = golden();
      var prev = 1.0;
      for (var d = 0.05; d <= growCrest; d += 0.05) {
        final s = at(w, 2, 2 + d);
        expect(s.scale, greaterThanOrEqualTo(prev - 1e-12),
            reason: 'rising while being sung, d=$d');
        prev = s.scale;
      }
    });

    test('the crest is as the voice leaves the letter, and nothing is higher',
        () {
      final w = golden();
      final crest = at(w, 0, growCrest);
      for (var d = 0.0; d <= 6; d += 0.05) {
        expect(at(w, 0, d).scale, lessThanOrEqualTo(crest.scale + 1e-12));
      }
      expect(crest.scale, greaterThan(1.02));
    });

    test('the letters BEHIND the voice come down, smoothly and slowly', () {
      final w = golden();
      var prev = at(w, 0, growCrest).scale;
      for (var d = growCrest + 0.05; d <= 6; d += 0.05) {
        final s = at(w, 0, d).scale;
        expect(s, lessThanOrEqualTo(prev + 1e-12),
            reason: 'falling behind the crest, d=$d');
        prev = s;
      }
      expect(at(w, 0, 6).scale, closeTo(1, 1e-9),
          reason: 'and back at rest once the wave has passed');
    });

    test('the fall is much longer than the rise - a swell, not a pulse', () {
      // Follow-through: the tail trails off behind the letter in front.
      final w = golden();
      double firstBelowHalf() {
        final crestExtra = at(w, 0, growCrest).scale - 1;
        for (var d = growCrest; d <= 8; d += 0.01) {
          if (at(w, 0, d).scale - 1 < crestExtra / 2) return d - growCrest;
        }
        return 8;
      }

      double risingHalf() {
        final crestExtra = at(w, 0, growCrest).scale - 1;
        for (var d = 0.0; d <= growCrest; d += 0.01) {
          if (at(w, 0, d).scale - 1 >= crestExtra / 2) return d;
        }
        return growCrest;
      }

      expect(firstBelowHalf(), greaterThan(risingHalf() * 1.8));
    });

    test('while the focus moves on to the next letter the previous one goes '
        'down', () {
      // The sea-wave behaviour: one letter coming up, the one before it falling.
      final w = golden();
      final before = [at(w, 1, 2.5), at(w, 2, 2.5)];
      final after = [at(w, 1, 2.9), at(w, 2, 2.9)];
      // Letter 2 (being sung) is rising; letter 1 (behind it) is falling.
      expect(after[1].scale, greaterThan(before[1].scale));
      expect(after[0].scale, lessThan(before[0].scale));
    });

    test('is continuous: moving the voice a hair never makes a letter jump',
        () {
      final w = golden();
      for (var i = 0; i < w.length; i++) {
        var prev = at(w, i, 0);
        for (var v = 0.005; v <= w.length + 6; v += 0.005) {
          final s = at(w, i, v);
          expect((s.scale - prev.scale).abs(), lessThan(0.0015),
              reason: 'letter $i at voice $v');
          expect((s.rise - prev.rise).abs(), lessThan(0.02));
          expect((s.bloom - prev.bloom).abs(), lessThan(0.02));
          prev = s;
        }
      }
    });

    test('is smooth, not merely continuous: the SLOPE has no steps either', () {
      // The difference between a wave and two ramps meeting at a corner.
      final w = golden();
      const h = 0.01;
      double slope(double v) =>
          (at(w, 0, v + h).scale - at(w, 0, v).scale) / h;
      for (var v = 0.0; v < 5; v += h) {
        expect((slope(v + h) - slope(v)).abs(), lessThan(0.12),
            reason: 'slope jumped at voice $v');
      }
    });

    test('neighbouring letters sit at neighbouring heights - one curve along '
        'the word', () {
      final w = golden();
      // Voice a little way into letter 4: letters 0..4 have the wave on them.
      final heights = [
        for (var i = 0; i < 5; i++) at(w, i, 4.5).scale - 1,
      ];
      final peak = heights.reduce((a, b) => a > b ? a : b);
      expect(peak, greaterThan(0.02));
      // The tallest is just behind the voice, and the tail trails off behind it
      // monotonically: a row of towers would not.
      final top = heights.indexOf(peak);
      expect(top, anyOf(3, 4));
      for (var i = 1; i <= top; i++) {
        expect(heights[i], greaterThanOrEqualTo(heights[i - 1] - 1e-12),
            reason: 'the tail behind the crest rises towards it: $heights');
      }
    });

    test('the tail after the word ends is continuous with the word', () {
      // The voice's speed must not change at the word's end, or the wave lurches.
      final w = golden();
      final last = w.length - 1;
      double sungSpeed(int a, int b) =>
          (w.voiceAt(b) - w.voiceAt(a)) / (b - a);
      final before = sungSpeed(w.endMs - 20, w.endMs - 10);
      final after = sungSpeed(w.endMs + 10, w.endMs + 20);
      expect(after, closeTo(before, before * 0.15));
      expect(w.voiceAt(w.endMs).toDouble(), closeTo(w.length.toDouble(), 1e-9));

      final atEnd = CharGrowth();
      w.sampleInto(last, w.endMs, atEnd);
      final done = CharGrowth();
      w.sampleInto(last, w.restsAtMs, done);
      expect(done.scale, closeTo(1, 1e-6), reason: 'and ends at rest');
    });

    test('the voice only ever moves forward through the tail', () {
      final w = golden();
      var prev = w.voiceAt(w.endMs);
      for (var t = w.endMs + 10; t <= w.restsAtMs + 1000; t += 10) {
        final v = w.voiceAt(t);
        expect(v, greaterThan(prev));
        prev = v;
      }
    });

    test('the word stays in the swell\'s hands until the wave has run out', () {
      final w = golden();
      expect(w.isAnimatingAt(w.restsAtMs), isTrue);
      expect(w.isAnimatingAt(w.restsAtMs + 1), isFalse);
      expect(w.isAnimatingAt(w.startMs - 1), isFalse);
      // Long enough for the flat lift (liftRiseMs) to have fallen away.
      expect(w.restsAtMs - w.endMs, greaterThanOrEqualTo(700));
      expect(w.restsAtMs - w.endMs, lessThanOrEqualTo(1500));
    });

    test('without a voice it assumes the word\'s mean pace', () {
      final w = golden();
      final a = CharGrowth();
      final b = CharGrowth();
      w.sampleInto(0, w.startMs + 1500, a);
      w.sampleInto(0, w.startMs + 1500, b, voice: 3.0);
      expect(a.scale, closeTo(b.scale, 1e-9));
    });

    test('even a one-letter hold swells WHILE it is held', () {
      // Letters are no longer only animated after the voice has left them.
      final w = grown('I', heldMs: 2400);
      final s = CharGrowth();
      w.sampleInto(0, w.startMs + 2000, s, voice: 0.83);
      expect(s.scale, greaterThan(1.01));
    });
  });

  group('how much each word has earned', () {
    double crestScale(GrowingWord w, int letter) {
      final s = CharGrowth();
      w.sampleInto(letter, w.startMs + 1, s, voice: letter + growCrest);
      return s.scale;
    }

    test('a word held barely long enough barely moves', () {
      final brief = grown('golden', heldMs: 900);
      final long = grown('golden', heldMs: 3000);
      expect(crestScale(brief, 0) - 1, lessThan((crestScale(long, 0) - 1) * 0.6));
    });

    test('a long word damps its tail', () {
      final w = grown('wonders', heldMs: 3000);
      expect(crestScale(w, w.length - 1), lessThan(crestScale(w, 0)));
    });

    test('a short word swells a little more than a long one', () {
      final short = grown('oh', heldMs: 3000);
      final long = grown('wonders', heldMs: 3000);
      expect(crestScale(short, 0), greaterThan(crestScale(long, 0)));
    });
  });

  group('the lean', () {
    test('letters lean away from the middle', () {
      final w = grown('golden');
      final first = CharGrowth();
      final last = CharGrowth();
      w.sampleInto(0, w.startMs + 1, first, voice: growCrest);
      w.sampleInto(w.length - 1, w.startMs + 1, last,
          voice: w.length - 1 + growCrest);
      expect(first.shift, lessThan(0));
      expect(last.shift, greaterThan(0));
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