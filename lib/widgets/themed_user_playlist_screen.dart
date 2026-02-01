import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/user_playlist_screen.dart';
import '../screens/material_you_user_playlist_screen.dart';

class ThemedUserPlaylistScreen extends StatelessWidget {
  const ThemedUserPlaylistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouUserPlaylistScreen()
        : const UserPlaylistScreen();
  }
}
