import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/material_you_track_tile.dart';
import '../models/album.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouAlbumScreen extends StatelessWidget {
  final String albumName;
  final String artistName;

  const MaterialYouAlbumScreen({
    required this.albumName,
    required this.artistName,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final albumDetails = musicProvider.currentAlbumDetails;
        final isLoading = musicProvider.isLoadingAlbum;
        final errorMessage = musicProvider.errorMessage;

        final bool isCorrectAlbumData = !isLoading &&
            albumDetails != null &&
            albumDetails.name == albumName &&
            albumDetails.artistName == artistName;

        return Scaffold(
          backgroundColor: MaterialYouTokens.surfaceDark,
          body: isLoading
              ? _buildLoadingState()
              : (errorMessage != null && !isCorrectAlbumData) || (!isLoading && albumDetails == null)
                  ? _buildErrorState(errorMessage ?? "Could not load album details.")
                  : _buildAlbumContent(context, musicProvider, albumDetails!),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(color: MaterialYouTokens.primaryVibrant),
    );
  }

  Widget _buildErrorState(String errorMsg) {
    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      appBar: AppBar(
        backgroundColor: MaterialYouTokens.surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            errorMsg,
            textAlign: TextAlign.center,
            style: MaterialYouTypography.bodyLarge(Colors.red),
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumContent(BuildContext context, MusicProvider musicProvider, Album album) {
    final colorScheme = Theme.of(context).colorScheme;
    final tracks = album.tracks;

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          expandedHeight: 300.0,
          pinned: true,
          stretch: true,
          backgroundColor: MaterialYouTokens.surfaceContainerDark,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
            onPressed: () => Navigator.of(context).pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            centerTitle: false,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.name,
                  style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  album.artistName + 
                      (album.releaseDate != null ? " • ${album.releaseDate!.year}" : ""),
                  style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (album.imageUrl.isNotEmpty)
                  Image.network(
                    album.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      color: MaterialYouTokens.surfaceContainerDark,
                      child: Icon(
                        Icons.album,
                        size: 100,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Container(
                    color: MaterialYouTokens.surfaceContainerDark,
                    child: Icon(
                      Icons.album,
                      size: 100,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.5, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.2),
                        Colors.black.withOpacity(0.9),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.share_outlined, color: colorScheme.onSurface),
              tooltip: "Share Album",
              onPressed: () {
                // TODO: Implement share album
              },
            ),
            IconButton(
              icon: Icon(Icons.more_vert, color: colorScheme.onSurface),
              tooltip: "More options",
              onPressed: () {
                // TODO: Show album options
              },
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: MaterialYouTokens.primaryVibrant,
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                  onPressed: tracks.isEmpty
                      ? null
                      : () {
                          musicProvider.playTrack(tracks.first, playlistTracks: tracks);
                        },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    musicProvider.shuffleEnabled ? Icons.shuffle_on : Icons.shuffle,
                    color: colorScheme.onSurface,
                    size: 30,
                  ),
                  tooltip: "Shuffle Play",
                  onPressed: tracks.isEmpty
                      ? null
                      : () {
                          musicProvider.playTrack(tracks.first, playlistTracks: tracks);
                          if (!musicProvider.shuffleEnabled) musicProvider.toggleShuffle();
                        },
                ),
              ],
            ),
          ),
        ),
        if (tracks.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Text(
                'No tracks found for this album.',
                style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final track = tracks[index];
                final isPlaying =
                    musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
                return MaterialYouTrackTile(
                  track: track,
                  isPlaying: isPlaying,
                  onTap: () => musicProvider.playTrack(
                    track,
                    playlistId: null,
                    playlistTracks: tracks,
                  ),
                );
              },
              childCount: tracks.length,
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
      ],
    );
  }
}
