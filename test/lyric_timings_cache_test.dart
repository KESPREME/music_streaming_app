import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyric_timings_codec.dart';
import 'package:music_streaming_app/services/lyrics/lyric_words.dart';

/// The line text a cache row holds, and what comes back out of it.
///
/// This is the shape the disk cache stores, so the round trip under test is the
/// real one rather than a stand-in.
(String lrc, List<LyricsEntry> reparsed) _cacheRoundTrip(List<LyricsEntry> input) {
  final buffer = StringBuffer();
  for (final e in input) {
    final m = (e.timeMs ~/ 60000).toString().padLeft(2, '0');
    final s = ((e.timeMs % 60000) / 1000).toStringAsFixed(2).padLeft(5, '0');
    buffer.writeln('[$m:$s]${e.text}');
  }
  final lrc = buffer.toString();

  final reparsed = <LyricsEntry>[];
  for (final line in lrc.split('\n')) {
    final m = RegExp(r'^\[(\d+):(\d+\.\d+)\](.*)$').firstMatch(line);
    if (m == null) continue;
    final ms = int.parse(m.group(1)!) * 60000 +
        (double.parse(m.group(2)!) * 1000).round();
    reparsed.add(LyricsEntry(timeMs: ms, text: m.group(3)!));
  }
  return (lrc, reparsed);
}

void main() {
  group('encodeTimings', () {
    test('a line-synced song costs nothing', () {
      final entries = [
        LyricsEntry(timeMs: 0, text: 'one'),
        LyricsEntry(timeMs: 1000, text: 'two'),
      ];
      expect(encodeTimings(entries), isNull);
    });

    test('word timings are encoded', () {
      final entries = [
        LyricsEntry(
          timeMs: 0,
          text: 'I am here',
          words: const [
            WordTiming(timeMs: 0, durationMs: 200, text: 'I'),
            WordTiming(timeMs: 300, durationMs: 200, text: 'am'),
            WordTiming(timeMs: 600, durationMs: 200, text: 'here'),
          ],
        ),
      ];
      final encoded = encodeTimings(entries)!;
      expect(encoded, isNotNull);
      final decoded = jsonDecode(encoded) as List;
      expect(decoded.length, 1);
      expect((decoded.first as List).length, 3);
    });

    test('a line with no timings inside a timed song is an empty list', () {
      final entries = [
        LyricsEntry(
          timeMs: 0,
          text: 'sung',
          words: const [WordTiming(timeMs: 0, durationMs: 100, text: 'sung')],
        ),
        LyricsEntry(timeMs: 500, text: 'unsung'),
      ];
      final decoded = jsonDecode(encodeTimings(entries)!) as List;
      expect((decoded[0] as List).length, 1);
      expect(decoded[1], isEmpty);
    });
  });

  group('attachTimings', () {
    test('word timings survive a cache round trip', () {
      // The regression this whole codec exists for: word timings used to be
      // dropped when a track was written to the cache, so the wipe had nothing
      // to draw from on the next launch.
      final original = [
        LyricsEntry(
          timeMs: 0,
          text: 'I am here',
          words: const [
            WordTiming(timeMs: 0, durationMs: 200, text: 'I'),
            WordTiming(timeMs: 300, durationMs: 200, text: 'am'),
            WordTiming(timeMs: 600, durationMs: 200, text: 'here'),
          ],
        ),
      ];

      final (lrc, reparsed) = _cacheRoundTrip(original);
      expect(lrc, contains('[00:00.00]I am here'));

      // Before re-attaching, the reparsed line has nothing.
      expect(reparsed.single.timedWords, isEmpty);

      final restored = attachTimings(reparsed, encodeTimings(original));
      expect(restored.single.timedWords.length, 3);
      expect(restored.single.isWordSynced, isTrue);
      expect(
        restored.single.timedWords.map((w) => w.text).toList(),
        ['I', 'am', 'here'],
      );
    });

    test('a payload of the wrong length is discarded, not misapplied', () {
      // Positional payloads invite this failure, and mis-assigning word
      // timings draws the wipe across the wrong words.
      final entries = [
        LyricsEntry(
          timeMs: 0,
          text: 'one two',
          words: const [WordTiming(timeMs: 0, durationMs: 100, text: 'one')],
        ),
        LyricsEntry(timeMs: 500, text: 'three'),
      ];
      final payload = encodeTimings(entries);

      final fewer = [LyricsEntry(timeMs: 0, text: 'one two')];
      expect(attachTimings(fewer, payload), fewer);

      final more = [
        ...fewer,
        LyricsEntry(timeMs: 500, text: 'three'),
        LyricsEntry(timeMs: 900, text: 'four'),
      ];
      expect(attachTimings(more, payload), more);
    });

    test('a corrupt payload degrades to no timings', () {
      final entries = [LyricsEntry(timeMs: 0, text: 'hello')];
      expect(attachTimings(entries, 'not json at all'), entries);
      expect(attachTimings(entries, '{"not":"a list"}'), entries);
      expect(attachTimings(entries, '[1,2,3]'), entries);
      expect(attachTimings(entries, null), entries);
    });

    test('malformed words inside a line are skipped, not fatal', () {
      final entries = [
        LyricsEntry(timeMs: 0, text: 'I am here'),
        LyricsEntry(timeMs: 500, text: 'second line'),
      ];
      // Two lines, to match. The first holds two good words and three entries
      // that are not word shapes at all; the second is malformed wholesale.
      final payload = jsonEncode([
        [
          [0, 200, 'I'],
          'nonsense',
          [999],
          [10, 20, 'am'],
        ],
        'not-a-list',
      ]);
      final restored = attachTimings(entries, payload);
      expect(
        restored.first.timedWords.map((w) => w.text).toList(),
        ['I', 'am'],
      );
      expect(restored[1].timedWords, isEmpty);
    });

    test('syllable spans survive the round trip', () {
      final original = [
        LyricsEntry(
          timeMs: 0,
          text: 'enough',
          lyricWords: [
            wordsFromRuns(const [
              TimedRun(startMs: 0, endMs: 100, raw: 'e'),
              TimedRun(startMs: 100, endMs: 400, raw: 'nough '),
            ]).single,
          ],
        ),
      ];
      final (_, reparsed) = _cacheRoundTrip(original);
      final restored = attachTimings(reparsed, encodeTimings(original));
      final word = restored.single.timedWords.single;
      expect(word.text, 'enough');
      expect(word.syllables, isNotEmpty);
      expect(word.syllables.last.end, 6);
    });

    test('a decoded word keeps the timing needed to interpolate', () {
      // A word whose syllable span came back as 0..0 would snap whole instead of
      // drawing across, which is the stutter the fractional wipe avoids.
      final entries = [
        LyricsEntry(
          timeMs: 0,
          text: 'held',
          words: const [WordTiming(timeMs: 0, durationMs: 900, text: 'held')],
        ),
      ];
      final (_, reparsed) = _cacheRoundTrip(entries);
      final restored = attachTimings(reparsed, encodeTimings(entries));
      final syllable = restored.single.timedWords.single.syllables.single;
      expect(syllable.startMs, 0);
      expect(syllable.endMs, 900);
    });
  });
}