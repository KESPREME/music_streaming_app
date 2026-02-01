import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../services/spotify_service.dart';
import 'spotify_playlist_selection_screen.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouPlaylistImportScreen extends StatefulWidget {
  const MaterialYouPlaylistImportScreen({super.key});

  @override
  State<MaterialYouPlaylistImportScreen> createState() => _MaterialYouPlaylistImportScreenState();
}

class _MaterialYouPlaylistImportScreenState extends State<MaterialYouPlaylistImportScreen> {
  bool _isLoading = false;
  String _selectedService = "Spotify";
  final TextEditingController _playlistUrlController = TextEditingController();
  final SpotifyService _spotifyService = SpotifyService();
  final List<String> _supportedServices = ["Spotify", "YouTube Music", "Amazon Music"];

  @override
  void dispose() {
    _playlistUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          'Import Playlists',
          style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImportCard(colorScheme),
            const SizedBox(height: 24),
            Text(
              'Quick Connect',
              style: MaterialYouTypography.titleMedium(colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildServiceButton('Spotify', Icons.music_note_rounded, const Color(0xFF1DB954), colorScheme),
                _buildServiceButton('YouTube', Icons.play_arrow_rounded, const Color(0xFFFF0000), colorScheme),
                _buildServiceButton('Amazon', Icons.shopping_cart_rounded, const Color(0xFF232F3E), colorScheme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MaterialYouTokens.surfaceContainerDark,
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeLarge),
        border: Border.all(color: colorScheme.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Import from URL',
            style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
          ),
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: MaterialYouTokens.surfaceVariantDark,
              borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
              border: Border.all(color: colorScheme.surfaceVariant),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                dropdownColor: MaterialYouTokens.surfaceContainerDark,
                value: _selectedService,
                isExpanded: true,
                style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
                icon: Icon(Icons.expand_more_rounded, color: colorScheme.onSurfaceVariant),
                items: _supportedServices.map((service) {
                  return DropdownMenuItem(
                    value: service,
                    child: Text(service),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedService = value!),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          TextField(
            controller: _playlistUrlController,
            style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
            decoration: InputDecoration(
              filled: true,
              fillColor: MaterialYouTokens.surfaceVariantDark,
              hintText: 'Paste playlist URL here',
              hintStyle: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
                borderSide: BorderSide(color: MaterialYouTokens.primaryVibrant),
              ),
              prefixIcon: Icon(Icons.link_rounded, color: colorScheme.onSurfaceVariant),
            ),
          ),
          
          const SizedBox(height: 24),
          
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: MaterialYouTokens.primaryVibrant,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
                ),
              ),
              onPressed: _isLoading ? null : _importPlaylistFromUrl,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('Import Playlist'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceButton(String service, IconData icon, Color color, ColorScheme colorScheme) {
    return InkWell(
      onTap: () => _connectToService(service),
      borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              service,
              style: MaterialYouTypography.bodySmall(colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importPlaylistFromUrl() async {
    final url = _playlistUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a URL')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? playlistId;
      if (_selectedService == 'Spotify' && url.contains('spotify.com/playlist/')) {
        final uri = Uri.parse(url);
        final pathSegments = uri.pathSegments;
        final playlistIndex = pathSegments.indexOf('playlist');
        if (playlistIndex >= 0 && playlistIndex < pathSegments.length - 1) {
          playlistId = pathSegments[playlistIndex + 1];
        }
      }

      if (playlistId == null) throw Exception('Could not extract playlist ID from URL');

      final playlistInfo = await _spotifyService.getPlaylistMetadata(playlistId);

      final imageUrl = (playlistInfo['images'] as List).isNotEmpty 
          ? playlistInfo['images'][0]['url'] 
          : '';
          
      final playlist = await _spotifyService.getPlaylistWithTracks(playlistId, playlistInfo['name'], imageUrl);
      
      if (mounted) {
        await Provider.of<MusicProvider>(context, listen: false).importPlaylist(playlist);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playlist imported successfully!')),
        );
        _playlistUrlController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _connectToService(String service) async {
    if (service != 'Spotify') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$service coming soon')),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final playlists = await _spotifyService.getUserPlaylists();
      
      if (!mounted) return;
      setState(() => _isLoading = false);
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SpotifyPlaylistSelectionScreen(
            playlists: playlists,
            onPlaylistSelected: (playlistMap) {
              Navigator.pop(context);
              _importSpotifyPlaylist(playlistMap);
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error connecting: $e')),
        );
      }
    }
  }

  Future<void> _importSpotifyPlaylist(Map<String, dynamic> playlistInfo) async {
    setState(() => _isLoading = true);
    
    try {
      final playlistId = playlistInfo['id'];
      final name = playlistInfo['name'];
      final images = playlistInfo['images'] as List;
      final imageUrl = images.isNotEmpty ? images[0]['url'] : '';
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Importing playlist...')),
      );
      
      final playlist = await _spotifyService.getPlaylistWithTracks(playlistId, name, imageUrl);
      
      if (mounted) {
        await Provider.of<MusicProvider>(context, listen: false).importPlaylist(playlist);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported "${playlist.name}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
