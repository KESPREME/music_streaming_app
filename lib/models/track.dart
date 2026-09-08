// import 'package:flutter/foundation.dart'; // For kIsWeb - Commented out as kIsWeb is not used

// lib/models/track.dart
class Track {
  final String id; // YouTube ID, Spotify ID, or File Path for local
  final String trackName;
  final String artistName;
  final String albumName;
  final String? albumId; // Album browse ID (e.g. MPREb_... or OLAK_...)
  final String previewUrl; // File Path for local, YT URL, Spotify Preview URL
  final String albumArtUrl; // URL or empty (local art needs separate handling)
  final String source; // 'youtube', 'spotify', 'local'
  final Duration? duration; // Added duration
  final int? _durationMs; // Duration in milliseconds (from InnerTube)
  final String? genre; // Mood/genre tag when the source gave evidence
  final bool isExplicit; // BitChord explicit badge [E]

  Track({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.albumId,
    required this.previewUrl,
    String? albumArtUrl,
    String? albumArt, // Alias for albumArtUrl (InnerTube uses this)
    this.source = 'youtube',
    this.duration,
    int? durationMs,
    this.genre,
    this.isExplicit = false,
  })  : albumArtUrl = albumArtUrl ?? albumArt ?? '',
        _durationMs = durationMs;

  /// Duration in milliseconds (for InnerTube/lyrics compatibility)
  int? get durationMs => _durationMs ?? duration?.inMilliseconds;

  /// Alias for albumArtUrl (InnerTube compatibility)
  String get albumArt => albumArtUrl;

  /// Alias for trackName
  String get title => trackName;

  /// Alias for artistName
  String get artist => artistName;

  /// Formatted duration string mm:ss
  String get durationText {
    if (duration == null) return '';
    final minutes = duration!.inMinutes;
    final seconds = (duration!.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] ??
          'unknown_${DateTime.now().millisecondsSinceEpoch}', // Provide fallback ID
      trackName: json['trackName'] ?? 'Unknown Track',
      artistName: json['artistName'] ?? 'Unknown Artist',
      albumName: json['albumName'] ?? 'Unknown Album',
      albumId: json['albumId'] as String?,
      previewUrl: json['previewUrl'] ?? '',
      albumArtUrl: json['albumArtUrl'] ?? '',
      source: json['source'] ?? 'unknown', // Default to 'unknown' if missing
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'])
          : null, // Added
      genre: json['genre'] as String?,
      isExplicit: json['isExplicit'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trackName': trackName,
      'artistName': artistName,
      'albumName': albumName,
      'albumId': albumId,
      'previewUrl': previewUrl,
      'albumArtUrl': albumArtUrl,
      'source': source,
      'duration': duration?.inMilliseconds, // Added
      'genre': genre,
      'isExplicit': isExplicit,
    };
  }

  // Added copyWith method
  Track copyWith({
    String? id,
    String? trackName,
    String? artistName,
    String? albumName,
    String? albumId,
    String? previewUrl,
    String? albumArtUrl,
    String? source,
    Duration? duration,
    int? durationMs,
    String? genre,
    bool? isExplicit,
  }) {
    return Track(
      id: id ?? this.id,
      trackName: trackName ?? this.trackName,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      albumId: albumId ?? this.albumId,
      previewUrl: previewUrl ?? this.previewUrl,
      albumArtUrl: albumArtUrl ?? this.albumArtUrl,
      source: source ?? this.source,
      duration: duration ?? this.duration,
      durationMs: durationMs ?? _durationMs,
      genre: genre ?? this.genre,
      isExplicit: isExplicit ?? this.isExplicit,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          runtimeType == other.runtimeType &&
          id ==
              other
                  .id && // Primarily rely on ID for equality if sources can differ
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

  /// BitChord parity (Song.isSameTrackAs): determines if two tracks represent
  /// the same song, comparing by ID or normalized title & artist so that
  /// YouTube album releases, audio tracks, and video singles match accurately.
  bool isSameTrackAs(Track? other) {
    if (other == null) return false;
    if (id.isNotEmpty && other.id.isNotEmpty && id == other.id) return true;

    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'\s*[\(\[\{].*?[\)\]\}]'), '') // remove (feat. ...), [Remastered], etc.
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final t1 = norm(trackName);
    final t2 = norm(other.trackName);
    if (t1.isEmpty || t2.isEmpty || t1 != t2) return false;

    final a1 = norm(artistName);
    final a2 = norm(other.artistName);
    if (a1.isEmpty || a2.isEmpty) return true;
    return a1 == a2 || a1.contains(a2) || a2.contains(a1);
  }
}
