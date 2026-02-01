import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../widgets/material_you_track_tile.dart';
import '../providers/music_provider.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouPlaylistSongsScreen extends StatelessWidget {
  final String playlistName;
  final List<Track> tracks;
  final String? playlistId;

  const MaterialYouPlaylistSongsScreen({
    super.key,
    required this.playlistName,
    required this.tracks,
    this.playlistId,
  });

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      appBar: AppBar(
        backgroundColor: MaterialYouTokens.surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          playlistName,
          style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: tracks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.queue_music,
                    size: 60,
                    color: colorScheme.onSurface.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This playlist is empty',
                    style: MaterialYouTypography.titleMedium(colorScheme.onSurface),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add some songs to get started!',
                    style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 120, top: 8),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final isPlaying = musicProvider.currentTrack?.id == track.id && 
                                 musicProvider.isPlaying;

                return MaterialYouTrackTile(
                  track: track,
                  isPlaying: isPlaying,
                  onTap: () {
                    musicProvider.playTrack(
                      track,
                      playlistId: playlistId,
                      playlistTracks: tracks,
                    );
                  },
                );
              },
            ),
    );
  }
}
