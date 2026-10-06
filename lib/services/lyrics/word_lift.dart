// lib/services/lyrics/word_lift.dart
// How far the word being sung lifts off the line.
//
// WHY A LIFT AND NOT A CLIP
//
// A clip tells the reader where the voice has got to, which is a horizontal
// fact. It does not tell them the line is *being sung*. In the reference this
// reads as two or three whole lines simply lighting up in turn, because within
// any one line nothing moves vertically: a word halfway through looks the same as
// a word that finished.
//
// A lift is per-word and per-moment. The word under the voice rises a couple of
// dp and comes back down, while its neighbours stay put. That is the difference
// between "this line is highlighted" and "this word is being sung right now", and
// it is the single thing the clip could not express.
//
// THE TWO BEATS
//
// Rising is keyed to the word's own duration but clamped at BOTH ends: it is
// neither longer than [liftRiseMs] nor shorter than [liftRiseMinMs]. A carried
// note does not rise in proportion to how long it is held - it is still one word
// arriving - and a 90ms syllable snapping up over its own 90ms is a twitch, not a
// lift. Falling is a flat [liftRiseMs] because a word stops being sung at an
// instant and then simply settles, with no duration of its own to key off.
// Taking the smaller of the two gives the rise-then-fall shape whichever of them
// is shorter.
//
// THE HEIGHT DEPENDS ON HOW LONG THE WORD WAS HELD
//
// A 90ms syllable and a 900ms held note are both "a word", but only the second
// has anything to show. Lift height eases from [liftFloor] at [liftQuickMs] to a
// full [wordRiseDp] at [liftHeldMs], so an ordinary line differs word to word by a
// little instead of every word rising the same amount.
//
// Note the two 900s mean different things and neither is a typo: [liftHeldMs] is
// how long a word must be HELD to earn the full height, while [liftRiseMs] is how
// long the rise itself takes.

import 'lyric_words.dart' show LyricWord;

/// How far up a fully-held word lifts, in logical pixels.
const double wordRiseDp = 2.0;

/// Longest a word is given to rise, and how long it then takes to settle back
/// down once it is past. Both are 700ms: a word stops being sung at an instant
/// and then settles, so the fall has no duration of its own to key off.
const double liftRiseMs = 700.0;

/// The quickest a word is EVER given to rise. A 90ms syllable snapping up over
/// its own 90ms reads as a twitch, so a short word still gets this much time.
const double liftRiseMinMs = 250.0;

/// A word sung in [liftQuickMs] or less only nudges up by [liftFloor].
const double liftQuickMs = 150.0;

/// How long a word has to be held to earn the whole [wordRiseDp].
const double liftHeldMs = 900.0;

/// The share of the full lift the quickest word still gets.
const double liftFloor = 0.25;

/// How much of the full lift a word of the given held duration earns.
double liftHeight(int heldMs) {
  final through =
      ((heldMs - liftQuickMs) / (liftHeldMs - liftQuickMs)).clamp(0.0, 1.0);
  return liftFloor + (1.0 - liftFloor) * _smooth(through);
}

/// How far word [index] of [line] has lifted at [positionMs], in logical pixels.
///
/// Zero whenever that word is not the one being sung, which is the common case
/// and is what lets the caller draw everything else as one flat run.
double wordLiftPx(List<LyricWord> words, int index, int positionMs) {
  if (index < 0 || index >= words.length) return 0;
  final word = words[index];

  // Outside the word's own window nothing is rising and nothing is settling, so
  // the word is flat. Checked FIRST, because clamping the ramps alone would leave
  // a word sitting at full height for a moment after it ended.
  if (positionMs <= word.startMs) return 0;
  if (positionMs >= word.endMs + liftRiseMs) return 0;

  // Negative when a source's timings disagree; clamped so the rise is a ramp and
  // not an instant jump, and so the height lookup still has a sane input.
  final raw = word.endMs - word.startMs;
  final heldMs = raw < 1 ? 1 : raw;

  // Clamped at BOTH ends, and this matters: a long note does not get a rise
  // proportional to how long it is held (the word is still moving), and a very
  // short one does not rise in 90ms (that is a twitch, not a lift).
  final riseMs = heldMs > liftRiseMs
      ? liftRiseMs
      : heldMs < liftRiseMinMs
          ? liftRiseMinMs
          : heldMs.toDouble();
  final rising = ((positionMs - word.startMs) / riseMs).clamp(0.0, 1.0);
  final falling =
      (1.0 - (positionMs - word.endMs) / liftRiseMs).clamp(0.0, 1.0);

  final progress = rising < falling ? rising : falling;
  if (progress <= 0) return 0;
  return liftHeight(heldMs) * _smooth(progress) * wordRiseDp;
}

/// How much of word [index]'s lift is still left at [positionMs]: its full
/// [liftHeight] while it is being sung, easing to zero over [liftRiseMs] once it
/// is past.
///
/// Split out of [wordLiftPx] because a word animated letter by letter has its own
/// way up but settles back down the same way every other word does - the fall is
/// the half of the movement the two share. A grown letter comes to rest at exactly
/// the lift [wordLiftPx] hands over to, so the two agree and the cheaper whole-word
/// slice can take over without a step.
double wordFall(List<LyricWord> words, int index, int positionMs) {
  if (index < 0 || index >= words.length) return 0;
  final word = words[index];
  final falling =
      (1.0 - (positionMs - word.endMs) / liftRiseMs).clamp(0.0, 1.0);
  return liftHeight(word.endMs - word.startMs) * _smooth(falling);
}

/// Index of the word under [positionMs], or -1 when none is.
///
/// Read once per frame so the caller can decide whether there is anything to
/// animate at all without walking every word twice.
int activeWordAt(List<LyricWord> words, int positionMs) {
  for (var i = 0; i < words.length; i++) {
    if (positionMs >= words[i].startMs && positionMs <= words[i].endMs) {
      return i;
    }
  }
  return -1;
}

/// Ease in and out of the ends, so the lift has no corners on it.
double _smooth(double fraction) =>
    fraction * fraction * (3.0 - 2.0 * fraction);
