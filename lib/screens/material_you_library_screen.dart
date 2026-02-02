import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../theme/material_you_typography.dart';
import '../theme/material_you_tokens.dart';
import '../widgets/material_you_fab.dart';
import '../widgets/material_you_elevated_card.dart';
import '../widgets/global_music_overlay.dart';

import '../widgets/themed_liked_songs_screen.dart';
import '../widgets/themed_recently_played_screen.dart';
import '../widgets/themed_user_playlist_screen.dart';
import '../widgets/themed_downloaded_songs_screen.dart';
import '../widgets/themed_playlist_import_screen.dart';
import '../widgets/themed_local_music_screen.dart';
import '../widgets/themed_playlist_detail_screen.dart';
import '../widgets/themed_artist_detail_screen.dart';
import 'material_you_local_search_screen.dart';

/// Material You Library Screen - Completely different from glassmorphism
/// Features:
/// - Material 3 tabs (not custom glass tabs)
/// - 2-column grid layout (not list)
/// - Elevated cards with shadows
/// - "Create Playlist" FAB (bottom right)
/// - Bold typography (24sp headers)
/// - Vibrant colors
class MaterialYouLibraryScreen extends StatefulWidget {
  const MaterialYouLibraryScreen({super.key});

  @override
  State<MaterialYouLibraryScreen> createState() => _MaterialYouLibraryScreenState();
}

class _MaterialYouLibraryScreenState extends State<MaterialYouLibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTab = 0;
  Future<List<dynamic>>? _artistsFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Cache the future to prevent constant refreshing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _artistsFuture = Provider.of<MusicProvider>(context, listen: false).getSmartLibraryArtists();
        });
      }
    });

    _tabController.addListener(() {
      setState(() {
        _currentTab = _tabController.index;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return PlayerAwarePopScope(
      child: Scaffold(
        backgroundColor: MaterialYouTokens.surfaceDark,
        body: SafeArea(
          child: Column(
            children: [
              // Header with large title
              _buildHeader(context, colorScheme),
              
              // Material 3 Tabs
              _buildMaterial3Tabs(context, colorScheme),
              
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLibraryGrid(context, colorScheme),
                    _buildPlaylistsGrid(context, colorScheme),
                    _buildArtistsGrid(context, colorScheme),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Create Playlist FAB (bottom right)
        floatingActionButton: _currentTab == 1
            ? MaterialYouFAB(
                icon: Icons.add_rounded,
                onPressed: () => _showCreatePlaylistDialog(context),
                isLarge: false, // 56dp for secondary action
              )
            : null,
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          // Large "Your Library" title
          Expanded(
            child: Text(
              'Your Library',
              style: MaterialYouTypography.displayLarge(colorScheme.onSurface),
            ),
          ),
          
          // Search icon button
          IconButton(
            icon: const Icon(Icons.search_rounded),
            iconSize: 28,
            color: colorScheme.onSurface,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MaterialYouLocalSearchScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMaterial3Tabs(BuildContext context, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: MaterialYouTokens.surfaceVariantDark,
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeExtraLarge),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(MaterialYouTokens.shapeExtraLarge),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: GoogleFonts.splineSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.splineSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        tabs: const [
          Tab(text: 'All'),
          Tab(text: 'Playlists'),
          Tab(text: 'Artists'),
        ],
      ),
    );
  }

  Widget _buildLibraryGrid(BuildContext context, ColorScheme colorScheme) {
    final List<Map<String, dynamic>> libraryItems = [
      {
        'title': 'Liked Songs',
        'icon': Icons.favorite_rounded,
        'color': MaterialYouTokens.primaryVibrant,
        'screen': const ThemedLikedSongsScreen(),
        'subtitle': 'Your heavy rotation',
      },
      {
        'title': 'Your Playlists',
        'icon': Icons.queue_music_rounded,
        'color': MaterialYouTokens.tertiaryVibrant,
        'screen': const ThemedUserPlaylistScreen(),
        'subtitle': 'Custom collections',
      },
      {
        'title': 'Recently Played',
        'icon': Icons.history_rounded,
        'color': const Color(0xFFFF9100),
        'screen': const ThemedRecentlyPlayedScreen(),
        'subtitle': 'Jump back in',
      },
      {
        'title': 'Downloaded',
        'icon': Icons.download_done_rounded,
        'color': const Color(0xFF00E676),
        'screen': const ThemedDownloadedSongsScreen(),
        'subtitle': 'Offline music',
      },
      {
        'title': 'Local Files',
        'icon': Icons.folder_open_rounded,
        'color': MaterialYouTokens.secondaryVibrant,
        'screen': const ThemedLocalMusicScreen(),
        'subtitle': 'Device storage',
      },
      {
        'title': 'Import Playlists',
        'icon': Icons.playlist_add_check_rounded,
        'color': Colors.grey,
        'screen': const ThemedPlaylistImportScreen(),
        'subtitle': 'Sync from Spotify/YT',
      },
    ];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 160), // Adjusted top padding
      itemCount: libraryItems.length,
      itemBuilder: (context, index) {
        final item = libraryItems[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildLibraryListItem(context, colorScheme, item),
        );
      },
    );
  }

  Widget _buildLibraryListItem(
    BuildContext context,
    ColorScheme colorScheme,
    Map<String, dynamic> item,
  ) {
    return MaterialYouElevatedCard(
      elevation: 0, // Flat for list style
      backgroundColor: Colors.transparent, // Transparent to blend
      borderRadius: MaterialYouTokens.shapeLarge,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => item['screen']),
        );
      },
      child: Container(
        decoration: BoxDecoration(
           color: MaterialYouTokens.surfaceContainerDark, // distinct background
           borderRadius: BorderRadius.circular(MaterialYouTokens.shapeLarge),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: (item['color'] as Color).withOpacity(0.15),
                borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
              ),
              child: Icon(
                item['icon'] as IconData,
                color: item['color'],
                size: 28,
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Text Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'],
                    style: MaterialYouTypography.headlineMedium(colorScheme.onSurface).copyWith(
                      fontSize: 18,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item['subtitle'] != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item['subtitle'],
                      style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Chevron
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistsGrid(BuildContext context, ColorScheme colorScheme) {
    // TODO: Get actual playlists from MusicProvider
    final musicProvider = Provider.of<MusicProvider>(context);
    final playlists = musicProvider.userPlaylists;

    if (playlists.isEmpty) {
      return _buildEmptyState(
        context,
        colorScheme,
        icon: Icons.queue_music_rounded,
        title: 'No playlists yet',
        subtitle: 'Create your first playlist',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 160),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildPlaylistListItem(context, colorScheme, playlist),
        );
      },
    );
  }

  Widget _buildPlaylistListItem(
    BuildContext context,
    ColorScheme colorScheme,
    dynamic playlist,
  ) {
    return MaterialYouElevatedCard(
      elevation: 0,
      backgroundColor: Colors.transparent,
      borderRadius: MaterialYouTokens.shapeLarge,
      onTap: () {
        // Navigate to playlist detail
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ThemedPlaylistDetailScreen(
              playlistId: playlist.id,
              playlistName: playlist.name,
              playlistImage: playlist.imageUrl,
              cachedTracks: playlist.tracks, // Pass cached tracks!
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
           color: MaterialYouTokens.surfaceContainerDark, 
           borderRadius: BorderRadius.circular(MaterialYouTokens.shapeLarge),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Album art 
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: MaterialYouTokens.primaryVibrant.withOpacity(0.2),
                borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
                image: playlist.imageUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(playlist.imageUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: playlist.imageUrl.isEmpty 
                  ? Icon(
                      Icons.music_note_rounded,
                      size: 28, // Smaller icon
                      color: colorScheme.primary,
                    )
                  : null,
            ),
            
            const SizedBox(width: 16),
            
            // Playlist info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: MaterialYouTypography.headlineMedium(colorScheme.onSurface).copyWith(
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${playlist.tracks.length} songs',
                    style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 8),
            
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistsGrid(BuildContext context, ColorScheme colorScheme) {
    // Use cached future to prevent rebuilds
    return FutureBuilder<List<dynamic>>(
      future: _artistsFuture, // Use cached future
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _artistsFuture != null) {
          return Center(child: CircularProgressIndicator(color: colorScheme.primary));
        }
        
        final artists = snapshot.data ?? [];
        
        if (artists.isEmpty) {
          return _buildEmptyState(
            context,
            colorScheme,
            icon: Icons.person_rounded,
            title: 'No artists yet',
            subtitle: 'Play some music to see your favorite artists',
          );
        }
        
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 160),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            // artist is a Track object acting as Artist metadata
            return MaterialYouElevatedCard(
              elevation: 0,
              backgroundColor: Colors.transparent,
              borderRadius: MaterialYouTokens.shapeLarge,
              onTap: () {
                // Use track ID as artist ID, but force search by name since
                // track IDs are not artist browse IDs
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ThemedArtistDetailScreen(
                      artistId: "", // Don't pass track ID as artist ID
                      artistName: artist.artistName,
                      artistImage: artist.albumArtUrl,
                      searchByName: true, // Always search by name from library
                    ),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: MaterialYouTokens.surfaceContainerDark,
                  borderRadius: BorderRadius.circular(MaterialYouTokens.shapeLarge),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.surfaceVariant,
                        image: (artist.albumArtUrl != null && artist.albumArtUrl.isNotEmpty) 
                            ? DecorationImage(
                                image: NetworkImage(artist.albumArtUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: (artist.albumArtUrl == null || artist.albumArtUrl.isEmpty) 
                          ? Icon(Icons.person, size: 40, color: colorScheme.onSurfaceVariant)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        artist.artistName,
                        style: MaterialYouTypography.labelLarge(colorScheme.onSurface).copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Artist',
                      style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme colorScheme, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 56,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: MaterialYouTypography.headlineLarge(colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final TextEditingController nameController = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: MaterialYouTokens.surfaceVariantDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MaterialYouTokens.shapeExtraLarge),
        ),
        title: Text(
          'Create Playlist',
          style: MaterialYouTypography.headlineMedium(colorScheme.onSurface),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: GoogleFonts.splineSans(
            color: colorScheme.onSurface,
            fontSize: 16,
          ),
          decoration: InputDecoration(
            labelText: 'Playlist Name',
            labelStyle: GoogleFonts.splineSans(
              color: colorScheme.onSurfaceVariant,
            ),
            hintText: 'My Awesome Mix',
            hintStyle: GoogleFonts.splineSans(
              color: colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: colorScheme.primary.withOpacity(0.5),
              ),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colorScheme.primary),
            ),
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
            child: Text(
              'Cancel',
              style: GoogleFonts.splineSans(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(dialogContext);
                _createPlaylist(context, musicProvider, name);
              }
            },
            child: Text(
              'Create',
              style: GoogleFonts.splineSans(fontWeight: FontWeight.w600),
            ),
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
        backgroundColor: MaterialYouTokens.primaryVibrant,
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ThemedUserPlaylistScreen(),
              ),
            );
          },
        ),
      ),
    );
  }
}
