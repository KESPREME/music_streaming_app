// lib/models/lyrics_entry.dart
// Data model for synced lyrics


/// Represents a single lyric line with timestamp
class LyricsEntry implements Comparable<LyricsEntry> {
  /// Timestamp in milliseconds
  final int timeMs;
  
  /// The lyric text
  final String text;
  
  const LyricsEntry({
    required this.timeMs,
    required this.text,
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
