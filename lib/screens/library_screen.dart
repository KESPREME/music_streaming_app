import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/music_provider.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/track_tile.dart';
import '../widgets/glass_surface.dart';
import '../widgets/glass_circle_button.dart';
import '../widgets/stagger_in.dart';
import '../widgets/themed_liked_songs_screen.dart';
import '../widgets/themed_recently_played_screen.dart';
import '../widgets/themed_user_playlist_screen.dart';
import '../widgets/themed_downloaded_songs_screen.dart';
import '../widgets/themed_playlist_import_screen.dart';
import '../widgets/themed_local_music_screen.dart';
import '../widgets/themed_playlist_detail_screen.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/themed_album_detail_screen.dart';
import 'glass_library_search_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final List<String> _filterChips = const [
    "All",
    "Playlists",
    "Artists",
    "Albums",
    "Songs",
    "Downloaded",
  ];
  String _selectedFilter = "All";

  Future<List<dynamic>>? _smartArtistsFuture;
  Future<List<Track>>? _smartAlbumsFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final p = Provider.of<MusicProvider>(context, listen: false);
        setState(() {
          _smartArtistsFuture = p.getSmartLibraryArtists();
          _smartAlbumsFuture = p.getSmartLibraryAlbums();
        });
      }
    });
  }

  Widget _buildLiquidLibraryCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget screen,
  }) {
    return SquishOnPress(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.14),
              Colors.white.withValues(alpha: 0.05),
              Colors.white.withValues(alpha: 0.02),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
          border: Border.all(
            color: color.withValues(alpha: 0.22),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.12),
              blurRadius: 18,
              spreadRadius: -4,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Glass pod with icon
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.32), width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.20),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: -0.2,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context);
    final accent = theme.colorScheme.primary;

    return PlayerAwarePopScope(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Liquid Glass App Bar
              SliverAppBar(
                surfaceTintColor: Colors.transparent,
                backgroundColor: Colors.transparent,
                pinned: true,
                elevation: 0,
                expandedHeight: 110,
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    final double percentage = ((constraints.maxHeight - kToolbarHeight) / (110 - kToolbarHeight)).clamp(0.0, 1.0);
                    final double blur = (1 - percentage) * 16;
                    final double overlayOpacity = (1 - percentage) * 0.50;

                    return ClipRRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                        child: FlexibleSpaceBar(
                          titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                          title: Text(
                            'Your Library',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontSize: 20 + (10 * percentage),
                              letterSpacing: -0.6,
                            ),
                          ),
                          background: Container(color: Colors.black.withValues(alpha: overlayOpacity)),
                        ),
                      ),
                    );
                  },
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GlassCircleButton(
                      icon: Icons.add_rounded,
                      size: 42,
                      iconSize: 22,
                      onTap: () => _showCreatePlaylistDialog(context),
                      semanticLabel: 'Create playlist',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GlassCircleButton(
                      icon: Icons.search_rounded,
                      size: 42,
                      iconSize: 20,
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const GlassLibrarySearchScreen()));
                      },
                      semanticLabel: 'Search library',
                    ),
                  ),
                ],
              ),

              // Fluid animated sliding filter pill switcher
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 56,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _filterChips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final label = _filterChips[index];
                      final isSelected = _selectedFilter == label;

                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedFilter = label);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: isSelected
                                ? RadialGradient(
                                    center: Alignment.center,
                                    radius: 2.2,
                                    colors: [
                                      accent.withValues(alpha: 0.32),
                                      accent.withValues(alpha: 0.14),
                                      Colors.white.withValues(alpha: 0.08),
                                    ],
                                  )
                                : null,
                            color: isSelected ? null : Colors.white.withValues(alpha: 0.06),
                            border: Border.all(
                              color: isSelected ? accent.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.10),
                              width: isSelected ? 1.0 : 0.75,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.25),
                                      blurRadius: 12,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Text(
                            label,
                            style: GoogleFonts.plusJakartaSans(
                              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.70),
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Filtered Content
              if (_selectedFilter == "All")
                _buildMainLibraryList(context, musicProvider)
              else if (_selectedFilter == "Playlists")
                _buildPlaylistsContent(context, musicProvider)
              else if (_selectedFilter == "Artists")
                _buildArtistsContent(context)
              else if (_selectedFilter == "Albums")
                _buildAlbumsContent(context)
              else if (_selectedFilter == "Songs")
                _buildSongsContent(context, musicProvider)
              else if (_selectedFilter == "Downloaded")
                _buildDownloadedContent(context, musicProvider),

              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainLibraryList(BuildContext context, MusicProvider musicProvider) {
    final likedCount = musicProvider.likedSongs.length;
    final playlistCount = musicProvider.userPlaylists.length;
    final recentsCount = musicProvider.recentlyPlayed.length;
    final localCount = musicProvider.localTracks.length;

    final List<Map<String, dynamic>> libraryItems = [
      {
        'title': 'Liked Songs',
        'icon': Icons.favorite_rounded,
        'color': const Color(0xFFFF4D6A),
        'screen': const ThemedLikedSongsScreen(),
        'subtitle': likedCount == 1 ? '1 song' : '$likedCount songs',
      },
      {
        'title': 'Your Playlists',
        'icon': Icons.queue_music_rounded,
        'color': const Color(0xFF2EC4FF),
        'screen': const ThemedUserPlaylistScreen(),
        'subtitle': playlistCount == 1 ? '1 playlist' : '$playlistCount playlists',
      },
      {
        'title': 'Recently Played',
        'icon': Icons.history_rounded,
        'color': const Color(0xFFFF9F1C),
        'screen': const ThemedRecentlyPlayedScreen(),
        'subtitle': recentsCount == 1 ? '1 song' : '$recentsCount songs',
      },
      {
        'title': 'Downloaded',
        'icon': Icons.download_done_rounded,
        'color': const Color(0xFF2ECC71),
        'screen': const ThemedDownloadedSongsScreen(),
        'subtitle': 'Offline music',
      },
      {
        'title': 'Local Files',
        'icon': Icons.folder_open_rounded,
        'color': const Color(0xFFB388FF),
        'screen': const ThemedLocalMusicScreen(),
        'subtitle': localCount == 1 ? '1 track' : '$localCount tracks',
      },
      {
        'title': 'Import Playlists',
        'icon': Icons.playlist_add_check_rounded,
        'color': const Color(0xFF00E5FF),
        'screen': const ThemedPlaylistImportScreen(),
        'subtitle': 'Spotify & YouTube',
      },
    ];

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.20,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => StaggerIn(
            index: index,
            child: _buildLiquidLibraryCard(
              context: context,
              title: libraryItems[index]['title'],
              subtitle: libraryItems[index]['subtitle'],
              icon: libraryItems[index]['icon'],
              color: libraryItems[index]['color'],
              screen: libraryItems[index]['screen'],
            ),
          ),
          childCount: libraryItems.length,
        ),
      ),
    );
  }

  Widget _buildPlaylistsContent(BuildContext context, MusicProvider musicProvider) {
    final playlists = musicProvider.userPlaylists;
    if (playlists.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.queue_music_rounded, size: 54, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text("No playlists yet", style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 16)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _showCreatePlaylistDialog(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create Playlist'),
              ),
            ],
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.all(20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.78,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => StaggerIn(
            index: index,
            child: _buildLiquidPlaylistCard(context, playlists[index]),
          ),
          childCount: playlists.length,
        ),
      ),
    );
  }

  Widget _buildLiquidPlaylistCard(BuildContext context, Playlist playlist) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ThemedPlaylistDetailScreen(
              playlistId: playlist.id,
              playlistName: playlist.name,
              playlistImage: playlist.imageUrl,
              cachedTracks: playlist.tracks,
            ),
          ),
        );
      },
      onLongPress: () => _showPlaylistOptions(context, playlist),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: playlist.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: ImageQualityUtils.getHighResArtwork(playlist.imageUrl),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey[900],
                          child: const Icon(Icons.music_note, color: Colors.white54),
                        ),
                      )
                    : Container(
                        color: Colors.white.withValues(alpha: 0.06),
                        child: const Center(
                          child: Icon(Icons.queue_music_rounded, color: Colors.white38, size: 40),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${playlist.tracks.length} tracks',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.50),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistsContent(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _smartArtistsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }
        final artists = snapshot.data ?? [];
        if (artists.isEmpty) {
          return SliverFillRemaining(
            child: Center(
              child: Text(
                "No artists found in library",
                style: GoogleFonts.plusJakartaSans(color: Colors.white54),
              ),
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.88,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final artist = artists[index];
                final name = artist.artistName as String;
                final imageUrl = artist.albumArtUrl as String;

                return StaggerIn(
                  index: index,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ThemedArtistDetailScreen(
                            artistId: "",
                            artistName: name,
                            artistImage: imageUrl,
                            searchByName: true,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.5),
                            ),
                            child: CircleAvatar(
                              radius: 42,
                              backgroundImage: NetworkImage(ImageQualityUtils.getHighResArtwork(imageUrl)),
                              backgroundColor: Colors.white10,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            name,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              childCount: artists.length,
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumsContent(BuildContext context) {
    return FutureBuilder<List<Track>>(
      future: _smartAlbumsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }
        final albums = snapshot.data ?? [];
        if (albums.isEmpty) {
          return SliverFillRemaining(
            child: Center(
              child: Text(
                "No albums found in library",
                style: GoogleFonts.plusJakartaSans(color: Colors.white54),
              ),
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.78,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final track = albums[index];
                return StaggerIn(
                  index: index,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ThemedAlbumDetailScreen(
                            albumId: "",
                            albumName: track.albumName,
                            artistName: track.artistName,
                            albumImage: track.albumArtUrl,
                            searchByName: true,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                              child: CachedNetworkImage(
                                imageUrl: ImageQualityUtils.getHighResArtwork(track.albumArtUrl),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorWidget: (_, __, ___) => Container(
                                  color: Colors.grey[900],
                                  child: const Icon(Icons.album_rounded, color: Colors.white30),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.albumName,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  track.artistName,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white.withValues(alpha: 0.50),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              childCount: albums.length,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSongsContent(BuildContext context, MusicProvider musicProvider) {
    final tracks = musicProvider.recentlyPlayed;
    if (tracks.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            "No recently played songs",
            style: GoogleFonts.plusJakartaSans(color: Colors.white54),
          ),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final track = tracks[index];
          final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
          return TrackTile(
            track: track,
            isPlaying: isPlaying,
            isRecentlyPlayedContext: true,
            onTap: () => musicProvider.playTrack(track, playlistTracks: tracks),
          );
        },
        childCount: tracks.length,
      ),
    );
  }

  Widget _buildDownloadedContent(BuildContext context, MusicProvider musicProvider) {
    return FutureBuilder<List<Track>>(
      future: musicProvider.getDownloadedTracks(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
        }
        final tracks = snapshot.data!;
        if (tracks.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                "No downloaded songs",
                style: GoogleFonts.plusJakartaSans(color: Colors.white54),
              ),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final track = tracks[index];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    track.albumArtUrl,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const Icon(Icons.music_note),
                  ),
                ),
                title: Text(
                  track.trackName,
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.artistName,
                  style: GoogleFonts.plusJakartaSans(color: Colors.white54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => musicProvider.playOfflineTrack(track, contextList: tracks),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38),
                  onPressed: () async {
                    await musicProvider.deleteDownloadedTrack(track.id);
                    if (mounted) setState(() {});
                  },
                ),
              );
            },
            childCount: tracks.length,
          ),
        );
      },
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final accent = Theme.of(context).colorScheme.primary;
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Create Playlist',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Playlist name',
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            hintText: 'My Awesome Mix',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent.withValues(alpha: 0.5))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent)),
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              Navigator.pop(dialogContext);
              _createPlaylist(context, musicProvider, v.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final n = nameController.text.trim();
              if (n.isNotEmpty) {
                Navigator.pop(dialogContext);
                _createPlaylist(context, musicProvider, n);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _createPlaylist(BuildContext context, MusicProvider musicProvider, String name) {
    final accent = Theme.of(context).colorScheme.primary;
    musicProvider.createPlaylist(name);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playlist "$name" created'),
        backgroundColor: accent,
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ThemedUserPlaylistScreen()),
          ),
        ),
      ),
    );
  }

  void _showPlaylistOptions(BuildContext context, Playlist playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => GlassSurface(
        tier: GlassTier.chrome,
        borderRadius: 24,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.edit_rounded, color: Colors.white),
                  title: Text('Rename', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    _showRenamePlaylistDialog(context, playlist);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                  title: Text('Delete', style: GoogleFonts.plusJakartaSans(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(context, playlist);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRenamePlaylistDialog(BuildContext context, Playlist playlist) {
    final accent = Theme.of(context).colorScheme.primary;
    final c = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: c,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Colors.grey[400]),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[700]!)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent)),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text('Save', style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
            onPressed: () {
              final n = c.text.trim();
              if (n.isNotEmpty && n != playlist.name) {
                context.read<MusicProvider>().renamePlaylist(playlist.id, n);
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Playlist playlist) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Playlist', style: TextStyle(color: Colors.white)),
        content: Text('Delete "${playlist.name}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
            onPressed: () {
              context.read<MusicProvider>().deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
