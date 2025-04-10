import 'track.dart'; // Assuming Track model exists

class Album {
  final String id;
  final String name;
  final String artistName; // Artist primarily associated with the album
  final String imageUrl;
  final List<Track> tracks; // Tracks belonging to the album
  final DateTime? releaseDate; // Optional release date

  Album({
    required this.id,
    required this.name,
    required this.artistName,
    required this.imageUrl,
    required this.tracks,
    this.releaseDate,
  });

// Add fromJson / toJson if needed
}