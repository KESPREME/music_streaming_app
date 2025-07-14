// lib/screens/recently_played_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart'; // Use standard TrackTile
import '../models/track.dart'; // Import Track model

class RecentlyPlayedScreen extends StatelessWidget {
  const RecentlyPlayedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Use Consumer to automatically rebuild when recentlyPlayed list changes
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final recentlyPlayedTracks = musicProvider.recentlyPlayed;

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1D1D1D),
            title: const Text(
              'Recently Played',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white), // iOS style back
              onPressed: () => Navigator.of(context).pop(),
            ),
            // Optional: Add a clear history button?
            // actions: [
            //   if (recentlyPlayedTracks.isNotEmpty)
            //     IconButton(
            //       icon: Icon(Icons.clear_all, color: Colors.white70),
            //       tooltip: "Clear History",
            //       onPressed: () { /* TODO: Implement clear history confirmation */ },
            //     ),
            // ],
          ),
          body: recentlyPlayedTracks.isEmpty
              ? const Center(
            child: Column( // Improved empty state
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_toggle_off, size: 60, color: Colors.white30),
                SizedBox(height: 16),
                Text(
                  'No recently played tracks',
                  style: TextStyle(color: Colors.white70, fontSize: 18),
                ),
                SizedBox(height: 8),
                Text(
                  'Start listening to build your history!',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),
          )
              : ListView.builder(
            itemExtent: 72.0, // Optimization for fixed height items
            itemCount: recentlyPlayedTracks.length,
            itemBuilder: (context, index) {
              final track = recentlyPlayedTracks[index];
              final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;

              // Use the standard TrackTile
              return TrackTile(
                track: track,
                isPlaying: isPlaying, // Pass playing state for highlight
                // Default onTap plays the track
                // onTap: () => musicProvider.playTrack(track, playlistTracks: recentlyPlayedTracks), // Optionally set context

                // TODO: To enable "Remove from Recently Played" in the menu:
                // 1. Modify TrackTile to accept a context identifier or specific callbacks.
                // 2. Example: Add `TrackListContext contextType = TrackListContext.recentlyPlayed` parameter.
                // 3. In TrackTile's buildMenuItems, show "Remove" if contextType is recentlyPlayed.
                // 4. In TrackTile's handleMenuSelection, call `provider.removeFromRecentlyPlayed(track.id)` for that item.
                // Example if TrackTile modified:
                // contextType: TrackListContext.recentlyPlayed,
              );
            },
          ),
        );
      },
    );
  }
}

// Example enum to define context (could be placed in a shared file)
// enum TrackListContext { general, playlist, recentlyPlayed, liked, search, downloads, local }