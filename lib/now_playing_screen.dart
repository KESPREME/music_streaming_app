import 'dart:ui'; // For ImageFilter
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../widgets/player_controls.dart'; // Assuming this will be styled or replaced by themed controls

class NowPlayingScreen extends StatefulWidget {
  final Track track; // Initial track, but current track from provider is source of truth

  const NowPlayingScreen({required this.track, Key? key}) : super(key: key);

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  // No local state needed if all driven by MusicProvider and theme

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final currentTrack = musicProvider.currentTrack ?? widget.track; // Fallback to initial track
        final isPlaying = musicProvider.isPlaying;
        // shuffleEnabled and repeatMode are available in musicProvider if needed for UI indication

        return Scaffold(
          // backgroundColor will be from theme.scaffoldBackgroundColor
          extendBodyBehindAppBar: true, // Allows content to go behind AppBar
          appBar: AppBar(
            backgroundColor: Colors.transparent, // Make AppBar transparent
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down), // Standard icon, color from theme
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
                  // TODO: Implement show queue bottom sheet or screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Queue button pressed (not implemented)")),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_outlined),
                tooltip: "More options",
                onPressed: () {
                  _showOptionsBottomSheet(context, currentTrack, theme, musicProvider);
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              // Blurred Background Image (like Spotify)
              Positioned.fill(
                child: currentTrack.albumArtUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: currentTrack.albumArtUrl,
                        fit: BoxFit.cover,
                        imageBuilder: (context, imageProvider) => Container(
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: imageProvider,
                              fit: BoxFit.cover,
                            ),
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.4)), // Dark overlay
                            ),
                          ),
                        ),
                        placeholder: (context, url) => Container(color: theme.colorScheme.surface),
                        errorWidget: (context, url, error) => Container(color: theme.colorScheme.surface),
                      )
                    : Container(color: theme.colorScheme.background), // Fallback background
              ),
              // Main Content
              Padding(
                padding: EdgeInsets.only(
                  top: kToolbarHeight + MediaQuery.of(context).padding.top + 20, // Below AppBar
                  bottom: MediaQuery.of(context).padding.bottom + 20, // Above system navigation
                  left: 24,
                  right: 24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween, // Distribute space
                  children: [
                    // Album Art - centered and responsive
                    Expanded(
                      flex: 5, // Give more space to album art
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: Container(
                            margin: const EdgeInsets.all(16), // Margin around art
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16), // Softer corners
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
                                  ? CachedNetworkImage(
                                      imageUrl: currentTrack.albumArtUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(color: theme.colorScheme.surfaceVariant, child: Center(child: Icon(Icons.music_note, size: 80, color: theme.colorScheme.onSurfaceVariant))),
                                      errorWidget: (context, url, error) => Container(color: theme.colorScheme.surfaceVariant, child: Center(child: Icon(Icons.broken_image, size: 80, color: theme.colorScheme.onSurfaceVariant))),
                                    )
                                  : Container(color: theme.colorScheme.surfaceVariant, child: Center(child: Icon(Icons.music_note, size: 80, color: theme.colorScheme.onSurfaceVariant))),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Track Info & Like Button
                    Expanded(
                      flex: 2, // Space for track info
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
                                  // setState is implicitly called by Consumer
                                },
                                tooltip: musicProvider.isSongLiked(currentTrack.id) ? "Unlike" : "Like",
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Progress Bar
                    Expanded(
                      flex: 1, // Space for progress bar
                      child: StreamBuilder<Duration>(
                        stream: musicProvider.positionStream,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final duration = musicProvider.duration;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Slider( // Uses SliderTheme from main.dart
                                value: position.inSeconds.toDouble().clamp(0.0, duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0),
                                min: 0,
                                max: duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0, // Avoid division by zero if duration is 0
                                onChanged: (value) {
                                  musicProvider.seekTo(Duration(seconds: value.toInt()));
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0), // Match slider padding
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
                    ),

                    // Playback Controls (using the PlayerControls widget, which should also be themed)
                    Expanded(
                      flex: 2, // Space for controls
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        child: PlayerControls(showLabels: false, compact: false), // Using existing controls
                                                                          // This widget should be updated to use theme colors
                      )
                    ),

                    // Additional Controls (Shuffle, Repeat, etc. - can be part of PlayerControls or separate)
                    // For now, assuming PlayerControls handles shuffle/repeat indication
                    // Or add a row here:
                    // Row(
                    //   mainAxisAlignment: MainAxisAlignment.spaceAround,
                    //   children: [
                    //     IconButton(icon: Icon(Icons.shuffle, color: musicProvider.shuffleEnabled ? theme.primaryColor : Colors.white70), onPressed: musicProvider.toggleShuffle),
                    //     IconButton(icon: Icon(Icons.repeat, color: musicProvider.repeatMode != RepeatMode.off ? theme.primaryColor : Colors.white70), onPressed: musicProvider.cycleRepeatMode),
                    //     // Add more like share, download status etc.
                    //   ],
                    // ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _showOptionsBottomSheet(BuildContext context, Track track, ThemeData theme, MusicProvider musicProvider) {
    // Using theme for bottom sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surfaceVariant, // Darker surface for bottom sheet
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Wrap( // Use Wrap for content that might overflow vertically
        children: [
          ListTile(
            leading: Icon(Icons.playlist_add_outlined, color: theme.iconTheme.color),
            title: Text('Add to Playlist', style: theme.textTheme.titleMedium),
            onTap: () {
              Navigator.pop(context); // Close this sheet
              _showAddToPlaylistBottomSheet(context, track, theme, musicProvider); // Show playlist selection
            },
          ),
          ListTile(
            leading: Icon(
              musicProvider.isTrackDownloaded(track.id) == true // This future needs to be resolved or use a state
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
              // Consider rebuilding NowPlayingScreen or parts of it if download status changes UI there
              if(mounted) setState(() {});
            },
          ),
          ListTile(
            leading: Icon(Icons.share_outlined, color: theme.iconTheme.color),
            title: Text('Share', style: theme.textTheme.titleMedium),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement share functionality using share_plus or similar
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Share (not implemented)")),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.album_outlined, color: theme.iconTheme.color),
            title: Text('Go to Album', style: theme.textTheme.titleMedium),
            onTap: () {
              Navigator.pop(context);
              // TODO: Navigate to AlbumScreen
               ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Go to Album (not implemented)")),
              );
            },
          ),
           ListTile(
            leading: Icon(Icons.person_outline, color: theme.iconTheme.color),
            title: Text('Go to Artist', style: theme.textTheme.titleMedium),
            onTap: () {
              Navigator.pop(context);
              // TODO: Navigate to ArtistScreen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Go to Artist (not implemented)")),
              );
            },
          ),
          const SizedBox(height: 16), // Padding at the bottom
        ],
      ),
    );
  }

  void _showAddToPlaylistBottomSheet(BuildContext context, Track track, ThemeData theme, MusicProvider musicProvider) {
    // This is a simplified version. A real app might have a scrollable list of playlists.
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surfaceVariant,
       shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add to Playlist', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.add_circle_outline, color: theme.colorScheme.primary),
              title: Text('Create New Playlist', style: theme.textTheme.titleMedium),
              onTap: () {
                Navigator.pop(context); // Close this sheet
                _showCreatePlaylistDialog(context, track, theme, musicProvider);
              },
            ),
            // Dynamically generate list of existing playlists
            if (musicProvider.userPlaylists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text("You haven't created any playlists yet.", style: theme.textTheme.bodyMedium),
              )
            else
              Flexible( // Use Flexible for scrollable content within BottomSheet
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: musicProvider.userPlaylists.length,
                  itemBuilder: (context, index) {
                    final playlist = musicProvider.userPlaylists[index];
                    bool isTrackInPlaylist = playlist.tracks.any((t) => t.id == track.id);
                    return ListTile(
                      leading: Icon(
                        isTrackInPlaylist ? Icons.playlist_add_check_circle_outlined : Icons.playlist_add_outlined,
                        color: isTrackInPlaylist ? theme.colorScheme.primary : theme.iconTheme.color,
                      ),
                      title: Text(playlist.name, style: theme.textTheme.titleMedium),
                      subtitle: Text('${playlist.tracks.length} tracks', style: theme.textTheme.bodySmall),
                      onTap: () {
                        Navigator.pop(context);
                        if (!isTrackInPlaylist) {
                          musicProvider.addTrackToPlaylist(playlist.id, track);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Added to ${playlist.name}')),
                          );
                        } else {
                           ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Track is already in ${playlist.name}')),
                          );
                        }
                        if(mounted) setState(() {}); // Rebuild to reflect changes if any
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, Track track, ThemeData theme, MusicProvider musicProvider) {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        // Theme for AlertDialog is set in main.dart
        title: Text('Create New Playlist', style: theme.dialogTheme.titleTextStyle),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration( // Uses theme.inputDecorationTheme
            hintText: 'Playlist name',
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'), // Uses theme.textButtonTheme
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton( // Uses theme.elevatedButtonTheme
            child: const Text('Create'),
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                musicProvider.createPlaylist(nameController.text.trim(), initialTracks: [track]);
                Navigator.pop(context); // Close dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Playlist "${nameController.text.trim()}" created.')),
                );
                 if(mounted) setState(() {}); // Rebuild to reflect changes
              }
            },
          ),
        ],
      ),
    );
  }

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
