import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/playlist.dart';
import '../widgets/material_you_track_tile.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';
import 'package:collection/collection.dart';

class MaterialYouPlaylistScreen extends StatelessWidget {
  final String playlistId;

  const MaterialYouPlaylistScreen({required this.playlistId, super.key});

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    final Playlist? playlist = musicProvider.userPlaylists.firstWhereOrNull(
      (p) => p.id == playlistId,
    );

    if (playlist == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Playlist not found or deleted.'),
              backgroundColor: MaterialYouTokens.surfaceContainerDark,
            ),
          );
        }
      });
      return Scaffold(backgroundColor: MaterialYouTokens.surfaceDark);
    }

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            stretch: true,
            backgroundColor: MaterialYouTokens.surfaceContainerDark,
            surfaceTintColor: Colors.transparent,
            elevation: 2,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              centerTitle: false,
              title: Text(
                playlist.name,
                style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  playlist.imageUrl.isNotEmpty
                      ? Image.network(
                          playlist.imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(color: MaterialYouTokens.surfaceContainerDark);
                          },
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: MaterialYouTokens.surfaceContainerDark,
                            child: Icon(
                              Icons.music_note,
                              color: colorScheme.onSurfaceVariant,
                              size: 80,
                            ),
                          ),
                        )
                      : Container(
                          color: MaterialYouTokens.surfaceContainerDark,
                          child: Icon(
                            Icons.queue_music,
                            color: colorScheme.onSurfaceVariant,
                            size: 80,
                          ),
                        ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.8, 1.0],
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
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.more_vert, color: colorScheme.onSurface),
                tooltip: "Playlist options",
                onPressed: () {
                  _showPlaylistOptionsBottomSheet(context, playlist);
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  Icon(Icons.music_note, color: colorScheme.onSurfaceVariant, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${playlist.tracks.length} track${playlist.tracks.length == 1 ? "" : "s"}',
                    style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: MaterialYouTokens.primaryVibrant,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play All'),
                    onPressed: playlist.tracks.isEmpty
                        ? null
                        : () {
                            musicProvider.playPlaylist(playlistId, startIndex: 0);
                          },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      musicProvider.shuffleEnabled && musicProvider.currentPlaylistId == playlistId
                          ? Icons.shuffle_on
                          : Icons.shuffle,
                      color: colorScheme.onSurface,
                      size: 28,
                    ),
                    tooltip: "Shuffle Play",
                    onPressed: playlist.tracks.isEmpty
                        ? null
                        : () {
                            musicProvider.playPlaylist(playlistId, startIndex: 0, shuffle: true);
                          },
                  ),
                ],
              ),
            ),
          ),
          if (playlist.tracks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'This playlist is empty.',
                  style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = playlist.tracks[index];
                  final isPlaying = musicProvider.currentTrack?.id == track.id && 
                                   musicProvider.isPlaying;

                  return MaterialYouTrackTile(
                    track: track,
                    isPlaying: isPlaying,
                    onTap: () {
                      musicProvider.playTrack(
                        track,
                        playlistId: playlistId,
                        playlistTracks: playlist.tracks,
                      );
                    },
                  );
                },
                childCount: playlist.tracks.length,
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      ),
    );
  }

  void _showPlaylistOptionsBottomSheet(BuildContext context, Playlist playlist) {
    final colorScheme = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: MaterialYouTokens.surfaceContainerDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MaterialYouTokens.shapeLarge)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_outlined, color: colorScheme.onSurface),
              title: Text(
                'Rename Playlist',
                style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
              ),
              onTap: () {
                Navigator.pop(context);
                _showRenamePlaylistDialog(context, playlist);
              },
            ),
            ListTile(
              leading: Icon(Icons.share_outlined, color: colorScheme.onSurface),
              title: Text(
                'Share Playlist',
                style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Share: Not Implemented')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(
                'Delete Playlist',
                style: MaterialYouTypography.bodyLarge(Colors.redAccent),
              ),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmationDialog(context, playlist);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRenamePlaylistDialog(BuildContext context, Playlist playlist) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final TextEditingController nameController = TextEditingController(text: playlist.name);
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MaterialYouTokens.surfaceContainerDark,
        title: Text(
          'Rename Playlist',
          style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colorScheme.onSurfaceVariant),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: MaterialYouTokens.primaryVibrant),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: MaterialYouTypography.labelLarge(colorScheme.onSurfaceVariant),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text(
              'Rename',
              style: MaterialYouTypography.labelLarge(MaterialYouTokens.primaryVibrant),
            ),
            onPressed: () {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty && newName != playlist.name) {
                musicProvider.renamePlaylist(playlist.id, newName);
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, Playlist playlist) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MaterialYouTokens.surfaceContainerDark,
        title: Text(
          'Delete Playlist?',
          style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
        ),
        content: Text(
          'Are you sure you want to permanently delete "${playlist.name}"?',
          style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: MaterialYouTypography.labelLarge(colorScheme.onSurfaceVariant),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text(
              'Delete',
              style: MaterialYouTypography.labelLarge(Colors.redAccent),
            ),
            onPressed: () {
              musicProvider.deletePlaylist(playlist.id);
              Navigator.pop(context);
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}
