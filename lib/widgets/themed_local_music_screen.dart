import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/local_music_screen.dart';
import '../screens/material_you_local_music_screen.dart';

class ThemedLocalMusicScreen extends StatelessWidget {
  const ThemedLocalMusicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouLocalMusicScreen()
        : const LocalMusicScreen();
  }
}
