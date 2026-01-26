// lib/models/lyrics_entry.dart
// Data model for synced lyrics with word-level timing support


/// Represents a single lyric line with timestamp
class LyricsEntry implements Comparable<LyricsEntry> {
  /// Timestamp in milliseconds
  final int timeMs;
  
  /// The lyric text
  final String text;
  
  /// Optional word-level timestamps for karaoke-style highlighting
  final List<WordTimestamp>? words;
  
  const LyricsEntry({
    required this.timeMs,
    required this.text,
    this.words,
  });
  
  /// Empty entry for list header
  static const LyricsEntry headEntry = LyricsEntry(timeMs: 0, text: '');
  
  /// Check if this is just a musical break (empty or just symbols)
  bool get isMusicalBreak {
    final trimmed = text.trim();
    return trimmed.isEmpty || 
           trimmed == '♪' || 
           trimmed == '♫' ||
           RegExp(r'^[♪♫\s]+$').hasMatch(trimmed);
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

/// Word-level timestamp for karaoke-style highlighting
class WordTimestamp {
  final String text;
  final double startTime; // in seconds
  final double endTime;   // in seconds
  
  const WordTimestamp({
    required this.text,
    required this.startTime,
    required this.endTime,
  });
  
  /// Start time in milliseconds
  int get startTimeMs => (startTime * 1000).round();
  
  /// End time in milliseconds
  int get endTimeMs => (endTime * 1000).round();
  
  /// Duration in milliseconds
  int get durationMs => endTimeMs - startTimeMs;
  
  @override
  String toString() => 'WordTimestamp("$text", $startTime-$endTime)';
}
