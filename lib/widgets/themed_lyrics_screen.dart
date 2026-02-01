import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/lyrics_screen.dart';
import '../screens/material_you_lyrics_screen.dart';

class ThemedLyricsScreen extends StatelessWidget {
  const ThemedLyricsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouLyricsScreen()
        : const LyricsScreen();
  }
}
