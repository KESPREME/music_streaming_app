import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/album_screen.dart';
import '../screens/material_you_album_screen.dart';

class ThemedAlbumScreen extends StatelessWidget {
  final String albumName;
  final String artistName;

  const ThemedAlbumScreen({
    required this.albumName,
    required this.artistName,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? MaterialYouAlbumScreen(
            albumName: albumName,
            artistName: artistName,
          )
        : AlbumScreen(
            albumName: albumName,
            artistName: artistName,
          );
  }
}
