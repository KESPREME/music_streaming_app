import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/liked_songs_screen.dart';
import '../screens/material_you_liked_songs_screen.dart';

class ThemedLikedSongsScreen extends StatelessWidget {
  const ThemedLikedSongsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouLikedSongsScreen()
        : const LikedSongsScreen();
  }
}
