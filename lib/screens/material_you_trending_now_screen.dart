import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/material_you_track_tile.dart';
import '../models/track.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouTrendingNowScreen extends StatelessWidget {
  const MaterialYouTrendingNowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final musicProvider = Provider.of<MusicProvider>(context);
    final List<Track> trendingTracks = musicProvider.fullTrendingTracks;

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      body: SafeArea(
        child: RefreshIndicator(
          color: MaterialYouTokens.primaryVibrant,
          backgroundColor: MaterialYouTokens.surfaceContainerDark,
          onRefresh: () => musicProvider.fetchTrendingTracks(forceRefresh: true),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(context, colorScheme),
              
              if (trendingTracks.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: musicProvider.errorMessage != null && 
                           musicProvider.errorMessage!.toLowerCase().contains("trending")
                        ? Text(
                            'Could not load trending tracks', 
                            style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant)
                          )
                        : (musicProvider.tracks.isEmpty && !musicProvider.isLoadingLocal)
                            ? Text(
                                'No trending tracks available', 
                                style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant)
                              )
                            : CircularProgressIndicator(
                                color: MaterialYouTokens.primaryVibrant,
                              ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = trendingTracks[index];
                        final isPlaying = musicProvider.currentTrack?.id == track.id && 
                                         musicProvider.isPlaying;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: MaterialYouTrackTile(
                            track: track,
                            isPlaying: isPlaying,
                            onTap: () {
                              musicProvider.playTrack(track, playlistTracks: trendingTracks);
                            },
                          ),
                        );
                      },
                      childCount: trendingTracks.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, ColorScheme colorScheme) {
    return SliverAppBar(
      backgroundColor: MaterialYouTokens.surfaceDark,
      surfaceTintColor: Colors.transparent,
      pinned: true,
      expandedHeight: 120,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: MaterialYouTokens.surfaceContainerDark,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final double percentage = ((constraints.maxHeight - kToolbarHeight) / 
                                     (120 - kToolbarHeight)).clamp(0.0, 1.0);

          return FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
            title: Text(
              'Trending Now',
              style: MaterialYouTypography.headlineSmall(colorScheme.onSurface)
                  .copyWith(fontSize: 20 + (8 * percentage)),
            ),
          );
        },
      ),
    );
  }
}
