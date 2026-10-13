// lib/utils/lyrics_utils.dart


import '../models/lyrics_entry.dart';
import '../services/lyrics/lyric_words.dart';

/// Utilities for parsing and manipulating lyrics
class LyricsUtils {
  /// Regex for parsing LRC lines: [mm:ss.xx] or [mm:ss.xxx]
  static final RegExp _lineRegex = RegExp(
    r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)',
  );
  
  /// Regex for word-level timestamp tags: <mm:ss.xx> or <mm:ss.xxx>
  static final RegExp _wordTimestampRegex = RegExp(
    r'<(\d{2}):(\d{2})\.(\d{2,3})>([^<]*)',
  );

  /// Regex for syllable tags: <word:start:end>
  static final RegExp _syllableTagRegex = RegExp(
    r'<([^:>]+):(\d+\.?\d*):(\d+\.?\d*)>',
  );

  static final RegExp _stampedLineRegex =
      RegExp(r'^\[\d{2}:\d{2}\.\d{2,3}\].*');
  static final RegExp _creditKeywordRegex = RegExp(
    r'(?:作词|作曲|编曲|制作人|录音|混音|监制|Written\s+by|Lyrics\s+by|Composed\s+by|Produced\s+by|Arranged\s+by|QQ音乐|酷狗音乐|网易云音乐|Lyricist|Composer|Credits)',
    caseSensitive: false,
  );

  static bool _isCredit(String line) {
    // Strip line timestamp [mm:ss.xx] and inline word timestamps <...>
    final text = line
        .replaceFirst(RegExp(r'^\[\d{2}:\d{2}\.\d{2,3}\]'), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
    if (text.isEmpty) return false;
    if (_creditKeywordRegex.hasMatch(text)) return true;

    final colonMatch = RegExp(r'^([^:：]{1,30})[:：]\s*(.+)').firstMatch(text);
    if (colonMatch != null) {
      final label = colonMatch.group(1)!.trim().toLowerCase();
      const knownCreditLabels = [
        'lyrics', 'lyric', 'lyricist', 'music', 'composer', 'composed', 'producer',
        'produced', 'arrangement', 'arranger', 'arranged', 'vocals', 'vocal',
        'artist', 'singer', 'mixing', 'mixer', 'mastering', 'recording', 'recorded',
        'sound', 'engineering', 'engineer', 'track', 'album', 'publisher', 'label',
        'written', 'author', 'writer', 'credits', 'credit', 'by',
        '作词', '作曲', '编曲', '制作', '制作人', '监制', '混音', '录音', '母带', '吉他', '贝斯', '鼓', '钢琴',
      ];
      if (knownCreditLabels.any((k) => label.contains(k))) return true;
      if (label.length <= 15 && !label.contains(' ') && colonMatch.group(2)!.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Strips metadata and credit lines from the beginning and end of LRC lyrics (BitChord KuGou parity).
  static String stripCredits(String lrcContent) {
    final rawLines = lrcContent.split('\n');
    final stampedLines = <String>[];

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // Skip unstamped tags like [ar:...], [ti:...], [by:...]
      if (trimmed.startsWith('[') && !_lineRegex.hasMatch(trimmed)) {
        continue;
      }
      if (_stampedLineRegex.hasMatch(trimmed)) {
        stampedLines.add(trimmed);
      }
    }

    if (stampedLines.isEmpty) return lrcContent;

    // Scan opening lines (within first 15 lines and within first 40s) for the last credit/header line
    final headLimit = stampedLines.length < 15 ? stampedLines.length : 15;
    int headCut = 0;

    for (int i = headLimit - 1; i >= 0; i--) {
      final line = stampedLines[i];
      final match = _lineRegex.firstMatch(line);
      final min = int.tryParse(match?.group(1) ?? '0') ?? 0;
      final sec = int.tryParse(match?.group(2) ?? '0') ?? 0;
      final timeMs = (min * 60 + sec) * 1000;
      if (timeMs > 40000) continue; // Not an opening credit line

      if (_isCredit(line)) {
        headCut = i + 1;
        break;
      }
    }

    // Also check if line 0 is a title - artist header without colons before first real sung line
    if (headCut == 0 && stampedLines.isNotEmpty) {
      final first = stampedLines.first;
      final match = _lineRegex.firstMatch(first);
      if (match != null) {
        final rawText = match.group(4)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
        final min = int.tryParse(match.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(match.group(2) ?? '0') ?? 0;
        if (min == 0 && sec < 4 && (rawText.contains(' - ') || _creditKeywordRegex.hasMatch(rawText))) {
          headCut = 1;
        }
      }
    }

    var body = stampedLines.skip(headCut).toList();

    // Scan tail lines (within last 6 lines) for outro credits
    if (body.isNotEmpty) {
      final tailLimit = body.length < 6 ? body.length : 6;
      int tailCut = 0;
      for (int i = 0; i < tailLimit; i++) {
        final line = body[body.length - 1 - i];
        if (_isCredit(line)) {
          tailCut = i + 1;
          break;
        }
      }
      if (tailCut > 0) {
        body = body.take(body.length - tailCut).toList();
      }
    }

    return body.join('\n');
  }

  /// Parse LRC formatted lyrics into list of LyricsEntry
  static List<LyricsEntry> parseLrc(String lrcContent) {
    final cleanedLrc = stripCredits(lrcContent);
    final entries = <LyricsEntry>[];
    
    // Add head entry for initial scroll
    entries.add(LyricsEntry.headEntry);
    
    final lines = cleanedLrc.split('\n');
    
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      
      // Skip metadata tags like [ar:Artist], [ti:Title], etc.
      if (trimmed.startsWith('[') && !_lineRegex.hasMatch(trimmed)) {
        if (RegExp(r'\[[a-zA-Z]+:').hasMatch(trimmed)) {
          continue;
        }
      }
      
      // Try to match the line
      final match = _lineRegex.firstMatch(trimmed);
      if (match == null) continue;
      
      try {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final centiseconds = match.group(3)!;
        
        int milliseconds;
        if (centiseconds.length == 2) {
          milliseconds = int.parse(centiseconds) * 10;
        } else {
          milliseconds = int.parse(centiseconds);
        }
        
        final timeMs = minutes * 60 * 1000 + seconds * 1000 + milliseconds;
        final rawContent = match.group(4)?.trim() ?? '';
        
        // 1. Check for explicit syllable tags: <word:start:end>
        List<WordTiming>? parsedWords;
        final syllableMatches = _syllableTagRegex.allMatches(rawContent).toList();
        if (syllableMatches.isNotEmpty) {
          final words = <WordTiming>[];
          var lyricWords = <LyricWord>[];
          final cleanBuffer = StringBuffer();
          for (final sm in syllableMatches) {
            final wordText = sm.group(1) ?? '';
            final startSec = double.tryParse(sm.group(2) ?? '0') ?? 0.0;
            final endSec = double.tryParse(sm.group(3) ?? '0') ?? startSec + 0.3;
            final wStartMs = (startSec * 1000).round();
            final wDurMs = ((endSec - startSec) * 1000).round().clamp(100, 5000);
            words.add(WordTiming(
              timeMs: wStartMs,
              durationMs: wDurMs,
              text: wordText.trim(),
            ));
            if (cleanBuffer.isNotEmpty) cleanBuffer.write(' ');
            cleanBuffer.write(wordText.trim());
          }
          parsedWords = words;
          // Word spans carried explicitly, so the wipe interpolates across a
          // word rather than arriving on its last letter.
          lyricWords = wordsFromWordTimings([
            for (final w in words)
              (timeMs: w.timeMs, durationMs: w.durationMs, text: w.text),
          ]);
          entries.add(LyricsEntry(
            timeMs: timeMs,
            text: cleanBuffer.toString(),
            words: parsedWords,
            lyricWords: lyricWords,
          ));
          continue;
        }

        // 2. Check for enhanced LRC timestamp tags: <mm:ss.xx> word
        final wordTimestampMatches = _wordTimestampRegex.allMatches(rawContent).toList();
        if (wordTimestampMatches.isNotEmpty) {
          final words = <WordTiming>[];
          final cleanBuffer = StringBuffer();
          for (int m = 0; m < wordTimestampMatches.length; m++) {
            final wMatch = wordTimestampMatches[m];
            final wMin = int.parse(wMatch.group(1)!);
            final wSec = int.parse(wMatch.group(2)!);
            final wCenti = wMatch.group(3)!;
            final wMs = (wCenti.length == 2)
                ? int.parse(wCenti) * 10
                : int.parse(wCenti);
            final wTime = wMin * 60 * 1000 + wSec * 1000 + wMs;
            final wText = wMatch.group(4)?.trim() ?? '';

            int wDuration = 400;
            if (m + 1 < wordTimestampMatches.length) {
              final nextMatch = wordTimestampMatches[m + 1];
              final nMin = int.parse(nextMatch.group(1)!);
              final nSec = int.parse(nextMatch.group(2)!);
              final nCenti = nextMatch.group(3)!;
              final nMs = (nCenti.length == 2)
                  ? int.parse(nCenti) * 10
                  : int.parse(nCenti);
              final nTime = nMin * 60 * 1000 + nSec * 1000 + nMs;
              wDuration = (nTime - wTime).clamp(80, 5000);
            }

            if (wText.isNotEmpty) {
              words.add(WordTiming(
                timeMs: wTime,
                durationMs: wDuration,
                text: wText,
              ));
              if (cleanBuffer.isNotEmpty) cleanBuffer.write(' ');
              cleanBuffer.write(wText);
            }
          }
          if (words.isNotEmpty) {
            parsedWords = words;
            entries.add(LyricsEntry(
              timeMs: timeMs,
              text: cleanBuffer.toString(),
              words: parsedWords,
              lyricWords: wordsFromWordTimings([
                for (final w in words)
                  (
                    timeMs: w.timeMs,
                    durationMs: w.durationMs,
                    text: w.text,
                  ),
              ]),
            ));
            continue;
          }
        }

        // Standard LRC clean text fallback
        final cleanText = rawContent
            .replaceAll(_syllableTagRegex, '')
            .replaceAll(RegExp(r'<\d{2}:\d{2}\.\d{2,3}>'), '')
            .trim();
        
        entries.add(LyricsEntry(
          timeMs: timeMs,
          text: cleanText.isEmpty ? rawContent : cleanText,
        ));
      } catch (e) {
        // Skip malformed lines
        continue;
      }
    }
    
    // Sort by timestamp - STABLY. List.sort is not stable, and two lines that
    // share a stamp (a chorus pasted twice, a gap marker on a line start) must
    // keep the order they were written in or the lyric reads out of order.
    final ordered = [
      for (var i = 0; i < entries.length; i++) (i, entries[i]),
    ]..sort((a, b) {
        final byTime = a.$2.timeMs.compareTo(b.$2.timeMs);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    final sorted = [for (final item in ordered) item.$2];

    // Close each line at the start of the next.
    //
    // NOTHING IS INVENTED HERE. This pass used to give every plain line a word
    // timing spread over its duration by an English vowel-group syllable
    // counter, so a source with no word timing at all (LRCLIB, KuGou, a plain
    // LRC) looked word-synced: `isWordSynced` was true for all of them, the
    // "prioritize word sync" setting could never tell a real word-synced answer
    // from a guess, and the sweep ran across words at invented speeds. A line
    // with no word timing now has none, and is lit as a whole line. Real
    // timing - enhanced-LRC stamps and syllable tags, handled above - is kept.
    final enrichedEntries = <LyricsEntry>[];
    for (int i = 0; i < sorted.length; i++) {
      final current = sorted[i];
      if (current.timeMs == 0 && current.text.isEmpty) {
        enrichedEntries.add(current);
        continue;
      }

      final nextTime = (i + 1 < sorted.length)
          ? sorted[i + 1].timeMs
          : current.timeMs + 4000;

      enrichedEntries.add(LyricsEntry(
        timeMs: current.timeMs,
        text: current.text,
        endMs: nextTime,
        words: current.words,
        lyricWords: current.lyricWords,
      ));
    }
    return enrichedEntries;
  }
  
  /// Find the current line index based on playback position
  /// Returns the index of the line that should be highlighted
  static int findCurrentLineIndex(List<LyricsEntry> entries, int positionMs) {
    if (entries.isEmpty) return -1;

    // Nothing stamped (plain text): there is no "current" line to follow, and
    // the loop below would answer "the last one" because every stamp is 0.
    if (entries.last.timeMs <= 0) return 0;

    int currentIndex = 0;
    
    for (int i = 0; i < entries.length; i++) {
      if (entries[i].timeMs <= positionMs) {
        currentIndex = i;
      } else {
        break;
      }
    }
    
    return currentIndex;
  }

  /// Parse plain text lyrics into [LyricsEntry] list, every line stamped 0.
  ///
  /// Stamped 0 on purpose. This used to step the lines four seconds apart so
  /// they would "scroll", which made text nobody had timed look synced: the
  /// panel followed a made-up schedule, the strip showed the wrong line, and
  /// `timeMs > 0` could no longer tell timed lyrics from untimed ones - the one
  /// question the race, the cache and the strip all ask.
  static List<LyricsEntry> parsePlainText(String plainText) {
    final entries = <LyricsEntry>[LyricsEntry.headEntry];
    for (final line in plainText.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      entries.add(LyricsEntry(timeMs: 0, text: trimmed));
    }
    return entries;
  }
}
