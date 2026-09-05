// lib/models/lyrics_entry.dart
// Data model for synced lyrics


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
  final List<WordTiming>? words;
  
  const LyricsEntry({
    required this.timeMs,
    required this.text,
    this.endMs,
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
