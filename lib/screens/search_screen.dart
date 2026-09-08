import 'dart:async'; 
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/search_history_store.dart';
import '../providers/music_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/glass_tokens.dart';
import '../widgets/track_tile.dart';
import '../widgets/glass_surface.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/themed_playlist_detail_screen.dart';
import '../core/navigation/root_navigator.dart';

class ArtistSearchTile extends StatelessWidget {
  final String artistName;
  final String? artistImageUrl;
  final VoidCallback onTap;

  const ArtistSearchTile({
    super.key,
    required this.artistName,
    this.artistImageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: themeProvider.isGlassmorphism
          ? _buildGlassmorphismTile(context, colorScheme)
          : _buildMaterialYouTile(context, colorScheme),
    );
  }

  Widget _buildGlassmorphismTile(BuildContext context, ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: _buildTileContent(context, colorScheme, isGlass: true),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialYouTile(BuildContext context, ColorScheme colorScheme) {
    return Material(
      elevation: 1,
      surfaceTintColor: colorScheme.surfaceTint,
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          child: _buildTileContent(context, colorScheme, isGlass: false),
        ),
      ),
    );
  }

  Widget _buildTileContent(BuildContext context, ColorScheme colorScheme, {required bool isGlass}) {
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: isGlass
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : colorScheme.primary.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: CircleAvatar(
            radius: 30,
            backgroundColor: isGlass ? Colors.grey[850] : colorScheme.surfaceContainerHighest,
            backgroundImage: artistImageUrl != null && artistImageUrl!.isNotEmpty
                ? NetworkImage(artistImageUrl!)
                : null,
            child: artistImageUrl == null || artistImageUrl!.isEmpty
                ? Icon(
                    Icons.person,
                    color: isGlass ? Colors.white54 : colorScheme.onSurfaceVariant,
                    size: 30,
                  )
                : null,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                artistName,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: isGlass ? Colors.white : colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "Artist",
                style: GoogleFonts.plusJakartaSans(
                  color: isGlass ? Colors.white54 : colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.chevron_right_rounded,
          color: isGlass
              ? Colors.white30
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ],
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.embedded = false,
    this.externalController,
    this.externalFocusNode,
    this.initialQuery,
    this.onPushDetail,
  });

  /// Embedded mode: lives inside MainScreen's search overlay; the input
  /// field lives in the nav pill (bound to [externalController]) so this
  /// screen renders only tabs + results.
  final bool embedded;
  final TextEditingController? externalController;
  final FocusNode? externalFocusNode;

  /// Pre-filled query (deep links: minemusic://search?q=...).
  final String? initialQuery;

  /// Pushes detail screens (Artist, Playlist, Album) in-place hosted by MainScreen
  final void Function(Widget screen)? onPushDetail;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final TextEditingController _searchController =
      widget.externalController ?? TextEditingController();
  String _searchQuery = "";
  Timer? _debounce;
  final List<String> _recentSearches = [];
  final SearchHistoryStore _historyStore = SearchHistoryStore();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _searchController.addListener(_onSearchChanged);
    _loadHistory();
    final initial = widget.initialQuery;
    if (initial != null && initial.isNotEmpty) {
      _searchController.text = initial;
      _searchQuery = initial;
      _addToHistory(initial);
      _performSearch(initial);
    }
  }

  /// Switching result kind re-runs the active query for that kind so the
  /// tab always reflects the current query (per-kind caches make this
  /// cheap — cache hits resolve synchronously in the provider).
  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_searchQuery.trim().isNotEmpty) {
      _performSearch(_searchQuery);
    }
  }

  Future<void> _loadHistory() async {
    await _historyStore.load();
    if (mounted) {
      setState(() => _recentSearches..clear()..addAll(_historyStore.entries));
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.removeListener(_onSearchChanged);
    if (widget.externalController == null) _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
       if (mounted) {
        final newQuery = _searchController.text;
        // FIX: Always trigger search if text is not empty
        // Use forceRefresh when searching same query again (user wants fresh results)
        final bool isSameQuery = newQuery == _searchQuery;
        setState(() {
          _searchQuery = newQuery;
        });
        if (_searchQuery.isNotEmpty) {
           _addToHistory(_searchQuery);
           _performSearch(_searchQuery, forceRefresh: isSameQuery);
        } else {
           Provider.of<MusicProvider>(context, listen: false).clearSearchResults();
        }
      }
    });
  }

  void _performSearch(String query, {bool forceRefresh = false}) {
    if (query.trim().isEmpty) return;
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    if (_tabController.index == 0) {
        musicProvider.searchTracks(query, forceRefresh: forceRefresh);
    } else if (_tabController.index == 1) {
        musicProvider.fetchArtistTracks(query, forceRefresh: forceRefresh);
    } else if (_tabController.index == 2) {
        musicProvider.searchPlaylists(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      // OPAQUE: this screen lives inside MainScreen's Stack ABOVE the home
      // content. Without a solid background the home screen bleeds through
      // and its text collides with search results.
      backgroundColor: const Color(0xFF0A0A0C),
      body: SafeArea(
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                floating: true,
                pinned: true,
                toolbarHeight: widget.embedded ? 8 : 90,
                // Grounded dark scrim (no BackdropFilter: solid backdrop
                // makes blur invisible work for the GPU).
                flexibleSpace: Container(
                  color: Colors.black.withValues(alpha: 0.6),
                ),
                title: widget.embedded
                    ? null
                    : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: GlassSurface(
                    tier: GlassTier.floating,
                    borderRadius: GlassTokens.radiusButton,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                      cursorColor: Theme.of(context).colorScheme.primary,
                      decoration: InputDecoration(
                        hintText: 'Search songs, artists...',
                        hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white.withValues(alpha: 0.45), fontWeight: FontWeight.w400),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 22),
                        prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 20),
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 8.0),
                      ),
                      onSubmitted: (query) {
                        _debounce?.cancel();
                        if (query != _searchQuery) {
                           setState(() => _searchQuery = query);
                        }
                        if (query.isNotEmpty) {
                          _addToHistory(query);
                          _performSearch(query);
                        }
                      },
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(50),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: GlassSurface(
                      tier: GlassTier.card,
                      borderRadius: 25,
                      padding: EdgeInsets.zero,
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          gradient: GlassTokens.inkBloom(Theme.of(context).colorScheme.primary, strength: 0.18),
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: GlassTokens.borderInteractiveSelected(Theme.of(context).colorScheme.primary), width: 0.8),
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
                        labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14),
                        unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500, fontSize: 14),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        onTap: (index) {
                          if (_searchQuery.trim().isNotEmpty) {
                            _performSearch(_searchQuery);
                          }
                        },
                        tabs: const [
                          Tab(text: 'Tracks'),
                          Tab(text: 'Artists'),
                          Tab(text: 'Playlists'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                SearchTabContent(
                  recentSearches: _recentSearches,
                  onSearchSelected: (query) {
                        _searchController.text = query;
                        setState(() => _searchQuery = query);
                        _performSearch(query);
                      },
                      onClearHistory: () {
                         setState(() {
                           _recentSearches.clear();
                         });
                         _historyStore.clear();
                      },
                      onRemoveHistoryItem: (query) {
                        setState(() {
                          _recentSearches.remove(query);
                        });
                        _historyStore.remove(query);
                      },
                      onRetry: () => _performSearch(_searchQuery),
                    ),
                    _buildArtistsTab(context, _searchQuery),
                    _buildPlaylistsTab(context, _searchQuery),
                  ],
                ),
          ),
      ),
    );
  }

  void _addToHistory(String query) {
    if (!_recentSearches.contains(query)) {
      setState(() {
        _recentSearches.insert(0, query);
        if (_recentSearches.length > 5) _recentSearches.removeLast();
      });
    }
    // Persist (dedupe/move-to-front handled by the store; UI list keeps its
    // existing 5-item display behavior).
    _historyStore.add(query);
  }



  Widget _buildArtistsTab(BuildContext context, String query) {
    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        if (provider.searchPhase == SearchPhase.loading &&
            query.trim().isNotEmpty) {
          return const _SearchLoadingView();
        }

        if (provider.searchPhase == SearchPhase.error) {
          return _SearchErrorView(
            message: provider.errorMessage ?? 'Search failed.',
            onRetry: () => _performSearch(query, forceRefresh: true),
          );
        }

        if (query.trim().isEmpty && provider.artistTracks.isEmpty) {
          return const _SearchIdleView(
            icon: Icons.person_search_outlined,
            message: 'Search for your favorite artists',
          );
        }

        if (provider.artistTracks.isEmpty && query.trim().isNotEmpty) {
          return _SearchEmptyView(message: 'No artists found for "$query"');
        }

        // Fix: Do not group by artistName. The results are already unique Artist objects.
        // In Artist Search Results:
        // track.trackName = Artist Name (e.g. "The Weeknd")
        // track.artistName = Subtitle/Description (e.g. "Artist • 269M...")
        final artists = provider.artistTracks;

        return ListView.builder(
          padding: const EdgeInsets.only(top: 10, bottom: 100),
          physics: const BouncingScrollPhysics(),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artistTrack = artists[index];
            final artistName = artistTrack.trackName; // Correct Name

            return ArtistSearchTile(
              artistName: artistName, 
              artistImageUrl: artistTrack.albumArtUrl,
              onTap: () {
                 final screen = ThemedArtistDetailScreen(
                   artistId: artistTrack.id,
                   artistName: artistName,
                   artistImage: artistTrack.albumArtUrl,
                 );
                 if (widget.onPushDetail != null) {
                   widget.onPushDetail!(screen);
                 } else {
                   final nav = mainNavigatorKey.currentState ??
                       rootNavigatorKey.currentState ??
                       Navigator.of(context);
                   nav.push(
                     MaterialPageRoute(builder: (_) => screen),
                   );
                 }
              }
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistsTab(BuildContext context, String query) {
    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        if (provider.searchPhase == SearchPhase.loading &&
            query.trim().isNotEmpty) {
          return const _SearchLoadingView();
        }

        if (provider.searchPhase == SearchPhase.error) {
          return _SearchErrorView(
            message: provider.errorMessage ?? 'Search failed.',
            onRetry: () => _performSearch(query, forceRefresh: true),
          );
        }

        if (query.trim().isEmpty && provider.playlistSearchResults.isEmpty) {
          return const _SearchIdleView(
            icon: Icons.queue_music_rounded,
            message: 'Search for playlists',
          );
        }

        if (provider.playlistSearchResults.isEmpty && query.trim().isNotEmpty) {
          return _SearchEmptyView(message: 'No playlists found for "$query"');
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 10, bottom: 100),
          physics: const BouncingScrollPhysics(),
          itemCount: provider.playlistSearchResults.length,
          itemBuilder: (context, index) {
            final playlist = provider.playlistSearchResults[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  playlist.albumArtUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_,__,___) => Container(
                    width: 56, height: 56, 
                    color: Colors.grey[900], 
                    child: const Icon(Icons.music_note, color: Colors.white24)
                  ),
                ),
              ),
              title: Text(
                playlist.trackName, // In search results, title is mapped to trackName
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Playlist • ${playlist.artistName}', // Owner/Artist
                style: GoogleFonts.plusJakartaSans(color: Colors.white54),
              ),
              onTap: () {
                final screen = ThemedPlaylistDetailScreen(
                  playlistId: playlist.id,
                  playlistName: playlist.trackName,
                  playlistImage: playlist.albumArtUrl,
                );
                if (widget.onPushDetail != null) {
                  widget.onPushDetail!(screen);
                } else {
                  final nav = mainNavigatorKey.currentState ??
                      rootNavigatorKey.currentState ??
                      Navigator.of(context);
                  nav.push(
                    MaterialPageRoute(builder: (_) => screen),
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}


class SearchTabContent extends StatelessWidget {
  final List<String> recentSearches;
  final Function(String) onSearchSelected;
  final VoidCallback onClearHistory;
  final Function(String) onRemoveHistoryItem;
  final VoidCallback onRetry;

  const SearchTabContent({
    super.key,
    this.recentSearches = const [],
    required this.onSearchSelected,
    required this.onClearHistory,
    required this.onRemoveHistoryItem,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final searchResults = musicProvider.searchedTracks;
        final phase = musicProvider.searchPhase;
        final activeQuery = musicProvider.activeSearchQuery;

        switch (phase) {
          case SearchPhase.loading:
            return const _SearchLoadingView();

          case SearchPhase.error:
            return _SearchErrorView(
              message: musicProvider.errorMessage ?? "Couldn't complete the search.",
              onRetry: onRetry,
            );

          case SearchPhase.empty:
            return _SearchEmptyView(message: 'No results for "$activeQuery"');

          case SearchPhase.idle:
            // Show history if available; otherwise the quiet discovery hint.
            if (recentSearches.isNotEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Recent Searches",
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                      ),
                      TextButton(
                        onPressed: onClearHistory,
                        child: Text("Clear All",
                            style: GoogleFonts.plusJakartaSans(
                                color:
                                    Theme.of(context).colorScheme.primary)),
                      ),
                    ],
                  ),
                  ...recentSearches.map((query) => ListTile(
                        leading: const Icon(Icons.history_rounded,
                            color: Colors.white54),
                        title: Text(query,
                            style: GoogleFonts.plusJakartaSans(
                                color: Colors.white)),
                        onTap: () => onSearchSelected(query),
                        onLongPress: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF1E1E1E),
                              title: const Text("Remove from history?",
                                  style: TextStyle(color: Colors.white)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text("Cancel",
                                      style:
                                          TextStyle(color: Colors.grey)),
                                ),
                                TextButton(
                                  onPressed: () {
                                    onRemoveHistoryItem(query);
                                    Navigator.pop(context);
                                  },
                                  child: Text("Remove",
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary)),
                                ),
                              ],
                            ),
                          );
                        },
                      )),
                ],
              );
            }
            return const _SearchIdleView(
              icon: Icons.search_rounded,
              message: 'Search for tracks, artists, or albums.',
            );

          case SearchPhase.results:
            return ListView.builder(
              padding: EdgeInsets.fromLTRB(0, 8, 0, 100 + MediaQuery.viewInsetsOf(context).bottom),
              itemExtent: 72.0,
              itemCount: searchResults.length,
              itemBuilder: (context, index) {
                final track = searchResults[index];
                final isPlaying = musicProvider.currentTrack?.id == track.id &&
                    musicProvider.isPlaying;

                return TrackTile(
                  key: ValueKey(track.id),
                  track: track,
                  isPlaying: isPlaying,
                  onTap: () {
                    musicProvider.playTrack(track, playlistTracks: searchResults);
                  },
                );
              },
            );
        }
      },
    );
  }
}

/// Quiet, shared search-state views. One visual language: icon + one line,
/// no cards, no decoration.

class _SearchLoadingView extends StatelessWidget {
  const _SearchLoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _SearchIdleView extends StatelessWidget {
  const _SearchIdleView({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white.withValues(alpha: 0.4), fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _SearchEmptyView extends StatelessWidget {
  const _SearchEmptyView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                size: 44, color: Colors.white.withValues(alpha: 0.12)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withValues(alpha: 0.65), fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different search.',
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchErrorView extends StatelessWidget {
  const _SearchErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 44, color: Colors.white.withValues(alpha: 0.12)),
            const SizedBox(height: 12),
            Text(
              "Couldn't complete the search",
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withValues(alpha: 0.65), fontSize: 15),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Try again',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
