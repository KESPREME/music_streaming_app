import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/material_you_track_tile.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouGenreSongsScreen extends StatelessWidget {
  final String genre;
  
  const MaterialYouGenreSongsScreen({required this.genre, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      appBar: AppBar(
        backgroundColor: MaterialYouTokens.surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          genre, 
          style: MaterialYouTypography.headlineSmall(colorScheme.onSurface)
        ),
      ),
      body: Consumer<MusicProvider>(
        builder: (context, provider, child) {
          if (provider.genreTracks.isEmpty) {
            if (provider.errorMessage != null && provider.errorMessage!.contains(genre)) {
              return Center(
                child: Text(
                  'Error loading tracks for $genre.',
                  style: MaterialYouTypography.bodyLarge(colorScheme.error),
                ),
              );
            }
            return Center(
              child: Text(
                'No songs found for $genre.',
                style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 120, top: 8),
            itemCount: provider.genreTracks.length,
            itemBuilder: (context, index) {
              final track = provider.genreTracks[index];
              final isPlaying = provider.currentTrack?.id == track.id && provider.isPlaying;
              return MaterialYouTrackTile(
                track: track,
                isPlaying: isPlaying,
                onTap: () {
                  provider.playTrack(track, playlistTracks: provider.genreTracks);
                },
              );
            },
          );
        },
      ),
    );
  }
}
