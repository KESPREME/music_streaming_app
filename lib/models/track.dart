// import 'package:flutter/foundation.dart'; // For kIsWeb - Commented out as kIsWeb is not used

// lib/models/track.dart
class Track {
  final String id; // YouTube ID, Spotify ID, or File Path for local
  final String trackName;
  final String artistName;
  final String albumName;
  final String previewUrl; // File Path for local, YT URL, Spotify Preview URL
  final String albumArtUrl; // URL or empty (local art needs separate handling)
  final String source; // 'youtube', 'spotify', 'local'
  final Duration? duration; // Added duration

  Track({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.previewUrl,
    required this.albumArtUrl,
    this.source = 'youtube',
    this.duration, // Added
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] ?? 'unknown_${DateTime.now().millisecondsSinceEpoch}', // Provide fallback ID
      trackName: json['trackName'] ?? 'Unknown Track',
      artistName: json['artistName'] ?? 'Unknown Artist',
      albumName: json['albumName'] ?? 'Unknown Album',
      previewUrl: json['previewUrl'] ?? '',
      albumArtUrl: json['albumArtUrl'] ?? '',
      source: json['source'] ?? 'unknown', // Default to 'unknown' if missing
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'])
          : null, // Added
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trackName': trackName,
      'artistName': artistName,
      'albumName': albumName,
      'previewUrl': previewUrl,
      'albumArtUrl': albumArtUrl,
      'source': source,
      'duration': duration?.inMilliseconds, // Added
    };
  }

  // Added copyWith method
  Track copyWith({
    String? id,
    String? trackName,
    String? artistName,
    String? albumName,
    String? previewUrl,
    String? albumArtUrl,
    String? source,
    Duration? duration,
  }) {
    return Track(
      id: id ?? this.id,
      trackName: trackName ?? this.trackName,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      previewUrl: previewUrl ?? this.previewUrl,
      albumArtUrl: albumArtUrl ?? this.albumArtUrl,
      source: source ?? this.source,
      duration: duration ?? this.duration,
    );
  }


  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Track &&
              runtimeType == other.runtimeType &&
              id == other.id && // Primarily rely on ID for equality if sources can differ
              // Only include other fields if strict equality across all properties is needed
              trackName == other.trackName &&
              artistName == other.artistName &&
              albumName == other.albumName &&
              previewUrl == other.previewUrl &&
              albumArtUrl == other.albumArtUrl &&
              source == other.source &&
              duration == other.duration; // Added duration

  @override
  int get hashCode =>
      id.hashCode ^ // Primarily hash ID
      // Include others if needed for specific map/set usage requiring full equality
      trackName.hashCode ^
      artistName.hashCode ^
      albumName.hashCode ^
      previewUrl.hashCode ^
      albumArtUrl.hashCode ^
      source.hashCode ^
      duration.hashCode; // Added duration
}