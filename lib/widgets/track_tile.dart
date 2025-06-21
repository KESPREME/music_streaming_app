import 'dart:typed_data'; // Keep, might be used for local artwork in future
// import 'package:cached_network_image/cached_network_image.dart'; // Commented out
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../screens/artist_screen.dart';
import '../screens/album_screen.dart';
// import '../widgets/playlist_selection_sheet.dart'; // For "Add to Playlist" modal

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;
  final bool isPlaying;
  final String? playlistId; // For contextual actions like "Remove from this playlist"
  final bool dense; // For a more compact tile, e.g., in queues

  const TrackTile({
    required this.track,
    this.onTap,
    this.isPlaying = false,
    this.playlistId,
    this.dense = false,
    super.key,
  });

  Widget _buildArtworkWidget(BuildContext context, ThemeData theme) {
    final artworkSize = dense ? 40.0 : 50.0;
    if (track.albumArtUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(dense ? 4 : 6),
        child: Image.network( // Replaced CachedNetworkImage
          track.albumArtUrl,
          width: artworkSize,
          height: artworkSize,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: artworkSize,
            height: artworkSize,
            color: theme.colorScheme.surfaceVariant,
            child: Icon(Icons.broken_image, size: artworkSize * 0.6, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
          ),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: artworkSize,
              height: artworkSize,
              color: theme.colorScheme.surfaceVariant,
              child: Center(child: CircularProgressIndicator(value: loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : null, strokeWidth: 2.0,)),
            );
          },
        ),
      );
    } else {
      return Container(
        width: artworkSize,
        height: artworkSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(dense ? 4 : 6),
          color: theme.colorScheme.surfaceVariant,
        ),
        child: Icon(Icons.music_note, size: artworkSize * 0.6, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false); // listen:false for actions
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: dense ? 12.0 : 16.0, vertical: dense ? 4.0 : 8.0),
      leading: _buildArtworkWidget(context, theme),
      title: Text(
        track.trackName,
        style: (dense ? theme.textTheme.bodyLarge : theme.textTheme.titleMedium)?.copyWith(
          color: isPlaying ? theme.colorScheme.primary : theme.colorScheme.onSurface,
          fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: dense ? 1 : 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: track.artistName.isNotEmpty
          ? Text(
              track.artistName,
              style: (dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert_outlined, color: theme.iconTheme.color?.withOpacity(0.7)),
        tooltip: "More options",
        onSelected: (value) => _handleMenuSelection(context, value, musicProvider, theme),
        itemBuilder: (BuildContext context) => _buildMenuItems(context, musicProvider, theme),
        color: theme.colorScheme.surfaceVariant, // Themed background for dropdown
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onTap: onTap ??
          () async {
            try {
              if (track.source == 'local' || await musicProvider.isTrackDownloaded(track.id)) {
                await musicProvider.playOfflineTrack(track);
              } else {
                await musicProvider.playTrack(track);
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Error playing: ${e.toString().split(':').last.trim()}'),
                  backgroundColor: theme.colorScheme.error,
                ));
              }
            }
          },
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(BuildContext context, MusicProvider musicProvider, ThemeData theme) {
    final items = <PopupMenuEntry<String>>[];
    // Use a Consumer or Selector if isLiked needs to be reactive within the menu itself upon opening.
    // For simplicity, this uses the state at the time of menu build.
    final bool isLiked = musicProvider.isSongLiked(track.id);

    // Helper to create styled ListTiles for PopupMenuItems
    Widget _menuItemContent(String title, IconData icon, {Color? iconColor}) {
      return Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? theme.iconTheme.color?.withOpacity(0.8)),
          const SizedBox(width: 12),
          Text(title, style: theme.textTheme.bodyMedium),
        ],
      );
    }

    items.add(PopupMenuItem(
      value: 'toggle_like',
      child: _menuItemContent(
        isLiked ? 'Unlike' : 'Like Song',
        isLiked ? Icons.favorite : Icons.favorite_border_outlined,
        iconColor: isLiked ? theme.colorScheme.primary : null,
      ),
    ));

    items.add(const PopupMenuDivider());

    items.add(PopupMenuItem(value: 'add_queue', child: _menuItemContent('Add to Queue', Icons.queue_music_outlined)));
    items.add(PopupMenuItem(value: 'play_next', child: _menuItemContent('Play Next', Icons.playlist_play_outlined)));
    items.add(PopupMenuItem(value: 'add_playlist', child: _menuItemContent('Add to Playlist', Icons.playlist_add_outlined)));

    bool isArtistValid = track.artistName.isNotEmpty && track.artistName != 'Unknown Artist';
    bool isAlbumValid = track.albumName.isNotEmpty && track.albumName != 'Unknown Album' && track.albumName != 'YouTube';

    if (isArtistValid || isAlbumValid) {
      items.add(const PopupMenuDivider());
      if (isArtistValid) {
        items.add(PopupMenuItem(value: 'goto_artist', child: _menuItemContent('Go to Artist', Icons.person_outline)));
      }
      if (isAlbumValid) {
        items.add(PopupMenuItem(value: 'goto_album', child: _menuItemContent('Go to Album', Icons.album_outlined)));
      }
    }

    // Future-based download status for menu item (can be complex for sync update)
    // Consider a simpler approach or ensure provider state is efficiently updated for this
    // For now, a basic check:
    // bool isDownloaded = musicProvider.downloadedTracksMetadata.containsKey(track.id); // Simplified check
    // if (track.source != 'local') {
    //   items.add(const PopupMenuDivider());
    //   if (isDownloaded) {
    //     items.add(PopupMenuItem(value: 'remove_download', child: _menuItemContent('Remove Download', Icons.download_done_outlined, iconColor: theme.colorScheme.primary)));
    //   } else if (musicProvider.isDownloading[track.id] ?? false) {
    //      items.add(PopupMenuItem(value: 'cancel_download', child: _menuItemContent('Cancel Download', Icons.cancel_outlined, iconColor: Colors.orangeAccent)));
    //   }
    //   else {
    //     items.add(PopupMenuItem(value: 'download', child: _menuItemContent('Download', Icons.download_outlined)));
    //   }
    // }


    items.add(const PopupMenuDivider());
    items.add(PopupMenuItem(value: 'share', child: _menuItemContent('Share', Icons.share_outlined)));

    if (playlistId != null) {
      items.add(const PopupMenuDivider());
      items.add(PopupMenuItem(
        value: 'remove_from_playlist',
        child: _menuItemContent('Remove from Playlist', Icons.remove_circle_outline_outlined, iconColor: theme.colorScheme.error),
      ));
    }
    return items;
  }

  void _handleMenuSelection(BuildContext context, String value, MusicProvider provider, ThemeData theme) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    bool isArtistValid = track.artistName.isNotEmpty && track.artistName != 'Unknown Artist';
    bool isAlbumValid = track.albumName.isNotEmpty && track.albumName != 'Unknown Album' && track.albumName != 'YouTube';

    switch (value) {
      case 'toggle_like':
        provider.toggleLike(track);
        // Feedback can be handled by observing provider state elsewhere or with a SnackBar
        // messenger.showSnackBar(SnackBar(content: Text(provider.isSongLiked(track.id) ? 'Added to Liked Songs' : 'Removed from Liked Songs'), duration: const Duration(seconds: 1)));
        break;
      case 'add_playlist':
        // TODO: Implement _showAddToPlaylistBottomSheet from NowPlayingScreen or similar
        // For now, placeholder:
        messenger.showSnackBar(SnackBar(
            content: Text('Add to playlist (not implemented)'),
            backgroundColor: theme.colorScheme.surfaceVariant,
            behavior: SnackBarBehavior.floating,
        ));
        break;
      case 'add_queue':
        provider.addToQueue(track);
        messenger.showSnackBar(SnackBar(content: Text('Added "${track.trackName}" to queue'), duration: const Duration(seconds: 1)));
        break;
      case 'play_next':
        provider.playNext(track);
        messenger.showSnackBar(SnackBar(content: Text('Playing "${track.trackName}" next'), duration: const Duration(seconds: 1)));
        break;
      case 'goto_artist':
        if (!isArtistValid) {
          messenger.showSnackBar(const SnackBar(content: Text('Artist details not available')));
          return;
        }
        await provider.navigateToArtist(track.artistName);
        if (!context.mounted) return;
        if (provider.currentArtistDetails != null) {
          navigator.push(MaterialPageRoute(builder: (_) => ArtistScreen(artistName: track.artistName)));
        } else {
          messenger.showSnackBar(SnackBar(content: Text(provider.errorMessage ?? 'Could not load artist'), backgroundColor: theme.colorScheme.error));
        }
        break;
      case 'goto_album':
        if (!isAlbumValid) {
          messenger.showSnackBar(const SnackBar(content: Text('Album details not available')));
          return;
        }
        await provider.navigateToAlbum(track.albumName, track.artistName);
        if (!context.mounted) return;
        if (provider.currentAlbumDetails != null) {
          navigator.push(MaterialPageRoute(builder: (_) => AlbumScreen(albumName: track.albumName, artistName: track.artistName)));
        } else {
          messenger.showSnackBar(SnackBar(content: Text(provider.errorMessage ?? 'Could not load album'), backgroundColor: theme.colorScheme.error));
        }
        break;
      case 'share':
        String shareText = 'Check out this track: ${track.trackName} by ${track.artistName}';
        if (track.source == 'youtube' && track.previewUrl.startsWith('http')) {
          shareText += '\nListen here: ${track.previewUrl}';
        }
        try {
          await Share.share(shareText, subject: 'Music Recommendation');
        } catch (e) {
          messenger.showSnackBar(const SnackBar(content: Text('Could not share track.')));
        }
        break;
      case 'remove_from_playlist':
        if (playlistId != null) {
          provider.removeTrackFromPlaylist(playlistId!, track.id);
          // SnackBar feedback is often handled in the provider or calling screen
        }
        break;
      // case 'download':
      //   if (!(await provider.isTrackDownloaded(track.id)) && !(provider.isDownloading[track.id] ?? false)) {
      //     provider.downloadTrack(track);
      //     messenger.showSnackBar(SnackBar(content: Text('Downloading ${track.trackName}...')));
      //   } else if (await provider.isTrackDownloaded(track.id)) {
      //      messenger.showSnackBar(SnackBar(content: Text('${track.trackName} is already downloaded.')));
      //   }
      //   break;
      // case 'remove_download':
      //   provider.deleteDownloadedTrack(track.id);
      //   messenger.showSnackBar(SnackBar(content: Text('Removed download for ${track.trackName}')));
      //   break;
      // case 'cancel_download':
      //   provider.cancelDownload(track.id);
      //   messenger.showSnackBar(SnackBar(content: Text('Download cancelled for ${track.trackName}')));
      //   break;
    }
  }
}