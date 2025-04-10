// lib/screens/playlist_songs_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Import Provider
import '../models/track.dart';
import '../widgets/track_tile.dart'; // Import standard TrackTile
import '../providers/music_provider.dart'; // Import MusicProvider

class PlaylistSongsScreen extends StatelessWidget {
  final String playlistName;
  final List<Track> tracks;
  // Optional: Pass playlistId if needed for context actions (like remove)
  final String? playlistId;

  const PlaylistSongsScreen({
    super.key,
    required this.playlistName,
    required this.tracks,
    this.playlistId, // Added optional playlistId
  });

  @override
  Widget build(BuildContext context) {
    // Access provider for isPlaying state if needed
    final musicProvider = Provider.of<MusicProvider>(context, listen: false); // Use listen:false if only for checking currentTrack

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D1D1D),
        title: Text(
          playlistName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white), // iOS style back
          onPressed: () => Navigator.of(context).pop(),
        ),
        // Optional: Add Play All/Shuffle buttons here if desired for this view
      ),
      body: tracks.isEmpty
          ? const Center(
        child: Column( // Improved empty state
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.queue_music, size: 60, color: Colors.white30),
            SizedBox(height: 16),
            Text(
              'This playlist is empty',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'Add some songs to get started!',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      )
          : ListView.builder(
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          // Check if this track is currently playing
          final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;

          // Use the standard TrackTile
          return TrackTile(
            track: track,
            isPlaying: isPlaying, // Pass playing state for highlighting
            // --- Contextual Playback ---
            // Option 1 (Simple - Plays track, may lose playlist context): Keep default onTap
            // Option 2 (Correct Context - Recommended): Override onTap
            onTap: () {
              musicProvider.playTrack(
                track,
                playlistId: playlistId, // Pass the playlistId if available
                playlistTracks: tracks, // Pass the full list for context
              );
            },
            // --- Contextual Remove ---
            // TODO: If you need "Remove from Playlist" here:
            // 1. Ensure playlistId is passed to this screen.
            // 2. Modify TrackTile to accept playlistId.
            // 3. Implement removal in TrackTile's handleMenuSelection using playlistId.
            // Example if TrackTile modified:
            // playlistId: playlistId,
          );
        },
      ),
    );
  }
}