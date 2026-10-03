import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/library_screen.dart';
import '../screens/material_you_library_screen.dart';

/// Theme-aware wrapper for Library Screen
/// Switches between LibraryScreen (Glassmorphism) and MaterialYouLibraryScreen (Material You)
class ThemedLibraryScreen extends StatelessWidget {
  const ThemedLibraryScreen({super.key, this.isActive = true});

  /// Whether the Library tab is the visible tab. Forwarded to the glass
  /// library so its per-pixel Liquid Orb stops ticking while off-screen.
  /// The Material You variant is intentionally left untouched (frozen).
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return themeProvider.isMaterialYou
        ? const MaterialYouLibraryScreen()
        : LibraryScreen(isActive: isActive);
  }
}

