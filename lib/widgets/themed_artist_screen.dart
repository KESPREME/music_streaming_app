import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/artist_screen.dart';
import '../screens/material_you_artist_screen.dart';

class ThemedArtistScreen extends StatelessWidget {
  final String artistName;

  const ThemedArtistScreen({
    required this.artistName,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? MaterialYouArtistScreen(artistName: artistName)
        : ArtistScreen(artistName: artistName);
  }
}
