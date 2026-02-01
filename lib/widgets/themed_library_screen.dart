import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/library_screen.dart';
import '../screens/material_you_library_screen.dart';

/// Theme-aware wrapper for Library Screen
/// Switches between LibraryScreen (Glassmorphism) and MaterialYouLibraryScreen (Material You)
class ThemedLibraryScreen extends StatelessWidget {
  const ThemedLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return themeProvider.isMaterialYou
        ? const MaterialYouLibraryScreen()
        : const LibraryScreen();
  }
}
