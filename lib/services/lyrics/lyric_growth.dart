// lib/services/lyrics/lyric_growth.dart
// The letter-by-letter swell on a word the singer is holding.
//
// WHY THIS EXISTS
//
// A word carried for a second and a half is the one moment in a line where there
// is time to watch something happen to it. Drawn the same as the syllables either
// side, a held note reads as a pause in the highlight - the sweep stops, the line
// looks stuck, and the singer sounds like they stopped too. Animating each letter
// in turn says "still holding" without adding a single word to the lyric.
//
// RARE BY DESIGN. Most lines have no qualifying word at all and pay nothing. The
// thresholds are deliberately steep, because the failure mode of getting this
// wrong is not "too subtle", it is "every word twitches" - a lyric that pulses
// constantly stops being readable and starts being noisy.
//
// A WAVE THAT TRAILS THE VOICE
//
// The swell is a single smooth wave riding behind the sweep: a letter starts at
// rest the instant the voice has fully sung it, swells to its peak as the wave
// crest passes over it, and settles back as the crest moves on. Neighbouring
// letters are always part-way through the same curve, so the height along the
// word is a continuous swell like a sea wave - never a row of separate columns.
//
// WHY NOT THE OLD STAGGERED TRAPEZOID
//
// Each letter used to run its own swell-hold-settle on a clock that began with
// the WORD, not with the letter being sung. A letter was drawn flat until the
// voice reached it and then snapped in part-way up its swell, and it also dropped
// from the flat word's lift to nothing before climbing again. On a long hold that
// is a tower: columns shooting up as the voice reaches each letter, standing
// there, and falling together. The wave is a function of how far the voice is
// past each letter, so it is zero at the handover and everything is continuous.
//
// THE PEAKS DIFFER LETTER BY LETTER
//
// Later letters move and light less. Two reasons, both from the reference: a long
// word is many letters to run a wave through, and left flat its tail is still
// swelling after the singer has moved on; and a word only just held long enough
// to qualify has no room for a wave, so it is damped towards a single swell.
//
// The lift is READ OFF the swell rather than set separately, so a letter that
// grows more also rises more. That is what keeps the two reading as one movement
// rather than two things happening at once.
//
// PURE ARITHMETIC, NO FLUTTER
//
// Nothing here imports Flutter. The peaks depend only on the word - its length
// and how long it is held - so they are computed once per word and the frame only
// asks where in its move a given letter has got to. That is what makes this
// testable without a widget test, and why it lives in services rather than
// widgets.

import 'dart:math' as math;

import 'lyric_words.dart' show LyricWord;

/// Where one letter of a held word has got to.
///
/// Written into rather than returned: this runs for every letter of the word on
/// every frame, and a line's worth of throwaway objects per frame is a cost with
/// nothing to show for it.
class CharGrowth {
  /// Swell about the letter's own centre. 1 is the letter as laid out.
  double scale = 1;

  /// Lean away from the middle of the word, in ems.
  double shift = 0;

  /// Lift, in multiples of the ordinary sung-word rise.
  double rise = 0;

  /// Bloom, 0..1, peaking partway up rather than at the top.
  double bloom = 0;
}

/// Letters, by UTF-16 code unit.
///
/// Deliberately code units rather than grapheme clusters. The renderer positions
/// each letter using the caret advances it measured per code unit, so a
/// grapheme-indexed list here would put the swell a character out of step with the
/// glyph it is meant to be on - and nothing would fail, it would just be visibly
/// wrong. Letters are also excluded from growth by script below, so the two
/// readings only ever differ for text that never animates anyway.
List<String> _lettersOf(String text) => <String>[
      for (var i = 0; i < text.length; i++) text[i],
    ];

/// One word held long enough to be animated a letter at a time.
class GrowingWord {
  GrowingWord(this.index, LyricWord word)
      : startMs = word.startMs,
        endMs = word.endMs,
        text = word.text {
    final letters = _lettersOf(text.trim());
    final chars = letters.length;
    _scalePeak = List<double>.filled(chars, 1);
    _shiftPeak = List<double>.filled(chars, 0);
    _risePeak = List<double>.filled(chars, 0);
    _bloomPeak = List<double>.filled(chars, 0);

    final held = (endMs - startMs) > 1 ? (endMs - startMs).toDouble() : 1.0;
    // How much of the full treatment this word has earned. Cubed, so the
    // difference between a word held one second and one held three is most of the
    // range, and everything under a second is barely anything.
    var fraction =
        (held - growRampMinMs) / (growRampMaxMs - growRampMinMs);
    fraction = fraction < 0 ? 0.0 : (fraction > 1 ? 1.0 : fraction);
    final earned = fraction * fraction * fraction;

    final decay = _decayRate(chars, held);
    final bloomPace = held / growBloomPaceMs;
    final pace = bloomPace > growBloomPaceMax ? growBloomPaceMax : bloomPace;
    final bloomSpread = switch (chars) {
      <= 3 => growBloomShort,
      >= 6 => growBloomLong,
      _ => 1.0,
    };
    // Short words swell a little more, having fewer letters to do it with.
    final base = chars <= 3 ? growBaseShort : growBaseLong;
    final liftRaw = held / growLiftPaceMs;
    final liftPace = liftRaw < growLiftFloor
        ? growLiftFloor
        : (liftRaw > 1 ? 1.0 : liftRaw);

    for (var i = 0; i < chars; i++) {
      final place = chars > 1 ? i / (chars - 1) : 0.0;
      final reach = earned * (1 - place * decay);
      final scale = 1 + base + reach * growScaleRange;
      _scalePeak[i] = scale * growScaleTrim;
      _bloomPeak[i] =
          (growBloomFloor + reach * growBloomRange) * pace * bloomSpread;
      // Read the lift off the swell, so the two cannot disagree.
      _risePeak[i] = ((scale - 1) / growScaleCeiling) * liftPace;
      // Letters lean away from the middle, so the word opens outwards rather
      // than every letter sliding the same way.
      final centre = (i + 0.5) / chars;
      _shiftPeak[i] =
          (centre - 0.5) * 2 * (scale - 1) * growShiftEm * growScaleTrim;
    }

    // The wave's temporal width: long enough to read as a swell, short enough
    // that the word has settled by the time the singer has moved on.
    final waveMs = (held * growWaveFraction)
        .clamp(growWaveMinMs, growWaveMaxMs)
        .toDouble();
    // The same width in letters, at the word's own pace.
    _waveLetters = waveMs * (chars / held);
    restsAtMs = endMs + waveMs.round();
  }
  /// Which of the line's words this is.
  final int index;

  final int startMs;
  final int endMs;
  final String text;

  /// When the wave has finished passing over the last letter.
  late final int restsAtMs;

  late final List<String> _letters = _lettersOf(text.trim());
  late final List<double> _scalePeak;
  late final List<double> _shiftPeak;
  late final List<double> _risePeak;
  late final List<double> _bloomPeak;

  int get length => _letters.length;

  /// Whether any letter of this word is mid-flight at [positionMs].
  bool isAnimatingAt(int positionMs) =>
      positionMs >= startMs && positionMs <= restsAtMs;

  /// How wide the wave is, in letters.
  late final double _waveLetters;

  /// Where letter [charIndex] has got to at [positionMs], written into [into].
  ///
  /// [voice] is how many letters of the word have been sung, fractional, as the
  /// sweep has them - passing it locks the wave to the fill exactly. Without it
  /// the voice is assumed to move at the word's mean pace.
  ///
  /// After the word ends the voice is carried on at that same pace, so the wave
  /// runs out over its own width instead of stopping mid-swell or being cut off.
  ///
  /// [into.rise] is the EXTRA lift over the ordinary sung-word lift (in
  /// multiples of it), not a replacement for it: the caller adds the two, so a
  /// letter handed over from the flat word keeps the height it had.
  /// [into.shift] comes back in ems, so the caller converts once using the size
  /// it is actually drawing at.
  void sampleInto(
    int charIndex,
    int positionMs,
    CharGrowth into, {
    double? voice,
  }) {
    if (charIndex < 0 || charIndex >= _letters.length) return;
    final n = _letters.length;
    final held = (endMs - startMs) > 1 ? (endMs - startMs).toDouble() : 1.0;

    final double sung;
    if (positionMs > endMs) {
      sung = n + (positionMs - endMs) * (n / held);
    } else {
      sung = voice ?? n * (positionMs - startMs) / held;
    }

    // How far the voice is past this letter's end, as a fraction of the wave.
    final past = sung - (charIndex + 1);
    final x = _waveLetters <= 0
        ? 1.0
        : (past <= 0 ? 0.0 : (past >= _waveLetters ? 1.0 : past / _waveLetters));
    // sin^2: zero at both ends WITH zero slope, so the letter eases into the
    // swell and out of it, and the crest passes over it at x = 0.5.
    final wave = 0.5 * (1 - math.cos(2 * math.pi * x));

    into.scale = 1 + (_scalePeak[charIndex] - 1) * wave;
    into.shift = _shiftPeak[charIndex] * wave;
    into.rise = _risePeak[charIndex] * wave;
    into.bloom = _bloomPeak[charIndex] * wave;
  }
  /// How much of the movement is taken back off the later letters.
  ///
  /// Two reasons, both from the reference. A long word is a lot of letters to run
  /// a wave through. And a word held only just long enough to qualify has no room
  /// for a wave, so the whole thing is damped towards one swell.
  static double _decayRate(int length, double heldMs) {
    final isLong = length > growDecayLongChars;
    final isQuick = heldMs < growDecayQuickMs;
    if (!isLong && !isQuick) return 0;
    var strength = 0.0;
    if (isLong) {
      final extra = (length - growDecayLongChars) / 5.0;
      strength += (extra < 1 ? extra : 1) * growDecayLong;
    }
    if (isQuick) {
      var short = 1 - (heldMs - growDecayQuickFloorMs) / 400;
      if (short < 0) short = 0;
      strength += short * (length > 3 ? growDecayQuick : growDecayQuickTiny);
    }
    return strength > growDecayMax ? growDecayMax : strength;
  }
}

/// Longest word worth running a wave through; past this it reads as a ripple.
const int growMaxChars = 7;

/// How long a word of each length must be held before it qualifies.
///
/// Steeper for short words than length alone suggests: a two-letter word held a
/// second is a held note, while a seven-letter one held the same second is just
/// being sung at an ordinary pace, and only the first has anything to show.
const int growMinSoloMs = 1100;
const int growMinShortMs = 1360;
const int growMinShortStepMs = 140;
const int growMinFourMs = 1050;
const int growMinLongMs = 900;
const int growMsPerChar = 200;

/// Decay tuning.
const int growDecayLongChars = 5;
const double growDecayQuickMs = 1200;
const double growDecayQuickFloorMs = 800;
const double growDecayLong = 0.4;
const double growDecayQuick = 0.3;
const double growDecayQuickTiny = 0.1;
const double growDecayMax = 0.7;

/// The wave's width in time: this fraction of the hold, within these bounds.
const double growWaveFraction = 0.7;
const double growWaveMinMs = 700;
const double growWaveMaxMs = 2000;
/// How much of the treatment a word has earned, from how long it is held.
const double growRampMinMs = 400;
const double growRampMaxMs = 3000;

/// Swell tuning.
const double growBaseShort = 0.05;
const double growBaseLong = 0.04;
const double growScaleRange = 0.08;
const double growScaleCeiling = 0.1;
const double growScaleTrim = 0.98;

/// Lean, in ems at the largest swell.
const double growShiftEm = 25 / 34;

/// Bloom tuning.
const double growBloomFloor = 0.35;
const double growBloomRange = 0.45;
const double growBloomPaceMs = 1500;
const double growBloomPaceMax = 1.1;
const double growBloomShort = 0.85;
const double growBloomLong = 1.1;

/// How fast a word is allowed to lift, from how long it is held.
const double growLiftPaceMs = 2000;
const double growLiftFloor = 0.3;

/// Whether [word] is held long enough, and short enough, to animate a letter at
/// a time.
///
/// Scripts whose letters are not laid out side by side independently are left
/// alone. Han, kana and Hangul draw as blocks and right-to-left scripts join up,
/// so moving one letter of such a word would come apart rather than swell. A
/// hyphenated word is really two words and would break at the hyphen.
bool canGrow(LyricWord word) {
  final text = word.text.trim();
  if (text.isEmpty) return false;

  final length = text.length;
  if (length > growMaxChars) return false;
  if (text.contains('-')) return false;
  for (final rune in text.runes) {
    if (_isBlockScript(rune) || _isJoinedScript(rune)) return false;
  }

  final held = word.endMs - word.startMs;
  return switch (length) {
    1 => held >= growMinSoloMs,
    <= 3 => held >= growMinShortMs + (length - 2) * growMinShortStepMs,
    4 => held >= growMinFourMs,
    _ => held >= growMinLongMs && held >= length * growMsPerChar,
  };
}

/// CJK ideographs, kana and Hangul: drawn as blocks rather than as independent
/// side-by-side letters.
bool _isBlockScript(int rune) =>
    (rune >= 0x2E80 && rune <= 0x9FFF) || // CJK radicals through unified
    (rune >= 0xAC00 && rune <= 0xD7AF) || // Hangul syllables
    (rune >= 0xF900 && rune <= 0xFAFF) || // CJK compatibility
    (rune >= 0x3000 && rune <= 0x303F) || // CJK punctuation
    (rune >= 0xFF00 && rune <= 0xFF60); // fullwidth forms

/// Arabic and friends: letters join, so they are not independent boxes.
bool _isJoinedScript(int rune) =>
    (rune >= 0x0600 && rune <= 0x06FF) || // Arabic
    (rune >= 0x0750 && rune <= 0x077F) || // Arabic supplement
    (rune >= 0x08A0 && rune <= 0x08FF) || // Arabic extended-A
    (rune >= 0xFB50 && rune <= 0xFDFF) || // Arabic presentation forms-A
    (rune >= 0xFE70 && rune <= 0xFEFF); // Arabic presentation forms-B

/// The held words on a line that have earned the treatment.
///
/// Returned in word order. Most lines have none, which is the point: the common
/// case is an empty list and no per-frame work beyond one scan.
List<GrowingWord> growingWordsOf(List<LyricWord> words) {
  final out = <GrowingWord>[];
  for (var i = 0; i < words.length; i++) {
    if (canGrow(words[i])) out.add(GrowingWord(i, words[i]));
  }
  return out;
}

/// Whether any held word on this line is mid-flight at [positionMs].
///
/// Answered without touching the per-letter peaks, so the lines that have no held
/// word - which is most of them - settle it in a comparison.
bool isGrowingAt(List<GrowingWord> growing, int positionMs) {
  for (final word in growing) {
    if (word.isAnimatingAt(positionMs)) return true;
  }
  return false;
}