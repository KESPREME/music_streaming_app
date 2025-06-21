import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Added for potential future use (e.g. playlist counts)

import '../providers/music_provider.dart'; // Added for potential future use
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
  late TabController _tabController;

  // Define categories for filtering, could be dynamic in the future
  final List<String> _filterChips = ["Playlists", "Artists", "Albums", "Songs", "Downloaded"];
  String? _selectedFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); // e.g., "My Music" and "Podcasts" (future)
                                                          // For now, only one main view, so TabController might be overkill
                                                          // but kept for potential future expansion.
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // final musicProvider = Provider.of<MusicProvider>(context); // Uncomment if needed for counts etc.

    // Define library items with new styling in mind
    final List<Map<String, dynamic>> libraryItems = [
      {
        'title': 'Liked Songs',
        'icon': Icons.favorite_border_outlined,
        'activeIcon': Icons.favorite,
        'color': theme.colorScheme.primary, // Use theme colors
        'screen': const LikedSongsScreen(),
        // 'subtitle': '${musicProvider.likedSongs.length} songs', // Example dynamic subtitle
      },
      {
        'title': 'Your Playlists',
        'icon': Icons.playlist_play_outlined,
        'activeIcon': Icons.playlist_play,
        'color': theme.colorScheme.secondary,
        'screen': const UserPlaylistScreen(),
        // 'subtitle': '${musicProvider.userPlaylists.length} playlists',
      },
      {
        'title': 'Recently Played',
        'icon': Icons.history_outlined,
        'activeIcon': Icons.history,
        'color': Colors.orangeAccent,
        'screen': const RecentlyPlayedScreen(),
      },
      {
        'title': 'Downloaded',
        'icon': Icons.download_outlined,
        'activeIcon': Icons.download_done,
        'color': theme.colorScheme.tertiary, // Using tertiary for variety
        'screen': const DownloadedSongsScreen(),
      },
      {
        'title': 'Local Files',
        'icon': Icons.folder_outlined,
        'activeIcon': Icons.folder,
        'color': Colors.blueGrey,
        'screen': const LocalMusicScreen(),
      },
      {
        'title': 'Import Playlists',
        'icon': Icons.playlist_add_outlined,
        'activeIcon': Icons.playlist_add_check,
        'color': Colors.teal,
        'screen': const PlaylistImportScreen(),
      },
    ];


    return Scaffold(
      appBar: AppBar(
        title: Text('Your Library', style: theme.textTheme.headlineSmall),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: "Create new playlist",
            onPressed: () {
              // TODO: Implement create playlist dialog/screen
               ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Create playlist (not implemented)")),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search_outlined),
            tooltip: "Search in library",
            onPressed: () {
              // TODO: Implement library-specific search
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Search library (not implemented)")),
              );
            },
          ),
        ],
        // Potentially add TabBar here if using multiple top-level library sections
        // bottom: TabBar(
        //   controller: _tabController,
        //   tabs: [
        //     Tab(text: "Music"),
        //     Tab(text: "Podcasts"), // Example
        //   ],
        // ),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _filterChips.length,
                    itemBuilder: (context, index) {
                      final chipLabel = _filterChips[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(chipLabel),
                          selected: _selectedFilter == chipLabel,
                          onSelected: (bool selected) {
                            setState(() {
                              _selectedFilter = selected ? chipLabel : null;
                            });
                            // TODO: Implement filtering logic based on _selectedFilter
                          },
                          backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                          selectedColor: theme.colorScheme.primary.withOpacity(0.3),
                          labelStyle: theme.textTheme.labelMedium?.copyWith(
                            color: _selectedFilter == chipLabel ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                          ),
                          checkmarkColor: theme.colorScheme.primary,
                          shape: StadiumBorder(side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3))),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ];
        },
        body: ListView.separated(
          padding: const EdgeInsets.all(16.0),
          itemCount: libraryItems.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = libraryItems[index];
            return _buildModernLibraryCard(
              context,
              theme: theme,
              title: item['title'],
              icon: item['icon'],
              activeIcon: item['activeIcon'],
              color: item['color'],
              subtitle: item['subtitle'], // Optional subtitle
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => item['screen']),
                );
              },
            );
          },
        ),
      )
    );
  }

  Widget _buildModernLibraryCard(
    BuildContext context, {
    required ThemeData theme,
    required String title,
    required IconData icon,
    IconData? activeIcon, // Optional active icon
    required Color color,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    // Determine if the item is "active" - placeholder logic
    bool isActive = title == "Liked Songs"; // Example: Liked Songs is always "active" looking

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
          // border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2))
        ),
        child: Row(
          children: [
            Icon(
              isActive && activeIcon != null ? activeIcon : icon,
              color: isActive ? color : theme.iconTheme.color,
              size: 28,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isActive ? color : theme.colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ]
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
