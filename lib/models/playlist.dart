import 'track.dart';

class Playlist {
  final String id;
  final String name;
  final String imageUrl;
  final List<Track> tracks;

  Playlist({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.tracks,
  });
  Playlist copyWith({
    String? id,
    String? name, // Ensure this parameter exists and is named 'name'
    String? imageUrl,
    List<Track>? tracks,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name, // Make sure 'name' is used here
      imageUrl: imageUrl ?? this.imageUrl,
      tracks: tracks ?? this.tracks,
    );
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'],
      name: json['name'],
      imageUrl: json['imageUrl'] ?? '',
      tracks: (json['tracks'] as List)
          .map((trackJson) => Track.fromJson(trackJson))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imageUrl': imageUrl,
      'tracks': tracks.map((track) => track.toJson()).toList(),
    };
  }
}
