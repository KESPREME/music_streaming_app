import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/artist_detail_screen.dart';
import '../screens/material_you_artist_detail_screen.dart';

class ThemedArtistDetailScreen extends StatelessWidget {
  final String artistId;
  final String artistName;
  final String? artistImage;
  final bool searchByName;

  const ThemedArtistDetailScreen({
    required this.artistId,
    required this.artistName,
    this.artistImage,
    this.searchByName = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? MaterialYouArtistDetailScreen(
            artistId: artistId,
            artistName: artistName,
            artistImage: artistImage,
            searchByName: searchByName,
          )
        : ArtistDetailScreen(
            artistId: artistId,
            artistName: artistName,
            artistImage: artistImage,
            searchByName: searchByName,
          );
  }
}
