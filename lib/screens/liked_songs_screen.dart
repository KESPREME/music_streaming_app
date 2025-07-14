// lib/screens/liked_songs_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart'; // Use standard TrackTile
import '../models/track.dart'; // Import model if needed

class LikedSongsScreen extends StatelessWidget {
  const LikedSongsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Use Consumer to rebuild when likedSongs list changes
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final likedSongs = musicProvider.likedSongs;

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1D1D1D),
            title: const Text(
              'Liked Songs',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white), // iOS style back
              onPressed: () => Navigator.of(context).pop(),
            ),
            // Optional: Play/Shuffle buttons for liked songs
            actions: [
              if (likedSongs.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.play_arrow, color: Colors.white),
                  tooltip: "Play Liked Songs",
                  onPressed: () {
                    // Play liked songs from the start
                    musicProvider.playTrack(
                        likedSongs.first,
                        playlistTracks: likedSongs
                    );
                  },
                ),
              if (likedSongs.isNotEmpty)
                IconButton(
                  icon: Icon(
                    // Reflect shuffle state only if this context is active? Or global?
                      musicProvider.shuffleEnabled ? Icons.shuffle_on : Icons.shuffle,
                      color: Colors.white
                  ),
                  tooltip: "Shuffle Liked Songs",
                  onPressed: () {
                    // Play liked songs shuffled
                    musicProvider.playTrack(
                      likedSongs.first, // Start with first logical track
                      playlistTracks: likedSongs,
                      // Assuming playTrack respects shuffle state if context matches
                    );
                    // Ensure shuffle is on if toggling it here
                    if (!musicProvider.shuffleEnabled) {
                      musicProvider.toggleShuffle();
                    }
                  },
                ),
              const SizedBox(width: 8), // Padding for actions
            ],
          ),
          body: likedSongs.isEmpty
              ? const Center(
            child: Column( // Improved empty state
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 60, color: Colors.white30),
                SizedBox(height: 16),
                Text(
                  'Songs you like will appear here',
                  style: TextStyle(color: Colors.white70, fontSize: 18),
                ),
                SizedBox(height: 8),
                Text(
                  'Tap the heart icon to save music.',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),
          )
              : ListView.builder(
            itemExtent: 72.0, // Optimization for fixed height items
            itemCount: likedSongs.length,
            itemBuilder: (context, index) {
              final track = likedSongs[index];
              final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;

              // Use the standard TrackTile
              return TrackTile(
                track: track,
                isPlaying: isPlaying, // Pass playing state for highlight
                // Override onTap to set the 'Liked Songs' list as context
                onTap: () {
                  musicProvider.playTrack(
                    track,
                    playlistTracks: likedSongs, // Pass the list
                    // No specific playlistId needed for 'Liked Songs' context
                  );
                },
                // Like button is handled via the PopupMenu in TrackTile now
                // showLikeButton: true, // Keep default or set explicitly
              );
            },
          ),
        );
      },
    );
  }
}