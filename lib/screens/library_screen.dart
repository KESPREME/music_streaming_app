import 'package:flutter/material.dart';
import '../theme/app_font.dart';
import '../utils/app_image_cache.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/music_provider.dart';
import '../services/innertube/library_playlists_parser.dart';
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
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/themed_album_detail_screen.dart';
import 'glass_library_search_screen.dart';

import '../widgets/library/library_header.dart';
import '../widgets/library/library_hero_artwork.dart';
import '../widgets/library/library_filter_bar.dart';
import '../services/replay/replay_summary.dart';
import '../widgets/replay/replay_card.dart';
import 'replay_screen.dart';
import '../widgets/library/library_shelves.dart';
import '../widgets/themed_options_sheet.dart';
import '../widgets/themed_playlist_detail_screen.dart';
import '../widgets/collection/collection_kit.dart' show CollectionStyle, showCollectionToast;
import '../widgets/playlist/open_playlist.dart';
import '../widgets/skeleton.dart';
import '../widgets/playlist/playlist_edit_sheet.dart';

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
        p.loadYouTubeLibraryPlaylists();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    // Single owner for horizontal screen margins across all major sections
    final horizontalGutter = (screenWidth * 0.045).clamp(16.0, 24.0);

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

              // 4. Tab Content (All / Playlists / Artists / Albums), faded in on
              // every switch so the change reads as one surface settling, not
              // a cut. Keyed by tab: a new key is a new fade.
              LibraryTabFade(
                key: ValueKey(_selectedFilter),
                sliver: switch (_selectedFilter) {
                  'Playlists' => _buildPlaylistsContent(context),
                  'Artists' => _buildArtistsContent(context),
                  'Albums' => _buildAlbumsContent(context),
                  _ => SliverMainAxisGroup(
                      slivers: _buildAllTabSlivers(context, horizontalGutter),
                    ),
                },
              ),

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
  // ALL TAB
  //
  // One listening card (the page's authored moment), the destinations as a row
  // of glass tiles, then shelves of real artwork: what you played, your
  // playlists, the albums and artists your library is made of. A shelf with
  // nothing in it is not drawn - except playlists, whose first card is always
  // "New playlist" so an empty library still has a way in.
  // ---------------------------------------------------------------------------

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  /// Liked Songs has its own live screen (search, sort, filters, swipe to
  /// remove with undo, multi-select) - never a snapshot.
  void _openLiked(BuildContext context) =>
      _push(context, const ThemedLikedSongsScreen());

  void _openRecents(BuildContext context) =>
      _push(context, const ThemedRecentlyPlayedScreen());

  void _openDownloads(BuildContext context) =>
      _push(context, const ThemedDownloadedSongsScreen());
  void _openPlaylist(BuildContext context, Playlist playlist) =>
      openUserPlaylist(context, playlist);

  void _openAlbum(BuildContext context, Track track) {
    _push(
      context,
      ThemedAlbumDetailScreen(
        albumId: '',
        albumName: track.albumName,
        artistName: track.artistName,
        albumImage: track.albumArtUrl,
        searchByName: true,
      ),
    );
  }

  void _openArtist(BuildContext context, String name, String imageUrl) {
    _push(
      context,
      ThemedArtistDetailScreen(
        artistId: '',
        artistName: name,
        artistImage: imageUrl,
        searchByName: true,
      ),
    );
  }

  void _showTab(String tab) {
    HapticFeedback.selectionClick();
    setState(() => _selectedFilter = tab);
  }

  List<Widget> _buildAllTabSlivers(BuildContext context, double gutter) {
    final provider = context.read<MusicProvider>();
    String count(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

    return [
      // Replay: the listening card wallet. Tap any face for the full Replay.
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ListenableBuilder(
            listenable: provider.listeningStats,
            builder: (context, _) => ReplayCardCarousel(
              summary: ReplaySummary.of(provider.listeningStats, ReplayPeriod.year),
              horizontalPadding: gutter,
              onTap: () => ReplayScreen.open(context),
            ),
          ),
        ),
      ),

      // Quick access
      SliverToBoxAdapter(
        child: LibraryShelfHeader(title: 'Quick access', horizontalPadding: gutter),
      ),
      SliverToBoxAdapter(
        child: Builder(builder: (context) {
          final liked = context.select<MusicProvider, int>((p) => p.likedSongs.length);
          final lists = context.select<MusicProvider, int>((p) => p.userPlaylists.length);
          final recents = context.select<MusicProvider, int>((p) => p.recentlyPlayed.length);
          final local = context.select<MusicProvider, int>((p) => p.localTracks.length);
          final tiles = <Widget>[
            LibraryQuickTile(
              title: 'Liked Songs',
              subtitle: count(liked, 'song', 'songs'),
              icon: Icons.favorite_rounded,
              color: const Color(0xFFE24362),
              onTap: () => _openLiked(context),
            ),
            LibraryQuickTile(
              title: 'Your Playlists',
              subtitle: count(lists, 'playlist', 'playlists'),
              icon: Icons.queue_music_rounded,
              color: const Color(0xFF2F7BEA),
              onTap: () => _push(context, const ThemedUserPlaylistScreen()),
            ),
            LibraryQuickTile(
              title: 'History',
              subtitle: count(recents, 'song', 'songs'),
              icon: Icons.history_rounded,
              color: const Color(0xFFE08A2A),
              onTap: () => _openRecents(context),
            ),
            LibraryQuickTile(
              title: 'Downloaded',
              subtitle: 'Offline music',
              icon: Icons.download_rounded,
              color: const Color(0xFF2EB15E),
              onTap: () => _openDownloads(context),
            ),
            LibraryQuickTile(
              title: 'Local Files',
              subtitle: count(local, 'track', 'tracks'),
              icon: Icons.folder_rounded,
              color: const Color(0xFF9B50DA),
              onTap: () => _push(context, const ThemedLocalMusicScreen()),
            ),
            LibraryQuickTile(
              title: 'Import',
              subtitle: 'From Spotify',
              icon: Icons.ios_share_rounded,
              color: const Color(0xFF3AA0C8),
              onTap: () => _push(context, const ThemedPlaylistImportScreen()),
            ),
          ];
          return LibraryRail(
            height: 124,
            gap: 12,
            horizontalPadding: gutter,
            itemCount: tiles.length,
            itemBuilder: (_, i) => StaggerIn(index: i, child: tiles[i]),
          );
        }),
      ),

      // Recently played
      SliverToBoxAdapter(
        child: Builder(builder: (context) {
          final recents = context.select<MusicProvider, List<Track>>((p) => p.recentlyPlayed);
          final playingId = context.select<MusicProvider, String?>((p) => p.currentTrack?.id);
          if (recents.isEmpty) return const SizedBox.shrink();
          final shown = recents.take(15).toList(growable: false);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LibraryShelfHeader(
                title: 'Recently played',
                horizontalPadding: gutter,
                onSeeAll: () => _openRecents(context),
              ),
              LibraryRail(
                height: LibraryArtCard.heightFor(148),
                horizontalPadding: gutter,
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final track = shown[i];
                  return LibraryArtCard(
                    imageUrl: track.albumArtUrl,
                    title: track.trackName,
                    subtitle: track.artistName,
                    playing: track.id == playingId,
                    onTap: () => context.read<MusicProvider>().playTrack(
                          track,
                          playlistTracks: recents,
                          playlistId: 'recently_played',
                        ),
                    onLongPress: () => ThemedOptionsSheet.show(
                      context,
                      track: track,
                      isRecentlyPlayedContext: true,
                    ),
                  );
                },
              ),
            ],
          );
        }),
      ),

      // Your playlists
      SliverToBoxAdapter(
        child: Builder(builder: (context) {
          final playlists = context.select<MusicProvider, List<Playlist>>((p) => p.userPlaylists);
          final youtube = context.select<MusicProvider, List<YouTubeLibraryPlaylist>>((p) => p.youtubeLibraryPlaylists);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LibraryShelfHeader(
                title: 'Your playlists',
                horizontalPadding: gutter,
                onSeeAll: playlists.isEmpty ? null : () => _push(context, const ThemedUserPlaylistScreen()),
              ),
              LibraryRail(
                height: LibraryArtCard.heightFor(148),
                horizontalPadding: gutter,
                itemCount: playlists.length + 1 + youtube.length,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return LibraryNewPlaylistCard(
                      onTap: () => _showCreatePlaylistDialog(context),
                    );
                  }
                  // Yours first, then the signed-in account's YouTube Music ones.
                  if (i > playlists.length) {
                    final y = youtube[i - 1 - playlists.length];
                    return LibraryArtCard(
                      imageUrl: y.thumbnailUrl,
                      title: y.title,
                      subtitle: 'YouTube Music',
                      icon: Icons.queue_music_rounded,
                      onTap: () => _push(
                        context,
                        ThemedPlaylistDetailScreen(
                          playlistId: y.browseId,
                          playlistName: y.title,
                          playlistImage: y.thumbnailUrl.isEmpty ? null : y.thumbnailUrl,
                        ),
                      ),
                    );
                  }
                  final playlist = playlists[i - 1];
                  return LibraryPlaylistCard(
                    playlist: playlist,
                    onTap: () => _openPlaylist(context, playlist),
                    onLongPress: () => _showPlaylistOptions(context, playlist),
                  );
                },
              ),
            ],
          );
        }),
      ),

      // Your albums
      SliverToBoxAdapter(
        child: FutureBuilder<List<Track>>(
          future: _smartAlbumsFuture,
          builder: (context, snapshot) {
            final albums = snapshot.data ?? const <Track>[];
            if (albums.isEmpty) return const SizedBox.shrink();
            final shown = albums.take(15).toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LibraryShelfHeader(
                  title: 'Your albums',
                  horizontalPadding: gutter,
                  onSeeAll: () => _showTab('Albums'),
                ),
                LibraryRail(
                  height: LibraryArtCard.heightFor(148),
                  horizontalPadding: gutter,
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final album = shown[i];
                    return LibraryArtCard(
                      imageUrl: album.albumArtUrl,
                      title: album.albumName,
                      subtitle: album.artistName,
                      icon: Icons.album_rounded,
                      onTap: () => _openAlbum(context, album),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),

      // Your artists
      SliverToBoxAdapter(
        child: FutureBuilder<List<dynamic>>(
          future: _smartArtistsFuture,
          builder: (context, snapshot) {
            final artists = snapshot.data ?? const <dynamic>[];
            if (artists.isEmpty) return const SizedBox.shrink();
            final shown = artists.take(15).toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LibraryShelfHeader(
                  title: 'Your artists',
                  horizontalPadding: gutter,
                  onSeeAll: () => _showTab('Artists'),
                ),
                LibraryRail(
                  height: LibraryArtistCard.heightFor(112),
                  horizontalPadding: gutter,
                  gap: 16,
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final artist = shown[i];
                    final name = artist.artistName as String;
                    final image = artist.albumArtUrl as String;
                    return LibraryArtistCard(
                      imageUrl: image,
                      name: name,
                      onTap: () => _openArtist(context, name, image),
                    );
                  },
                ),
              ],
            );
          },
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
                style: AppFont.style(
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
        openUserPlaylist(context, playlist);
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
                    style: AppFont.style(
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
                    style: AppFont.style(
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
          // The grid's own shape, not a spinner: the cards land where the
          // placeholders were.
          return const SkeletonScope(
            child: SliverSkeletonCardGrid(circle: true, aspectRatio: 0.88),
          );
        }
        final rawArtists = snapshot.data ?? [];
        if (rawArtists.isEmpty) {
          return SliverFillRemaining(
            child: Center(
              child: Text(
                'No artists found in library',
                style: AppFont.style(
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
                              // Disk-cached and decoded at the circle's size,
                              // not a fresh full-size download per card.
                              backgroundImage: ResizeImage(
                                CachedNetworkImageProvider(
                                  ImageQualityUtils.getHighResArtwork(imageUrl),
                                ),
                                width: 256,
                                height: 256,
                              ),
                              backgroundColor: Colors.white10,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            name,
                            style: AppFont.style(
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
          return const SkeletonScope(
            child: SliverSkeletonCardGrid(circle: false, aspectRatio: 0.82),
          );
        }
        final rawAlbums = snapshot.data ?? [];
        if (rawAlbums.isEmpty) {
          return SliverFillRemaining(
            child: Center(
              child: Text(
                'No albums found in library',
                style: AppFont.style(
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
                                  style: AppFont.style(
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
                                  style: AppFont.style(
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

  /// "New playlist": the same create sheet as everywhere else (name, description,
  /// cover), then a way to open what was made.
  Future<void> _showCreatePlaylistDialog(BuildContext context) async {
    final made = await showPlaylistEditSheet(context);
    if (made == null || !context.mounted) return;
    showCollectionToast(
      context,
      'Created "${made.name}"',
      icon: Icons.playlist_add_check_rounded,
      action: SnackBarAction(
        label: 'Open',
        textColor: CollectionStyle.accent,
        onPressed: () => openUserPlaylist(context, made),
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
                    style: AppFont.style(
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
                    style: AppFont.style(
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

/// Fades a tab's content in when it arrives (the screen keys this by tab).
/// Opacity only, on a sliver, so a long grid costs one layer, not a rebuild.
class LibraryTabFade extends StatefulWidget {
  const LibraryTabFade({super.key, required this.sliver});

  final Widget sliver;

  @override
  State<LibraryTabFade> createState() => _LibraryTabFadeState();
}

class _LibraryTabFadeState extends State<LibraryTabFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduce) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SliverFadeTransition(opacity: _opacity, sliver: widget.sliver);
}
