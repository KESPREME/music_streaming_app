import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({Key? key, required this.playlist}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Consumer<MusicProvider>(
        builder: (context, musicProvider, child) {
          // Find the latest version of the playlist
          final currentPlaylist = musicProvider.userPlaylists
              .firstWhere((p) => p.id == playlist.id, orElse: () => playlist);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(currentPlaylist.name),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.deepPurple.shade800,
                          Colors.deepPurple.shade500,
                        ],
                      ),
                    ),
                    child: Center(
                      child: currentPlaylist.imageUrl.isNotEmpty
                          ? Image.network(
                        currentPlaylist.imageUrl,
                        fit: BoxFit.cover,
                        width: 120,
                        height: 120,
                      )
                          : Icon(
                        Icons.playlist_play,
                        color: Colors.white,
                        size: 80,
                      ),
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.play_circle_filled),
                    onPressed: () {
                      if (currentPlaylist.tracks.isNotEmpty) {
                        musicProvider.playTrack(currentPlaylist.tracks.first);
                      }
                    },
                  ),
                ],
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    if (index >= currentPlaylist.tracks.length) return null;
                    return _buildTrackItem(
                      context,
                      currentPlaylist.tracks[index],
                      index,
                      musicProvider,
                      currentPlaylist.id,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTrackItem(
      BuildContext context,
      Track track,
      int index,
      MusicProvider musicProvider,
      String playlistId,
      ) {
    final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          track.albumArtUrl,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 50,
            height: 50,
            color: Colors.grey[800],
            child: const Icon(Icons.music_note, color: Colors.white),
          ),
        ),
      ),
      title: Text(
        track.trackName,
        style: TextStyle(
          color: isPlaying ? Colors.deepPurple : Colors.white,
          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        track.artistName,
        style: TextStyle(color: Colors.grey[400]),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert, color: Colors.white),
        onPressed: () => _showTrackOptions(context, track, musicProvider, playlistId),
      ),
      onTap: () {
        musicProvider.playTrack(track);
      },
    );
  }

  void _showTrackOptions(
      BuildContext context,
      Track track,
      MusicProvider musicProvider,
      String playlistId,
      ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_arrow, color: Colors.white),
            title: const Text('Play', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              musicProvider.playTrack(track);
            },
          ),
          ListTile(
            leading: Icon(
              musicProvider.isSongLiked(track.id) ? Icons.favorite : Icons.favorite_border,
              color: musicProvider.isSongLiked(track.id) ? Colors.red : Colors.white,
            ),
            title: Text(
              musicProvider.isSongLiked(track.id) ? 'Remove from Liked Songs' : 'Add to Liked Songs',
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              if (musicProvider.isSongLiked(track.id)) {
                musicProvider.unlikeSong(track.id);
              } else {
                musicProvider.likeSong(track);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download, color: Colors.white),
            title: const Text('Download', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              musicProvider.downloadTrack(track);
            },
          ),
          ListTile(
            leading: const Icon(Icons.remove_circle_outline, color: Colors.white),
            title: const Text('Remove from Playlist', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              musicProvider.removeTrackFromPlaylist(playlistId, track.id);
            },
          ),
        ],
      ),
    );
  }
}
