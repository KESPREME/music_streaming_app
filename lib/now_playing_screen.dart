import 'dart:ui'; // For ImageFilter
// import 'package:cached_network_image/cached_network_image.dart'; // Commented out
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../widgets/player_controls.dart';
import '../widgets/playlist_selection_dialog.dart'; // Import the new dialog
import '../screens/album_screen.dart'; // Import AlbumScreen
import '../screens/artist_screen.dart'; // Import ArtistScreen
import '../screens/queue_screen.dart'; // Import QueueScreen

class NowPlayingScreen extends StatefulWidget {
  final Track track; // Initial track, but current track from provider is source of truth

  const NowPlayingScreen({required this.track, Key? key}) : super(key: key);

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final currentTrack = musicProvider.currentTrack ?? widget.track;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: _buildAppBar(context, theme, currentTrack, musicProvider),
          body: Stack(
            children: [
              _buildBlurredBackground(context, theme, currentTrack),
              Padding(
                padding: EdgeInsets.only(
                  top: kToolbarHeight + MediaQuery.of(context).padding.top + 20,
                  bottom: MediaQuery.of(context).padding.bottom + 20,
                  left: 24,
                  right: 24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildAlbumArt(context, theme, currentTrack),
                    _buildTrackInfo(context, theme, currentTrack, musicProvider),
                    _buildProgressBar(context, musicProvider),
                    const PlayerControls(showLabels: false, compact: false),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  AppBar _buildAppBar(BuildContext context, ThemeData theme, Track track, MusicProvider musicProvider) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.keyboard_arrow_down),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: "Close player",
      ),
      title: Text(
        'Now Playing',
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.queue_music_outlined),
          tooltip: "View Queue",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const QueueScreen()),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.more_vert_outlined),
          tooltip: "More options",
          onPressed: () {
            _showOptionsBottomSheet(context, track, theme, musicProvider);
          },
        ),
      ],
    );
  }

  Widget _buildBlurredBackground(BuildContext context, ThemeData theme, Track currentTrack) {
    return Positioned.fill(
      child: currentTrack.albumArtUrl.isNotEmpty
          ? Image.network(
              currentTrack.albumArtUrl,
              fit: BoxFit.cover,
              frameBuilder: (BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) {
                  return Container(
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: NetworkImage(currentTrack.albumArtUrl),
                        fit: BoxFit.cover,
                      ),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                      child: Container(
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.4)),
                      ),
                    ),
                  );
                } else {
                  return Container(color: theme.colorScheme.surface);
                }
              },
              errorBuilder: (context, error, stackTrace) => Container(color: theme.colorScheme.background),
            )
          : Container(color: theme.colorScheme.background),
    );
  }

  Widget _buildAlbumArt(BuildContext context, ThemeData theme, Track currentTrack) {
    return Expanded(
      flex: 5,
      child: Center(
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16.0),
              child: currentTrack.albumArtUrl.isNotEmpty
                  ? Image.network(
                      currentTrack.albumArtUrl,
                      fit: BoxFit.cover,
                      cacheWidth: (MediaQuery.of(context).size.width * MediaQuery.of(context).devicePixelRatio).round(),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(color: theme.colorScheme.surfaceVariant, child: Center(child: CircularProgressIndicator(value: loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : null)));
                      },
                      errorBuilder: (context, error, stackTrace) => Container(color: theme.colorScheme.surfaceVariant, child: Center(child: Icon(Icons.broken_image, size: 80, color: theme.colorScheme.onSurfaceVariant))),
                    )
                  : Container(color: theme.colorScheme.surfaceVariant, child: Center(child: Icon(Icons.music_note, size: 80, color: theme.colorScheme.onSurfaceVariant))),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackInfo(BuildContext context, ThemeData theme, Track currentTrack, MusicProvider musicProvider) {
    return Expanded(
      flex: 2,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentTrack.trackName,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      currentTrack.artistName,
                      style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onBackground.withOpacity(0.7)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  musicProvider.isSongLiked(currentTrack.id) ? Icons.favorite : Icons.favorite_border,
                  color: musicProvider.isSongLiked(currentTrack.id) ? theme.colorScheme.primary : theme.iconTheme.color,
                  size: 28,
                ),
                onPressed: () {
                  musicProvider.toggleLike(currentTrack);
                },
                tooltip: musicProvider.isSongLiked(currentTrack.id) ? "Unlike" : "Like",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, MusicProvider musicProvider) {
    final theme = Theme.of(context);
    return Expanded(
      flex: 1,
      child: StreamBuilder<Duration>(
        stream: musicProvider.positionStream,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          final duration = musicProvider.duration;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Slider(
                value: position.inSeconds.toDouble().clamp(0.0, duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0),
                min: 0,
                max: duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0,
                onChanged: (value) {
                  musicProvider.seekTo(Duration(seconds: value.toInt()));
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(position), style: theme.textTheme.bodySmall),
                    Text(_formatDuration(duration), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _showOptionsBottomSheet(BuildContext context, Track track, ThemeData theme, MusicProvider musicProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: Icon(Icons.playlist_add_outlined, color: theme.iconTheme.color),
            title: Text('Add to Playlist', style: theme.textTheme.titleMedium),
            onTap: () {
              Navigator.pop(context);
              showPlaylistSelectionDialog(context, track);
            },
          ),
          ListTile(
            leading: Icon(
              musicProvider.isTrackDownloaded(track.id) == true
                  ? Icons.download_done_outlined
                  : Icons.download_outlined,
              color: musicProvider.isTrackDownloaded(track.id) == true ? theme.colorScheme.primary : theme.iconTheme.color,
            ),
            title: Text(
              musicProvider.isTrackDownloaded(track.id) == true ? 'Remove Download' : 'Download',
              style: theme.textTheme.titleMedium
            ),
            onTap: () async {
              Navigator.pop(context);
              if (await musicProvider.isTrackDownloaded(track.id)) {
                 _showDownloadOptionsBottomSheet(context, track, theme, musicProvider);
              } else if (!(musicProvider.isDownloading[track.id] ?? false)) {
                musicProvider.downloadTrack(track);
                 ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Downloading ${track.trackName}...')),
                );
              }
              if(mounted) setState(() {});
            },
          ),
          ListTile(
            leading: Icon(Icons.share_outlined, color: theme.iconTheme.color),
            title: Text('Share', style: theme.textTheme.titleMedium),
            onTap: () async {
              Navigator.pop(context);

              String shareText = 'Listening to: ${track.trackName} by ${track.artistName}';
              String? shareableLink;

              if (track.source == 'youtube' && track.previewUrl.startsWith('http')) {
                shareableLink = track.previewUrl;
              } else if (track.source == 'spotify') {
                // Example: shareableLink = 'https://open.spotify.com/track/${track.id}';
              }

              if (shareableLink != null) {
                shareText += '\n\n$shareableLink';
              }

              try {
                await Share.share(shareText, subject: 'Check out this track: ${track.trackName}');
              } catch (e) {
                print('Error sharing track from NowPlayingScreen: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not share track.'))
                  );
                }
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.album_outlined, color: theme.iconTheme.color),
            title: Text('Go to Album', style: theme.textTheme.titleMedium),
            onTap: () async {
              Navigator.pop(context);
              bool isAlbumValid = track.albumName.isNotEmpty && track.albumName != 'Unknown Album' && track.albumName != 'YouTube';
              if (!isAlbumValid) {
                 if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Album details not available')));
                }
                return;
              }
              await musicProvider.navigateToAlbum(track.albumName, track.artistName);
              if (context.mounted) {
                if (musicProvider.currentAlbumDetails != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AlbumScreen(albumName: track.albumName, artistName: track.artistName)),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(musicProvider.errorMessage ?? 'Could not load album details'), backgroundColor: theme.colorScheme.error),
                  );
                }
              }
            },
          ),
           ListTile(
            leading: Icon(Icons.person_outline, color: theme.iconTheme.color),
            title: Text('Go to Artist', style: theme.textTheme.titleMedium),
            onTap: () async {
              Navigator.pop(context);
              bool isArtistValid = track.artistName.isNotEmpty && track.artistName != 'Unknown Artist';
              if (!isArtistValid) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Artist details not available')));
                }
                return;
              }
              await musicProvider.navigateToArtist(track.artistName);
              if (context.mounted) {
                if (musicProvider.currentArtistDetails != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ArtistScreen(artistName: track.artistName)),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(musicProvider.errorMessage ?? 'Could not load artist details'), backgroundColor: theme.colorScheme.error),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 16), // Padding at the bottom
        ],
      ),
    );
  }

  // Removed _showAddToPlaylistBottomSheet as its functionality is replaced by showPlaylistSelectionDialog
  // Removed _showCreatePlaylistDialog as its functionality is part of showPlaylistSelectionDialog

   void _showDownloadOptionsBottomSheet(BuildContext context, Track track, ThemeData theme, MusicProvider musicProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surfaceVariant,
       shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text('Remove Download', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error)),
            onTap: () {
              Navigator.pop(context);
              musicProvider.deleteDownloadedTrack(track.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Download removed')),
              );
              if(mounted) setState(() {}); // Rebuild to reflect changes
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
