import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../services/playlist_import_service.dart';
import '../models/playlist.dart';
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
  final PlaylistImportService _importService = PlaylistImportService();
  final List<String> _supportedServices = ["Spotify", "YouTube Music"];

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
                _buildServiceButton('YouTube Music', Icons.play_arrow_rounded, const Color(0xFFFF0000), colorScheme),
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
      Playlist playlist;
      if (_selectedService == 'Spotify') {
        playlist = await _importService.importSpotifyPlaylist(url);
      } else if (_selectedService == 'YouTube Music') {
        playlist = await _importService.importYoutubePlaylist(url);
      } else {
        throw Exception('Unsupported service');
      }
      
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
    setState(() {
      _selectedService = service;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Selected $service. Please enter the playlist URL above.')),
    );
  }
}
