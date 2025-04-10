import 'package:flutter/material.dart';
import 'liked_songs_screen.dart';
import 'recently_played_screen.dart';
import 'user_playlist_screen.dart';
import 'downloaded_songs_screen.dart';
import 'playlist_import_screen.dart';
import 'local_music_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D1D1D),
        title: const Text(
          'Your Library',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              _buildLibraryCard(
                context,
                title: 'Liked Songs',
                icon: Icons.favorite,
                color: Colors.redAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LikedSongsScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildLibraryCard(
                context,
                title: 'Recently Played',
                icon: Icons.history,
                color: Colors.blueAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RecentlyPlayedScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildLibraryCard(
                context,
                title: 'Your Playlists',
                icon: Icons.playlist_play,
                color: Colors.greenAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const UserPlaylistScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildLibraryCard(
                context,
                title: 'Downloaded Songs',
                icon: Icons.download_done_rounded,
                color: Colors.orangeAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DownloadedSongsScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildLibraryCard(
                context,
                title: 'Local Music',
                icon: Icons.folder, // or Icons.music_note or Icons.audio_file
                color: Colors.amberAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LocalMusicScreen()),
                  );
                },
              ),

              const SizedBox(height: 16),
              _buildLibraryCard(
                context,
                title: 'Import Playlists',
                icon: Icons.playlist_add,
                color: Colors.purpleAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PlaylistImportScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryCard(
      BuildContext context, {
        required String title,
        required IconData icon,
        required Color color,
        required VoidCallback onTap,
      }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1D1D),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white70,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
