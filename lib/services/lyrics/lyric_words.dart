// lib/services/lyrics/lyric_words.dart
// Two-level word/syllable model for progressive lyric illumination.
//
// WHY TWO LEVELS
//
// Every format that times syllables says which pieces belong to the same word
// the same way: by leaving the space out.
//
//   Apple TTML   <span>e</span><span>nough</span>
//   A2 line      <00:31.83>e<00:31.99>nough
//   QQ           e(31839,157)nough(31996,533)
//
// So a timed run that neither ends in whitespace nor is followed by a run
// starting with one is the front of a word that carries on. [wordsFromRuns]
// glues runs back into words on exactly that rule, and each word keeps its
// runs as syllables so a line that genuinely carries syllable timing can
// illuminate at that resolution instead of at its word's.
//
// THE TWO CASES WHERE A MISSING SPACE SAYS NOTHING
//
//   * Han, kana and Thai are written without spaces at all, so their absence
//     is not a statement about words. Gluing there would turn a whole line
//     into one word that lifts as one. Each run stays a word, exactly as it
//     did before syllables were looked for.
//   * A writer that emits no whitespace anywhere in a line is not stating word
//     boundaries, it is omitting them. Each run stays a word, which is how such
//     lines read before syllables were considered at all. [spacingIsExplicit]
//     lets a caller that rebuilt the spacing itself say so, so even a line
//     that is one long split word is believed.

import 'package:flutter/foundation.dart';

/// One stamped run of text as a provider wrote it, spacing untouched.
///
/// [raw] keeps whatever whitespace surrounded it, because that whitespace is
/// the only thing saying where one word stops.
@immutable
class TimedRun {
  const TimedRun({required this.startMs, required this.endMs, required this.raw});

  final int startMs;
  final int endMs;
  final String raw;
}

/// One syllable of one word: where it sits in the word's text, and when.
@immutable
class LyricSyllable {
  const LyricSyllable({
    required this.startMs,
    required this.endMs,
    required this.start,
    required this.end,
  });

  final int startMs;
  final int endMs;

  /// Character offset of this syllable within its word's text.
  final int start;

  /// Character offset just past this syllable.
  final int end;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricSyllable &&
          startMs == other.startMs &&
          endMs == other.endMs &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(startMs, endMs, start, end);

  @override
  String toString() => 'LyricSyllable($startMs-$endMs, [$start,$end))';
}

/// A word, and the syllables it was timed in.
@immutable
class LyricWord {
  const LyricWord({
    required this.startMs,
    required this.endMs,
    required this.text,
    this.syllables = const <LyricSyllable>[],
  });

  final int startMs;
  final int endMs;
  final String text;

  /// Timed syllables. Empty when the source only timed the word.
  final List<LyricSyllable> syllables;

  /// Whether this word carries finer than word-level timing.
  bool get isSyllableSynced => syllables.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricWord &&
          startMs == other.startMs &&
          endMs == other.endMs &&
          text == other.text;

  @override
  int get hashCode => Object.hash(startMs, endMs, text);

  @override
  String toString() =>
      'LyricWord($startMs-$endMs, "$text", ${syllables.length} syl)';
}

/// Glues [runs] into words, each keeping its runs as [LyricSyllable]s.
List<LyricWord> wordsFromRuns(
  List<TimedRun> runs, {
  bool spacingIsExplicit = false,
}) {
  if (runs.isEmpty) return const <LyricWord>[];

  // Only attempt to glue when the line actually carries whitespace, or the
  // caller rebuilt the spacing from a flag of its own.
  final glue = spacingIsExplicit ||
      runs.any((run) => run.raw.trim().isEmpty ? false : _hasSpace(run.raw));

  final words = <LyricWord>[];
  final current = StringBuffer();
  final parts = <LyricSyllable>[];
  var start = 0;
  var end = 0;

  void flush() {
    if (current.isEmpty) return;
    final text = current.toString();
    words.add(LyricWord(
      startMs: start,
      endMs: end < start ? start : end,
      text: text,
      syllables: normalizeSyllables(
        parts,
        text.length,
        startMs: start,
        endMs: end < start ? start : end,
      ),
    ));
    current.clear();
    parts.clear();
  }

  for (final run in runs) {
    final content = run.raw.trim();
    if (content.isEmpty) {
      // A blank run - a lone space, or the bare stamp that closes an A2 line -
      // ends the word in hand.
      flush();
      continue;
    }

    final joins = glue &&
        current.isNotEmpty &&
        !_startsWithSpace(run.raw) &&
        !_endsUnspacedScript(current.toString()) &&
        !_startsUnspacedScript(content);
    if (!joins) flush();

    if (current.isEmpty) {
      start = run.startMs;
      end = run.startMs;
    }

    final from = current.length;
    current.write(content);
    final runEnd = run.startMs > run.endMs ? run.startMs : run.endMs;
    parts.add(LyricSyllable(
      startMs: run.startMs,
      endMs: runEnd,
      start: from,
      end: current.length,
    ));
    if (runEnd > end) end = runEnd;

    if (!glue || _endsWithSpace(run.raw)) flush();
  }
  flush();
  return words;
}

/// Rebuilds syllable offsets so they tile the word exactly, front to back.
///
/// Providers do not agree on whether a syllable's stamp covers the space that
/// follows it, and some leave gaps where a trailing space should be. Both
/// make a wipe jump: the clip is asked for a character range that does not
/// match the characters on screen. Normalising once here means the renderer
/// can trust every syllable it is handed.
///
/// A word with no syllables comes back as a single syllable covering it, and
/// crucially it carries [startMs]..[endMs] - the WORD's own timing, not a
/// placeholder. That is what keeps a word-only source rendering through the
/// same path with real interpolation: a syllable stamped 0..0 is never
/// "partway through", so the wipe would snap word to word instead of drawing
/// across the word, which is the stutter the fractional count exists to avoid.
List<LyricSyllable> normalizeSyllables(
  List<LyricSyllable> parts,
  int length, {
  int startMs = 0,
  int endMs = 0,
}) {
  if (length <= 0) return const <LyricSyllable>[];

  if (parts.isEmpty) {
    return <LyricSyllable>[
      LyricSyllable(
        startMs: startMs,
        endMs: endMs,
        start: 0,
        end: length,
      ),
    ];
  }

  final sorted = List<LyricSyllable>.of(parts)
    ..sort((a, b) => a.start.compareTo(b.start));

  final out = <LyricSyllable>[];
  var cursor = 0;
  for (final part in sorted) {
    // Never let a part start before the previous one ended: overlapping stamps
    // would make the wipe stutter backwards.
    final from = part.start < cursor ? cursor : part.start;
    if (from >= length) break;
    final to = part.end > length ? length : part.end;
    if (to <= from) continue;
    out.add(LyricSyllable(
      startMs: part.startMs,
      endMs: part.endMs,
      start: from,
      end: to,
    ));
    cursor = to;
  }

  if (out.isEmpty) {
    return <LyricSyllable>[
      LyricSyllable(
        startMs: startMs,
        endMs: endMs,
        start: 0,
        end: length,
      ),
    ];
  }

  // Close the gap a provider left at the end of the word, so the wipe finishes
  // on the word's last letter rather than stopping short of it.
  final last = out.last;
  if (last.end < length) {
    out[out.length - 1] = LyricSyllable(
      startMs: last.startMs,
      endMs: last.endMs,
      start: last.start,
      end: length,
    );
  }
  return out;
}

bool _hasSpace(String raw) => raw.runes.any(_isSpaceRune);

bool _endsWithSpace(String raw) =>
    raw.isNotEmpty && _isSpaceRune(raw.runes.last);

bool _startsWithSpace(String raw) =>
    raw.isNotEmpty && _isSpaceRune(raw.runes.first);

bool _isSpaceRune(int rune) =>
    rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D;

/// Scripts written without spaces between words.
///
/// A run in one of these is a word of its own. Glued, a whole line would
/// become one word and lift as one.
bool _startsUnspacedScript(String text) {
  if (text.isEmpty) return false;
  final rune = text.runes.first;
  return _isUnspacedRune(rune);
}

bool _endsUnspacedScript(String text) {
  if (text.isEmpty) return false;
  final rune = text.runes.last;
  return _isUnspacedRune(rune);
}

bool _isUnspacedRune(int r) =>
    (r >= 0x3400 && r <= 0x9FFF) || // Han
    (r >= 0x3040 && r <= 0x30FF) || // hiragana and katakana
    (r >= 0x3000 && r <= 0x303F) || // CJK punctuation
    (r >= 0xFF00 && r <= 0xFFEF) || // full-width forms
    (r >= 0x0E00 && r <= 0x0E7F); // Thai

/// Converts word-level [WordTiming]s into [LyricWord]s.
///
/// The bridge for every source that times words but not syllables, so those
/// lines render through the syllable path with one syllable per word.
List<LyricWord> wordsFromWordTimings(
  List<({int timeMs, int durationMs, String text})> timings,
) {
  final words = <LyricWord>[];
  for (final t in timings) {
    final text = t.text.trim();
    if (text.isEmpty) continue;
    final endMs = t.timeMs + (t.durationMs <= 0 ? 0 : t.durationMs);
    final wordEnd = endMs < t.timeMs ? t.timeMs : endMs;
    words.add(LyricWord(
      startMs: t.timeMs,
      endMs: wordEnd,
      text: text,
      syllables: normalizeSyllables(
        const <LyricSyllable>[],
        text.length,
        startMs: t.timeMs,
        endMs: wordEnd,
      ),
    ));
  }
  return words;
}

/// Where each timed word sits in [text], as a `(start, end)` character span, or
/// null where it could not be found.
///
/// THE ONE SPAN FINDER. The sweep, the lift, the held-word swell and the
/// geometry all need to know which characters a word covers, and they used to
/// find out three different ways - two of which disagreed about repeated words
/// and trimmed whitespace, so the clip and the lift could light different
/// letters of the same line. Everything now reads this.
///
/// Located by WALKING the text with a search, not by summing word lengths: the
/// line text carries separators the words do not, and a source's word timings
/// are not obliged to tile it. Walking (rather than searching from the start)
/// is also what makes a line that repeats a word ("again, again") light each
/// occurrence in its own turn. Mirrors BitChord's `LyricLine.wordSpans`.
List<(int, int)?> locateWordSpans(String text, List<LyricWord> words) {
  final out = List<(int, int)?>.filled(words.length, null);
  var cursor = 0;
  for (var i = 0; i < words.length; i++) {
    final needle = words[i].text.trim();
    if (needle.isEmpty) continue;
    final at = text.indexOf(needle, cursor);
    if (at < 0) continue;
    out[i] = (at, at + needle.length);
    cursor = at + needle.length;
  }
  return out;
}

/// The ranges the sweep moves across at CONSTANT speed: each syllable of a
/// split word, otherwise the whole word.
///
/// A glyph-by-glyph interpolation runs fast over an "i" and slow over an "m",
/// because a character is a unit of count and not of width. Interpolating across
/// a syllable's pixel width instead is what makes a held syllable draw
/// evenly (BitChord `LyricLine.sweepSpans`, `horizontalAt`).
List<(int, int)> sweepSpansOf(List<LyricWord> words, List<(int, int)?> spans) {
  final out = <(int, int)>[];
  for (var i = 0; i < words.length && i < spans.length; i++) {
    final span = spans[i];
    if (span == null) continue;
    final word = words[i];
    if (word.syllables.length > 1) {
      for (final s in word.syllables) {
        final a = span.$1 + s.start;
        final b = span.$1 + s.end;
        if (b > a && b <= span.$2) out.add((a, b));
      }
    } else {
      out.add(span);
    }
  }
  return out;
}
