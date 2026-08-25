// lib/utils/lyrics_utils.dart


import '../models/lyrics_entry.dart';

/// Utilities for parsing and manipulating lyrics
class LyricsUtils {
  /// Regex for parsing LRC lines: [mm:ss.xx] or [mm:ss.xxx]
  static final RegExp _lineRegex = RegExp(
    r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)',
  );
  
  /// Regex for word-level karaoke tags: <word:start:end> (stripped from output)
  static final RegExp _wordTagRegex = RegExp(
    r'<[^:>]+:\d+\.?\d*:\d+\.?\d*>',
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
        
        // Strip word-timing tags; keep raw text if nothing remains
        final cleanText = text.replaceAll(_wordTagRegex, '').trim();
        
        entries.add(LyricsEntry(
          timeMs: timeMs,
          text: cleanText.isEmpty ? text : cleanText,
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
}
