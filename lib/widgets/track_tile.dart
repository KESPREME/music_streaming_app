// lib/widgets/track_tile.dart

// Dart Core Libraries
import 'dart:typed_data'; // For potential artwork data

// Flutter Foundation & Material
import 'package:flutter/material.dart';

// Flutter Packages
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart'; // For sharing functionality

// Only import on_audio_query if actively querying artwork within the tile (less efficient)
// import 'package:on_audio_query/on_audio_query.dart';

// Your Project Model Imports
import '../models/track.dart'; // Import your Track model

// Your Project Provider Imports
import '../providers/music_provider.dart'; // Import your MusicProvider

// Your Project Screen Imports (Needed for Navigation Actions)
import '../screens/artist_screen.dart'; // Import placeholder ArtistScreen
import '../screens/album_screen.dart'; // Import placeholder AlbumScreen
// Import your playlist selection widget/modal if implementing "Add to Playlist"
// import '../widgets/playlist_selection_sheet.dart'; // Example

// Optional: Define context enum if needed for more complex menu variations
// enum TrackListContext { general, playlist, recentlyPlayed, liked, search, downloads, local }

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap; // Optional custom tap action (e.g., for setting playlist context)
  final bool isPlaying;     // To indicate if this track is currently playing

  // Optional: Pass context identifiers if specific menu actions are needed
  final String? playlistId; // Example for removing from specific playlist
  // final TrackListContext? listContext; // Example using an enum

  const TrackTile({
    required this.track,
    this.onTap,
    this.isPlaying = false, // Default to false
    this.playlistId,      // Make playlistId optional
    // this.listContext,
    super.key
  });

  // --- Artwork Widget ---
  // Builds the leading widget displaying album art or a placeholder
  Widget _buildArtworkWidget(BuildContext context) {
    // Prioritize network URL if available (covers YouTube, Spotify etc.)
    if (track.albumArtUrl.isNotEmpty) {
      return Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Colors.grey[850], // Background placeholder color
        ),
        // ClipRRect ensures the image adheres to the container's border radius
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            track.albumArtUrl,
            fit: BoxFit.cover, // Cover the container bounds
            // Display placeholder icon on network error
            errorBuilder: (context, error, stackTrace) {
              // Log error for debugging
              // print("Error loading image ${track.albumArtUrl}: $error");
              return const Center(child: Icon(Icons.music_note, color: Colors.white70, size: 30));
            },
            // Display a loading indicator while the image is fetched
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child; // Image is loaded
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null, // Indeterminate progress if size unknown
                  strokeWidth: 2.0,
                  color: Colors.deepPurple.withOpacity(0.6),
                ),
              );
            },
          ),
        ),
      );
    }
    // Fallback for local files or tracks without a network URL
    else {
      // Show a placeholder icon
      return Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Colors.grey[850], // Consistent placeholder background
        ),
        child: const Center(child: Icon(Icons.music_note, color: Colors.white70, size: 30)),
      );
      // Note on local artwork: Displaying embedded artwork efficiently requires
      // extracting it when loading tracks and storing it in the Track model.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use listen: false when only calling methods (like in handleMenuSelection)
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    // --- Menu Item Builder ---
    // Dynamically creates the list of options for the PopupMenuButton
    List<PopupMenuEntry<String>> buildMenuItems(BuildContext context) {
      final items = <PopupMenuEntry<String>>[];
      // Use listen: true here or specific Selector for reactivity if needed
      final bool isLiked = Provider.of<MusicProvider>(context, listen: true).isSongLiked(track.id);

      // 1. Like/Unlike Option
      items.add(PopupMenuItem(
        value: 'toggle_like',
        child: ListTile(
          leading: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.redAccent : Colors.white70, size: 22),
          title: Text(isLiked ? 'Unlike' : 'Like Song', style: const TextStyle(color: Colors.white, fontSize: 14)),
          dense: true, contentPadding: EdgeInsets.zero,
        ),
      ));

      items.add(const PopupMenuDivider(height: 1));

      // 2. Queue Options
      items.add(const PopupMenuItem(
          value: 'add_queue',
          child: ListTile( leading: Icon(Icons.queue_music, color: Colors.white70, size: 22), title: Text('Add to Queue', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)
      ));
      items.add(const PopupMenuItem(
          value: 'play_next',
          child: ListTile( leading: Icon(Icons.playlist_play, color: Colors.white70, size: 22), title: Text('Play Next', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)
      ));

      // 3. Playlist Option
      items.add(const PopupMenuItem(
          value: 'add_playlist',
          child: ListTile( leading: Icon(Icons.playlist_add, color: Colors.white70, size: 22), title: Text('Add to Playlist', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)
      ));


      // 4. Go To Options (Conditional)
      bool isArtistValid = track.artistName.isNotEmpty && track.artistName != 'Unknown Artist';
      bool isAlbumValid = track.albumName.isNotEmpty && track.albumName != 'Unknown Album' && track.albumName != 'YouTube'; // Check generic name
      if (isArtistValid || isAlbumValid) {
        items.add(const PopupMenuDivider(height: 1));
        if (isArtistValid) { items.add(const PopupMenuItem(value: 'goto_artist', child: ListTile(leading: Icon(Icons.person, color: Colors.white70, size: 22), title: Text('Go to Artist', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero))); }
        if (isAlbumValid) { items.add(const PopupMenuItem(value: 'goto_album', child: ListTile(leading: Icon(Icons.album, color: Colors.white70, size: 22), title: Text('Go to Album', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero))); }
      }

      // 5. Download Options (Conditional - Requires Provider State)
      // Example implementation (requires checking provider state)
      // bool isDownloaded = musicProvider.isTrackDownloaded(track.id); // Need async or state check
      // bool isDownloading = musicProvider.isDownloading[track.id] ?? false;
      // if (track.source != 'local') { // Can't download local files
      //    items.add(const PopupMenuDivider(height: 1));
      //    if (isDownloaded) {
      //        items.add(const PopupMenuItem(value: 'remove_download', child: ListTile(leading: Icon(Icons.download_done, color: Colors.deepPurple), title: Text('Remove Download', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)));
      //    } else if (isDownloading) {
      //        // Optionally show progress or just cancel
      //        items.add(const PopupMenuItem(value: 'cancel_download', child: ListTile(leading: Icon(Icons.cancel, color: Colors.orange), title: Text('Cancel Download', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)));
      //    } else {
      //        items.add(const PopupMenuItem(value: 'download', child: ListTile(leading: Icon(Icons.download, color: Colors.white70), title: Text('Download', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)));
      //    }
      // }

      // 6. Share Option
      items.add(const PopupMenuDivider(height: 1));
      items.add(const PopupMenuItem(
          value: 'share',
          child: ListTile( leading: Icon(Icons.share, color: Colors.white70, size: 22), title: Text('Share', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)
      ));

      // 7. Contextual Remove Option (Example - Requires passing context/ID)
      if (playlistId != null) { // Check if playlistId was passed
        items.add(const PopupMenuDivider(height: 1));
        items.add(const PopupMenuItem(value: 'remove_from_playlist', child: ListTile(leading: Icon(Icons.remove_circle_outline, color: Colors.orangeAccent, size: 22), title: Text('Remove from Playlist', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)));
      }
      // else if (listContext == TrackListContext.recentlyPlayed) { // Example using enum
      //    items.add(const PopupMenuDivider(height: 1));
      //    items.add(const PopupMenuItem(value: 'remove_from_recent', child: ListTile(leading: Icon(Icons.delete_sweep, color: Colors.orangeAccent, size: 22), title: Text('Remove from Recently Played', style: TextStyle(color: Colors.white, fontSize: 14)), dense: true, contentPadding: EdgeInsets.zero)));
      // }


      return items;
    }

    // --- Menu Selection Handler ---
    // Called when a user taps an option from the PopupMenuButton
    void handleMenuSelection(BuildContext context, String value) async { // Make async for navigation/sharing
      // Use listen: false here as we are only calling actions/methods
      final provider = Provider.of<MusicProvider>(context, listen: false);
      final messenger = ScaffoldMessenger.of(context); // Cache for showing SnackBars
      final navigator = Navigator.of(context); // Cache navigator

      // Check validity for navigation actions before the switch
      bool isArtistValid = track.artistName.isNotEmpty && track.artistName != 'Unknown Artist';
      bool isAlbumValid = track.albumName.isNotEmpty && track.albumName != 'Unknown Album' && track.albumName != 'YouTube';

      switch (value) {
        case 'toggle_like':
          provider.toggleLike(track);
          // Optional feedback
          // final bool isNowLiked = provider.isSongLiked(track.id); // Check state *after* toggle
          // messenger.showSnackBar(SnackBar(content: Text(isNowLiked ? 'Added to Liked Songs' : 'Removed from Liked Songs'), duration: Duration(seconds: 1)));
          break;
        case 'add_playlist':
        // TODO: Implement UI to show playlist selection
        // Example: showModalBottomSheet(context: context, builder: (_) => YourPlaylistSelectionWidget(trackToAdd: track));
          messenger.showSnackBar(const SnackBar(content: Text('Add to Playlist: Not Implemented Yet'), duration: Duration(seconds: 2)));
          break;
        case 'add_queue':
          provider.addToQueue(track); // Call provider method
          messenger.showSnackBar(SnackBar(content: Text('Added "${track.trackName}" to queue'), duration: const Duration(seconds: 1)));
          break;
        case 'play_next':
          provider.playNext(track); // Call provider method
          messenger.showSnackBar(SnackBar(content: Text('Playing "${track.trackName}" next'), duration: const Duration(seconds: 1)));
          break;
        case 'goto_artist':
          if (!isArtistValid) {
            messenger.showSnackBar(const SnackBar(content: Text('Artist details not available'), duration: Duration(seconds: 2)));
            return;
          }
          await provider.navigateToArtist(track.artistName); // Trigger data fetch
          if (!context.mounted) return; // Check mounted after await
          if (provider.currentArtistDetails != null) { // Check if data was loaded
            navigator.push(MaterialPageRoute(builder: (_) => ArtistScreen(artistName: track.artistName)));
          } else { // Show error if provider failed to load data
            messenger.showSnackBar(SnackBar(content: Text(provider.errorMessage ?? 'Could not load artist'), backgroundColor: Colors.redAccent));
          }
          break;
        case 'goto_album':
          if (!isAlbumValid) {
            messenger.showSnackBar(const SnackBar(content: Text('Album details not available'), duration: Duration(seconds: 2)));
            return;
          }
          await provider.navigateToAlbum(track.albumName, track.artistName); // Trigger data fetch
          if (!context.mounted) return;
          if (provider.currentAlbumDetails != null) { // Check if data was loaded
            navigator.push(MaterialPageRoute(builder: (_) => AlbumScreen(albumName: track.albumName, artistName: track.artistName)));
          } else {
            messenger.showSnackBar(SnackBar(content: Text(provider.errorMessage ?? 'Could not load album'), backgroundColor: Colors.redAccent));
          }
          break;
        case 'share':
          String shareText = 'Check out: ${track.trackName} by ${track.artistName}';
          if (track.source == 'youtube' && track.previewUrl.startsWith('http')) { shareText += '\n${track.previewUrl}'; }
          // else if (track.source == 'spotify') { shareText += '\nhttps://open.spotify.com/track/${track.id}'; } // Example Spotify link
          try { await Share.share(shareText, subject: 'Check out this track!'); }
          catch (e) { print("Error sharing: $e"); messenger.showSnackBar(const SnackBar(content: Text('Could not share track.'), duration: Duration(seconds: 2))); }
          break;

      // --- Handle Contextual Remove Actions ---
        case 'remove_from_playlist':
          if (playlistId != null) { // Check if playlistId was provided to the tile
            provider.removeTrackFromPlaylist(playlistId!, track.id);
            // SnackBar feedback is handled in the provider method currently
          } else {
            print("Error: remove_from_playlist called without playlistId");
          }
          break;
      // case 'remove_from_recent': // Example if using listContext enum
      //    provider.removeFromRecentlyPlayed(track.id);
      //    break;

      // --- Handle Download Actions ---
      // case 'download': provider.downloadTrack(track); break;
      // case 'remove_download': provider.deleteDownloadedTrack(track.id); break;
      // case 'cancel_download': provider.cancelDownload(track.id); break;
      }
    }

    // --- Build Method ---
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      leading: _buildArtworkWidget(context),
      title: Text(
        track.trackName,
        style: TextStyle( color: isPlaying ? Theme.of(context).colorScheme.primary : Colors.white, fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal, fontSize: 15 ),
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
        itemBuilder: buildMenuItems,
        color: const Color(0xFF282828),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onTap: onTap ?? () async { // Default tap action: Play the track
        try {
          if (track.source == 'local') { await musicProvider.playOfflineTrack(track); }
          else { await musicProvider.playTrack(track); }
        } catch (e) {
          if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Error playing: ${e.toString().split(':').last.trim()}'), backgroundColor: Colors.redAccent)); }
        }
      },
    );
  }
}