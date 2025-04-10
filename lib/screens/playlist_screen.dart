// lib/screens/playlist_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/playlist.dart';
import '../widgets/track_tile.dart'; // Import the updated TrackTile
import 'package:collection/collection.dart';

class PlaylistScreen extends StatelessWidget {
  final String playlistId;

  const PlaylistScreen({required this.playlistId, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use watch to rebuild if playlists change (e.g., name edit, deletion)
    final musicProvider = Provider.of<MusicProvider>(context);

    // Find the playlist safely
    final Playlist? playlist = musicProvider.userPlaylists.firstWhereOrNull(
          (p) => p.id == playlistId,
    );

    // Handle playlist not found case
    if (playlist == null) {
      // It's better to pop back immediately if the playlist is gone
      // or show a dedicated "Not Found" screen.
      // Popping back is often preferred if deletion might happen while user is here.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
          // Show a message on the previous screen
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Playlist not found or deleted.'), backgroundColor: Colors.red),
          );
        }
      });
      // Return an empty scaffold while waiting for pop
      return const Scaffold(backgroundColor: Color(0xFF121212));
    }

    // Build the main UI if playlist is found
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220, // Slightly more height for title space
            pinned: true, // Keep AppBar visible when scrolling
            stretch: true, // Allow stretching on overscroll
            backgroundColor: const Color(0xFF1D1D1D), // Consistent dark color
            // Use leading for back button consistency
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              centerTitle: false, // Align title left
              title: Text(
                playlist.name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18), // Adjusted size
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Playlist Image or Placeholder
                  playlist.imageUrl.isNotEmpty
                      ? Image.network(
                    playlist.imageUrl,
                    fit: BoxFit.cover,
                    // Add loading builder
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(color: Colors.grey[850]); // Placeholder color while loading
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey[850],
                      child: const Icon(Icons.music_note, color: Colors.white70, size: 80),
                    ),
                  )
                      : Container( // Placeholder if no image URL
                    color: Colors.grey[850],
                    child: const Icon(Icons.queue_music, color: Colors.white70, size: 80), // Different placeholder
                  ),
                  // Gradient Overlay for text visibility
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.8, 1.0], // Adjust stops for gradient effect
                        colors: [
                          Colors.black.withOpacity(0.0),
                          Colors.black.withOpacity(0.4),
                          Colors.black.withOpacity(0.8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // stretchModes: const [StretchMode.zoomBackground, StretchMode.fadeTitle],
            ),
            actions: [
              // Playlist Options Menu
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                tooltip: "Playlist options",
                onPressed: () {
                  _showPlaylistOptionsBottomSheet(context, playlist);
                },
              ),
            ],
          ),
          // Header section with track count and play buttons
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  Icon(Icons.music_note, color: Colors.grey[400], size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${playlist.tracks.length} track${playlist.tracks.length == 1 ? "" : "s"}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  const Spacer(), // Pushes buttons to the right
                  // Play All Button
                  IconButton(
                    icon: const Icon(Icons.play_circle_fill, color: Colors.deepPurpleAccent, size: 36),
                    tooltip: "Play All",
                    onPressed: playlist.tracks.isEmpty ? null : () {
                      musicProvider.playPlaylist(playlistId, startIndex: 0);
                    },
                  ),
                  const SizedBox(width: 8),
                  // Shuffle Button
                  IconButton(
                    icon: Icon(
                      // Reflect current shuffle state if playlist context matches
                        musicProvider.shuffleEnabled && musicProvider.currentPlaylistId == playlistId
                            ? Icons.shuffle_on
                            : Icons.shuffle,
                        color: Colors.white70,
                        size: 28
                    ),
                    tooltip: "Shuffle Play",
                    onPressed: playlist.tracks.isEmpty ? null : () {
                      // Ensure shuffle is ON when shuffle playing
                      musicProvider.playPlaylist(playlistId, startIndex: 0, shuffle: true); // Assuming playPlaylist takes shuffle bool
                    },
                  ),
                ],
              ),
            ),
          ),
          // Track List
          if (playlist.tracks.isEmpty)
            const SliverFillRemaining( // Use SliverFillRemaining for empty state in CustomScrollView
              child: Center(
                child: Text('This playlist is empty.', style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final track = playlist.tracks[index];
                  final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;

                  // Use the standard TrackTile
                  return TrackTile(
                    track: track,
                    isPlaying: isPlaying, // Pass playing state for highlighting
                    // Custom onTap to set the correct playlist context when playing
                    onTap: () {
                      musicProvider.playTrack(
                        track,
                        playlistId: playlistId, // Pass current playlist ID
                        playlistTracks: playlist.tracks, // Pass the list of tracks
                      );
                    },
                    // TODO: To enable "Remove from Playlist" in the TrackTile's menu:
                    // 1. Modify TrackTile to accept an optional playlistId parameter.
                    // 2. Modify TrackTile's buildMenuItems to show "Remove from Playlist" if playlistId is not null.
                    // 3. Modify TrackTile's handleMenuSelection to call provider.removeTrackFromPlaylist(playlistId!, track.id) for that menu item.
                    // Pass the playlistId here:
                    // playlistId: playlistId, // Example if TrackTile is modified
                  );
                },
                childCount: playlist.tracks.length,
              ),
            ),
        ],
      ),
    );
  }

  // --- Bottom Sheet for Playlist Options ---
  void _showPlaylistOptionsBottomSheet(BuildContext context, Playlist playlist) {
    // No provider needed here if actions below call it with listen: false
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF282828), // Darker background
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea( // Ensure content is within safe area
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.white70),
              title: const Text('Rename Playlist', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showRenamePlaylistDialog(context, playlist); // Show rename dialog
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined, color: Colors.white70),
              title: const Text('Share Playlist', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement share functionality (e.g., share playlist link if applicable)
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Share: Not Implemented')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete Playlist', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context); // Close bottom sheet first
                _showDeleteConfirmationDialog(context, playlist); // Show confirmation dialog
              },
            ),
            const SizedBox(height: 8), // Add some bottom padding
          ],
        ),
      ),
    );
  }

  // --- Dialog for Renaming Playlist ---
  void _showRenamePlaylistDialog(BuildContext context, Playlist playlist) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final TextEditingController nameController = TextEditingController(text: playlist.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Rename Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Colors.grey[600]),
            // Add borders for better visibility
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[700]!)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.deepPurpleAccent)),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Rename', style: TextStyle(color: Colors.deepPurpleAccent)),
            onPressed: () {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty && newName != playlist.name) {
                musicProvider.renamePlaylist(playlist.id, newName);
              }
              Navigator.pop(context); // Close the dialog
            },
          ),
        ],
      ),
    );
  }


  // --- Dialog for Deleting Playlist ---
  void _showDeleteConfirmationDialog(BuildContext context, Playlist playlist) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF282828), // Consistent dark color
        title: const Text('Delete Playlist?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to permanently delete "${playlist.name}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            onPressed: () => Navigator.pop(context), // Close only this dialog
          ),
          TextButton(
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            onPressed: () {
              musicProvider.deletePlaylist(playlist.id);
              Navigator.pop(context); // Close the confirmation dialog
              // Check if the current screen can still be popped (might already be gone if playlist deleted)
              if (Navigator.canPop(context)) {
                Navigator.pop(context); // Go back from PlaylistScreen itself
              }
            },
          ),
        ],
      ),
    );
  }
}