import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../models/track.dart';
import '../screens/playlist_detail_screen.dart';
import '../screens/material_you_playlist_detail_screen.dart';

import '../screens/album_detail_screen.dart';

class ThemedPlaylistDetailScreen extends StatelessWidget {
  final String playlistId;
  final String playlistName;
  final String? playlistImage;
  final List<Track>? cachedTracks;
  final bool searchAlbumByName;
  final String? artistNameHint;

  const ThemedPlaylistDetailScreen({
    required this.playlistId,
    required this.playlistName,
    this.playlistImage,
    this.cachedTracks,
    this.searchAlbumByName = false,
    this.artistNameHint,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isAlbum = searchAlbumByName ||
        playlistId.startsWith('MPREb_') ||
        playlistId.startsWith('OLAK');

    if (themeProvider.isMaterialYou) {
      return MaterialYouPlaylistDetailScreen(
        playlistId: playlistId,
        playlistName: playlistName,
        playlistImage: playlistImage,
        cachedTracks: cachedTracks,
        searchAlbumByName: searchAlbumByName,
        artistNameHint: artistNameHint,
      );
    }

    if (isAlbum) {
      return AlbumDetailScreen(
        albumId: playlistId,
        albumName: playlistName,
        artistName: artistNameHint,
        albumImage: playlistImage,
        cachedTracks: cachedTracks,
        searchByName: searchAlbumByName,
      );
    }

    return PlaylistDetailScreen(
      playlistId: playlistId,
      playlistName: playlistName,
      playlistImage: playlistImage,
      cachedTracks: cachedTracks,
      searchAlbumByName: searchAlbumByName,
      artistNameHint: artistNameHint,
    );
  }
}

