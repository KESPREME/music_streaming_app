// lib/services/lyrics/lyric_sweep.dart
// The wipe: how much of a lyric line has been sung at a given moment.
//
// WHY A FRACTIONAL CHARACTER COUNT
//
// The renderer clips a copy of the line to `revealedChars` characters. So this
// returns a fraction, not a boolean and not a word index: a word is several
// characters wide, and a clip that snapped word to word looks like a
// typewriter. Interpolating within a word is what makes a held note draw
// slowly and a rattled-off one snap, which is the whole difference between
// reading the singing and watching a list.
//
// THE INTER-WORD GAP
//
// Whitespace between two words is credited to the pause between them, so the
// wipe keeps creeping through the gap instead of resting on the last letter of
// the previous word and then jumping. Without this the highlight visibly
// stalls between every pair of words, which reads as a dropped frame.

import 'dart:math' as math;

import '../../models/lyrics_entry.dart';
import 'lyric_words.dart' show LyricWord;

/// Characters revealed in [entry] at [positionMs].
///
/// FRACTIONAL, never rounded. A caller that rounded this (the old renderer did)
/// snaps the wipe to whole glyphs - 10-15px steps at lyric size - and a held
/// note then draws as a staircase. The renderer interpolates between character
/// edges instead.
double revealedChars(LyricsEntry entry, int positionMs) {
  final text = entry.text;
  if (text.isEmpty) return 0;

  final words = entry.timedWords;
  if (words.isEmpty) {
    // No per-word timing: the line lights whole at its own start stamp.
    return positionMs >= entry.timeMs ? text.length.toDouble() : 0;
  }

  // The spans are found ONCE per entry and shared with the renderer, so the
  // wipe and the lift can never disagree about which letters a word covers.
  final spans = entry.wordSpans;

  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final span = spans[i];
    // A word the text does not contain (a provider's text and timing disagree)
    // is skipped rather than mis-clipped.
    if (span == null) continue;
    final (start, end) = span;

    if (positionMs < word.startMs) return start.toDouble();
    if (positionMs < word.endMs) {
      return start + _charsSungInWord(word, positionMs, end - start);
    }

    // Past this word. If there is a next one, fill the gap over the pause.
    var next = i + 1;
    while (next < words.length && spans[next] == null) {
      next++;
    }
    if (next < words.length) {
      if (positionMs < words[next].startMs) {
        final target = spans[next]!.$1;
        final pause = math.max(1, words[next].startMs - word.endMs);
        final through = (positionMs - word.endMs) / pause;
        return end + through * (target - end);
      }
    }
  }

  return text.length.toDouble();
}

/// How many of [word]'s characters have been sung at [positionMs].
///
/// Within a syllable this is proportional. Between syllables the previous
/// syllable's slice is held, which is what keeps a source that times only
/// whole words from stuttering at its own word boundaries.
///
/// [length] is the word's span in the line, which can differ from its text when
/// a source padded it; the result is scaled to it.
double _charsSungInWord(LyricWord word, int positionMs, int length) {
  final syllables = word.syllables;

  if (syllables.isEmpty) {
    final span = math.max(1, word.endMs - word.startMs);
    final through =
        ((positionMs - word.startMs) / span).clamp(0.0, 1.0).toDouble();
    return through * length;
  }

  for (final syllable in syllables) {
    if (positionMs < syllable.startMs) {
      return syllable.start.toDouble();
    }
    if (positionMs < syllable.endMs) {
      final span = syllable.length;
      if (span <= 0) return syllable.start.toDouble();
      final through = (positionMs - syllable.startMs) /
          math.max(1, syllable.endMs - syllable.startMs);
      return (syllable.start + through * span)
          .clamp(syllable.start.toDouble(), syllable.end.toDouble())
          .toDouble();
    }
  }
  return length.toDouble();
}
/// The active line at [positionMs], or -1 when none has started.
///
/// Linear, like the rest of the lookup path here: a song has tens to hundreds
/// of lines and this runs once per frame on one of them, so a binary search
/// would be complexity bought for nothing.
int activeLineIndex(List<LyricsEntry> entries, int positionMs) {
  var active = -1;
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].timeMs <= positionMs) {
      active = i;
    } else {
      break;
    }
  }
  return active;
}

/// How far the auto-scroll should lead the singing, in milliseconds.
///
/// Scrolling to the line being sung puts it under the singer's mouth and
/// leaves the reader looking at what just passed. Leading by a beat puts the
/// line being sung where the eye already is. Clamped, because the gap between
/// two lines decides how much lead is even possible: in a fast passage there is
/// no gap to lead by, and in a slow one a huge lead would run the whole verse
/// off the top.
int scrollLeadMs(List<LyricsEntry> entries, int positionMs) {
  const minLead = 350;
  const maxLead = 500;
  if (entries.isEmpty) return minLead;

  final current = activeLineIndex(entries, positionMs);
  if (current < 0 || current + 1 >= entries.length) return minLead;

  final thisLine = entries[current];
  final next = entries[current + 1];
  final gap = next.timeMs - (thisLine.endMs ?? thisLine.timeMs);
  if (gap <= 0) return minLead;
  return gap.clamp(minLead, maxLead);
}

/// Where the list has to scroll for a given lyric row to sit at its top inset.
///
/// Pure geometry, kept beside [scrollLeadMs] because it is the same kind of rule
/// and belongs to the same place: the panel owns the timing, this file owns the
/// arithmetic.
///
/// The old call was `ensureVisible(alignment: 0.32)` - a FRACTION OF THE
/// VIEWPORT - which parked the sung line a third of the way down the screen and
/// pushed everything not yet sung toward the bottom edge. BitChord anchors at
/// `scrollOffset = 0` (PlayerLyrics.kt:1742, 1759).
///
/// Derivation, once: a row's screen position is `topInset - pixels + cum(row)`,
/// and `cum(row) = pixels + rowTop - topInset`, so the pixels that put it back on
/// the inset ARE `cum(row)` = `pixels + rowTop - topInset`.
///
/// The order matters in a way that is easy to get backwards. Scrolling DOWN
/// moves content UP, so a row sitting 300px BELOW the inset needs MORE scroll,
/// not less: at `pixels = 400` a row at `rowTop = 356` wants `700`. Reading it
/// the other way scrolls the list away from its own target.
double topAnchorOffset({
  required double currentPixels,
  required double rowTopInViewport,
  required double topInset,
  required double minScrollExtent,
  required double maxScrollExtent,
}) {
  final raw = currentPixels + rowTopInViewport - topInset;
  if (raw < minScrollExtent) return minScrollExtent;
  if (raw > maxScrollExtent) return maxScrollExtent;
  return raw;
}

/// Convenience: the line the auto-scroll should centre on, leading the singing.
int focusLineIndex(List<LyricsEntry> entries, int positionMs) {
  if (entries.isEmpty) return -1;
  final target = positionMs + scrollLeadMs(entries, positionMs);
  final lead = activeLineIndex(entries, target);
  return lead >= 0 ? lead : activeLineIndex(entries, positionMs);
}