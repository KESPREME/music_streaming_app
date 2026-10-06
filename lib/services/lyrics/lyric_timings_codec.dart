// lib/services/lyrics/lyric_timings_codec.dart
// JSON codec for word/syllable timings, so the disk cache can keep them.
//
// WHY A SEPARATE PAYLOAD
//
// The cached lyrics column holds `[mm:ss.xx]text` lines, which is what every
// provider can produce and what a plain LRC reader needs. Word and syllable
// timings are encoded beside it rather than inside it, because embedding them
// in the line text would make the cached string unreadable to anything that
// does not know this codec - including the plain-LRC export.
//
// SHAPE
//
// One list per line, parallel to the line list:
//   [[{s,e,t}, ...], [], [{s,e,t,"y0","y1"}, ...]]
// where s/e are the word's start/end in ms, t its text, and y0/y1 the
// character range of the first syllable when the source timed finer than a
// word. A line with no timings is an empty list, which costs two bytes rather
// than a flag.
//
// COMPACT ON PURPOSE
//
// A four-minute song is a few kilobytes here. Encoding the common case -
// word-level, no syllables - as four small values keeps it that way, and the
// whole payload is dropped rather than truncated if it somehow is not.

import 'dart:convert';

import '../../models/lyrics_entry.dart';
import 'lyric_words.dart';

/// Encodes word/syllable timings for [entries].
///
/// Returns null when no entry carries timings, so a line-synced song costs
/// nothing extra in the cache.
String? encodeTimings(List<LyricsEntry> entries) {
  final anyTimed = entries.any((e) => e.timedWords.isNotEmpty);
  if (!anyTimed) return null;

  final payload = <List<Object?>>[];
  for (final entry in entries) {
    final words = entry.timedWords;
    if (words.isEmpty) {
      payload.add(const <Object?>[]);
      continue;
    }
    final line = <Object?>[];
    for (final word in words) {
      // Only the first syllable's span is stored. Rendering interpolates
      // across syllables from this, which is enough to avoid snapping word to
      // word, and storing every span triples the payload for a difference
      // nobody can see.
      final syllable = word.syllables.isEmpty ? null : word.syllables.first;
      line.add(<Object?>[
        word.startMs,
        word.endMs,
        word.text,
        if (syllable != null) ...[syllable.start, syllable.end],
      ]);
    }
    payload.add(line);
  }

  try {
    return jsonEncode(payload);
  } catch (e) {
    // A cache miss is always recoverable by refetching; a throw here would take
    // the whole fetch path down over an optimisation.
    return null;
  }
}

/// Decodes a payload written by [encodeTimings].
///
/// Tolerant by construction: a truncated list, a line of the wrong shape, or a
/// word that is not an object all decode to something usable rather than
/// throwing. Corrupt cache data must never be worse than no cache data.
List<List<LyricWord>> decodeTimings(String? payload) {
  if (payload == null || payload.isEmpty) return const [];

  List<Object?> decoded;
  try {
    final raw = jsonDecode(payload);
    if (raw is! List) return const [];
    decoded = raw;
  } catch (e) {
    return const [];
  }

  final out = <List<LyricWord>>[];
  for (final line in decoded) {
    if (line is! List) {
      out.add(const <LyricWord>[]);
      continue;
    }
    final words = <LyricWord>[];
    for (final item in line) {
      if (item is! List || item.length < 3) continue;
      final startMs = item[0];
      final endMs = item[1];
      final text = item[2];
      if (startMs is! num || endMs is! num || text is! String) continue;
      if (text.isEmpty) continue;

      final syllables = <LyricSyllable>[];
      if (item.length >= 5) {
        final s0 = item[3];
        final s1 = item[4];
        if (s0 is num && s1 is num && s1 > s0) {
          syllables.add(LyricSyllable(
            startMs: startMs.toInt(),
            endMs: endMs.toInt(),
            start: s0.toInt(),
            end: s1.toInt(),
          ));
        }
      }

      words.add(LyricWord(
        startMs: startMs.toInt(),
        endMs: endMs.toInt(),
        text: text,
        syllables: normalizeSyllables(
          syllables,
          text.length,
          startMs: startMs.toInt(),
          endMs: endMs.toInt(),
        ),
      ));
    }
    out.add(words);
  }
  return out;
}

/// Re-attaches decoded timings to parsed lines.
///
/// The line list is the source of truth for text and timing; timings are
/// positional, so a payload that no longer matches the line count is discarded
/// rather than applied to the wrong lines. That mismatch is the failure mode a
/// positional format invites, and mis-assigning word timings draws the sweep
/// across the wrong words.
List<LyricsEntry> attachTimings(
  List<LyricsEntry> entries,
  String? payload,
) {
  final decoded = decodeTimings(payload);
  if (decoded.isEmpty) return entries;
  if (decoded.length != entries.length) return entries;

  final out = <LyricsEntry>[];
  for (var i = 0; i < entries.length; i++) {
    final words = decoded[i];
    out.add(words.isEmpty
        ? entries[i]
        : LyricsEntry(
            timeMs: entries[i].timeMs,
            text: entries[i].text,
            endMs: entries[i].endMs,
            lyricWords: words,
          ));
  }
  return out;
}