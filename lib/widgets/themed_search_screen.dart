import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/search_screen.dart';
import '../screens/material_you_search_screen.dart';

/// Theme-aware wrapper for Search Screen
/// Switches between SearchScreen (Glassmorphism) and MaterialYouSearchScreen (Material You)
class ThemedSearchScreen extends StatelessWidget {
  final void Function(Widget screen)? onPushDetail;
  const ThemedSearchScreen({super.key, this.onPushDetail});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return themeProvider.isMaterialYou
        ? MaterialYouSearchScreen(onPushDetail: onPushDetail)
        : SearchScreen(onPushDetail: onPushDetail);
  }
}

