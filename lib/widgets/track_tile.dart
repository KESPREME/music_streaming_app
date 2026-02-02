// Keep, might be used for local artwork in future
// import 'package:cached_network_image/cached_network_image.dart'; // Commented out
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../screens/artist_screen.dart';
import '../screens/album_screen.dart';
import 'playlist_selection_dialog.dart'; // Import the dialog
import 'themed_options_sheet.dart';
import 'glass_snackbar.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;
  final bool isPlaying;
  final String? playlistId; // For contextual actions like "Remove from this playlist"
  final bool dense; // For a more compact tile, e.g., in queues
  final bool isInQueueContext; // New parameter
  final bool isRecentlyPlayedContext;
  final Color? backgroundColor;

  const TrackTile({
    required this.track,
    this.onTap,
    this.isPlaying = false,
    this.playlistId,
    this.dense = false,
    this.isInQueueContext = false, // Default to false
    this.isRecentlyPlayedContext = false,
    this.backgroundColor,
    super.key,
  });

  Widget _buildArtworkWidget(BuildContext context, ThemeData theme) {
    final artworkSize = dense ? 40.0 : 50.0;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (artworkSize * pixelRatio).round();

    if (track.albumArtUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(dense ? 4 : 6),
        child: Image.network( // Replaced CachedNetworkImage
          track.albumArtUrl,
          width: artworkSize,
          height: artworkSize,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: artworkSize,
            height: artworkSize,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Icon(Icons.broken_image, size: artworkSize * 0.6, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
          ),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: artworkSize,
              height: artworkSize,
              color: theme.colorScheme.surfaceContainerHighest,
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
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        child: Icon(Icons.music_note, size: artworkSize * 0.6, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false); // listen:false for actions
    final theme = Theme.of(context);

    // Standard height for a non-dense ListTile is around 72.0 with default padding
    // Our leading is 50, vertical padding is 8*2=16. Total height is ~66.
    // We can use this for itemExtent optimization in ListView.builder.

    return ListTile(
      tileColor: backgroundColor, // Apply background color
      contentPadding: EdgeInsets.symmetric(horizontal: dense ? 12.0 : 16.0, vertical: dense ? 4.0 : 8.0),
      leading: _buildArtworkWidget(context, theme),
      title: Text(
        track.trackName,
        style: (dense ? theme.textTheme.bodyLarge : theme.textTheme.titleMedium)?.copyWith(
          color: isPlaying ? const Color(0xFFFF1744) : theme.colorScheme.onSurface,
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
      trailing: IconButton(
        icon: Icon(Icons.more_vert_rounded, color: theme.iconTheme.color?.withOpacity(0.7)),
        onPressed: () {
          ThemedOptionsSheet.show(
            context,
            track: track,
            isRecentlyPlayedContext: isRecentlyPlayedContext,
          );
        },
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
                showGlassSnackBar(context, 'Error playing: ${e.toString().split(':').last.trim()}');
              }
            }
          },
    );
  }
}

