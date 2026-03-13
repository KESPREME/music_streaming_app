import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/library_screen.dart';
import '../screens/material_you_library_screen.dart';

/// Theme-aware wrapper for Library Screen
/// Switches between LibraryScreen (Glassmorphism) and MaterialYouLibraryScreen (Material You)
class ThemedLibraryScreen extends StatefulWidget {
  const ThemedLibraryScreen({super.key});

  @override
  State<ThemedLibraryScreen> createState() => _ThemedLibraryScreenState();
}

class _ThemedLibraryScreenState extends State<ThemedLibraryScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return themeProvider.isMaterialYou
        ? const MaterialYouLibraryScreen()
        : const LibraryScreen();
  }
}
