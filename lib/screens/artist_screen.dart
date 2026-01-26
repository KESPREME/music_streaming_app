import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart';
import '../models/artist.dart';
import '../models/album.dart';
import 'album_screen.dart'; // For navigating to album screen

class ArtistScreen extends StatelessWidget {
  final String artistName;

  const ArtistScreen({required this.artistName, super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final artistDetails = musicProvider.currentArtistDetails;
        final isLoading = musicProvider.isLoadingArtist;
        final errorMessage = musicProvider.errorMessage; // Get error message

        // Check if the loaded data is for the correct artist we navigated for
        final bool isCorrectArtistData = !isLoading && artistDetails?.name == artistName;

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: isLoading
              ? _buildLoadingState() // Show loading indicator
          // Show error if failed OR if data is null/wrong after loading finished
              : (errorMessage != null && !isCorrectArtistData) || (!isLoading && artistDetails == null)
              ? _buildErrorState(errorMessage ?? "Could not load artist details.")
              : _buildArtistContent(context, musicProvider, artistDetails!), // Show content
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
  }

  Widget _buildErrorState(String errorMsg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Text(
          errorMsg,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.redAccent, fontSize: 16),
        ),
      ),
    );
  }

  // Main content built using CustomScrollView for collapsing AppBar effect
  Widget _buildArtistContent(BuildContext context, MusicProvider musicProvider, Artist artist) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          expandedHeight: 250.0, // Height of the expanded AppBar
          pinned: true, // Keep visible when scrolled
          stretch: true,
          backgroundColor: const Color(0xFF1D1D1D), // Dark background
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            title: Text(
              artist.name,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            background: Stack(
              fit: StackFit.expand,
              children: [
                // Artist Image (if available)
                if (artist.imageUrl.isNotEmpty)
                  Image.network(
                    artist.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (c,e,s) => Container(color: Colors.grey[850], child: const Icon(Icons.person, size: 80, color: Colors.white70)),
                  )
                else // Placeholder
                  Container(color: Colors.grey[850], child: const Icon(Icons.person, size: 80, color: Colors.white70)),
                // Gradient overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      stops: const [0.0, 0.6, 1.0],
                      colors: [ Colors.transparent, Colors.black.withOpacity(0.4), Colors.black.withOpacity(0.9)],
                    ),
                  ),
                ),
              ],
            ),
            stretchModes: const [StretchMode.zoomBackground, StretchMode.fadeTitle],
          ),
        ),

        // Body content using SliverList or SliverToBoxAdapter
        SliverList(
          delegate: SliverChildListDelegate(
              [
                // Optional Bio Section
                if (artist.bio != null && artist.bio!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Biography', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(artist.bio!, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                      ],
                    ),
                  ),

                // Top Tracks Section
                _buildSectionHeader('Top Tracks'),
                if (artist.topTracks == null || artist.topTracks!.isEmpty)
                  _buildEmptySectionPlaceholder("No top tracks found for this artist.")
                else
                  ...artist.topTracks!.map((track) { // Use spread operator (...)
                    final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
                    return TrackTile(
                      track: track,
                      isPlaying: isPlaying,
                      onTap: () => musicProvider.playTrack(track, playlistTracks: artist.topTracks),
                    );
                  }), // Convert map result to list


                // Albums Section
                _buildSectionHeader('Albums'),
                if (artist.topAlbums == null || artist.topAlbums!.isEmpty)
                  _buildEmptySectionPlaceholder("No albums found for this artist.")
                else
                  _buildAlbumList(context, musicProvider, artist.topAlbums!),

                const SizedBox(height: 20), // Bottom padding
              ]
          ),
        ),
      ],
    );
  }

  // Helper for section headers
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 12.0),
      child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
    );
  }

  // Helper for empty sections
  Widget _buildEmptySectionPlaceholder(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(message, style: const TextStyle(color: Colors.white70)),
    );
  }

  // Helper to build the horizontal album list
  Widget _buildAlbumList(BuildContext context, MusicProvider musicProvider, List<Album> albums) {
    return SizedBox(
      height: 190, // Adjust height for album art + text
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final album = albums[index];
          return SizedBox(
            width: 140, // Width of each album item
            child: GestureDetector(
              onTap: () async {
                // Fetch full album details and navigate
                await musicProvider.navigateToAlbum(album.name, album.artistName);
                if (context.mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(albumName: album.name, artistName: album.artistName)));
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1.0, // Square image
                    child: Container(
                      decoration: BoxDecoration(color: Colors.grey[850], borderRadius: BorderRadius.circular(8)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: album.imageUrl.isNotEmpty
                            ? Image.network(album.imageUrl, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.album, color: Colors.white70))
                            : const Icon(Icons.album, color: Colors.white70, size: 40),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(album.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  // Optional: Show year if available
                  // if (album.releaseDate != null)
                  //   Text(album.releaseDate!.year.toString(), style: TextStyle(color: Colors.grey[400], fontSize: 11)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}