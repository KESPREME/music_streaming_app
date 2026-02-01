import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/downloaded_songs_screen.dart';
import '../screens/material_you_downloaded_songs_screen.dart';

class ThemedDownloadedSongsScreen extends StatelessWidget {
  const ThemedDownloadedSongsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouDownloadedSongsScreen()
        : const DownloadedSongsScreen();
  }
}
