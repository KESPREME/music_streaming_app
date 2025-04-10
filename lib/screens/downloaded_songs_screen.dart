import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';

class DownloadedSongsScreen extends StatefulWidget {
  const DownloadedSongsScreen({Key? key}) : super(key: key);

  @override
  State<DownloadedSongsScreen> createState() => _DownloadedSongsScreenState();
}

class _DownloadedSongsScreenState extends State<DownloadedSongsScreen> {
  List<Track> _downloadedTracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDownloadedSongs();
  }

  Future<void> _loadDownloadedSongs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final musicProvider = Provider.of<MusicProvider>(context, listen: false);
      final tracks = await musicProvider.getDownloadedTracks();

      setState(() {
        _downloadedTracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading downloaded songs: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D1D1D),
        title: const Text(
          'Downloaded Songs',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Consumer<MusicProvider>(
        builder: (context, musicProvider, child) {
          final downloadingTracks = musicProvider.currentlyDownloadingTracks;

          if (_downloadedTracks.isEmpty && downloadingTracks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.download_rounded,
                    size: 80,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No downloaded songs yet',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Download songs to listen offline',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadDownloadedSongs,
            child: ListView(
              children: [
                // Currently downloading section
                if (downloadingTracks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Downloading',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...downloadingTracks.map((track) {
                    final progress = musicProvider.downloadProgress[track.id] ?? 0.0;
                    return _buildDownloadingItem(track, progress, musicProvider);
                  }),
                  const Divider(color: Colors.grey),
                ],

                // Downloaded section
                if (_downloadedTracks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Downloaded',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ..._downloadedTracks.map((track) => _buildDownloadedItem(track, musicProvider)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDownloadingItem(Track track, double progress, MusicProvider musicProvider) {
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
        style: const TextStyle(color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            track.artistName,
            style: TextStyle(color: Colors.grey[400]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          const SizedBox(height: 2),
          Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.cancel, color: Colors.white),
        onPressed: () {
          musicProvider.cancelDownload(track.id);
        },
      ),
    );
  }

  Widget _buildDownloadedItem(Track track, MusicProvider musicProvider) {
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
        style: const TextStyle(color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.artistName,
        style: TextStyle(color: Colors.grey[400]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_arrow, color: Colors.white),
            onPressed: () {
              musicProvider.playOfflineTrack(track);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: () async {
              try {
                await musicProvider.deleteDownloadedTrack(track.id);
                _loadDownloadedSongs(); // Refresh the list
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Deleted ${track.trackName}')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error deleting track: $e')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
