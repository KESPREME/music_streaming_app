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

  // The swell is ONE wave riding behind the sweep, not a column per letter. These
  // sample it by "voice": how many letters of the word have been sung.
  group('the wave', () {
    // Six letters held three seconds: a 2s wave, four letters wide.
    GrowingWord golden() => grown('golden');
    double width(GrowingWord w) =>
        (w.restsAtMs - w.endMs) * (w.length / (w.endMs - w.startMs));

    CharGrowth at(GrowingWord w, int letter, double voice) {
      final s = CharGrowth();
      w.sampleInto(letter, w.startMs + 1, s, voice: voice);
      return s;
    }

    test('a letter is exactly at rest the instant it has been sung', () {
      // The handover from the flat word. Anything but rest here is a pop.
      final w = golden();
      for (var i = 0; i < w.length; i++) {
        final s = at(w, i, i + 1.0);
        expect(s.scale, 1);
        expect(s.rise, 0);
        expect(s.bloom, 0);
        expect(s.shift, 0);
      }
    });

    test('a letter is not touched before the voice reaches it', () {
      final w = golden();
      final s = at(w, 3, 2.0);
      expect(s.scale, 1);
      expect(s.rise, 0);
    });

    test('swells as the crest passes over it and peaks half a wave behind the '
        'voice', () {
      final w = golden();
      final crest = at(w, 0, 1 + width(w) / 2);
      final early = at(w, 0, 1 + width(w) * 0.1);
      expect(crest.scale, greaterThan(1.02));
      expect(early.scale, lessThan(crest.scale));
      expect(crest.rise, greaterThan(early.rise));
    });

    test('settles back to rest a full wave behind the voice', () {
      final w = golden();
      final s = at(w, 0, 1 + width(w));
      expect(s.scale, closeTo(1, 1e-9));
      expect(s.rise, closeTo(0, 1e-9));
      expect(s.bloom, closeTo(0, 1e-9));
    });

    test('never dips below the laid-out size, and bloom stays in range', () {
      final w = golden();
      for (var v = 0.0; v <= w.length + width(w); v += 0.05) {
        for (var i = 0; i < w.length; i++) {
          final s = at(w, i, v);
          expect(s.scale, greaterThanOrEqualTo(1 - 1e-9));
          expect(s.bloom, inInclusiveRange(0, 1.3));
        }
      }
    });

    test('is continuous: moving the voice a hair never makes a letter jump',
        () {
      // The tower, as a test. A letter that pops in at 55% of its swell, or
      // steps between frames, fails this.
      final w = golden();
      for (var i = 0; i < w.length; i++) {
        var prev = at(w, i, 0);
        for (var v = 0.01; v <= w.length + width(w); v += 0.01) {
          final s = at(w, i, v);
          expect((s.scale - prev.scale).abs(), lessThan(0.004),
              reason: 'letter $i at voice $v');
          expect((s.rise - prev.rise).abs(), lessThan(0.02));
          expect((s.bloom - prev.bloom).abs(), lessThan(0.02));
          prev = s;
        }
      }
    });

    test('has no zero-slope plateau of its own: height eases in and out', () {
      // sin^2 leaves the ground and returns to it with zero slope - the
      // difference between a swell and a step.
      final w = golden();
      final start = at(w, 0, 1 + 0.01);
      final end = at(w, 0, 1 + width(w) - 0.01);
      expect(start.scale - 1, lessThan(0.0005));
      expect(end.scale - 1, lessThan(0.0005));
    });

    test('neighbouring letters sit at neighbouring heights - one curve along '
        'the word', () {
      final w = golden();
      // Voice at 5 letters: letters 0..4 are sung, and the crest (half a wave,
      // 2 letters, behind the voice) is over letter 3.
      final heights = [
        for (var i = 0; i < 5; i++) at(w, i, 5.0).scale - 1,
      ];
      final peak = heights.reduce((a, b) => a > b ? a : b);
      expect(peak, greaterThan(0.02));
      // The tallest is near the crest, and no neighbour is more than ~60% of
      // the peak away from the next: a row of towers would step from ~0 to ~peak.
      expect(heights.indexOf(peak), anyOf(2, 3));
      for (var i = 1; i < heights.length; i++) {
        expect((heights[i] - heights[i - 1]).abs(), lessThan(peak * 0.65),
            reason: 'letters ${i - 1} and $i: $heights');
      }
    });

    test('the wave runs out after the last letter, and the word stays '
        'animating until it has', () {
      final w = golden();
      expect(w.isAnimatingAt(w.restsAtMs), isTrue);
      expect(w.isAnimatingAt(w.restsAtMs + 1), isFalse);
      expect(w.isAnimatingAt(w.startMs - 1), isFalse);

      final last = w.length - 1;
      final atEnd = CharGrowth();
      w.sampleInto(last, w.endMs, atEnd);
      expect(atEnd.scale, 1, reason: 'the last letter starts from rest');

      final done = CharGrowth();
      w.sampleInto(last, w.restsAtMs, done);
      expect(done.scale, closeTo(1, 1e-6), reason: 'and ends at rest');
    });

    test('without a voice it assumes the word\'s mean pace', () {
      final w = golden();
      final a = CharGrowth();
      final b = CharGrowth();
      w.sampleInto(0, w.startMs + 1500, a);
      w.sampleInto(0, w.startMs + 1500, b, voice: 3.0);
      expect(a.scale, closeTo(b.scale, 1e-9));
    });

    test('the wave\'s width in time is bounded', () {
      final brief = grown('oh', heldMs: 1400);
      final long = grown('oh', heldMs: 6000);
      expect(brief.restsAtMs - brief.endMs, inInclusiveRange(700, 2000));
      expect(long.restsAtMs - long.endMs, 2000);
    });
  });

  group('how much each word has earned', () {
    double crestScale(GrowingWord w, int letter) {
      final span = (w.endMs - w.startMs).toDouble();
      final pace = w.length / span;
      final waveMs = (span * growWaveFraction).clamp(growWaveMinMs, growWaveMaxMs);
      final s = CharGrowth();
      w.sampleInto(letter, w.startMs + 1, s,
          voice: letter + 1 + waveMs * pace / 2);
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
      final crest = 1 + 2.0;
      w.sampleInto(0, w.startMs + 1, first, voice: crest);
      w.sampleInto(w.length - 1, w.startMs + 1, last,
          voice: w.length + 2.0);
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