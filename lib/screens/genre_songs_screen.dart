import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart';

class GenreSongsScreen extends StatelessWidget {
  final String genre;
  const GenreSongsScreen({required this.genre, super.key});

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final theme = Theme.of(context);
    // Ensure fetchGenreTracks was called before navigating here.
    // Data is expected to be in musicProvider.genreTracks

    return Scaffold(
      appBar: AppBar(
        title: Text(genre, style: theme.textTheme.headlineSmall),
        // Back button is added automatically by Navigator
      ),
      body: Consumer<MusicProvider>(
        builder: (context, provider, child) {
          if (provider.genreTracks.isEmpty) {
            // Could be loading, error, or truly empty. Provider should have flags for this.
            // For now, a simple check.
            if (provider.errorMessage != null && provider.errorMessage!.contains(genre)) {
               return Center(child: Text('Error loading tracks for $genre.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)));
            }
            return Center(child: Text('No songs found for $genre.', style: theme.textTheme.bodyMedium));
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            itemCount: provider.genreTracks.length,
            itemBuilder: (context, index) {
              final track = provider.genreTracks[index];
              final isPlaying = provider.currentTrack?.id == track.id && provider.isPlaying;
              return TrackTile(
                track: track,
                isPlaying: isPlaying,
                // onTap will be handled by TrackTile's default or can be overridden if needed
              );
            },
          );
        },
      ),
    );
  }
}
