import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/playlist_screen.dart';
import '../screens/material_you_playlist_screen.dart';

class ThemedPlaylistScreen extends StatelessWidget {
  final String playlistId;

  const ThemedPlaylistScreen({
    required this.playlistId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? MaterialYouPlaylistScreen(playlistId: playlistId)
        : PlaylistScreen(playlistId: playlistId);
  }
}
