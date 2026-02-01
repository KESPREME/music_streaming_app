import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/playback_settings_screen.dart';
import '../screens/material_you_playback_settings_screen.dart';

class ThemedPlaybackSettingsScreen extends StatelessWidget {
  const ThemedPlaybackSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouPlaybackSettingsScreen()
        : const PlaybackSettingsScreen();
  }
}
