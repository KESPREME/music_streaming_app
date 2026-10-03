import 'package:flutter/material.dart';
import '../utils/app_image_cache.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/music_provider.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/glass_surface.dart';
import '../widgets/stagger_in.dart';
import '../theme/glass_tokens.dart';
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

import '../widgets/library/library_header.dart';
import '../widgets/library/library_hero_artwork.dart';
import '../widgets/library/library_filter_bar.dart';
import '../widgets/library/library_action_card.dart';
import '../widgets/library/library_brand_promo_card.dart';

/// Mine Music — Library Screen.
///
/// Refined visual presentation:
/// - AMOLED black foundation with restrained, calm optical weight.
/// - Apple-level liquid glass material (subtle transmission, soft internal light).
/// - Tight, intentional hero footprint with dominant editorial typography.
/// - Calibrated semantic card accents (crimson, calm azure, honey amber, emerald, violet, slate ice).
/// - Dynamic layout-aware content clearance preventing overlap with persistent bottom navigation.
/// - Granular Provider rebuild isolation.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.isActive = true});

  /// Whether this tab is currently visible. Gating the Liquid Orb on this
  /// keeps an off-screen tab from running a per-pixel fragment shader at
  /// 60fps. Defaults to true so behaviour is unchanged for other callers.
  final bool isActive;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _selectedFilter = 'All';
  LibrarySortOption _currentSort = LibrarySortOption.recentlyAdded;

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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    // Single owner for horizontal screen margins across all major sections
    final horizontalGutter = (screenWidth * 0.045).clamp(16.0, 24.0);
    final columnGap = (screenWidth * 0.030).clamp(12.0, 16.0);

    // Derived card geometry: wide + compact, bounded to prevent vertical cramping on narrow devices
    final contentWidth = screenWidth - (2 * horizontalGutter);
    final cardWidth = (contentWidth - columnGap) / 2;
    final childAspectRatio = cardWidth <= 165
        ? 1.52
        : (cardWidth <= 240 ? 1.58 : 1.65);

    return PlayerAwarePopScope(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent, // AMOLED ambient canvas shines through
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // 1. Top App Bar: Understated 3D Brand Mark + Dual Glass Action Buttons
              SliverToBoxAdapter(
                child: LibraryHeader(
                  horizontalPadding: horizontalGutter,
                  onCreatePlaylist: () => _showCreatePlaylistDialog(context),
                  onSearchTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GlassLibrarySearchScreen(),
                      ),
                    );
                  },
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 6),
              ),

              // 2. Hero Section: Tightened Footprint, Dominant Editorial Title & Atmospheric Liquid Depth
              SliverToBoxAdapter(
                child: LibraryHeroArtwork(
                  horizontalPadding: horizontalGutter,
                  isActive: widget.isActive,
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 8),
              ),

              // 3. Filter Segmented Capsule & Companion Sort Button
              SliverToBoxAdapter(
                child: LibraryFilterBar(
                  horizontalPadding: horizontalGutter,
                  selectedCategory: _selectedFilter,
                  onCategorySelected: (category) {
                    setState(() => _selectedFilter = category);
                  },
                  currentSort: _currentSort,
                  onSortChanged: (sort) {
                    setState(() => _currentSort = sort);
                  },
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 8),
              ),

              // 4. Tab Content (All / Playlists / Artists / Albums)
              if (_selectedFilter == 'All')
                ..._buildAllTabSlivers(
                  context,
                  horizontalGutter,
                  columnGap,
                  childAspectRatio,
                )
              else if (_selectedFilter == 'Playlists')
                _buildPlaylistsContent(context)
              else if (_selectedFilter == 'Artists')
                _buildArtistsContent(context)
              else if (_selectedFilter == 'Albums')
                _buildAlbumsContent(context),

              // 5. Dynamic Scroll Clearance for Docked Mini-Player & Bottom Navigation
              SliverToBoxAdapter(
                child: Builder(
                  builder: (context) {
                    final hasTrack = context.select<MusicProvider, bool>(
                      (p) => p.currentTrack != null && !p.hideMiniPlayer,
                    );
                    final bottomInset = MediaQuery.of(context).padding.bottom;
                    // Clearance derived from actual player & nav tokens
                    final baseClearance = hasTrack
                        ? (GlassTokens.playerBottomInset + GlassTokens.playerPillHeight + 20.0)
                        : (GlassTokens.playerBottomInset + 14.0);
                    return SizedBox(height: baseClearance + bottomInset);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ALL TAB: 2-Column Action Cards Grid + Promotional Brand Card
  // ---------------------------------------------------------------------------

  List<Widget> _buildAllTabSlivers(
    BuildContext context,
    double horizontalGutter,
    double columnGap,
    double childAspectRatio,
  ) {
    return [
      // 2-Column Grid (6 Cards)
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: horizontalGutter),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: columnGap,
            mainAxisSpacing: columnGap,
          ),
          delegate: SliverChildListDelegate.fixed([
            // 1. Liked Songs (Calibrated Coral Crimson)
            Builder(
              builder: (context) {
                final likedCount = context.select<MusicProvider, int>(
                  (p) => p.likedSongs.length,
                );
                return StaggerIn(
                  index: 0,
                  child: LibraryActionCard(
                    title: 'Liked Songs',
                    subtitle: likedCount == 1 ? '1 song' : '$likedCount songs',
                    icon: Icons.favorite_rounded,
                    color: const Color(0xFFE24362), // Restrained coral crimson
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ThemedLikedSongsScreen(),
                      ),
                    ),
                  ),
                );
              },
            ),
            // 2. Your Playlists (Calibrated Calm Azure)
            Builder(
              builder: (context) {
                final playlistCount = context.select<MusicProvider, int>(
                  (p) => p.userPlaylists.length,
                );
                return StaggerIn(
                  index: 1,
                  child: LibraryActionCard(
                    title: 'Your Playlists',
                    subtitle: playlistCount == 1 ? '1 playlist' : '$playlistCount playlists',
                    icon: Icons.queue_music_rounded,
                    color: const Color(0xFF2575DC), // Calm azure
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ThemedUserPlaylistScreen(),
                      ),
                    ),
                  ),
                );
              },
            ),
            // 3. Recently Played (Calibrated Honey Amber)
            Builder(
              builder: (context) {
                final recentsCount = context.select<MusicProvider, int>(
                  (p) => p.recentlyPlayed.length,
                );
                return StaggerIn(
                  index: 2,
                  child: LibraryActionCard(
                    title: 'Recently Played',
                    subtitle: recentsCount == 1 ? '1 song' : '$recentsCount songs',
                    icon: Icons.history_rounded,
                    color: const Color(0xFFD68524), // Warm honey amber
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ThemedRecentlyPlayedScreen(),
                      ),
                    ),
                  ),
                );
              },
            ),
            // 4. Downloaded (Calibrated Subdued Emerald)
            StaggerIn(
              index: 3,
              child: LibraryActionCard(
                title: 'Downloaded',
                subtitle: 'Offline music',
                icon: Icons.download_rounded,
                color: const Color(0xFF2EA858), // Subdued emerald
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ThemedDownloadedSongsScreen(),
                  ),
                ),
              ),
            ),
            // 5. Local Files (Calibrated Amethyst Violet)
            Builder(
              builder: (context) {
                final localCount = context.select<MusicProvider, int>(
                  (p) => p.localTracks.length,
                );
                return StaggerIn(
                  index: 4,
                  child: LibraryActionCard(
                    title: 'Local Files',
                    subtitle: localCount == 1 ? '1 track' : '$localCount tracks',
                    icon: Icons.folder_rounded,
                    color: const Color(0xFF9348CE), // Deep amethyst violet
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ThemedLocalMusicScreen(),
                      ),
                    ),
                  ),
                );
              },
            ),
            // 6. Import Playlists (Calibrated Muted Slate Ice)
            StaggerIn(
              index: 5,
              child: LibraryActionCard(
                title: 'Import Playlists',
                subtitle: 'Spotify & YouTube',
                icon: Icons.ios_share_rounded,
                color: const Color(0xFF3896BE), // Muted slate ice
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ThemedPlaylistImportScreen(),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),

      SliverToBoxAdapter(
        child: SizedBox(height: columnGap),
      ),

      // Promotional Brand Identity Card: "Listen your way."
      SliverToBoxAdapter(
        child: StaggerIn(
          index: 6,
          child: LibraryBrandPromoCard(
            horizontalPadding: horizontalGutter,
            isActive: widget.isActive,
          ),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // PLAYLISTS TAB
  // ---------------------------------------------------------------------------

  Widget _buildPlaylistsContent(BuildContext context) {
    final rawPlaylists = context.select<MusicProvider, List<Playlist>>(
      (p) => p.userPlaylists,
    );

    final playlists = List<Playlist>.from(rawPlaylists);
    switch (_currentSort) {
      case LibrarySortOption.alphabetical:
        playlists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case LibrarySortOption.trackCount:
        playlists.sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
        break;
      case LibrarySortOption.recentlyAdded:
        break;
    }

    if (playlists.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.queue_music_rounded,
                size: 54,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                'No playlists yet',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.82,
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
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0C0D11),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.6,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: playlist.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: ImageQualityUtils.getHighResArtwork(playlist.imageUrl),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          memCacheWidth: AppImageCache.cardMemCache,
                          memCacheHeight: AppImageCache.cardMemCache,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.white.withValues(alpha: 0.04),
                          child: const Icon(Icons.music_note_rounded, color: Colors.white38),
                        ),
                      )
                    : Container(
                        color: Colors.white.withValues(alpha: 0.04),
                        child: const Center(
                          child: Icon(Icons.queue_music_rounded, color: Colors.white38, size: 36),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
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
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
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

  // ---------------------------------------------------------------------------
  // ARTISTS TAB
  // ---------------------------------------------------------------------------

  Widget _buildArtistsContent(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _smartArtistsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
          );
        }
        final rawArtists = snapshot.data ?? [];
        if (rawArtists.isEmpty) {
          return SliverFillRemaining(
            child: Center(
              child: Text(
                'No artists found in library',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white54,
                  fontSize: 15,
                ),
              ),
            ),
          );
        }

        final artists = List<dynamic>.from(rawArtists);
        if (_currentSort == LibrarySortOption.alphabetical) {
          artists.sort((a, b) => (a.artistName as String)
              .toLowerCase()
              .compareTo((b.artistName as String).toLowerCase()));
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                            artistId: '',
                            artistName: name,
                            artistImage: imageUrl,
                            searchByName: true,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C0D11),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 0.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
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
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 1.2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 42,
                              backgroundImage: NetworkImage(
                                ImageQualityUtils.getHighResArtwork(imageUrl),
                              ),
                              backgroundColor: Colors.white10,
                            ),
                          ),
                          const SizedBox(height: 12),
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

  // ---------------------------------------------------------------------------
  // ALBUMS TAB
  // ---------------------------------------------------------------------------

  Widget _buildAlbumsContent(BuildContext context) {
    return FutureBuilder<List<Track>>(
      future: _smartAlbumsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
          );
        }
        final rawAlbums = snapshot.data ?? [];
        if (rawAlbums.isEmpty) {
          return SliverFillRemaining(
            child: Center(
              child: Text(
                'No albums found in library',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white54,
                  fontSize: 15,
                ),
              ),
            ),
          );
        }

        final albums = List<Track>.from(rawAlbums);
        if (_currentSort == LibrarySortOption.alphabetical) {
          albums.sort((a, b) => a.albumName.toLowerCase().compareTo(b.albumName.toLowerCase()));
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.82,
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
                            albumId: '',
                            albumName: track.albumName,
                            artistName: track.artistName,
                            albumImage: track.albumArtUrl,
                            searchByName: true,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C0D11),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 0.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
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
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                                child: CachedNetworkImage(
                                  imageUrl: ImageQualityUtils.getHighResArtwork(track.albumArtUrl),
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  memCacheWidth: AppImageCache.cardMemCache,
                                  memCacheHeight: AppImageCache.cardMemCache,
                                errorWidget: (_, __, ___) => Container(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  child: const Icon(Icons.album_rounded, color: Colors.white30),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
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
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
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

  // ---------------------------------------------------------------------------
  // PLAYLIST MANAGEMENT & CONTEXT DIALOGS (Zero Regressions)
  // ---------------------------------------------------------------------------

  void _showCreatePlaylistDialog(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final accent = Theme.of(context).colorScheme.primary;
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF16181F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          'Create Playlist',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
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
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accent.withValues(alpha: 0.5)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accent),
            ),
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
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
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
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.edit_rounded, color: Colors.white),
                  title: Text(
                    'Rename',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showRenamePlaylistDialog(context, playlist);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                  title: Text(
                    'Delete',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
        backgroundColor: const Color(0xFF16181F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Rename Playlist',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
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
        backgroundColor: const Color(0xFF16181F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
