import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/home_screen.dart';
import '../screens/material_you_home_screen.dart';

/// Theme-aware wrapper for Home Screen
/// Switches between HomeScreen (Glassmorphism) and MaterialYouHomeScreen (Material You)
class ThemedHomeScreen extends StatelessWidget {
  const ThemedHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return themeProvider.isMaterialYou
        ? const MaterialYouHomeScreen()
        : const HomeScreen();
  }
}
