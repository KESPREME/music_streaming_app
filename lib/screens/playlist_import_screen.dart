import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../services/spotify_service.dart';
import '../services/spotify_service.dart';
import 'spotify_playlist_selection_screen.dart';
import '../widgets/liquid_snackbar.dart';

class PlaylistImportScreen extends StatefulWidget {
  const PlaylistImportScreen({super.key});

  @override
  State<PlaylistImportScreen> createState() => _PlaylistImportScreenState();
}

class _PlaylistImportScreenState extends State<PlaylistImportScreen> {
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
         decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
              ? [const Color(0xFF121212), const Color(0xFF1E1E1E), const Color(0xFF000000)]
              : [const Color(0xFFF7F7F7), const Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                surfaceTintColor: Colors.transparent,
                backgroundColor: Colors.transparent,
                floating: true,
                pinned: true,
                elevation: 0,
                expandedHeight: 100,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  color: isDark ? Colors.white : Colors.black,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                flexibleSpace: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      child: FlexibleSpaceBar(
                        titlePadding: const EdgeInsets.only(left: 50, bottom: 16),
                        title: Text(
                          'Import Playlists',
                          style: GoogleFonts.splineSans(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 20,
                          ),
                        ),
                        background: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGlassContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Import from URL',
                              style: GoogleFonts.splineSans(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 20),
                            
                            // Service Dropdown
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  dropdownColor: const Color(0xFF2C2C2C),
                                  value: _selectedService,
                                  isExpanded: true,
                                  style: GoogleFonts.splineSans(color: Colors.white),
                                  icon: const Icon(Icons.expand_more_rounded, color: Colors.white70),
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
                            
                            // URL Field
                            TextField(
                              controller: _playlistUrlController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.08),
                                hintText: 'Paste playlist URL here',
                                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Colors.white24),
                                ),
                                prefixIcon: const Icon(Icons.link_rounded, color: Colors.white54),
                              ),
                            ),
                            
                            const SizedBox(height: 24),
                            
                            // Action Button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).primaryColor,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                onPressed: _isLoading ? null : _importPlaylistFromUrl,
                                child: _isLoading 
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text('Import Playlist', style: GoogleFonts.splineSans(fontWeight: FontWeight.bold, color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      Text(
                        'Quick Connect',
                        style: GoogleFonts.splineSans(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildServiceButton('Spotify', Icons.music_note_rounded, const Color(0xFF1DB954)),
                          _buildServiceButton('YouTube', Icons.play_arrow_rounded, const Color(0xFFFF0000)),
                          _buildServiceButton('Amazon', Icons.shopping_cart_rounded, const Color(0xFF232F3E)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassContainer({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildServiceButton(String service, IconData icon, Color color) {
    return InkWell(
      onTap: () => _connectToService(service),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              service,
              style: GoogleFonts.splineSans(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12, 
                fontWeight: FontWeight.w600
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importPlaylistFromUrl() async {
    final url = _playlistUrlController.text.trim();
    if (url.isEmpty) {
      showLiquidSnackBar(context, 'Please enter a URL', isError: true);
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

      if (playlistId == null) throw Exception('Could not extract playlist ID from URL');

      // Efficiently fetch ONLY the target playlist metadata
      final playlistInfo = await _spotifyService.getPlaylistMetadata(playlistId);

      final imageUrl = (playlistInfo['images'] as List).isNotEmpty 
          ? playlistInfo['images'][0]['url'] 
          : '';
          
      final playlist = await _spotifyService.getPlaylistWithTracks(playlistId, playlistInfo['name'], imageUrl);
      
      if(mounted) {
         await Provider.of<MusicProvider>(context, listen: false).importPlaylist(playlist);
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Playlist imported successfully!')));
         _playlistUrlController.clear();
      }

    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _connectToService(String service) async {
    if (service != 'Spotify') {
      showLiquidSnackBar(context, '$service coming soon', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      // 1. Fetch User Playlists
      final playlists = await _spotifyService.getUserPlaylists();
      
      if (!mounted) return;
      setState(() => _isLoading = false); // Stop loading before nav
      
      // 2. Navigate to Selection Screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SpotifyPlaylistSelectionScreen(
            playlists: playlists,
            onPlaylistSelected: (playlistMap) {
               Navigator.pop(context); // Close selection screen
               _importSpotifyPlaylist(playlistMap); // Start import
            },
          ),
        ),
      );

    } catch (e) {
      if(mounted) {
         setState(() => _isLoading = false);
         showLiquidSnackBar(context, 'Error connecting: $e', isError: true);
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
       
       showLiquidSnackBar(context, 'Importing playlist...');
       
       final playlist = await _spotifyService.getPlaylistWithTracks(playlistId, name, imageUrl);
       
       if(mounted) {
          await Provider.of<MusicProvider>(context, listen: false).importPlaylist(playlist);
          showLiquidSnackBar(context, 'Imported "${playlist.name}"');
       }
     } catch (e) {
       if(mounted) showLiquidSnackBar(context, 'Import Error: $e', isError: true);
     } finally {
       if(mounted) setState(() => _isLoading = false);
     }
  }
}
