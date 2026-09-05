import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../presentation/explore/explore_top_pill.dart';
import '../utils/color_utils.dart';
import '../utils/image_quality_utils.dart';
import 'package:cached_network_image/cached_network_image.dart';

class GlassOptionsSheet extends StatelessWidget {
  final Track track;
  final String? playlistId;
  final bool isInQueueContext;
  final bool isRecentlyPlayedContext; // New context
  final VoidCallback? onDislike; // Explore-only: null hides the row

  const GlassOptionsSheet({
    super.key,
    required this.track,
    this.playlistId,
    this.isInQueueContext = false,
    this.isRecentlyPlayedContext = false,
    this.onDislike,
  });

  /// Helper to show the options sheet while hiding the mini player
  static Future<void> show(
    BuildContext context, {
    required Track track,
    String? playlistId,
    bool isInQueueContext = false,
    bool isRecentlyPlayedContext = false,
    VoidCallback? onDislike,
  }) async {
    final provider = Provider.of<MusicProvider>(context, listen: false);

    final wasHidden = provider.hideMiniPlayer;
    // Hide Mini Player
    provider.setHideMiniPlayer(true);

    try {
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.28),
        isScrollControlled: true,
        sheetAnimationStyle: const AnimationStyle(
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
          duration: Duration(milliseconds: 320),
        ),
        builder: (context) => GlassOptionsSheet(
          track: track,
          playlistId: playlistId,
          isInQueueContext: isInQueueContext,
          isRecentlyPlayedContext: isRecentlyPlayedContext,
          onDislike: onDislike,
        ),
      );
    } finally {
      // Restore Mini Player
      if (!wasHidden) {
        provider.setHideMiniPlayer(false);
      }
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

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xF2141418),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 1.0,
              ),
            ),
            child: GlassSurface(
              tier: GlassTier.sheet,
              borderRadius: 32,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle Bar
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 36,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2.25),
                      ),
                    ),

                    // Header (Track Info matching Image 3)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 6, 20, 16),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: ImageQualityUtils.getHighResArtwork(
                                track.albumArtUrl,
                              ),
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                width: 52,
                                height: 52,
                                color: Colors.grey[900],
                                child: const Icon(
                                  Icons.music_note,
                                  color: Colors.white24,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.trackName,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  track.artistName,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              provider.toggleLike(track);
                            },
                            icon: Icon(
                              isLiked
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: isLiked
                                  ? colorScheme.primary
                                  : Colors.white,
                              size: 26,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),

                    // Options List matching Image 3
                    Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // 1. Add to a playlist...
                        _buildOption(
                          context,
                          icon: Icons.playlist_add_rounded,
                          label: 'Add to a playlist...',
                          onTap: () async {
                            final rootContext = context;
                            Navigator.pop(context);
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

                        // 2. Mine Music Code
                        _buildOption(
                          context,
                          icon: Icons.qr_code_2_rounded,
                          label: 'Mine Music Code',
                          fallbackLabel: 'Muzo Code',
                          onTap: () {
                            Navigator.pop(context);
                            final accent = ColorUtils.getVibrantAccent(
                              provider.paletteGenerator,
                              const Color(0xFFE89838),
                            );
                            showDialog(
                              context: context,
                              builder: (_) => SongCodeDialog(
                                track: track,
                                accent: accent,
                              ),
                            );
                          },
                        ),

                        // 3. Go to album
                        if (track.albumName.isNotEmpty &&
                            track.albumName != 'Unknown Album')
                          _buildOption(
                            context,
                            icon: Icons.album_outlined,
                            label: 'Go to album',
                            fallbackLabel: 'Go to Album',
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

                        // 4. Go to artist
                        if (track.artistName.isNotEmpty &&
                            track.artistName != 'Unknown Artist')
                          _buildOption(
                            context,
                            icon: Icons.person_outline_rounded,
                            label: 'Go to artist',
                            onTap: () async {
                              Navigator.pop(context);
                              await ArtistPickerSheet.showIfNeeded(
                                context,
                                provider,
                                track.artistName,
                              );
                            },
                          ),

                        // 4. Download
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
                            IconData icon = Icons.file_download_outlined;
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

                        // 5. Share
                        _buildOption(
                          context,
                          icon: Icons.ios_share_rounded,
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

                        if (onDislike != null)
                          _buildOption(
                            context,
                            icon: Icons.heart_broken_rounded,
                            label: 'Not interested',
                            onTap: () {
                              Navigator.pop(context);
                              onDislike!.call();
                            },
                          ),

                        // 6. Song Info
                        _buildOption(
                          context,
                          icon: Icons.info_outline_rounded,
                          label: 'Song Info',
                          onTap: () {
                            Navigator.pop(context);
                            showDialog(
                              context: context,
                              builder: (_) => SongInfoDialog(track: track),
                            );
                          },
                        ),

                        // 7. Force Canvas
                        _buildOption(
                          context,
                          icon: Icons.bolt_rounded,
                          label: 'Force Canvas',
                          onTap: () {
                            provider.toggleCanvas();
                            Navigator.pop(context);
                            showGlassSnackBar(
                              context,
                              provider.isCanvasActive
                                  ? 'Canvas mode enabled'
                                  : 'Canvas mode disabled',
                            );
                          },
                        ),

                        // 8. Sleep Timer
                        _buildOption(
                          context,
                          icon: Icons.timer_outlined,
                          label: 'Sleep Timer',
                          onTap: () {
                            Navigator.pop(context);
                            _showSleepTimerSheet(context, provider);
                          },
                        ),

                        // Contextual items
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
    String? fallbackLabel,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 0),
        visualDensity: const VisualDensity(vertical: -1.5),
        minLeadingWidth: 28,
        horizontalTitleGap: 14,
        leading: Icon(icon, color: effectiveColor, size: 22),
        title: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: effectiveColor,
                fontWeight: FontWeight.w500,
                fontSize: 15.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (fallbackLabel != null)
              Opacity(
                opacity: 0.0,
                child: Text(
                  fallbackLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (label == 'Go to artist')
              const Opacity(
                opacity: 0,
                child: Text(
                  'Go to Artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
      ),
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

  void _showSleepTimerSheet(BuildContext context, MusicProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassSurface(
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
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Sleep Timer',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...[15, 30, 45, 60].map(
                (mins) => ListTile(
                  title: Text(
                    '$mins Minutes',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white),
                  ),
                  onTap: () {
                    provider.setSleepTimer(mins);
                    Navigator.pop(ctx);
                    showGlassSnackBar(context, 'Sleep timer set for $mins minutes');
                  },
                ),
              ),
              ListTile(
                title: Text(
                  'End of Track',
                  style: GoogleFonts.plusJakartaSans(color: Colors.white),
                ),
                onTap: () {
                  provider.setSleepTimer(0);
                  Navigator.pop(ctx);
                  showGlassSnackBar(context, 'Playback will stop after this track');
                },
              ),
              ListTile(
                title: Text(
                  'Turn Off',
                  style: GoogleFonts.plusJakartaSans(color: Colors.white54),
                ),
                onTap: () {
                  provider.setSleepTimer(-1);
                  Navigator.pop(ctx);
                  showGlassSnackBar(context, 'Sleep timer turned off');
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Song Information Dialog with detailed metadata
class SongInfoDialog extends StatelessWidget {
  final Track track;

  const SongInfoDialog({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: GlassSurface(
        tier: GlassTier.sheet,
        borderRadius: 24,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: track.albumArtUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: track.albumArtUrl,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 52,
                              height: 52,
                              color: Colors.grey[900],
                              child: const Icon(Icons.music_note,
                                  color: Colors.white30),
                            ),
                          )
                        : Container(
                            width: 52,
                            height: 52,
                            color: Colors.grey[900],
                            child: const Icon(Icons.music_note,
                                color: Colors.white30),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.trackName,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artistName,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, thickness: 0.5, color: Colors.white12),
              const SizedBox(height: 14),
              _buildInfoRow(
                'Album',
                track.albumName.isNotEmpty ? track.albumName : 'Single',
              ),
              _buildInfoRow('Duration', _formatDuration(track.duration ?? (track.durationMs != null ? Duration(milliseconds: track.durationMs!) : null))),
              _buildInfoRow('Quality', 'Lossless • High Fidelity (320kbps AAC)'),
              _buildInfoRow(
                'Source',
                track.source.isNotEmpty
                    ? track.source.toUpperCase()
                    : 'MINE MUSIC STREAM',
              ),
              _buildInfoRow('Track ID', track.id),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration? d) {
    if (d == null || d == Duration.zero) return '--:--';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
