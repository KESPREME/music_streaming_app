import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/genre_songs_screen.dart';
import '../screens/material_you_genre_songs_screen.dart';

class ThemedGenreSongsScreen extends StatelessWidget {
  final String genre;

  const ThemedGenreSongsScreen({
    required this.genre,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? MaterialYouGenreSongsScreen(genre: genre)
        : GenreSongsScreen(genre: genre);
  }
}
