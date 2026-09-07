import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../models/track.dart';
import '../screens/album_detail_screen.dart';
import '../screens/material_you_playlist_detail_screen.dart';

class ThemedAlbumDetailScreen extends StatelessWidget {
  final String albumId;
  final String albumName;
  final String? artistName;
  final String? albumImage;
  final List<Track>? cachedTracks;
  final bool searchByName;

  const ThemedAlbumDetailScreen({
    super.key,
    required this.albumId,
    required this.albumName,
    this.artistName,
    this.albumImage,
    this.cachedTracks,
    this.searchByName = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? MaterialYouPlaylistDetailScreen(
            playlistId: albumId,
            playlistName: albumName,
            playlistImage: albumImage,
            cachedTracks: cachedTracks,
            searchAlbumByName: searchByName,
            artistNameHint: artistName,
          )
        : AlbumDetailScreen(
            albumId: albumId,
            albumName: albumName,
            artistName: artistName,
            albumImage: albumImage,
            cachedTracks: cachedTracks,
            searchByName: searchByName,
          );
  }
}
