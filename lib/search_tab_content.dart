import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart';

class SearchTabContent extends StatelessWidget {
  // searchQuery is no longer needed as this widget will now directly consume provider state
  const SearchTabContent({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Use a Consumer to listen for changes to searchedTracks
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        // The parent SearchScreen is responsible for triggering the search
        // and updating the provider. This widget just displays the results.
        final searchResults = musicProvider.searchedTracks;

        // The parent SearchScreen's search bar state determines what is shown.
        // If the query is empty, the provider's list should also be empty.
        if (searchResults.isEmpty) {
          return Center(
            child: Text(
              'Search for tracks, artists, or albums.',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6)),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          itemExtent: 72.0, // Optimization for fixed height items
          itemCount: searchResults.length,
          itemBuilder: (context, index) {
            final track = searchResults[index];
            final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;

            return TrackTile(
              track: track,
              isPlaying: isPlaying,
              onTap: () {
                // Play the track and set the search results as the current playback context
                musicProvider.playTrack(track, playlistTracks: searchResults);
              },
            );
          },
        );
      },
    );
  }
}