import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart';
import '../models/track.dart';

class TrendingNowScreen extends StatelessWidget {
  const TrendingNowScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context);
    // Use fullTrendingTracks for this screen
    final List<Track> trendingTracks = musicProvider.fullTrendingTracks;

    return Scaffold(
      appBar: AppBar(
        title: Text('Trending Now', style: theme.textTheme.headlineSmall),
        // Back button is handled by Navigator automatically
      ),
      body: RefreshIndicator(
        onRefresh: () => musicProvider.fetchTrendingTracks(forceRefresh: true),
        backgroundColor: theme.colorScheme.surface,
        color: theme.colorScheme.primary,
        child: trendingTracks.isEmpty
            ? Center(
                child: musicProvider.errorMessage != null && musicProvider.errorMessage!.toLowerCase().contains("trending")
                    ? Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'Could not load trending tracks.\n${musicProvider.errorMessage}',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      )
                     // Check if provider is generally idle and trending is actually empty
                    : (musicProvider.tracks.isEmpty && musicProvider.fullTrendingTracks.isEmpty && !musicProvider.isLoadingLocal)
                        ? Text('No trending tracks available right now.', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.7)))
                        : const CircularProgressIndicator(),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                itemCount: trendingTracks.length,
                itemBuilder: (context, index) {
                  final track = trendingTracks[index];
                  final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
                  return TrackTile(
                    track: track,
                    isPlaying: isPlaying,
                    onTap: () {
                      musicProvider.playTrack(track, playlistTracks: trendingTracks);
                    },
                  );
                },
              ),
      ),
    );
  }
}