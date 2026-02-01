import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/material_you_track_tile.dart';
import '../widgets/material_you_elevated_card.dart';
import '../models/artist.dart';
import '../models/album.dart';
import '../widgets/themed_album_screen.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouArtistScreen extends StatelessWidget {
  final String artistName;

  const MaterialYouArtistScreen({required this.artistName, super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final artistDetails = musicProvider.currentArtistDetails;
        final isLoading = musicProvider.isLoadingArtist;
        final errorMessage = musicProvider.errorMessage;

        final bool isCorrectArtistData = !isLoading && artistDetails?.name == artistName;

        return Scaffold(
          backgroundColor: MaterialYouTokens.surfaceDark,
          body: isLoading
              ? _buildLoadingState()
              : (errorMessage != null && !isCorrectArtistData) || (!isLoading && artistDetails == null)
                  ? _buildErrorState(errorMessage ?? "Could not load artist details.")
                  : _buildArtistContent(context, musicProvider, artistDetails!),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Text(
          errorMsg,
          textAlign: TextAlign.center,
          style: MaterialYouTypography.bodyLarge(Colors.red),
        ),
      ),
    );
  }

  Widget _buildArtistContent(BuildContext context, MusicProvider musicProvider, Artist artist) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return CustomScrollView(
      slivers: <Widget>[
        _buildSliverAppBar(context, artist, colorScheme),
        
        if (artist.bio != null && artist.bio!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Biography',
                    style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    artist.bio!,
                    style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

        _buildSectionHeader('Top Tracks', colorScheme),
        if (artist.topTracks == null || artist.topTracks!.isEmpty)
          _buildEmptySectionPlaceholder("No top tracks found for this artist.", colorScheme)
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final track = artist.topTracks![index];
                final isPlaying = musicProvider.currentTrack?.id == track.id && 
                                 musicProvider.isPlaying;
                return MaterialYouTrackTile(
                  track: track,
                  isPlaying: isPlaying,
                  onTap: () => musicProvider.playTrack(track, playlistTracks: artist.topTracks),
                );
              },
              childCount: artist.topTracks!.length,
            ),
          ),

        _buildSectionHeader('Albums', colorScheme),
        if (artist.topAlbums == null || artist.topAlbums!.isEmpty)
          _buildEmptySectionPlaceholder("No albums found for this artist.", colorScheme)
        else
          _buildAlbumList(context, musicProvider, artist.topAlbums!, colorScheme),

        const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
      ],
    );
  }

  Widget _buildSliverAppBar(BuildContext context, Artist artist, ColorScheme colorScheme) {
    return SliverAppBar(
      expandedHeight: 250.0,
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
        title: Text(
          artist.name,
          style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (artist.imageUrl.isNotEmpty)
              Image.network(
                artist.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Container(
                  color: MaterialYouTokens.surfaceContainerDark,
                  child: Icon(Icons.person, size: 80, color: colorScheme.onSurfaceVariant),
                ),
              )
            else
              Container(
                color: MaterialYouTokens.surfaceContainerDark,
                child: Icon(Icons.person, size: 80, color: colorScheme.onSurfaceVariant),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.6, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.4),
                    Colors.black.withOpacity(0.9),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 12.0),
        child: Text(
          title,
          style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget _buildEmptySectionPlaceholder(String message, ColorScheme colorScheme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Text(
          message,
          style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildAlbumList(BuildContext context, MusicProvider musicProvider, List<Album> albums, ColorScheme colorScheme) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 190,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          scrollDirection: Axis.horizontal,
          itemCount: albums.length,
          separatorBuilder: (context, index) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final album = albums[index];
            return SizedBox(
              width: 140,
              child: GestureDetector(
                onTap: () async {
                  await musicProvider.navigateToAlbum(album.name, album.artistName);
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ThemedAlbumScreen(
                          albumName: album.name,
                          artistName: album.artistName,
                        ),
                      ),
                    );
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Material(
                      elevation: 2,
                      surfaceTintColor: Colors.transparent, // FIX: No white tint
                      borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
                        child: album.imageUrl.isNotEmpty
                            ? Image.network(
                                album.imageUrl,
                                width: 140,
                                height: 140,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => Container(
                                  width: 140,
                                  height: 140,
                                  color: MaterialYouTokens.surfaceContainerDark,
                                  child: Icon(Icons.album, color: colorScheme.onSurfaceVariant),
                                ),
                              )
                            : Container(
                                width: 140,
                                height: 140,
                                color: MaterialYouTokens.surfaceContainerDark,
                                child: Icon(Icons.album, color: colorScheme.onSurfaceVariant, size: 40),
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      album.name,
                      style: MaterialYouTypography.bodyMedium(colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
