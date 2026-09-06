// lib/utils/lyrics_utils.dart


import '../models/lyrics_entry.dart';

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
  static final RegExp _creditColonRegex = RegExp(r'\][^\[]+[:：].+');
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
          entries.add(LyricsEntry(
            timeMs: timeMs,
            text: cleanBuffer.toString(),
            words: parsedWords,
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
    
    // Sort by timestamp
    entries.sort();

    // Compute endMs and natural character-weighted word timings for lines without word tags
    final enrichedEntries = <LyricsEntry>[];
    for (int i = 0; i < entries.length; i++) {
      final current = entries[i];
      if (current.timeMs == 0 && current.text.isEmpty) {
        enrichedEntries.add(current);
        continue;
      }

      final nextTime = (i + 1 < entries.length)
          ? entries[i + 1].timeMs
          : current.timeMs + 4000;

      // If already parsed with word-level precision, keep it
      if (current.words != null && current.words!.isNotEmpty) {
        enrichedEntries.add(LyricsEntry(
          timeMs: current.timeMs,
          text: current.text,
          endMs: nextTime,
          words: current.words,
        ));
        continue;
      }

      final totalGap = (nextTime - current.timeMs).clamp(600, 20000);
      final rawWords = current.text
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();

      final wordTimings = <WordTiming>[];
      if (rawWords.isNotEmpty) {
        // Syllable-based singing cadence: singers hold syllable-rich words
        // and naturally elongate the last word of a phrase.
        final List<double> weights = [];
        for (int w = 0; w < rawWords.length; w++) {
          final word = rawWords[w].replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
          // Estimate syllable count via vowel groups
          double syllables = _estimateSyllables(word).toDouble();
          if (syllables < 1) syllables = 1;
          // End-of-phrase elongation: last word gets 1.6x, penultimate 1.15x
          if (w == rawWords.length - 1 && rawWords.length > 1) {
            syllables *= 1.6;
          } else if (w == rawWords.length - 2 && rawWords.length > 2) {
            syllables *= 1.15;
          }
          // Short function words ("a", "I", "to") never exceed 1 syllable weight
          if (word.length <= 2) {
            syllables = syllables.clamp(0.0, 1.2);
          }
          weights.add(syllables);
        }

        final double totalWeight = weights.fold(0.0, (acc, w) => acc + w);

        // Vocal lines fill ~93% of the gap (singers use most of the duration)
        final double targetSingingDuration = (totalGap * 0.93)
            .clamp(600.0, totalGap.toDouble());

        int currentStart = current.timeMs;
        for (int w = 0; w < rawWords.length; w++) {
          final wShare = weights[w] / totalWeight;
          final wDuration = (targetSingingDuration * wShare).round()
              .clamp(150, 5000);
          wordTimings.add(WordTiming(
            timeMs: currentStart,
            durationMs: wDuration,
            text: rawWords[w],
          ));
          currentStart += wDuration;
        }
      }

      enrichedEntries.add(LyricsEntry(
        timeMs: current.timeMs,
        text: current.text,
        endMs: nextTime,
        words: wordTimings,
      ));
    }
    
    return enrichedEntries;
  }
  
  /// Find the current line index based on playback position
  /// Returns the index of the line that should be highlighted
  static int findCurrentLineIndex(List<LyricsEntry> entries, int positionMs) {
    if (entries.isEmpty) return -1;
    
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

  /// Estimate syllable count for a word using vowel-group heuristic.
  /// Handles common English patterns: silent-e, diphthongs, -le endings.
  static int _estimateSyllables(String word) {
    if (word.isEmpty) return 1;
    final w = word.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (w.isEmpty) return 1;
    if (w.length <= 2) return 1;

    // Count vowel groups (consecutive vowels = 1 syllable)
    int count = 0;
    bool prevVowel = false;
    const vowels = {'a', 'e', 'i', 'o', 'u', 'y'};

    for (int i = 0; i < w.length; i++) {
      final isVowel = vowels.contains(w[i]);
      if (isVowel && !prevVowel) {
        count++;
      }
      prevVowel = isVowel;
    }

    // Silent-e: trailing 'e' after consonant doesn't add syllable
    if (w.endsWith('e') && !w.endsWith('le') && count > 1) {
      count--;
    }
    // Common suffixes that add syllable
    if (w.endsWith('tion') || w.endsWith('sion')) {
      // Already counted, no adjustment needed
    }
    // Words ending in -ed after consonant (jumped, walked) don't add syllable
    if (w.endsWith('ed') && w.length > 3) {
      final beforeEd = w[w.length - 3];
      if (beforeEd != 't' && beforeEd != 'd' && !vowels.contains(beforeEd)) {
        if (count > 1) count--;
      }
    }

    return count < 1 ? 1 : count;
  }

  /// Parse plain text lyrics into [LyricsEntry] list with artificial spacing
  static List<LyricsEntry> parsePlainText(String plainText) {
    final entries = <LyricsEntry>[LyricsEntry.headEntry];
    final lines = plainText.split('\n');
    int timeMs = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      entries.add(LyricsEntry(timeMs: timeMs, text: trimmed));
      timeMs += 4000;
    }
    return entries;
  }
}
