import 'album.dart'; // Assuming Album model exists
import 'track.dart'; // Assuming Track model exists

class Artist {
  final String id;
  final String name;
  final String imageUrl;
  final String? bio; // Optional biography
  final List<Album>? topAlbums; // Optional list of albums
  final List<Track>? topTracks; // Optional list of tracks

  Artist({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.bio,
    this.topAlbums,
    this.topTracks,
  });

// Add fromJson / toJson if needed for caching or API responses
}