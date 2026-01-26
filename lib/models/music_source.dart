// lib/models/music_source.dart

/// Music source options for the app

enum MusicSource {
  youtube('YouTube Music', 'youtube'),
  local('Local Files', 'local');

  final String displayName;
  final String value;
  
  const MusicSource(this.displayName, this.value);
  
  static MusicSource fromString(String value) {
    return MusicSource.values.firstWhere(
      (source) => source.value == value,
      orElse: () => MusicSource.youtube, // Default to YouTube Music
    );
  }
  
  /// Get icon for this source
  String get iconName {
    switch (this) {
      case MusicSource.youtube:
        return 'music_note';
      case MusicSource.local:
        return 'folder';
    }
  }
  
  /// Get description for this source
  String get description {
    switch (this) {
      case MusicSource.youtube:
        return 'Stream millions of songs from YouTube Music';
      case MusicSource.local:
        return 'Play music files stored on your device';
    }
  }
}
