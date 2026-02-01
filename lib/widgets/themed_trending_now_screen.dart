import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/trending_now_screen.dart';
import '../screens/material_you_trending_now_screen.dart';

class ThemedTrendingNowScreen extends StatelessWidget {
  const ThemedTrendingNowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouTrendingNowScreen()
        : const TrendingNowScreen();
  }
}
