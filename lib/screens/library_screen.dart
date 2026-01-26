import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';

import 'liked_songs_screen.dart';
import 'recently_played_screen.dart';
import 'user_playlist_screen.dart';
import 'downloaded_songs_screen.dart';
import 'playlist_import_screen.dart';
import 'local_music_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  final List<String> _filterChips = ["Playlists", "Artists", "Albums", "Songs", "Downloaded"];
  String? _selectedFilter;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget _buildLiquidLibraryCard(BuildContext context, Map<String, dynamic> item) {
    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => item['screen']));
      },
      borderRadius: BorderRadius.circular(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03), // Ultra subtle glass
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                   color: Colors.black.withOpacity(0.1),
                   blurRadius: 10,
                   offset: const Offset(0, 4),
                )
              ]
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (item['color'] as Color).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: (item['color'] as Color).withOpacity(0.3)),
                  ),
                  child: Icon(item['icon'] as IconData, color: item['color'], size: 26),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['title'],
                        style: GoogleFonts.splineSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: Colors.white,
                        ),
                      ),
                      if (item['subtitle'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          item['subtitle'],
                          style: GoogleFonts.splineSans(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 13,
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                   decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                  ),
                  child: Icon(Icons.arrow_forward_rounded, color: Colors.white.withOpacity(0.5), size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final List<Map<String, dynamic>> libraryItems = [
      {
        'title': 'Liked Songs',
        'icon': Icons.favorite_rounded,
        'color': const Color(0xFFFF1744),
        'screen': const LikedSongsScreen(),
        'subtitle': 'Your heavy rotation',
      },
      {
        'title': 'Your Playlists',
        'icon': Icons.queue_music_rounded,
        'color': const Color(0xFF00E5FF),
        'screen': const UserPlaylistScreen(),
        'subtitle': 'Custom collections',
      },
      {
        'title': 'Recently Played',
        'icon': Icons.history_rounded,
        'color': const Color(0xFFFF9100),
        'screen': const RecentlyPlayedScreen(),
        'subtitle': 'Jump back in',
      },
      {
        'title': 'Downloaded',
        'icon': Icons.download_done_rounded,
        'color': const Color(0xFF00E676),
        'screen': const DownloadedSongsScreen(),
        'subtitle': 'Offline music',
      },
      {
        'title': 'Local Files',
        'icon': Icons.folder_open_rounded,
        'color': const Color(0xFFEA80FC),
        'screen': const LocalMusicScreen(),
        'subtitle': 'Device storage',
      },
      {
        'title': 'Import Playlists',
        'icon': Icons.playlist_add_check_rounded,
        'color': Colors.grey,
        'screen': const PlaylistImportScreen(),
        'subtitle': 'Sync from Spotify/YT',
      },
    ];

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
                pinned: true,
                elevation: 0,
                expandedHeight: 120, // Compact header for library
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    final double percentage = ((constraints.maxHeight - kToolbarHeight) / (120 - kToolbarHeight)).clamp(0.0, 1.0);
                    final double blur = (1 - percentage) * 15; // Blur up to 15px when collapsed
                    final double overlayOpacity = (1 - percentage) * 0.5;

                    return ClipRRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                        child: FlexibleSpaceBar(
                          titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                          title: Text(
                            'Your Library', 
                            style: GoogleFonts.splineSans(
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 20 + (8 * percentage), // 20 -> 28
                            ),
                          ),
                          background: Stack(
                            fit: StackFit.expand,
                            children: [
                               // Transparent bg to show gradient
                               Container(color: Colors.transparent),
                               
                               // Liquid Overlay (Darkens/Glassifies on collapse)
                               Container(
                                 color: Colors.black.withOpacity(overlayOpacity), // Only darken, no image
                               ),
                               
                               if (percentage < 0.05)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(height: 1, color: Colors.white.withOpacity(0.1)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                ),
                actions: [
                  IconButton(
                     icon: const Icon(Icons.add_circle_outline_rounded),
                     color: isDark ? Colors.white : Colors.black,
                     onPressed: () => _showCreatePlaylistDialog(context),
                  ),
                  IconButton(
                     icon: const Icon(Icons.search_rounded),
                     color: isDark ? Colors.white : Colors.black,
                     onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Search local library")));
                     },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              
              // 2. Filter Chips
              SliverToBoxAdapter(
                child: Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: _filterChips.length,
                    separatorBuilder: (_,__) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final label = _filterChips[index];
                      final isSelected = _selectedFilter == label;
                      return GestureDetector(
                        onTap: () {
                           setState(() => _selectedFilter = isSelected ? null : label);
                        },
                        child:  AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFFF1744) : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? const Color(0xFFFF1744) : Colors.white.withOpacity(0.1)
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            label,
                            style: GoogleFonts.splineSans(
                              color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              
              // 3. Grid/List of items
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 160),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = libraryItems[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildLiquidLibraryCard(context, item),
                      );
                    },
                    childCount: libraryItems.length,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    // Keep existing logic but style the dialog if possible later
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Create Playlist', style: GoogleFonts.splineSans(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Playlist Name',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
            hintText: 'My Awesome Mix',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: const Color(0xFFFF1744).withOpacity(0.5))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF1744))),
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(dialogContext);
              _createPlaylist(context, musicProvider, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF1744)),
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(dialogContext);
                _createPlaylist(context, musicProvider, name);
              }
            },
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _createPlaylist(BuildContext context, MusicProvider musicProvider, String name) {
    musicProvider.createPlaylist(name);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playlist "$name" created'),
        backgroundColor: const Color(0xFFFF1744),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const UserPlaylistScreen(),
              ),
            );
          },
        ),
      ),
    );
  }
}
