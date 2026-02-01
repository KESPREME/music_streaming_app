import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/playlist_import_screen.dart';
import '../screens/material_you_playlist_import_screen.dart';

class ThemedPlaylistImportScreen extends StatelessWidget {
  const ThemedPlaylistImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouPlaylistImportScreen()
        : const PlaylistImportScreen();
  }
}
