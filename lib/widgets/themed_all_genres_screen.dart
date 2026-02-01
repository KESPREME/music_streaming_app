import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/all_genres_screen.dart';
import '../screens/material_you_all_genres_screen.dart';

class ThemedAllGenresScreen extends StatelessWidget {
  const ThemedAllGenresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouAllGenresScreen()
        : const AllGenresScreen();
  }
}
