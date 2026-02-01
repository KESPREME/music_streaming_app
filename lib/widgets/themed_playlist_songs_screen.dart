import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../models/track.dart';
import '../screens/playlist_songs_screen.dart';
import '../screens/material_you_playlist_songs_screen.dart';

class ThemedPlaylistSongsScreen extends StatelessWidget {
  final String playlistName;
  final List<Track> tracks;
  final String? playlistId;

  const ThemedPlaylistSongsScreen({
    required this.playlistName,
    required this.tracks,
    this.playlistId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? MaterialYouPlaylistSongsScreen(
            playlistName: playlistName,
            tracks: tracks,
            playlistId: playlistId,
          )
        : PlaylistSongsScreen(
            playlistName: playlistName,
            tracks: tracks,
            playlistId: playlistId,
          );
  }
}
