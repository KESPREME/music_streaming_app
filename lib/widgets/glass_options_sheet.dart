import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../screens/playlist_detail_screen.dart'; // Unified for Album View
import '../theme/glass_tokens.dart';
import 'glass_surface.dart';
import 'playlist_selection_dialog.dart';
import 'glass_snackbar.dart';
import 'artist_picker_sheet.dart'; // Multi-artist selection
import 'glass_download_selection_sheet.dart';

class GlassOptionsSheet extends StatelessWidget {
  final Track track;
  final String? playlistId;
  final bool isInQueueContext;
  final bool isRecentlyPlayedContext; // New context

  const GlassOptionsSheet({
    super.key,
    required this.track,
    this.playlistId,
    this.isInQueueContext = false,
    this.isRecentlyPlayedContext = false,
  });

  /// Helper to show the options sheet while hiding the mini player
  static Future<void> show(
    BuildContext context, {
    required Track track,
    String? playlistId,
    bool isInQueueContext = false,
    bool isRecentlyPlayedContext = false,
  }) async {
    final provider = Provider.of<MusicProvider>(context, listen: false);

    // Hide Mini Player
    provider.setHideMiniPlayer(true);

    try {
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => GlassOptionsSheet(
          track: track,
          playlistId: playlistId,
          isInQueueContext: isInQueueContext,
          isRecentlyPlayedContext: isRecentlyPlayedContext,
        ),
      );
    } finally {
      // Restore Mini Player
      provider.setHideMiniPlayer(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Check if liked (requires listening to provider or passing in state,
    // but Consumer is safer for up-to-date state in a sheet)

    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        final isLiked = provider.isSongLiked(track.id);

        return GlassSurface(
          tier: GlassTier.sheet,
          borderRadius: GlassTokens.radiusSheet,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle Bar
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header (Track Info)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          track.albumArtUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 56,
                            height: 56,
                            color: Colors.grey[900],
                            child: const Icon(
                              Icons.music_note,
                              color: Colors.white24,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.trackName,
                              style: GoogleFonts.splineSans(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              track.artistName,
                              style: GoogleFonts.splineSans(
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => provider.toggleLike(track),
                        icon: Icon(
                          isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: isLiked
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 0.5),

                // Options List
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildOption(
                          context,
                          icon: Icons.queue_music_rounded,
                          label: 'Add to Queue',
                          onTap: () {
                            provider.addToQueue(track);
                            Navigator.pop(context);
                            showGlassSnackBar(context, 'Added to Queue');
                          },
                        ),
                        _buildOption(
                          context,
                          icon: Icons.playlist_play_rounded,
                          label: 'Play Next',
                          onTap: () {
                            provider.playNext(track);
                            Navigator.pop(context);
                            showGlassSnackBar(context, 'Playing Next');
                          },
                        ),
                        _buildOption(
                          context,
                          icon: Icons.playlist_add_rounded,
                          label: 'Add to Playlist',
                          onTap: () async {
                            final rootContext = context;
                            Navigator.pop(context);
                            // Use a small delay to ensure the bottom sheet is fully closed
                            await Future.delayed(
                              const Duration(milliseconds: 100),
                            );
                            if (rootContext.mounted) {
                              await showPlaylistSelectionDialog(
                                rootContext,
                                track,
                              );
                            }
                          },
                        ),

                        // Download Option with status indicator
                        Builder(
                          builder: (context) {
                            final isDownloaded = provider.isTrackDownloadedSync(
                              track.id,
                            );
                            final isDownloading =
                                provider.isDownloading[track.id] == true;
                            final isQueued = provider.downloadQueue.any(
                              (t) => t.id == track.id,
                            );
                            final progress =
                                provider.downloadProgress[track.id] ?? 0.0;

                            String label = 'Download';
                            IconData icon = Icons.download_rounded;
                            Color? color;

                            if (isDownloaded) {
                              label = 'Downloaded';
                              icon = Icons.download_done_rounded;
                              color = Colors.green;
                            } else if (isDownloading) {
                              label =
                                  'Downloading... ${(progress * 100).toInt()}%';
                              icon = Icons.downloading_rounded;
                              color = colorScheme.primary;
                            } else if (isQueued) {
                              label = 'Queued';
                              icon = Icons.hourglass_top_rounded;
                            }

                            return _buildOption(
                              context,
                              icon: icon,
                              label: label,
                              color: color,
                              onTap: isDownloaded || isDownloading || isQueued
                                  ? () {
                                      Navigator.pop(context);
                                      if (isDownloaded) {
                                        showGlassSnackBar(
                                          context,
                                          '${track.trackName} already downloaded',
                                        );
                                      } else {
                                        showGlassSnackBar(
                                          context,
                                          'Download in progress',
                                        );
                                      }
                                    }
                                  : () async {
                                      Navigator.pop(context);
                                      showGlassSnackBar(
                                        context,
                                        'Starting download: ${track.trackName}',
                                      );
                                      await provider.downloadTrack(track);
                                    },
                            );
                          },
                        ),

                        if (track.artistName.isNotEmpty &&
                            track.artistName != 'Unknown Artist')
                          _buildOption(
                            context,
                            icon: Icons.person_outline_rounded,
                            label: 'Go to Artist',
                            onTap: () async {
                              Navigator.pop(context);
                              // FIX: Use ArtistPickerSheet for multi-artist tracks
                              await ArtistPickerSheet.showIfNeeded(
                                context,
                                provider,
                                track.artistName,
                              );
                            },
                          ),

                        if (track.albumName.isNotEmpty &&
                            track.albumName != 'Unknown Album')
                          _buildOption(
                            context,
                            icon: Icons.album_outlined,
                            label: 'Go to Album',
                            onTap: () async {
                              Navigator.pop(context);
                              await _navigateToAlbum(
                                context,
                                provider,
                                track.albumName,
                                track.artistName,
                              );
                            },
                          ),

                        _buildOption(
                          context,
                          icon: Icons.share_rounded,
                          label: 'Share',
                          onTap: () {
                            Navigator.pop(context);
                            SharePlus.instance.share(
                              ShareParams(
                                text:
                                    'Check out this track: ${track.trackName} by ${track.artistName}\n${track.previewUrl}',
                              ),
                            );
                          },
                        ),

                        if (playlistId != null)
                          _buildOption(
                            context,
                            icon: Icons.remove_circle_outline_rounded,
                            label: 'Remove from Playlist',
                            color: colorScheme.error,
                            onTap: () {
                              provider.removeTrackFromPlaylist(
                                playlistId!,
                                track.id,
                              );
                              Navigator.pop(context);
                            },
                          ),

                        if (isInQueueContext)
                          _buildOption(
                            context,
                            icon: Icons.delete_sweep_rounded,
                            label: 'Remove from Queue',
                            color: colorScheme.error,
                            onTap: () {
                              provider.removeFromQueue(track);
                              Navigator.pop(context);
                            },
                          ),

                        if (isRecentlyPlayedContext)
                          _buildOption(
                            context,
                            icon: Icons.history_toggle_off_rounded,
                            label: 'Remove from History',
                            color: colorScheme.error,
                            onTap: () {
                              provider.removeFromRecentlyPlayed(track.id);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Removed from Recently Played'),
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: effectiveColor),
      title: Text(
        label,
        style: GoogleFonts.splineSans(
          color: effectiveColor,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
    );
  }

  Future<void> _navigateToAlbum(
    BuildContext context,
    MusicProvider provider,
    String albumName,
    String artistName,
  ) async {
    showGlassSnackBar(
      context,
      'Loading album...',
      duration: const Duration(milliseconds: 500),
    );
    await provider.navigateToAlbum(albumName, artistName);
    if (context.mounted && provider.currentAlbumDetails != null) {
      // FIX: Ensure mini player is visible when going to details screen
      provider.setHideMiniPlayer(false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlaylistDetailScreen(
            playlistId: provider.currentAlbumDetails!.id,
            playlistName: provider.currentAlbumDetails!.name,
            playlistImage: provider.currentAlbumDetails!.imageUrl,
            cachedTracks: provider.currentAlbumDetails!.tracks,
          ),
        ),
      );
    }
  }
}

class GlassPlaylistOptionsSheet extends StatelessWidget {
  final String playlistName;
  final String? playlistImage;
  final List<Track> tracks;

  const GlassPlaylistOptionsSheet({
    super.key,
    required this.playlistName,
    this.playlistImage,
    required this.tracks,
  });

  static Future<void> show(
    BuildContext context, {
    required String playlistName,
    String? playlistImage,
    required List<Track> tracks,
  }) async {
    final provider = Provider.of<MusicProvider>(context, listen: false);
    provider.setHideMiniPlayer(true);
    try {
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => GlassPlaylistOptionsSheet(
          playlistName: playlistName,
          playlistImage: playlistImage,
          tracks: tracks,
        ),
      );
    } finally {
      provider.setHideMiniPlayer(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final provider = Provider.of<MusicProvider>(context, listen: false);

    return GlassSurface(
      tier: GlassTier.sheet,
      borderRadius: GlassTokens.radiusSheet,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: playlistImage != null
                        ? Image.network(
                            playlistImage!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey[900],
                              width: 56,
                              height: 56,
                            ),
                          )
                        : Container(
                            color: Colors.grey[900],
                            width: 56,
                            height: 56,
                            child: const Icon(
                              Icons.music_note,
                              color: Colors.white24,
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      playlistName,
                      style: GoogleFonts.splineSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 0.5),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildOption(
                      context,
                      icon: Icons.download_rounded,
                      label: 'Download Playlist',
                      onTap: () {
                        Navigator.pop(context);
                        provider.downloadTracks(tracks);
                        showGlassSnackBar(
                          context,
                          'Downloading ${tracks.length} tracks',
                        );
                      },
                    ),
                    _buildOption(
                      context,
                      icon: Icons.checklist_rounded,
                      label: 'Select to Download',
                      onTap: () async {
                        final rootContext = context;
                        Navigator.pop(context);
                        await Future.delayed(const Duration(milliseconds: 100));
                        if (rootContext.mounted) {
                          await showModalBottomSheet(
                            context: rootContext,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (c) => GlassDownloadSelectionSheet(
                              tracks: tracks,
                              playlistName: playlistName,
                            ),
                          );
                        }
                      },
                    ),
                    _buildOption(
                      context,
                      icon: Icons.queue_music_rounded,
                      label: 'Add All to Queue',
                      onTap: () {
                        Navigator.pop(context);
                        for (var t in tracks) {
                          provider.addToQueue(t);
                        }
                        showGlassSnackBar(
                          context,
                          'Added ${tracks.length} to queue',
                        );
                      },
                    ),
                    _buildOption(
                      context,
                      icon: Icons.shuffle_rounded,
                      label: 'Shuffle Play',
                      onTap: () {
                        Navigator.pop(context);
                        provider.shuffleAndPlay(tracks);
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: effectiveColor),
      title: Text(
        label,
        style: GoogleFonts.splineSans(
          color: effectiveColor,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
    );
  }
}
