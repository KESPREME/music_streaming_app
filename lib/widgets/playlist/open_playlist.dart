import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../providers/theme_provider.dart';
import '../../screens/user_playlist_detail_screen.dart';
import '../themed_playlist_detail_screen.dart';

/// Opens one of the listener's own playlists.
///
/// The glass theme gets the live screen (edit, reorder, remove with undo, add
/// songs). Material You keeps its existing detail screen: it is being rebuilt
/// separately and is not touched here.
Future<void> openUserPlaylist(BuildContext context, Playlist playlist) {
  var materialYou = false;
  try {
    materialYou = Provider.of<ThemeProvider>(context, listen: false).isMaterialYou;
  } catch (_) {
    // No ThemeProvider above (a bare test host): glass is the default.
  }
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => materialYou
        ? ThemedPlaylistDetailScreen(
            playlistId: playlist.id,
            playlistName: playlist.name,
            playlistImage: playlist.imageUrl,
            cachedTracks: playlist.tracks,
          )
        : UserPlaylistDetailScreen(playlistId: playlist.id),
  ));
}
