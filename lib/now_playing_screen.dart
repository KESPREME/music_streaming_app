import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/track.dart';
import 'providers/music_provider.dart';

class NowPlayingScreen extends StatefulWidget {
  final Track track;

  const NowPlayingScreen({required this.track, Key? key}) : super(key: key);

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  @override
  Widget build(BuildContext context) {
    // Use Consumer to rebuild when track changes
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        // Always use the current track from provider, not the one passed in
        final currentTrack = musicProvider.currentTrack ?? widget.track;
        final isPlaying = musicProvider.isPlaying;
        final shuffleEnabled = musicProvider.shuffleEnabled;
        final repeatMode = musicProvider.repeatMode;

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'Now Playing',
              style: TextStyle(color: Colors.white),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () {
                  _showOptionsBottomSheet(context, currentTrack);
                },
              ),
            ],
          ),
          body: Column(
            children: [
              const Spacer(),
              // Album Art
              Container(
                width: MediaQuery.of(context).size.width * 0.8,
                height: MediaQuery.of(context).size.width * 0.8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  color: Colors.grey[800],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    currentTrack.albumArtUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.music_note,
                        color: Colors.white,
                        size: 80,
                      );
                    },
                  ),
                ),
              ),
              const Spacer(),
              // Track Info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentTrack.trackName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentTrack.artistName,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Progress Bar with StreamBuilder for real-time updates
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    StreamBuilder<Duration>(
                      stream: musicProvider.positionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? Duration.zero;
                        final duration = musicProvider.duration;

                        return Column(
                          children: [
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                activeTrackColor: Colors.deepPurple,
                                inactiveTrackColor: Colors.grey[800],
                                thumbColor: Colors.white,
                                overlayColor: Colors.deepPurple.withOpacity(0.3),
                              ),
                              child: Slider(
                                value: position.inSeconds.toDouble().clamp(0, duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0),
                                min: 0,
                                max: duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0,
                                onChanged: (value) {
                                  musicProvider.seekTo(Duration(seconds: value.toInt()));
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(position),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  Text(
                                    _formatDuration(duration),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Shuffle and Repeat Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: shuffleEnabled ? Colors.deepPurple : Colors.white70,
                      size: 24,
                    ),
                    onPressed: () {
                      musicProvider.toggleShuffle();
                      // Force rebuild
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: Icon(
                      repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
                      color: repeatMode != RepeatMode.off ? Colors.deepPurple : Colors.white70,
                      size: 24,
                    ),
                    onPressed: () {
                      musicProvider.cycleRepeatMode();
                      // Force rebuild
                      setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Playback Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.skip_previous,
                      color: Colors.white,
                      size: 36,
                    ),
                    onPressed: () {
                      musicProvider.skipToPrevious();
                    },
                  ),
                  const SizedBox(width: 20),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Colors.deepPurple,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 36,
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          musicProvider.pauseTrack();
                        } else {
                          musicProvider.resumeTrack();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    icon: const Icon(
                      Icons.skip_next,
                      color: Colors.white,
                      size: 36,
                    ),
                    onPressed: () {
                      musicProvider.skipToNext();
                    },
                  ),
                ],
              ),
              const Spacer(),
              // Additional Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(
                        musicProvider.isSongLiked(currentTrack.id) ? Icons.favorite : Icons.favorite_border,
                        color: musicProvider.isSongLiked(currentTrack.id) ? Colors.deepPurple : Colors.white70,
                        size: 24,
                      ),
                      onPressed: () {
                        if (musicProvider.isSongLiked(currentTrack.id)) {
                          musicProvider.unlikeSong(currentTrack.id);
                        } else {
                          musicProvider.likeSong(currentTrack);
                        }
                        // Force rebuild
                        setState(() {});
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.playlist_add,
                        color: Colors.white70,
                        size: 24,
                      ),
                      onPressed: () {
                        _showAddToPlaylistBottomSheet(context, currentTrack);
                      },
                    ),
                    FutureBuilder<bool>(
                      future: musicProvider.isTrackDownloaded(currentTrack.id),
                      builder: (context, snapshot) {
                        final isDownloaded = snapshot.data ?? false;
                        final isDownloading = musicProvider.isDownloading[currentTrack.id] ?? false;
                        final downloadProgress = musicProvider.downloadProgress[currentTrack.id] ?? 0.0;

                        return IconButton(
                          icon: isDownloaded
                              ? const Icon(Icons.download_done, color: Colors.deepPurple)
                              : isDownloading
                              ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                              value: downloadProgress,
                              strokeWidth: 2,
                            ),
                          )
                              : const Icon(Icons.download, color: Colors.white70),
                          onPressed: () {
                            if (!isDownloaded && !isDownloading) {
                              musicProvider.downloadTrack(currentTrack);
                            } else if (isDownloaded) {
                              _showDownloadOptionsBottomSheet(context, currentTrack);
                            }
                          },
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.share,
                        color: Colors.white70,
                        size: 24,
                      ),
                      onPressed: () {
                        // Implement share functionality
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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

  void _showOptionsBottomSheet(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1D1D1D),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.playlist_add, color: Colors.white),
            title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _showAddToPlaylistBottomSheet(context, track);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share, color: Colors.white),
            title: const Text('Share', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              // Implement share functionality
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white),
            title: const Text('Track Info', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              // Show track info
            },
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistBottomSheet(BuildContext context, Track track) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1D1D1D),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text(
              'Add to Playlist',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: musicProvider.userPlaylists.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    leading: const Icon(Icons.add, color: Colors.deepPurple),
                    title: const Text('Create New Playlist', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      _showCreatePlaylistDialog(context, track);
                    },
                  );
                }

                final playlist = musicProvider.userPlaylists[index - 1];
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.music_note, color: Colors.white),
                  ),
                  title: Text(playlist.name, style: const TextStyle(color: Colors.white)),
                  subtitle: Text('${playlist.tracks.length} tracks', style: const TextStyle(color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    musicProvider.addTrackToPlaylist(playlist.id, track);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added to ${playlist.name}')),
                    );
                    // Force rebuild
                    setState(() {});
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, Track track) {
    final TextEditingController nameController = TextEditingController();
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1D1D),
        title: const Text('Create Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.deepPurple),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Create', style: TextStyle(color: Colors.deepPurple)),
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                musicProvider.createPlaylist(nameController.text.trim(), initialTracks: [track]); // NEW - Correct named parameter
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created playlist ${nameController.text.trim()}')),
                );
                // Force rebuild
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  void _showDownloadOptionsBottomSheet(BuildContext context, Track track) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1D1D1D),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Remove Download', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              musicProvider.deleteDownloadedTrack(track.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Download removed')),
              );
              // Force rebuild
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
