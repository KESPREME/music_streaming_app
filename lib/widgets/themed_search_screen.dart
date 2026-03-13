import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/search_screen.dart';
import '../screens/material_you_search_screen.dart';

/// Theme-aware wrapper for Search Screen
/// Switches between SearchScreen (Glassmorphism) and MaterialYouSearchScreen (Material You)
class ThemedSearchScreen extends StatefulWidget {
  const ThemedSearchScreen({super.key});

  @override
  State<ThemedSearchScreen> createState() => _ThemedSearchScreenState();
}

class _ThemedSearchScreenState extends State<ThemedSearchScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return themeProvider.isMaterialYou
        ? const MaterialYouSearchScreen()
        : const SearchScreen();
  }
}
