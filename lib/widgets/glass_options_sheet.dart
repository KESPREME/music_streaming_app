import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../screens/artist_screen.dart';
import '../screens/album_screen.dart';
import 'playlist_selection_dialog.dart';

class GlassOptionsSheet extends StatelessWidget {
  final Track track;
  final String? playlistId;
  final bool isInQueueContext;

  const GlassOptionsSheet({
    super.key,
    required this.track,
    this.playlistId,
    this.isInQueueContext = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final isDark = theme.brightness == Brightness.dark;
    
    // Check if liked (requires listening to provider or passing in state, 
    // but Consumer is safer for up-to-date state in a sheet)
    
    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        final isLiked = provider.isSongLiked(track.id);
        
        return Container(
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1E1E1E) : Colors.white).withOpacity(0.8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle Bar
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    
                    // Header (Track Info)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              track.albumArtUrl,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_,__,___) => Container(
                                width: 56, 
                                height: 56, 
                                color: Colors.grey[900],
                                child: const Icon(Icons.music_note, color: Colors.white24),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.trackName,
                                  style: GoogleFonts.splineSans(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  track.artistName,
                                  style: GoogleFonts.splineSans(
                                    fontSize: 14,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => provider.toggleLike(track),
                            icon: Icon(
                              isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              color: isLiked ? const Color(0xFFFF1744) : (isDark ? Colors.white : Colors.black),
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const Divider(height: 1, thickness: 0.5),
                    
                    // Options List
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildOption(
                              context, 
                              icon: Icons.queue_music_rounded, 
                              label: 'Add to Queue',
                              onTap: () {
                                provider.addToQueue(track);
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to Queue')));
                              },
                              isDark: isDark,
                            ),
                            _buildOption(
                              context,
                              icon: Icons.playlist_play_rounded,
                              label: 'Play Next',
                              onTap: () {
                                provider.playNext(track);
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playing Next')));
                              },
                              isDark: isDark,
                            ),
                            _buildOption(
                              context,
                              icon: Icons.playlist_add_rounded,
                              label: 'Add to Playlist',
                              onTap: () async {
                                Navigator.pop(context);
                                await showPlaylistSelectionDialog(context, track);
                              },
                              isDark: isDark,
                            ),
                            
                            if (track.artistName.isNotEmpty && track.artistName != 'Unknown Artist')
                              _buildOption(
                                context,
                                icon: Icons.person_outline_rounded,
                                label: 'Go to Artist',
                                onTap: () async {
                                  Navigator.pop(context);
                                  await _navigateToArtist(context, provider, track.artistName);
                                },
                                isDark: isDark,
                              ),
                              
                            if (track.albumName.isNotEmpty && track.albumName != 'Unknown Album')
                              _buildOption(
                                context,
                                icon: Icons.album_outlined,
                                label: 'Go to Album',
                                onTap: () async {
                                  Navigator.pop(context);
                                  await _navigateToAlbum(context, provider, track.albumName, track.artistName);
                                },
                                isDark: isDark,
                              ),
                              
                            _buildOption(
                              context,
                              icon: Icons.share_rounded,
                              label: 'Share',
                              onTap: () {
                                Navigator.pop(context);
                                Share.share('Check out this track: ${track.trackName} by ${track.artistName}\n${track.previewUrl}');
                              },
                              isDark: isDark,
                            ),
                            
                             if (playlistId != null)
                              _buildOption(
                                context,
                                icon: Icons.remove_circle_outline_rounded,
                                label: 'Remove from Playlist',
                                color: Colors.redAccent,
                                onTap: () {
                                  provider.removeTrackFromPlaylist(playlistId!, track.id);
                                  Navigator.pop(context);
                                },
                                isDark: isDark,
                              ),
                              
                            if (isInQueueContext)
                              _buildOption(
                                context,
                                icon: Icons.delete_sweep_rounded,
                                label: 'Remove from Queue',
                                color: Colors.redAccent,
                                onTap: () {
                                  provider.removeFromQueue(track);
                                  Navigator.pop(context);
                                },
                                isDark: isDark,
                              ),
                              
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildOption(BuildContext context, {
    required IconData icon, 
    required String label, 
    required VoidCallback onTap,
    Color? color,
    required bool isDark,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? (isDark ? Colors.white : Colors.black)),
      title: Text(
        label,
        style: GoogleFonts.splineSans(
          color: color ?? (isDark ? Colors.white : Colors.black),
          fontWeight: FontWeight.w500,
          fontSize: 16
        ),
      ),
      onTap: onTap,
    );
  }

  Future<void> _navigateToArtist(BuildContext context, MusicProvider provider, String artistName) async {
    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loading artist...'), duration: Duration(milliseconds: 500)));
    await provider.navigateToArtist(artistName);
     if (context.mounted && provider.currentArtistDetails != null) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(artistName: artistName)));
     }
  }

  Future<void> _navigateToAlbum(BuildContext context, MusicProvider provider, String albumName, String artistName) async {
     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loading album...'), duration: Duration(milliseconds: 500)));
    await provider.navigateToAlbum(albumName, artistName);
    if (context.mounted && provider.currentAlbumDetails != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(albumName: albumName, artistName: artistName)));
    }
  }
}
