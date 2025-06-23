import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';

Future<void> showPlaylistSelectionDialog(BuildContext context, Track trackToAdd) async {
  final musicProvider = Provider.of<MusicProvider>(context, listen: false);
  final theme = Theme.of(context);

  // TextEditingController for the new playlist name
  final TextEditingController newPlaylistNameController = TextEditingController();

  await showModalBottomSheet(
    context: context,
    backgroundColor: theme.colorScheme.surfaceVariant,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext bottomSheetContext) {
      // Use a StatefulBuilder to manage the list of playlists dynamically if a new one is created
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setStateModal) {
          final userPlaylists = musicProvider.userPlaylists;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Add to Playlist',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Icon(Icons.add_circle_outline, color: theme.colorScheme.primary, size: 28),
                  title: Text('Create New Playlist', style: theme.textTheme.titleMedium),
                  onTap: () async {
                    // Close current bottom sheet
                    Navigator.pop(bottomSheetContext);
                    // Show dialog to create new playlist
                    final String? createdPlaylistName = await showDialog<String>(
                      context: context, // Use the original context for the dialog
                      builder: (BuildContext dialogContext) {
                        return AlertDialog(
                          title: Text('Create New Playlist', style: theme.dialogTheme.titleTextStyle),
                          content: TextField(
                            controller: newPlaylistNameController,
                            autofocus: true,
                            decoration: InputDecoration(hintText: "Playlist Name"),
                            style: theme.textTheme.bodyLarge,
                          ),
                          actions: <Widget>[
                            TextButton(
                              child: Text('Cancel', style: theme.textButtonTheme.style?.textStyle?.resolve({MaterialState.pressed})),
                              onPressed: () {
                                Navigator.pop(dialogContext); // Close dialog
                                newPlaylistNameController.clear();
                              },
                            ),
                            ElevatedButton(
                              child: Text('Create & Add', style: theme.elevatedButtonTheme.style?.textStyle?.resolve({})),
                              onPressed: () async {
                                final playlistName = newPlaylistNameController.text.trim();
                                if (playlistName.isNotEmpty) {
                                  await musicProvider.createPlaylist(playlistName, initialTracks: [trackToAdd]);
                                  newPlaylistNameController.clear();
                                  Navigator.pop(dialogContext, playlistName); // Close dialog, return name
                                }
                              },
                            ),
                          ],
                        );
                      },
                    );

                    if (createdPlaylistName != null) {
                       ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('"${trackToAdd.trackName}" added to new playlist "$createdPlaylistName"')),
                      );
                      // No need to call setStateModal here as the bottom sheet for selection is already closed.
                    }
                  },
                ),
                const Divider(),
                if (userPlaylists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0),
                    child: Center(
                      child: Text(
                        'No playlists available. Create one!',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7)),
                      ),
                    ),
                  )
                else
                  Expanded( // Make the list scrollable if many playlists
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: userPlaylists.length,
                      itemBuilder: (context, index) {
                        final playlist = userPlaylists[index];
                        final bool trackExistsInPlaylist = playlist.tracks.any((t) => t.id == trackToAdd.id);
                        return ListTile(
                          leading: Icon(
                            trackExistsInPlaylist ? Icons.playlist_add_check_circle_rounded : Icons.playlist_add_outlined,
                            color: trackExistsInPlaylist ? theme.colorScheme.primary : theme.iconTheme.color,
                            size: 28,
                          ),
                          title: Text(playlist.name, style: theme.textTheme.titleMedium),
                          subtitle: Text('${playlist.tracks.length} tracks', style: theme.textTheme.bodySmall),
                          onTap: () async {
                            if (!trackExistsInPlaylist) {
                              await musicProvider.addTrackToPlaylist(playlist.id, trackToAdd);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('"${trackToAdd.trackName}" added to "${playlist.name}"')),
                              );
                            } else {
                               ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Track already in "${playlist.name}"')),
                              );
                            }
                            Navigator.pop(bottomSheetContext); // Close bottom sheet
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
  // Dispose controller if it were part of a StatefulWidget's state
  // newPlaylistNameController.dispose(); // This line would cause an error here.
  // Controller should be disposed if this dialog were a StatefulWidget itself.
}
