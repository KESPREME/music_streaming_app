// lib/widgets/track_tile.dart
import 'dart:typed_data'; // For potential artwork data (though not fully implemented for local files here)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// Only import on_audio_query if actively querying artwork within the tile (less efficient)
// import 'package:on_audio_query/on_audio_query.dart';
import '../models/track.dart'; // Import your Track model
import '../providers/music_provider.dart'; // Import your MusicProvider

// Import necessary screens or helpers for menu actions if you implement them
// e.g., import '../screens/artist_screen.dart';
// e.g., import '../screens/album_screen.dart';
// e.g., import 'package:share_plus/share_plus.dart'; // For sharing

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap; // Optional custom tap action
  final bool isPlaying;     // To indicate if this track is currently playing

  const TrackTile({
    required this.track,
    this.onTap,
    this.isPlaying = false, // Default to false
    super.key
  });

  // Helper to build the leading artwork widget
  Widget _buildArtworkWidget(BuildContext context) {
    // Prioritize network URL if available (covers YouTube, Spotify etc.)
    if (track.albumArtUrl.isNotEmpty) {
      return Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Colors.grey[850], // Background placeholder color
        ),
        child: ClipRRect( // Clip the image to match the container's border radius
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            track.albumArtUrl,
            fit: BoxFit.cover,
            // Error handling for network image loading
            errorBuilder: (context, error, stackTrace) {
              print("Error loading image ${track.albumArtUrl}: $error"); // Log error
              return const Center(child: Icon(Icons.music_note, color: Colors.white70, size: 30));
            },
            // Loading indicator while the image is fetched
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child; // Image is loaded, display it
              // Show a progress indicator while loading
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null, // Indeterminate if total size is unknown
                  strokeWidth: 2.0,
                  color: Colors.deepPurple.withOpacity(0.6),
                ),
              );
            },
          ),
        ),
      );
    }
    // Fallback for local files or tracks without a network URL (show placeholder icon)
    else {
      return Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Colors.grey[850], // Consistent placeholder background
        ),
        // Placeholder icon for missing artwork
        child: const Center(child: Icon(Icons.music_note, color: Colors.white70, size: 30)),
      );
      // Note: Displaying actual local artwork embedded in files requires more setup.
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    // --- Menu Item Builder ---
    List<PopupMenuEntry<String>> buildMenuItems(BuildContext context) {
      final items = <PopupMenuEntry<String>>[];
      final bool isLiked = Provider.of<MusicProvider>(context, listen: true).isSongLiked(track.id); // listen:true needed

      items.add(PopupMenuItem( value: 'toggle_like', child: ListTile( leading: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.redAccent : Colors.white70, size: 22), title: Text(isLiked ? 'Unlike' : 'Like Song', style: const TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)));
      items.add(const PopupMenuDivider(height: 1));
      items.add(const PopupMenuItem( value: 'add_queue', child: ListTile( leading: Icon(Icons.queue_music, color: Colors.white70, size: 22), title: Text('Add to Queue', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)));
      items.add(const PopupMenuItem( value: 'add_playlist', child: ListTile( leading: Icon(Icons.playlist_add, color: Colors.white70, size: 22), title: Text('Add to Playlist', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)));

      bool canGoToArtist = track.artistName.isNotEmpty && track.artistName != 'Unknown Artist' && track.source != 'local';
      bool canGoToAlbum = track.albumName.isNotEmpty && track.albumName != 'Unknown Album' && track.source != 'local';
      if (canGoToArtist || canGoToAlbum) {
        items.add(const PopupMenuDivider(height: 1));
        if (canGoToArtist) { items.add(const PopupMenuItem(value: 'goto_artist', child: ListTile(leading: Icon(Icons.person, color: Colors.white70, size: 22), title: Text('Go to Artist', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero))); }
        if (canGoToAlbum) { items.add(const PopupMenuItem(value: 'goto_album', child: ListTile(leading: Icon(Icons.album, color: Colors.white70, size: 22), title: Text('Go to Album', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero))); }
      }
      // TODO: Add Download/Remove Download Menu Items based on state
      items.add(const PopupMenuDivider(height: 1));
      items.add(const PopupMenuItem( value: 'share', child: ListTile( leading: Icon(Icons.share, color: Colors.white70, size: 22), title: Text('Share', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)));
      return items;
    }

    // --- Menu Selection Handler ---
    void handleMenuSelection(BuildContext context, String value) {
      final provider = Provider.of<MusicProvider>(context, listen: false);
      final messenger = ScaffoldMessenger.of(context);
      switch (value) {
        case 'toggle_like': provider.toggleLike(track); break;
        case 'add_playlist': messenger.showSnackBar(const SnackBar(content: Text('Add to Playlist: Not Implemented Yet'), duration: Duration(seconds: 2))); break;
        case 'add_queue': messenger.showSnackBar(const SnackBar(content: Text('Add to Queue: Not Implemented Yet'), duration: Duration(seconds: 2))); break;
        case 'goto_artist': messenger.showSnackBar(SnackBar(content: Text('Go to Artist: ${track.artistName} (Not Implemented)'), duration: Duration(seconds: 2))); break;
        case 'goto_album': messenger.showSnackBar(SnackBar(content: Text('Go to Album: ${track.albumName} (Not Implemented)'), duration: Duration(seconds: 2))); break;
        case 'share': messenger.showSnackBar(const SnackBar(content: Text('Share: Not Implemented Yet'), duration: Duration(seconds: 2))); break;
      // TODO: Handle download actions
      }
    }

    // --- Build Method ---
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      leading: _buildArtworkWidget(context),
      title: Text(
        track.trackName,
        style: TextStyle( color: isPlaying ? Theme.of(context).colorScheme.primary : Colors.white, fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal, fontSize: 15 ),
        maxLines: 1, overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.artistName,
        style: TextStyle(color: Colors.grey[400], fontSize: 13),
        maxLines: 1, overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: Colors.grey[500]),
        tooltip: "More options",
        onSelected: (value) => handleMenuSelection(context, value),
        itemBuilder: buildMenuItems, // Use the builder function
        color: const Color(0xFF282828),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onTap: onTap ?? () async {
        try {
          if (track.source == 'local') { await musicProvider.playOfflineTrack(track); }
          else { await musicProvider.playTrack(track); }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Error playing: ${e.toString().split(':').last.trim()}'), backgroundColor: Colors.redAccent));
          }
        }
      },
    );
  }
}