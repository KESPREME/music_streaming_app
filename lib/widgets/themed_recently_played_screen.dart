import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/recently_played_screen.dart';
import '../screens/material_you_recently_played_screen.dart';

class ThemedRecentlyPlayedScreen extends StatelessWidget {
  const ThemedRecentlyPlayedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouRecentlyPlayedScreen()
        : const RecentlyPlayedScreen();
  }
}
