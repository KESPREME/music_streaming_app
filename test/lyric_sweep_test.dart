import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyric_clock.dart';
import 'package:music_streaming_app/services/lyrics/lyric_sweep.dart';
import 'package:music_streaming_app/services/lyrics/lyric_words.dart';

LyricsEntry _entry(
  String text, {
  int timeMs = 0,
  int? endMs,
  List<LyricWord>? words,
  List<WordTiming>? legacy,
}) =>
    LyricsEntry(
      timeMs: timeMs,
      text: text,
      endMs: endMs,
      lyricWords: words,
      words: legacy,
    );

void main() {
  group('wordsFromRuns', () {
    test('glues runs that carry no space between them', () {
      // Apple's <span>e</span><span>nough</span>
      final words = wordsFromRuns(const [
        TimedRun(startMs: 0, endMs: 100, raw: 'e'),
        TimedRun(startMs: 100, endMs: 400, raw: 'nough '),
      ]);
      expect(words.length, 1);
      expect(words.first.text, 'enough');
      expect(words.first.startMs, 0);
      expect(words.first.endMs, 400);
      // The glued word keeps its pieces as syllables.
      expect(words.first.syllables.length, 2);
      expect(words.first.syllables[0].start, 0);
      expect(words.first.syllables[1].start, 1);
      expect(words.first.syllables[1].end, 6); // "enough" is six letters
    });

    test('splits on an explicit space', () {
      final words = wordsFromRuns(const [
        TimedRun(startMs: 0, endMs: 100, raw: 'I '),
        TimedRun(startMs: 100, endMs: 400, raw: 'am '),
      ]);
      expect(words.map((w) => w.text).toList(), ['I', 'am']);
    });

    test('a leading blank run ends the word in hand', () {
      final words = wordsFromRuns(const [
        TimedRun(startMs: 0, endMs: 100, raw: 'e'),
        TimedRun(startMs: 100, endMs: 120, raw: ' '),
        TimedRun(startMs: 120, endMs: 300, raw: 'nough'),
      ]);
      expect(words.map((w) => w.text).toList(), ['e', 'nough']);
    });

    test('Han and kana runs each stay a word', () {
      // No spaces in these scripts, so gluing would make one word of a whole
      // line and lift it as one.
      final words = wordsFromRuns(const [
        TimedRun(startMs: 0, endMs: 200, raw: '君'),
        TimedRun(startMs: 200, endMs: 400, raw: 'は'),
        TimedRun(startMs: 400, endMs: 600, raw: '僕'),
      ]);
      expect(words.map((w) => w.text).toList(), ['君', 'は', '僕']);
    });

    test('no whitespace anywhere means every run is its own word', () {
      // A writer that omits boundaries is not stating them.
      final words = wordsFromRuns(const [
        TimedRun(startMs: 0, endMs: 100, raw: 'he'),
        TimedRun(startMs: 100, endMs: 300, raw: 'llo'),
      ]);
      expect(words.map((w) => w.text).toList(), ['he', 'llo']);
    });

    test('spacingIsExplicit overrides the no-whitespace rule', () {
      final words = wordsFromRuns(
        const [
          TimedRun(startMs: 0, endMs: 100, raw: 'hel'),
          TimedRun(startMs: 100, endMs: 300, raw: 'lo'),
        ],
        spacingIsExplicit: true,
      );
      expect(words.map((w) => w.text).toList(), ['hello']);
    });
  });

  group('normalizeSyllables', () {
    test('a word with no syllables comes back as one covering syllable', () {
      final out = normalizeSyllables(const [], 7);
      expect(out.length, 1);
      expect(out.first.start, 0);
      expect(out.first.end, 7);
    });

    test('syllables tile the word with no gaps or overlaps', () {
      final out = normalizeSyllables(
        const [
          LyricSyllable(startMs: 0, endMs: 100, start: 0, end: 1),
          // Deliberately overlapping the previous end.
          LyricSyllable(startMs: 100, endMs: 200, start: 0, end: 2),
        ],
        5,
      );
      expect(out.first.start, 0);
      for (var i = 1; i < out.length; i++) {
        expect(out[i].start, greaterThanOrEqualTo(out[i - 1].end));
      }
      expect(out.last.end, 5);
    });

    test('a gap before the last letter is closed', () {
      final out = normalizeSyllables(
        const [LyricSyllable(startMs: 0, endMs: 100, start: 0, end: 3)],
        6,
      );
      expect(out.last.end, 6);
    });

    test('parts past the end of the word are dropped', () {
      final out = normalizeSyllables(
        const [
          LyricSyllable(startMs: 0, endMs: 100, start: 0, end: 2),
          LyricSyllable(startMs: 100, endMs: 200, start: 2, end: 99),
        ],
        4,
      );
      expect(out.last.end, 4);
    });
  });

  group('timedWords', () {
    test('prefers syllable data when present', () {
      final e = _entry('hello', words: const [
        LyricWord(startMs: 0, endMs: 200, text: 'hello'),
      ]);
      expect(e.timedWords.length, 1);
      expect(e.isWordSynced, isTrue);
    });

    test('converts legacy word timings', () {
      final e = _entry('I am here', legacy: const [
        WordTiming(timeMs: 0, durationMs: 100, text: 'I'),
        WordTiming(timeMs: 100, durationMs: 100, text: 'am'),
        WordTiming(timeMs: 200, durationMs: 100, text: 'here'),
      ]);
      expect(e.timedWords.map((w) => w.text).toList(), ['I', 'am', 'here']);
      expect(e.isWordSynced, isTrue);
      expect(e.isSyllableSynced, isFalse);
    });

    test('a line with no timings is not word synced', () {
      expect(_entry('plain').isWordSynced, isFalse);
      expect(_entry('plain').timedWords, isEmpty);
    });

    test('animatesUntilMs covers the whole line, not just its words', () {
      // A line whose endMs runs past its last word: the highlight must not be
      // released before the line is, or the active line pops out early.
      final e = _entry(
        'held note',
        timeMs: 100,
        endMs: 4000,
        words: const [LyricWord(startMs: 100, endMs: 300, text: 'held note')],
      );
      expect(e.animatesUntilMs, 4000);
    });
  });

  group('revealedChars', () {
    final entry = _entry('I am here', words: const [
      LyricWord(startMs: 0, endMs: 200, text: 'I'),
      LyricWord(startMs: 300, endMs: 500, text: 'am'),
      LyricWord(startMs: 600, endMs: 800, text: 'here'),
    ]);

    test('nothing revealed before the first word', () {
      expect(revealedChars(entry, -10), 0);
    });

    test('a word lights progressively, not word-at-a-time', () {
      // "I" spans characters 0..1 over 0-200ms. Halfway through it the wipe
      // must be inside the word, not snapped to its end.
      expect(revealedChars(entry, 100), greaterThan(0.0));
      expect(revealedChars(entry, 100), lessThan(1.0));
      expect(revealedChars(entry, 200), closeTo(1.0, 0.01));
    });

    test('the wipe creeps through the gap rather than resting', () {
      // "I" ends at 200 and "am" starts at 300. The space at index 1 must fill
      // over that pause: at 250 it is half done. Without this the highlight
      // visibly stalls on the last letter of every word.
      expect(revealedChars(entry, 250), closeTo(1.5, 0.01));
      // At the moment "am" begins, only "I " is revealed.
      expect(revealedChars(entry, 300), closeTo(2.0, 0.01));
      // And "am" itself draws gradually rather than arriving whole.
      final midAm = revealedChars(entry, 400);
      expect(midAm, greaterThan(2.0));
      expect(midAm, lessThan(4.0));
      expect(revealedChars(entry, 500), closeTo(4.0, 0.01));
    });

    test('fully revealed once every word has sung', () {
      expect(revealedChars(entry, 5000), closeTo(9.0, 0.01));
    });

    test('a line with no word timing lights whole at its start stamp', () {
      final plain = _entry('plain line', timeMs: 1000);
      expect(revealedChars(plain, 999), 0);
      expect(revealedChars(plain, 1000), 10);
    });

    test('never runs past the end of the text', () {
      final ragged = _entry('hi', words: const [
        LyricWord(startMs: 0, endMs: 50, text: 'hi'),
        LyricWord(startMs: 50, endMs: 90, text: 'hi'),
      ]);
      final revealed = revealedChars(ragged, 10000);
      expect(revealed, lessThanOrEqualTo(2.0));
      expect(revealed, greaterThanOrEqualTo(0.0));
    });

    test('an empty line reveals nothing', () {
      expect(revealedChars(_entry(''), 5000), 0);
    });

    test('a repeated word lines up by walking, not searching', () {
      // "again, again" - both occurrences must light in order.
      final repeat = _entry('again, again', words: const [
        LyricWord(startMs: 0, endMs: 100, text: 'again'),
        LyricWord(startMs: 200, endMs: 300, text: 'again'),
      ]);
      expect(revealedChars(repeat, 50), lessThan(5.0));
      expect(revealedChars(repeat, 250), greaterThan(6.0));
    });

    test('timing that disagrees with the text still progresses', () {
      // Provider text says "one" but its timing names "two". The wipe must not
      // stall forever.
      final mismatched = _entry('one two three', words: const [
        LyricWord(startMs: 0, endMs: 100, text: 'zzz'),
        LyricWord(startMs: 200, endMs: 300, text: 'qqq'),
      ]);
      final revealed = revealedChars(mismatched, 5000);
      expect(revealed, greaterThan(0.0));
    });
  });

  group('active line and focus', () {
    final entries = [
      _entry('one', timeMs: 0, endMs: 1000),
      _entry('two', timeMs: 2000, endMs: 3000),
      _entry('three', timeMs: 4000, endMs: 5000),
    ];

    test('activeLineIndex finds the last started line', () {
      expect(activeLineIndex(entries, 0), 0);
      expect(activeLineIndex(entries, 1500), 0);
      expect(activeLineIndex(entries, 2000), 1);
      expect(activeLineIndex(entries, 9999), 2);
    });

    test('a line stays active until the next one starts', () {
      expect(isActiveLine(entries, 0, 500), isTrue);
      // 1500 is inside the gap after line 0's words but before line 1 starts,
      // so line 0 must still be lit.
      expect(isActiveLine(entries, 0, 1500), isTrue);
      expect(isActiveLine(entries, 0, 2000), isFalse);
    });

    test('focus leads the singing rather than trailing it', () {
      // Just after line 0 starts, the scroll should already be aiming at
      // something at or ahead of the current line, never behind.
      final focus = focusLineIndex(entries, 100);
      expect(focus, greaterThanOrEqualTo(activeLineIndex(entries, 100)));
    });

    test('scrollLead is clamped into a sane band', () {
      expect(scrollLeadMs(entries, 100), inInclusiveRange(350, 500));
    });

    test('scrollLead tolerates an empty list', () {
      expect(scrollLeadMs(const [], 0), 350);
    });
  });

  group('LyricClock', () {
    test('isAnimating gates a line to its own window', () {
      expect(
        LyricClock.isAnimating(nowMs: 500, fromMs: 0, untilMs: 1000),
        isTrue,
      );
      expect(
        LyricClock.isAnimating(nowMs: 5000, fromMs: 0, untilMs: 1000),
        isFalse,
      );
      // One millisecond of slack either side so a line does not pop out on the
      // frame its neighbour takes over.
      expect(
        LyricClock.isAnimating(nowMs: 1001, fromMs: 0, untilMs: 1000),
        isTrue,
      );
    });

    test('clampRevealed holds a wipe inside its line', () {
      expect(LyricClock.clampRevealed(-5, 10), 0);
      expect(LyricClock.clampRevealed(50, 10), 10);
      expect(LyricClock.clampRevealed(5, 10), 5);
    });
  });
}