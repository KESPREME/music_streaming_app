import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/services/lyrics/lyric_words.dart';
import 'package:music_streaming_app/services/lyrics/word_lift.dart';

LyricWord _word(String text, int startMs, int endMs) =>
    LyricWord(startMs: startMs, endMs: endMs, text: text);

void main() {
  group('the lift itself', () {
    final w = _word('golden', 1000, 2000);

    test('is flat before the word starts', () {
      expect(wordLiftPx([w], 0, 999), 0);
      // At its own start stamp too, not merely before it.
      expect(wordLiftPx([w], 0, 1000), 0);
    });

    test('settles back to flat exactly one settle-length after it ends', () {
      // Pinned on BOTH sides of the boundary, not at some point well past it.
      // "Eventually zero" cannot tell a 700ms settle from a 9000ms one - a
      // suite that only checks the far end of the fall pins nothing about it.
      final settle = liftRiseMs.toInt();
      expect(
        wordLiftPx([w], 0, 2000 + settle - 1),
        greaterThan(0),
        reason: 'still settling one millisecond before the settle is up',
      );
      expect(
        wordLiftPx([w], 0, 2000 + settle),
        0,
        reason: 'flat the moment the settle is up',
      );
    });

    test('the settle is halfway down half a settle-length after the end', () {
      // The shape, not just the endpoints. With the settle at 700ms this is
      // smooth(0.5) = exactly half the full height; stretch it to 900ms and the
      // word is still at two thirds, which is a slower, lazier fall.
      expect(wordLiftPx([w], 0, 2000 + (liftRiseMs / 2).toInt()),
          closeTo(wordRiseDp / 2, 0.02));
    });

    test('rises partway through the word', () {
      final lift = wordLiftPx([w], 0, 1500);
      expect(lift, greaterThan(0));
      expect(lift, lessThanOrEqualTo(wordRiseDp));
    });

    test('peaks when the rise completes, not at the start', () {
      // A word that jumped to full height the instant it began would read as a
      // flash. The peak is where the RISE finishes - 700ms in, clamped to the
      // word's own duration for a quicker one.
      final atStart = wordLiftPx([w], 0, 1001);
      final atPeak = wordLiftPx([w], 0, 1700);
      expect(atPeak, greaterThan(atStart));
      expect(atPeak, closeTo(wordRiseDp, 0.01));
    });

    test('holds full height until the word actually ends', () {
      // The fall is driven by the word's END, so a word at its last millisecond
      // is still at full height. Falling earlier would make the lift land before
      // the voice stops.
      expect(wordLiftPx([w], 0, 1999), closeTo(wordRiseDp, 0.01));
    });

    test('never exceeds the full rise', () {
      for (var t = 1000; t <= 2000; t += 10) {
        expect(wordLiftPx([w], 0, t), lessThanOrEqualTo(wordRiseDp + 0.0001));
        expect(wordLiftPx([w], 0, t), greaterThanOrEqualTo(0));
      }
    });
  });

  group('rise time is bounded at both ends, not fixed', () {
    test('a very short word still gets a minimum time to rise', () {
      // A 90ms syllable does NOT snap up over its own 90ms - it gets a 250ms
      // floor. Without the floor it travels from the line to the top of its own
      // (low) height inside 90ms, which reads as a twitch rather than a lift.
      //
      // So the assertion is that it has NOT finished rising at its last
      // millisecond. "Greater than zero" would pass under either behaviour,
      // which is why this pins a ceiling too.
      final quick = _word('I', 1000, 1090);
      final atItsEnd = wordLiftPx([quick], 0, 1090);
      expect(atItsEnd, greaterThan(0));
      expect(
        atItsEnd,
        lessThan(wordRiseDp * liftFloor / 2),
        reason: 'a 90ms word must not complete its whole rise in 90ms',
      );
      expect(wordLiftPx([quick], 0, 1001), lessThan(atItsEnd),
          reason: 'and it still has to be on its way up at the start');
    });

    test('a long word takes the full ramp', () {
      final long = _word('wonderful', 1000, 2000);
      expect(wordLiftPx([long], 0, 1200), greaterThan(0));
      // A word held well past the ramp does not get a slower rise because it is
      // longer - it is still one word arriving, so the ramp stays put.
      expect(wordLiftPx([long], 0, 1700), closeTo(wordRiseDp, 0.01));
    });
  });

  group('lift height depends on how long the word was held', () {
    test('a quick word barely lifts', () {
      // Otherwise every word in an ordinary line rises the same and the
      // emphasis means nothing.
      expect(liftHeight(90), lessThan(liftHeight(900)));
      expect(liftHeight(90), closeTo(liftFloor, 0.01));
      expect(liftHeight(2000), closeTo(1.0, 0.01));
    });

    test('the height eases between the two ends', () {
      final low = liftHeight(200);
      final mid = liftHeight(500);
      final high = liftHeight(900);
      expect(low, lessThan(mid));
      expect(mid, lessThan(high));
    });

    test('nothing is clamped out of range', () {
      expect(liftHeight(0), closeTo(liftFloor, 0.01));
      expect(liftHeight(999999), closeTo(1.0, 0.01));
    });
  });

  group('only one word lifts at a time', () {
    final words = [
      _word('so', 1000, 1400),
      _word('here', 1500, 2200),
      _word('I', 2300, 2500),
    ];

    test('the word under the clock is the one that lifts', () {
      expect(activeWordAt(words, 1600), 1);
      expect(activeWordAt(words, 1000), 0);
      expect(activeWordAt(words, 2350), 2);
    });

    test('the sung word rises while the one before it falls', () {
      // THE REGRESSION THIS PINS. A clip lights a horizontal prefix, so a
      // finished word and a word being sung look alike and the line reads as
      // lighting up whole.
      //
      // Not "the sung word is higher" - that is not true and should not be: a
      // short word leaves a long fall behind it, so for a moment the previous
      // word is still above the one being sung. What separates them is the
      // DIRECTION. One is going up and one is coming down, so the eye reads
      // motion rather than a highlight.
      final at = 1600;
      final active = activeWordAt(words, at);
      final activeNow = wordLiftPx(words, active, at);
      final activeLater = wordLiftPx(words, active, at + 60);

      final previousNow = wordLiftPx(words, active - 1, at);
      final previousLater = wordLiftPx(words, active - 1, at + 60);

      expect(activeLater, greaterThan(activeNow),
          reason: 'the word being sung must be on its way up');
      expect(previousLater, lessThan(previousNow),
          reason: 'the word before it must be on its way down');
    });

    test('the word before is settling down, not flat and not lifted', () {
      // It ended at 1400 and is inside its 700ms settle, so it is on its way back
      // to the line. This is what makes the movement read as continuous instead
      // of as a word blinking in and out.
      final settling = wordLiftPx(words, 0, 1600);
      expect(settling, greaterThan(0));
      expect(settling, lessThan(wordRiseDp));
    });

    test('the fall is monotonic all the way back to the line', () {
      // Sampled across the whole settle, so a curve that overshoots or stalls
      // cannot pass by being right at one instant. Stepped to the end of the
      // settle rather than to "some time later", so it also proves the fall
      // finishes where it claims to.
      var previous = wordRiseDp + 1;
      final settleEnd = 1400 + liftRiseMs.toInt();
      for (var t = 1400; t <= settleEnd; t += 25) {
        final lift = wordLiftPx(words, 0, t);
        expect(lift, lessThanOrEqualTo(previous + 0.0001));
        previous = lift;
      }
      expect(previous, 0);
    });

    test('a word well before the line is flat', () {
      // Far enough outside its window that it is not even settling.
      expect(wordLiftPx(words, 0, 500), 0);
      expect(wordLiftPx(words, 2, 500), 0);
    });

    test('a gap between words lifts nothing ahead of it', () {
      expect(activeWordAt(words, 1450), -1);
      // Word 0 ended at 1400 so it is still settling, which is correct. Nothing
      // AHEAD of the gap has started: a word that rose before the voice reached
      // it would be the lift lying about where the singing is.
      expect(wordLiftPx(words, 0, 1450), greaterThan(0));
      expect(wordLiftPx(words, 1, 1450), 0);
      expect(wordLiftPx(words, 2, 1450), 0);
    });
  });

  group('the settle a grown word shares', () {
    final w = _word('golden', 1000, 2000);

    test('is the whole lift while the word is still being sung', () {
      // A letter animated one at a time rises on its own schedule but comes back
      // down with every other word. This is that half of the movement.
      expect(wordFall([w], 0, 1000), closeTo(1.0, 0.01));
      expect(wordFall([w], 0, 1500), closeTo(1.0, 0.01));
      expect(wordFall([w], 0, 2000), closeTo(1.0, 0.01));
    });

    test('eases to zero across the settle and is flat after it', () {
      expect(wordFall([w], 0, 2350), closeTo(0.5, 0.02));
      expect(wordFall([w], 0, 2000 + liftRiseMs.toInt()), 0);
      expect(wordFall([w], 0, 2000 + liftRiseMs.toInt() + 500), 0);
    });

    test('hands a grown letter over to the plain word lift without a step', () {
      // THE HANDOVER. Once a grown word is done being grown it is drawn by the
      // cheap whole-word slice, which reads [wordLiftPx]. A letter resting at the
      // end of its swell sits at `growRest` times the word's settle, and that has
      // to equal what the plain slice gives - otherwise the word jumps at the
      // instant the two swap, which is exactly the seam this split creates.
      final atRest = 2000;
      expect(
        wordLiftPx([w], 0, atRest),
        closeTo(wordFall([w], 0, atRest) * wordRiseDp, 0.0001),
        reason: 'a settled grown letter must land where the plain word lands',
      );
    });

    test('a short word settles no slower than a long one, proportionally', () {
      // The settle carries the word's HEIGHT, so a quick word comes down from a
      // lower place over the same time rather than taking longer to get there.
      final quick = _word('I', 1000, 1090);
      expect(wordFall([quick], 0, 1090), closeTo(liftFloor, 0.01));
      expect(wordFall([quick], 0, 1090 + (liftRiseMs / 2).toInt()),
          closeTo(liftFloor / 2, 0.02));
    });

    test('defensive: out-of-range is flat, not a crash', () {
      final words = [w];
      expect(wordFall(words, 99, 1500), 0);
      expect(wordFall(words, -1, 1500), 0);
      expect(wordFall(const [], 0, 1500), 0);
    });
  });

  group('defensive', () {
    test('an out-of-range index is flat, not a crash', () {
      final words = [_word('a', 0, 1000)];
      expect(wordLiftPx(words, 99, 500), 0);
      expect(wordLiftPx(words, -1, 500), 0);
    });

    test('an empty line lifts nothing and names no active word', () {
      expect(activeWordAt(const [], 500), -1);
      expect(wordLiftPx(const [], 0, 500), 0);
    });

    test('a zero-length word produces no NaN', () {
      final broken = _word('hmm', 500, 500);
      final lift = wordLiftPx([broken], 0, 500);
      expect(lift.isNaN, isFalse);
      expect(lift, greaterThanOrEqualTo(0));
    });

    test('a word whose end precedes its start produces no NaN', () {
      // A source whose timings disagree with each other must not put NaN into a
      // Transform, which renders as nothing at all.
      final broken = _word('hmm', 2000, 1000);
      final lift = wordLiftPx([broken], 0, 1500);
      expect(lift.isNaN, isFalse);
    });
  });
}