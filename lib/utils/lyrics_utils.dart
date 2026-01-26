// lib/utils/lyrics_utils.dart


import '../models/lyrics_entry.dart';

/// Utilities for parsing and manipulating lyrics
class LyricsUtils {
  /// Regex for parsing LRC lines: [mm:ss.xx] or [mm:ss.xxx]
  static final RegExp _lineRegex = RegExp(
    r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)',
  );
  
  /// Regex for parsing word-level timestamps in format: <word:start:end>
  static final RegExp _wordRegex = RegExp(
    r'<([^:]+):(\d+\.?\d*):(\d+\.?\d*)>',
  );
  
  /// Parse LRC formatted lyrics into list of LyricsEntry
  static List<LyricsEntry> parseLrc(String lrcContent) {
    final entries = <LyricsEntry>[];
    
    // Add head entry for initial scroll
    entries.add(LyricsEntry.headEntry);
    
    final lines = lrcContent.split('\n');
    
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      
      // Skip metadata tags like [ar:Artist], [ti:Title], etc.
      if (trimmed.startsWith('[') && !_lineRegex.hasMatch(trimmed)) {
        // Check if it's a metadata tag
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
        
        // Handle both 2-digit and 3-digit centiseconds/milliseconds
        int milliseconds;
        if (centiseconds.length == 2) {
          milliseconds = int.parse(centiseconds) * 10;
        } else {
          milliseconds = int.parse(centiseconds);
        }
        
        final timeMs = minutes * 60 * 1000 + seconds * 1000 + milliseconds;
        final text = match.group(4)?.trim() ?? '';
        
        // Parse word-level timestamps if present
        List<WordTimestamp>? words;
        if (_wordRegex.hasMatch(text)) {
          words = _parseWordTimestamps(text);
        }
        
        // Clean text of word timestamp tags
        final cleanText = text.replaceAll(_wordRegex, '').trim();
        
        entries.add(LyricsEntry(
          timeMs: timeMs,
          text: cleanText.isEmpty ? text : cleanText,
          words: words,
        ));
        
      } catch (e) {
        // Skip malformed lines
        continue;
      }
    }
    
    // Sort by timestamp
    entries.sort();
    
    return entries;
  }
  
  /// Parse word-level timestamps from text
  static List<WordTimestamp> _parseWordTimestamps(String text) {
    final words = <WordTimestamp>[];
    
    final matches = _wordRegex.allMatches(text);
    for (final match in matches) {
      try {
        final word = match.group(1)!;
        final startTime = double.parse(match.group(2)!);
        final endTime = double.parse(match.group(3)!);
        
        words.add(WordTimestamp(
          text: word,
          startTime: startTime,
          endTime: endTime,
        ));
      } catch (_) {
        continue;
      }
    }
    
    return words.isEmpty ? [] : words;
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
  
  /// Find the current word index within a line based on playback position
  static int findCurrentWordIndex(LyricsEntry entry, int positionMs) {
    if (entry.words == null || entry.words!.isEmpty) return -1;
    
    for (int i = entry.words!.length - 1; i >= 0; i--) {
      if (entry.words![i].startTimeMs <= positionMs) {
        return i;
      }
    }
    
    return -1;
  }
  
  /// Calculate progress within a word (0.0 to 1.0)
  static double getWordProgress(WordTimestamp word, int positionMs) {
    if (positionMs < word.startTimeMs) return 0.0;
    if (positionMs >= word.endTimeMs) return 1.0;
    
    final elapsed = positionMs - word.startTimeMs;
    return elapsed / word.durationMs;
  }
  
  /// Convert milliseconds to timestamp string [mm:ss.xx]
  static String formatTimestamp(int ms) {
    final minutes = ms ~/ 60000;
    final seconds = (ms ~/ 1000) % 60;
    final centiseconds = (ms % 1000) ~/ 10;
    
    return '[${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${centiseconds.toString().padLeft(2, '0')}]';
  }
  
  /// Check if text contains Japanese characters
  static bool isJapanese(String text) {
    return RegExp(r'[\u3040-\u309F\u30A0-\u30FF]').hasMatch(text);
  }
  
  /// Check if text contains Korean characters
  static bool isKorean(String text) {
    return RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF]').hasMatch(text);
  }
  
  /// Check if text contains Chinese characters
  static bool isChinese(String text) {
    return RegExp(r'[\u4E00-\u9FFF\u3400-\u4DBF]').hasMatch(text);
  }
  
  /// Check if text contains Cyrillic characters
  static bool isCyrillic(String text) {
    return RegExp(r'[\u0400-\u04FF]').hasMatch(text);
  }
  
  /// Clean up lyrics text (remove extra whitespace, etc.)
  static String cleanLyricsText(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^\s+|\s+$', multiLine: true), '')
        .trim();
  }
}
