import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/playlist.dart';
import 'playlist_detail_screen.dart';

class UserPlaylistScreen extends StatefulWidget {
  const UserPlaylistScreen({super.key});

  @override
  State<UserPlaylistScreen> createState() => _UserPlaylistScreenState();
}

class _UserPlaylistScreenState extends State<UserPlaylistScreen> {
  late ScrollController _scrollController;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final isScrolled = _scrollController.hasClients && _scrollController.offset > 10;
    if (isScrolled != _isScrolled) {
      setState(() {
        _isScrolled = isScrolled;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
          child: Consumer<MusicProvider>(
            builder: (context, musicProvider, child) {
              final playlists = musicProvider.userPlaylists;
              // Add dummy 'create new' item at the start or just use FAB actions
              
              return CustomScrollView(
                controller: _scrollController,
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
                        filter: ImageFilter.blur(
                          sigmaX: _isScrolled ? 10 : 0,
                          sigmaY: _isScrolled ? 10 : 0,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          color: _isScrolled ? Colors.black.withOpacity(0.5) : Colors.transparent,
                          child: FlexibleSpaceBar(
                            titlePadding: const EdgeInsets.only(left: 50, bottom: 16),
                            title: Text(
                              'Your Playlists',
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
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.add_rounded, size: 28),
                        color: const Color(0xFF00E5FF), // Cyan Accent
                        onPressed: () => _showCreatePlaylistDialog(context),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),

                  if (playlists.isEmpty)
                     SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.queue_music_rounded, size: 80, color: Colors.white.withOpacity(0.1)),
                             const SizedBox(height: 16),
                            Text(
                              'No playlists yet',
                              style: GoogleFonts.splineSans(
                                color: Colors.white.withOpacity(0.6), 
                                fontSize: 18,
                                fontWeight: FontWeight.w500
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create or import playlists to get started',
                              style: GoogleFonts.splineSans(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 14
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E5FF), // Cyan
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              ),
                              onPressed: () => _showCreatePlaylistDialog(context),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Create Playlist', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, // Grid layout for playlists
                          childAspectRatio: 0.8,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final playlist = playlists[index];
                            return _buildLiquidPlaylistCard(context, playlist);
                          },
                          childCount: playlists.length,
                        ),
                      ),
                    ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
                ],
              );
            },
          ),
        ),
       ),
    );
  }

  Widget _buildLiquidPlaylistCard(BuildContext context, Playlist playlist) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlaylistDetailScreen(
              playlistId: playlist.id,
              playlistName: playlist.name,
              playlistImage: playlist.imageUrl,
              cachedTracks: playlist.tracks, // Pass cached tracks
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: playlist.imageUrl.isNotEmpty
                    ? Image.network(
                        playlist.imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_,__,___) => Container(
                          color: Colors.grey[900],
                          child: const Center(child: Icon(Icons.music_note, color: Colors.white24, size: 40)),
                        ),
                      )
                    : Container(
                        color: Colors.grey[900],
                        child: const Center(child: Icon(Icons.music_note, color: Colors.white24, size: 40)),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: GoogleFonts.splineSans(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${playlist.tracks.length} tracks',
                    style: GoogleFonts.splineSans(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
             Align(
              alignment: Alignment.centerRight,
               child: IconButton(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
                onPressed: () => _showPlaylistOptions(context, playlist),
                           ),
             ),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Create Playlist', style: GoogleFonts.splineSans(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
           autofocus: true,
          decoration: InputDecoration(
            hintText: 'Playlist Name',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
             enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.5))),
             focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
          ),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6))),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)), // Cyan
            child: const Text('Create', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                final musicProvider = Provider.of<MusicProvider>(context, listen: false);
                musicProvider.createPlaylist(nameController.text.trim(), initialTracks: []);
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showPlaylistOptions(BuildContext context, Playlist playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Colors.white),
              title: Text('Rename', style: GoogleFonts.splineSans(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showRenamePlaylistDialog(context, playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: Text('Delete', style: GoogleFonts.splineSans(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(context, playlist);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenamePlaylistDialog(BuildContext context, Playlist playlist) {
    final nameController = TextEditingController(text: playlist.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Rename Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Colors.grey[400]),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey[700]!),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Save', style: TextStyle(color: Color(0xFF00E5FF))),
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                // Implement rename functionality (Needs support in Provider/Model ideally)
                // For now just close
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Playlist', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${playlist.name}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            onPressed: () {
              final musicProvider = Provider.of<MusicProvider>(context, listen: false);
              musicProvider.deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
