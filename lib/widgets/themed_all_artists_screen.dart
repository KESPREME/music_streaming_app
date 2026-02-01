import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/all_artists_screen.dart';
import '../screens/material_you_all_artists_screen.dart';

class ThemedAllArtistsScreen extends StatelessWidget {
  const ThemedAllArtistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouAllArtistsScreen()
        : const AllArtistsScreen();
  }
}
