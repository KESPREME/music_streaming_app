// lib/models/lyrics_entry.dart
// Data model for synced lyrics

import '../services/lyrics/lyric_growth.dart';
import '../services/lyrics/lyric_words.dart';
import '../services/lyrics/word_lift.dart' show liftRiseMs;

/// Represents word or syllable-level timing for karaoke sync
class WordTiming {
  final int timeMs;
  final int durationMs;
  final String text;

  const WordTiming({
    required this.timeMs,
    required this.durationMs,
    required this.text,
  });
}

/// Represents a single lyric line with timestamp
class LyricsEntry implements Comparable<LyricsEntry> {
  /// Timestamp in milliseconds
  final int timeMs;

  /// The lyric text
  final String text;

  /// Optional end timestamp in milliseconds
  final int? endMs;

  /// Optional word or syllable-level timing list
  ///
  /// Word-level timings, as produced by the plain-LRC heuristic and the
  /// enhanced-LRC parser. Preferred sources fill [lyricWords] instead, which
  /// carries syllables; read [timedWords] rather than this, so both paths reach
  /// the renderer through one shape.
  final List<WordTiming>? words;

  /// Word and syllable timings, when the source times finer than a word.
  final List<LyricWord>? lyricWords;

  // Not const: [timedWords] is a lazily built cache, and a generative const
  // constructor cannot have one. Nothing relied on const construction - the two
  // call sites that used the old const head sentinel just read [headEntry].
  LyricsEntry({
    required this.timeMs,
    required this.text,
    this.endMs,
    this.words,
    this.lyricWords,
  });

  /// Empty entry for list header
  static final LyricsEntry headEntry = LyricsEntry(timeMs: 0, text: '');

  /// Check if this is just a musical break (empty or just symbols/dots)
  bool get isMusicalBreak {
    final trimmed = text.trim();
    return trimmed.isEmpty ||
        trimmed == '♪' ||
        trimmed == '♫' ||
        trimmed == '• • •' ||
        trimmed == '...' ||
        trimmed.startsWith('♪') ||
        RegExp(r'^[♪♫•\.\s]+$').hasMatch(trimmed);
  }

  /// Words to render with, whichever field the source filled.
  ///
  /// Converted once and cached. The conversion is pure but this is read per
  /// line per frame while a line is animating, so it must not run each time.
  late final List<LyricWord> timedWords = _buildTimedWords();

  List<LyricWord> _buildTimedWords() {
    final direct = lyricWords;
    if (direct != null && direct.isNotEmpty) return direct;

    final legacy = words;
    if (legacy == null || legacy.isEmpty) return const <LyricWord>[];

    return wordsFromWordTimings([
      for (final w in legacy)
        (timeMs: w.timeMs, durationMs: w.durationMs, text: w.text),
    ]);
  }

  /// Whether this entry carries word- or syllable-level timing.
  bool get isWordSynced => lyricWords?.isNotEmpty == true ||
      (words != null && words!.isNotEmpty);

  /// Whether this entry carries true syllable-level timing.
  ///
  /// Drives the finer wipe and the held-note letter swell. A line that is only
  /// word-synced still gets a word-by-word sweep; it just does not claim more
  /// resolution than the source gave.
  bool get isSyllableSynced =>
      lyricWords?.any((w) => w.isSyllableSynced) == true;

  /// First moment this line has anything to animate.
  int get animatesFromMs => timedWords.isEmpty
      ? timeMs
      : timedWords.first.startMs < timeMs
          ? timedWords.first.startMs
          : timeMs;

  /// Where each timed word sits in [text], found once.
  ///
  /// The single answer to "which characters is this word", shared by the sweep,
  /// the lift, the held-word swell and the geometry (see [locateWordSpans]).
  late final List<(int, int)?> wordSpans = locateWordSpans(text, timedWords);

  /// The ranges the wipe crosses at constant speed. See [sweepSpansOf].
  late final List<(int, int)> sweepSpans = sweepSpansOf(timedWords, wordSpans);

  /// The held words on this line that earn the letter-by-letter swell.
  ///
  /// Empty for almost every line, which is the point: the common case costs one
  /// scan at first use and nothing per frame.
  late final List<GrowingWord> growingWords = growingWordsOf(timedWords);

  /// Last moment this line has anything to animate.
  ///
  /// Drives the per-line repaint gate: a line outside its own window must not
  /// repaint on a 60Hz clock, or isolating the sweep buys nothing.
  ///
  /// It has to cover the SETTLE as well as the singing. A word keeps falling
  /// back to the line for [liftRiseMs] after it ends, and a held word's letters
  /// keep moving until they come to rest; a window that closed at the last
  /// word's end froze both mid-motion and the line then jumped the rest of the
  /// way on the next repaint. BitChord: nimatesUntilMs = max(endMs,
  /// lastWord.end + 700, growing.restsAt) (LyricLine.kt).
  late final int animatesUntilMs = _computeAnimatesUntilMs();

  int _computeAnimatesUntilMs() {
    if (timedWords.isEmpty) return endMs ?? timeMs;
    final last = timedWords.last;
    final wordsEnd = last.endMs > timeMs ? last.endMs : timeMs;
    final lineEnd = endMs ?? wordsEnd;
    var until = wordsEnd > lineEnd ? wordsEnd : lineEnd;
    final settled = wordsEnd + liftRiseMs.round();
    if (settled > until) until = settled;
    for (final word in growingWords) {
      if (word.restsAtMs > until) until = word.restsAtMs;
    }
    return until;
  }

  @override
  int compareTo(LyricsEntry other) => timeMs.compareTo(other.timeMs);

  @override
  String toString() => 'LyricsEntry(time: $timeMs, text: "$text")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsEntry &&
          runtimeType == other.runtimeType &&
          timeMs == other.timeMs &&
          text == other.text;

  @override
  int get hashCode => timeMs.hashCode ^ text.hashCode;
}