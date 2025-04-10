import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../services/spotify_service.dart';
import '../services/api_service.dart';
import '../models/playlist.dart';

class PlaylistImportScreen extends StatefulWidget {
  const PlaylistImportScreen({Key? key}) : super(key: key);

  @override
  State<PlaylistImportScreen> createState() => _PlaylistImportScreenState();
}

class _PlaylistImportScreenState extends State<PlaylistImportScreen> {
  bool _isLoading = false;
  String _selectedService = "Spotify"; // Default service
  final TextEditingController _playlistUrlController = TextEditingController();

  // Use late keyword to initialize after constructor
  final ApiService _apiService = ApiService();
  late final SpotifyService _spotifyService;

  final List<String> _supportedServices = [
    "Spotify",
    "YouTube Music",
    "Amazon Music"
  ];

  @override
  void initState() {
    super.initState();
    // Initialize SpotifyService in initState
    _spotifyService = SpotifyService(_apiService);
  }

  @override
  void dispose() {
    _playlistUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D1D1D),
        title: const Text('Import Playlists'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import from music services',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Service selection dropdown
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              value: _selectedService,
              dropdownColor: Colors.grey[800],
              style: TextStyle(color: Colors.white),
              items: _supportedServices.map((service) {
                return DropdownMenuItem(
                  value: service,
                  child: Text(service),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedService = value!;
                });
              },
            ),

            const SizedBox(height: 24),
            Text(
              'Playlist URL',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),

            // Playlist URL input
            TextField(
              controller: _playlistUrlController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[800],
                hintText: 'Paste playlist URL here',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Import button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _isLoading ? null : _importPlaylistFromUrl,
                child: _isLoading
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text('Import Playlist'),
              ),
            ),

            const SizedBox(height: 16),

            // Alternative import methods
            Text(
              'Or connect directly to your account',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),

            // Service connection buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildServiceButton('Spotify', Icons.music_note, Colors.green),
                _buildServiceButton('YouTube', Icons.play_arrow, Colors.red),
                _buildServiceButton('Amazon', Icons.shopping_cart, Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceButton(String service, IconData icon, Color color) {
    return InkWell(
      onTap: () => _connectToService(service),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            service,
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _importPlaylistFromUrl() async {
    final url = _playlistUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a playlist URL')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Extract playlist ID from URL
      String? playlistId;

      if (_selectedService == 'Spotify' && url.contains('spotify.com/playlist/')) {
        // Example: https://open.spotify.com/playlist/37i9dQZF1DX0XUsuxWHRQd
        final uri = Uri.parse(url);
        final pathSegments = uri.pathSegments;
        final playlistIndex = pathSegments.indexOf('playlist');
        if (playlistIndex >= 0 && playlistIndex < pathSegments.length - 1) {
          playlistId = pathSegments[playlistIndex + 1];
        }
      }

      if (playlistId == null) {
        throw Exception('Could not extract playlist ID from URL');
      }

      // Get playlist details
      final playlists = await _spotifyService.getUserPlaylists();
      final playlistInfo = playlists.firstWhere(
            (p) => p['id'] == playlistId,
        orElse: () => {
          'id': playlistId,
          'name': 'Imported Playlist',
          'images': [{'url': ''}]
        },
      );

      final name = playlistInfo['name'];
      final imageUrl = playlistInfo['images'].isNotEmpty
          ? playlistInfo['images'][0]['url']
          : '';

      // Get playlist with tracks
      final playlist = await _spotifyService.getPlaylistWithTracks(
          playlistId,
          name,
          imageUrl
      );

      // Save to provider
      final musicProvider = Provider.of<MusicProvider>(context, listen: false);
      await musicProvider.importPlaylist(playlist);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playlist imported successfully!')),
      );

      // Clear input
      _playlistUrlController.clear();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error importing playlist: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _connectToService(String service) async {
    if (service != 'Spotify') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$service import is not implemented yet')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Get user's playlists from Spotify
      final playlists = await _spotifyService.getUserPlaylists();

      // Show playlist selection dialog
      final selectedPlaylists = await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
          builder: (context) => PlaylistSelectionScreen(playlists: playlists),
        ),
      );

      if (selectedPlaylists != null && selectedPlaylists.isNotEmpty) {
        final musicProvider = Provider.of<MusicProvider>(context, listen: false);

        // Import each selected playlist
        for (final playlistId in selectedPlaylists) {
          final playlistInfo = playlists.firstWhere((p) => p['id'] == playlistId);
          final name = playlistInfo['name'];
          final imageUrl = playlistInfo['images'].isNotEmpty
              ? playlistInfo['images'][0]['url']
              : '';

          // Get playlist with tracks
          final playlist = await _spotifyService.getPlaylistWithTracks(
              playlistId,
              name,
              imageUrl
          );

          // Save to provider
          await musicProvider.importPlaylist(playlist);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${selectedPlaylists.length} playlists imported!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error connecting to $service: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

// Playlist Selection Screen
class PlaylistSelectionScreen extends StatefulWidget {
  final List<Map<String, dynamic>> playlists;

  const PlaylistSelectionScreen({Key? key, required this.playlists}) : super(key: key);

  @override
  State<PlaylistSelectionScreen> createState() => _PlaylistSelectionScreenState();
}

class _PlaylistSelectionScreenState extends State<PlaylistSelectionScreen> {
  final Set<String> _selectedPlaylistIds = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D1D1D),
        title: const Text('Select Playlists'),
      ),
      body: ListView.builder(
        itemCount: widget.playlists.length,
        itemBuilder: (context, index) {
          final playlist = widget.playlists[index];
          final isSelected = _selectedPlaylistIds.contains(playlist['id']);

          return CheckboxListTile(
            title: Text(
              playlist['name'],
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              '${playlist['tracks']['total']} tracks',
              style: TextStyle(color: Colors.grey),
            ),
            secondary: playlist['images'] != null && playlist['images'].isNotEmpty
                ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                playlist['images'][0]['url'],
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 50,
                  height: 50,
                  color: Colors.grey[800],
                  child: Icon(Icons.music_note, color: Colors.white),
                ),
              ),
            )
                : null,
            value: isSelected,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedPlaylistIds.add(playlist['id']);
                } else {
                  _selectedPlaylistIds.remove(playlist['id']);
                }
              });
            },
            checkColor: Colors.black,
            activeColor: Colors.deepPurple,
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: _selectedPlaylistIds.isEmpty
              ? null
              : () {
            Navigator.pop(context, _selectedPlaylistIds.toList());
          },
          child: Text('Import ${_selectedPlaylistIds.length} Playlists'),
        ),
      ),
    );
  }
}
