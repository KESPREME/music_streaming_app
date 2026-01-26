import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart';
import '../models/album.dart';
// import '../models/track.dart'; // Commented out: Track is used via TrackTile and Album model

class AlbumScreen extends StatelessWidget {
  final String albumName;
  final String artistName;

  const AlbumScreen({
    required this.albumName,
    required this.artistName,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final albumDetails = musicProvider.currentAlbumDetails;
        final isLoading = musicProvider.isLoadingAlbum;
        final errorMessage = musicProvider.errorMessage;

        // Check if the loaded data is for the correct album/artist
        final bool isCorrectAlbumData = !isLoading &&
            albumDetails != null &&
            albumDetails.name == albumName &&
            albumDetails.artistName == artistName;

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: isLoading
              ? _buildLoadingState()
              : (errorMessage != null && !isCorrectAlbumData) || (!isLoading && albumDetails == null)
              ? _buildErrorState(errorMessage ?? "Could not load album details.")
              : _buildAlbumContent(context, musicProvider, albumDetails!),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
  }

  Widget _buildErrorState(String errorMsg) {
    // Provide a way back if loading fails
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,), // Simple AppBar for back button
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            errorMsg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 16),
          ),
        ),
      ),
    );
  }

  // Build content using CustomScrollView and SliverAppBar
  Widget _buildAlbumContent(BuildContext context, MusicProvider musicProvider, Album album) {
    final tracks = album.tracks;

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          expandedHeight: 300.0, // Make header larger for album art
          pinned: true,
          stretch: true,
          backgroundColor: const Color(0xFF1D1D1D),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            centerTitle: false, // Align left
            title: Column( // Use Column for title and subtitle
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.name,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                Text(
                  // Show artist and year if available
                  album.artistName + (album.releaseDate != null ? " • ${album.releaseDate!.year}" : ""),
                  style: TextStyle(color: Colors.grey[300], fontSize: 12, fontWeight: FontWeight.w400),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            background: Stack(
              fit: StackFit.expand,
              children: [
                // Album Image
                if (album.imageUrl.isNotEmpty)
                  Image.network(album.imageUrl, fit: BoxFit.cover, errorBuilder: (c,e,s)=> Container(color: Colors.grey[850], child: const Icon(Icons.album, size: 100, color: Colors.white70)))
                else
                  Container(color: Colors.grey[850], child: const Icon(Icons.album, size: 100, color: Colors.white70)),
                // Gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      stops: const [0.0, 0.5, 1.0],
                      colors: [ Colors.transparent, Colors.black.withOpacity(0.2), Colors.black.withOpacity(0.9)],
                    ),
                  ),
                ),
              ],
            ),
            stretchModes: const [StretchMode.zoomBackground, StretchMode.fadeTitle],
          ),
          actions: [
            // Optional actions like share, like album
            IconButton(
                icon: const Icon(Icons.share_outlined, color: Colors.white),
                tooltip: "Share Album",
                onPressed: () { /* TODO: Implement share album */ }
            ),
            IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                tooltip: "More options",
                onPressed: () { /* TODO: Show album options */ }
            )
          ],
        ),

        // Play All / Shuffle Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end, // Align buttons right
              children: [
                // TODO: Add track count/total duration if desired
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.play_circle_fill, color: Colors.deepPurpleAccent, size: 40),
                  tooltip: "Play Album",
                  onPressed: tracks.isEmpty ? null : () {
                    musicProvider.playTrack(tracks.first, playlistTracks: tracks);
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                      musicProvider.shuffleEnabled && musicProvider.currentPlaylistId == null && listEquals(musicProvider.localTracks, tracks) // Basic check if context matches
                          ? Icons.shuffle_on
                          : Icons.shuffle,
                      color: Colors.white70,
                      size: 30
                  ),
                  tooltip: "Shuffle Play",
                  onPressed: tracks.isEmpty ? null : () {
                    musicProvider.playTrack(tracks.first, playlistTracks: tracks);
                    if (!musicProvider.shuffleEnabled) musicProvider.toggleShuffle(); // Ensure shuffle is on
                  },
                ),
              ],
            ),
          ),
        ),

        // Track List
        if (tracks.isEmpty)
          const SliverFillRemaining(
            child: Center(child: Text('No tracks found for this album.', style: TextStyle(color: Colors.white70))),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final track = tracks[index];
                final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
                return TrackTile(
                  track: track,
                  isPlaying: isPlaying,
                  // Play track, setting this album list as the context
                  onTap: () => musicProvider.playTrack(
                      track,
                      playlistId: null, // Not an app playlist
                      playlistTracks: tracks
                  ),
                );
              },
              childCount: tracks.length,
            ),
          ),
      ],
    );
  }
}