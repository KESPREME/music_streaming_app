import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_font.dart';
import '../services/search_history_store.dart';
import '../providers/music_provider.dart';
import '../providers/theme_provider.dart';
import '../models/track.dart';
import '../models/search_history_entry.dart';
import '../utils/color_utils.dart';
import '../widgets/search_result_row.dart';
import '../widgets/search_skeleton.dart';
import '../widgets/search_glass_pills.dart';
import '../widgets/search_grid_cards.dart';
import '../widgets/glass_circle_button.dart';
import '../widgets/themed_options_sheet.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/themed_playlist_detail_screen.dart';
import '../core/navigation/root_navigator.dart';
import 'album_detail_screen.dart';
import '../theme/amoled_theme.dart';

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

  Widget _buildGlassmorphismTile(
      BuildContext context, ColorScheme colorScheme) {
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

  Widget _buildTileContent(BuildContext context, ColorScheme colorScheme,
      {required bool isGlass}) {
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
            backgroundColor: isGlass
                ? Colors.grey[850]
                : colorScheme.surfaceContainerHighest,
            backgroundImage:
                artistImageUrl != null && artistImageUrl!.isNotEmpty
                    ? NetworkImage(artistImageUrl!)
                    : null,
            child: artistImageUrl == null || artistImageUrl!.isEmpty
                ? Icon(
                    Icons.person,
                    color:
                        isGlass ? Colors.white54 : colorScheme.onSurfaceVariant,
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
                style: AppFont.style(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: isGlass ? Colors.white : colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "Artist",
                style: AppFont.style(
                  color:
                      isGlass ? Colors.white54 : colorScheme.onSurfaceVariant,
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
  /// screen renders only scope + chips + results.
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
  static const _tabs = ['Songs', 'Videos', 'Albums', 'Artists', 'Playlists'];

  late TabController _tabController;
  late final TextEditingController _searchController =
      widget.externalController ?? TextEditingController();
  late final FocusNode _dockFocusNode = FocusNode();
  String _searchQuery = "";
  Timer? _debounce;
  SearchScope _scope = SearchScope.mineMusic;

  /// Scroll-linked header chrome (0 at rest → 1 settled): drives the scrim
  /// behind the fixed pills. Quantized to avoid a setState per pixel.
  double _headerScrim = 0.0;

  /// Fixed header heights: segmented (62) + chips (48). Lenses never scroll
  /// (easy lenses detach from scrolling transforms), content slides under.
  static const double _kHeaderFull = 110.0;
  static const double _kHeaderSlim = 62.0;
  final List<SearchHistoryEntry> _recentSearches = [];
  final SearchHistoryStore _historyStore = SearchHistoryStore();

  SearchKind get _activeKind => SearchKind.values[_tabController.index];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _searchController.addListener(_onSearchChanged);
    _loadHistory();
    final initial = widget.initialQuery;
    if (initial != null && initial.isNotEmpty) {
      _searchController.text = initial;
      _searchQuery = initial;
      _commitSearch(initial);
    }
  }

  /// Switching filter re-runs the active query for that kind so the tab
  /// always reflects the current query (per-kind caches make this cheap —
  /// cache hits resolve synchronously in the provider).
  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_searchQuery.trim().isNotEmpty && _scope == SearchScope.mineMusic) {
      _performSearch(_searchQuery);
    } else {
      setState(() {});
    }
  }

  Future<void> _loadHistory() async {
    await _historyStore.load();
    if (mounted) {
      setState(() => _recentSearches
        ..clear()
        ..addAll(_historyStore.entries));
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.removeListener(_onSearchChanged);
    if (widget.externalController == null) _searchController.dispose();
    _dockFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final newQuery = _searchController.text;
      // Same text (e.g. external controller echo): nothing to do.
      if (newQuery == _searchQuery) return;
      setState(() => _searchQuery = newQuery);
      if (newQuery.trim().isNotEmpty) {
        // Typing only searches — history records on explicit commit
        // (submit / suggestion / history tap), BitChord record-on-commit parity.
        _performSearch(newQuery);
      } else {
        Provider.of<MusicProvider>(context, listen: false).clearSearchResults();
      }
    });
  }

  void _performSearch(String query, {bool forceRefresh = false}) {
    if (query.trim().isEmpty || _scope != SearchScope.mineMusic) return;
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    musicProvider.commitSearch(
      query,
      _activeKind,
      forceRefresh: forceRefresh,
    );
    // Typeahead alongside (cheap endpoint; fail-silent).
    musicProvider.fetchSearchSuggestions(query);
  }

  /// Explicit commit: keyboard submit, suggestion/history tap, retry.
  /// Records history and honors the visible filter chip.
  void _commitSearch(String query, {bool forceRefresh = false}) {
    final q = query.trim();
    if (q.isEmpty) return;
    _debounce?.cancel();
    if (_searchQuery != q) setState(() => _searchQuery = q);
    if (_searchController.text != q) _searchController.text = q;
    _addToHistory(q);
    _performSearch(q, forceRefresh: forceRefresh);
  }

  void _pushDetail(Widget screen) {
    if (widget.onPushDetail != null) {
      widget.onPushDetail!(screen);
      return;
    }
    final nav = mainNavigatorKey.currentState ??
        rootNavigatorKey.currentState ??
        Navigator.of(context);
    nav.push(MaterialPageRoute(builder: (_) => screen));
  }

  void _openAlbumResult(Track album) {
    final id = album.id;
    if (id.startsWith('MPREb_') || id.startsWith('OLAK')) {
      _pushDetail(AlbumDetailScreen(
        albumId: id,
        albumName: album.trackName,
        artistName: album.artistName,
        albumImage: album.albumArtUrl,
      ));
    } else if (id.startsWith('VL') ||
        id.startsWith('PL') ||
        id.startsWith('RDCLAK')) {
      _pushDetail(ThemedPlaylistDetailScreen(
        playlistId: id,
        playlistName: album.trackName,
        playlistImage: album.albumArtUrl,
      ));
    } else {
      ThemedOptionsSheet.show(context, track: album);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      // OPAQUE: this screen lives inside MainScreen's Stack ABOVE the home
      // content. Without a solid background the home screen bleeds through
      // and its text collides with search results.
      backgroundColor: AmoledTheme.canvasOf(context, const Color(0xFF0A0A0C)),
      body: SafeArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollUpdateNotification) {
              // Dismiss keyboard on list drag.
              if (n.dragDetails != null) {
                FocusManager.instance.primaryFocus?.unfocus();
              }
              // Scroll-linked chrome: vertical lists only (chips scroller
              // is horizontal and must not drive the scrim).
              if (n.metrics.axis == Axis.vertical) {
                final t = (n.metrics.pixels / 90).clamp(0.0, 1.0);
                final q = (t * 20).round() / 20;
                if (q != _headerScrim) {
                  setState(() => _headerScrim = q);
                }
              }
            }
            return false;
          },
          child: Stack(
            children: [
              // Scroll body sits below the fixed header; rows slide under it.
              AnimatedPadding(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(
                  top: _scope == SearchScope.mineMusic
                      ? _kHeaderFull
                      : _kHeaderSlim,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.02),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _scope == SearchScope.mineMusic
                      ? TabBarView(
                          key: const ValueKey('muzo_results'),
                          controller: _tabController,
                          children: [
                            SearchTabContent(
                              recentSearches: _recentSearches,
                              onEntryTapped: _onHistoryEntryTapped,
                              onClearHistory: () {
                                setState(() => _recentSearches.clear());
                                _historyStore.clear();
                              },
                              onRemoveHistoryItem: (id) {
                                setState(() => _recentSearches
                                    .removeWhere((e) => e.id == id));
                                _historyStore.remove(id);
                              },
                              onRetry: () => _commitSearch(_searchQuery,
                                  forceRefresh: true),
                              onSuggestionSelected: (query) =>
                                  _commitSearch(query),
                              onResultTapped: (track) =>
                                  _recordPlayedTrack(track),
                            ),
                            _buildVideosTab(context, _searchQuery),
                            _buildAlbumsTab(context, _searchQuery),
                            _buildArtistsTab(context, _searchQuery),
                            _buildPlaylistsTab(context, _searchQuery),
                          ],
                        )
                      : _LibraryScopeBody(
                          key: const ValueKey('library_results'),
                          query: _searchQuery,
                          onPushDetail: _pushDetail,
                        ),
                ),
              ),
              // Fixed glass header: lenses never scroll (easy lenses detach
              // from scrolling transforms), rows slide underneath instead.
              // Scroll-linked scrim fades in behind the pills like TopFadeBlur.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: RepaintBoundary(
                  child: Stack(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        height: (_scope == SearchScope.mineMusic
                                ? _kHeaderFull
                                : _kHeaderSlim) +
                            28,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.55, 1.0],
                            colors: [
                              Colors.black
                                  .withValues(alpha: 0.6 * _headerScrim),
                              Colors.black
                                  .withValues(alpha: 0.28 * _headerScrim),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      Consumer<MusicProvider>(
                        builder: (context, p, _) {
                          final accent = ColorUtils.getVibrantAccent(
                              p.paletteGenerator, muzoMauve);
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SearchScopeSegmented(
                                scope: _scope,
                                accent: accent,
                                onChanged: (scope) {
                                  if (scope == _scope) return;
                                  setState(() => _scope = scope);
                                },
                              ),
                              if (_scope == SearchScope.mineMusic)
                                AnimatedBuilder(
                                  animation: _tabController,
                                  builder: (context, _) => SearchFilterChips(
                                    labels: _tabs,
                                    index: _tabController.index,
                                    accent: accent,
                                    onSelected: (index) {
                                      _tabController.animateTo(
                                        index,
                                        duration:
                                            const Duration(milliseconds: 260),
                                        curve: Curves.easeOutCubic,
                                      );
                                      if (_searchQuery.trim().isNotEmpty) {
                                        _performSearch(_searchQuery);
                                      } else {
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              // Floating glass search dock (standalone route only — embedded
              // mode types in the nav pill; the mini player owns this edge).
              if (!widget.embedded)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12 + MediaQuery.viewInsetsOf(context).bottom,
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        GlassCircleButton(
                          icon: Icons.home_outlined,
                          semanticLabel: 'Close search',
                          onTap: () {
                            _searchController.clear();
                            _dockFocusNode.unfocus();
                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SearchDockShell(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: TextField(
                                controller: _searchController,
                                focusNode: _dockFocusNode,
                                style: AppFont.style(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500),
                                cursorColor:
                                    Theme.of(context).colorScheme.primary,
                                decoration: InputDecoration(
                                  hintText: 'Search songs, artists...',
                                  hintStyle: AppFont.style(
                                      color:
                                          Colors.white.withValues(alpha: 0.45),
                                      fontWeight: FontWeight.w400),
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  prefixIcon: IconButton(
                                    icon: const Icon(Icons.search_outlined,
                                        color: Colors.white54, size: 22),
                                    onPressed: () {
                                      final q = _searchController.text.trim();
                                      if (q.isNotEmpty) {
                                        _commitSearch(q);
                                        _dockFocusNode.unfocus();
                                      }
                                    },
                                  ),
                                  prefixIconConstraints: const BoxConstraints(
                                      minWidth: 44, minHeight: 44),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded,
                                              color: Colors.white54, size: 20),
                                          onPressed: () {
                                            _searchController.clear();
                                          },
                                        )
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 14.0, horizontal: 8.0),
                                ),
                                onSubmitted: _commitSearch,
                                textInputAction: TextInputAction.search,
                              ),
                            ),
                          ),
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

  void _addToHistory(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _recentSearches.removeWhere((e) =>
          e.kind == SearchHistoryKind.query &&
          e.id.toLowerCase() == trimmed.toLowerCase());
      _recentSearches.insert(0, SearchHistoryEntry.query(trimmed));
      if (_recentSearches.length > 10) _recentSearches.removeLast();
    });
    // Persist (dedupe/move-to-front handled by the store)
    _historyStore.addQuery(trimmed);
    try {
      final p = Provider.of<MusicProvider>(context, listen: false);
      p.rememberSearchQuery(trimmed);
    } catch (_) {}
  }

  /// Records the track that was just played from the results.
  ///
  /// Replaces the old behaviour, which recorded the *query* on any result tap -
  /// so the list could only ever echo words, with no artwork and nothing to tap
  /// back into. Recording the track is what makes a row carry a cover and play
  /// on demand. The query itself is still recorded by [_addToHistory] on submit,
  /// so searching is still remembered.
  void _recordPlayedTrack(Track track) {
    final entry = SearchHistoryEntry.track(
      id: track.id,
      title: track.trackName,
      artist: track.artistName,
      artworkUrl: track.albumArtUrl,
    );
    setState(() {
      _recentSearches
          .removeWhere((e) => e.id.toLowerCase() == entry.id.toLowerCase());
      _recentSearches.insert(0, entry);
      if (_recentSearches.length > 10) _recentSearches.removeLast();
    });
    _historyStore.addTrack(
      id: track.id,
      title: track.trackName,
      artist: track.artistName,
      artworkUrl: track.albumArtUrl,
    );
  }

  /// Tapping a recent-searches row.
  ///
  /// A track row plays the track again; a query row re-runs the search. The
  /// entry is deliberately *not* re-recorded here - tapping an existing row
  /// should not bump it to the top, which is why the row's own timestamp is
  /// only ever set when the thing was first played or searched.
  void _onHistoryEntryTapped(SearchHistoryEntry entry) {
    if (entry.kind == SearchHistoryKind.query) {
      _commitSearch(entry.title);
      return;
    }
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    musicProvider.playTrack(
      Track(
        id: entry.id,
        trackName: entry.title,
        artistName: entry.subtitle,
        albumName: '',
        previewUrl: '',
        albumArtUrl: entry.artworkUrl,
      ),
    );
  }

  bool _showsLoading(MusicProvider p, SearchKind kind, String query) =>
      p.searchPhase == SearchPhase.loading &&
      p.activeSearchKind == kind &&
      query.trim().isNotEmpty;

  bool _showsError(MusicProvider p, SearchKind kind) =>
      p.searchPhase == SearchPhase.error && p.activeSearchKind == kind;

  Widget _buildVideosTab(BuildContext context, String query) {
    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        final videos = provider.videoSearchResults;
        if (_showsLoading(provider, SearchKind.videos, query)) {
          return _SuggestionOrSpinner(
            query: query,
            isVideo: true,
            onSuggestionSelected: (q) => _commitSearch(q),
          );
        }
        if (_showsError(provider, SearchKind.videos)) {
          return _SearchErrorView(
            message: provider.errorMessage ?? 'Search failed.',
            onRetry: () => _commitSearch(query, forceRefresh: true),
          );
        }
        if (query.trim().isEmpty && videos.isEmpty) {
          return const _SearchIdleView(
            icon: Icons.play_circle_outline_rounded,
            message: 'Search for music videos',
          );
        }
        if (videos.isEmpty && query.trim().isNotEmpty) {
          return _SearchEmptyView(message: 'No videos found for "$query"');
        }
        return ListView.builder(
          key: ValueKey('videos:$query'),
          padding: EdgeInsets.fromLTRB(0, 8, 0, widget.embedded ? 100 : 170),
          physics: const BouncingScrollPhysics(),
          itemCount: videos.length,
          itemBuilder: (context, index) {
            final video = videos[index];
            final isPlaying = video.isSameTrackAs(provider.currentTrack) &&
                provider.isPlaying;
            return SearchResultRow.staged(
              key: ValueKey(video.id),
              index: index,
              track: video,
              isVideo: true,
              isPlaying: isPlaying,
              onTap: () {
                if (_searchQuery.trim().isNotEmpty) {
                  _addToHistory(_searchQuery.trim());
                }
                provider.playTrack(video, playlistTracks: videos);
              },
              onMore: () => ThemedOptionsSheet.show(context, track: video),
            );
          },
        );
      },
    );
  }

  Widget _buildAlbumsTab(BuildContext context, String query) {
    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        final albums = provider.albumSearchResults;
        if (_showsLoading(provider, SearchKind.albums, query)) {
          return _SuggestionOrSpinner(
            query: query,
            onSuggestionSelected: (q) => _commitSearch(q),
          );
        }
        if (_showsError(provider, SearchKind.albums)) {
          return _SearchErrorView(
            message: provider.errorMessage ?? 'Search failed.',
            onRetry: () => _commitSearch(query, forceRefresh: true),
          );
        }
        if (query.trim().isEmpty && albums.isEmpty) {
          return const _SearchIdleView(
            icon: Icons.album_outlined,
            message: 'Search for albums',
          );
        }
        if (albums.isEmpty && query.trim().isNotEmpty) {
          return _SearchEmptyView(message: 'No albums found for "$query"');
        }
        return GridView.builder(
          key: ValueKey('albums:$query'),
          padding: EdgeInsets.fromLTRB(16, 12, 16, widget.embedded ? 100 : 170),
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.77,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return SearchMediaGridCard(
              key: ValueKey(album.id),
              index: index,
              track: album,
              subtitle:
                  album.artistName.isNotEmpty ? album.artistName : 'Album',
              onTap: () {
                if (_searchQuery.trim().isNotEmpty) {
                  _addToHistory(_searchQuery.trim());
                }
                _openAlbumResult(album);
              },
              onLongPress: () => ThemedOptionsSheet.show(context, track: album),
            );
          },
        );
      },
    );
  }

  Widget _buildArtistsTab(BuildContext context, String query) {
    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        if (_showsLoading(provider, SearchKind.artists, query)) {
          return _SuggestionOrSpinner(
            query: query,
            circular: true,
            onSuggestionSelected: (q) => _commitSearch(q),
          );
        }

        if (_showsError(provider, SearchKind.artists)) {
          return _SearchErrorView(
            message: provider.errorMessage ?? 'Search failed.',
            onRetry: () => _commitSearch(query, forceRefresh: true),
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

        // In Artist Search Results:
        // track.trackName = Artist Name (e.g. "The Weeknd")
        // track.artistName = Subtitle/Description (e.g. "Artist • 269M...")
        final artists = provider.artistTracks;

        return GridView.builder(
          key: ValueKey('artists:$query'),
          padding: EdgeInsets.fromLTRB(16, 14, 16, widget.embedded ? 100 : 170),
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.77,
            crossAxisSpacing: 16,
            mainAxisSpacing: 20,
          ),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artistTrack = artists[index];
            final artistName = artistTrack.trackName;

            return SearchArtistGridCard(
              key: ValueKey(artistTrack.id),
              index: index,
              artistName: artistName,
              artistImageUrl: artistTrack.albumArtUrl,
              subtitle: 'Artist',
              onTap: () {
                if (_searchQuery.trim().isNotEmpty) {
                  _addToHistory(_searchQuery.trim());
                }
                final screen = ThemedArtistDetailScreen(
                  artistId: artistTrack.id,
                  artistName: artistName,
                  artistImage: artistTrack.albumArtUrl,
                );
                _pushDetail(screen);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistsTab(BuildContext context, String query) {
    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        if (_showsLoading(provider, SearchKind.playlists, query)) {
          return _SuggestionOrSpinner(
            query: query,
            onSuggestionSelected: (q) => _commitSearch(q),
          );
        }

        if (_showsError(provider, SearchKind.playlists)) {
          return _SearchErrorView(
            message: provider.errorMessage ?? 'Search failed.',
            onRetry: () => _commitSearch(query, forceRefresh: true),
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

        return GridView.builder(
          key: ValueKey('playlists:$query'),
          padding: EdgeInsets.fromLTRB(16, 12, 16, widget.embedded ? 100 : 170),
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.77,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
          ),
          itemCount: provider.playlistSearchResults.length,
          itemBuilder: (context, index) {
            final playlist = provider.playlistSearchResults[index];
            return SearchMediaGridCard(
              key: ValueKey(playlist.id),
              index: index,
              track: playlist,
              subtitle: 'Playlist',
              onTap: () {
                if (_searchQuery.trim().isNotEmpty) {
                  _addToHistory(_searchQuery.trim());
                }
                _pushDetail(ThemedPlaylistDetailScreen(
                  playlistId: playlist.id,
                  playlistName: playlist.trackName,
                  playlistImage: playlist.albumArtUrl,
                ));
              },
              onLongPress: () =>
                  ThemedOptionsSheet.show(context, track: playlist),
            );
          },
        );
      },
    );
  }
}

/// On-device library scope: local tracks + user playlists, same row language.
class _LibraryScopeBody extends StatelessWidget {
  final String query;
  final void Function(Widget screen) onPushDetail;

  const _LibraryScopeBody(
      {super.key, required this.query, required this.onPushDetail});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        final q = query.trim().toLowerCase();
        if (q.isEmpty) {
          return const _SearchIdleView(
            icon: Icons.library_music_outlined,
            message: 'Search your downloads and playlists',
          );
        }
        final tracks = provider.localTracks
            .where((t) =>
                t.trackName.toLowerCase().contains(q) ||
                t.artistName.toLowerCase().contains(q) ||
                t.albumName.toLowerCase().contains(q))
            .toList();
        final playlists = provider.userPlaylists
            .where((p) => p.name.toLowerCase().contains(q))
            .toList();
        if (tracks.isEmpty && playlists.isEmpty) {
          return _SearchEmptyView(
              message: 'Nothing in your library for "$query"');
        }
        return ListView.builder(
          key: ValueKey('library:$q'),
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
          physics: const BouncingScrollPhysics(),
          itemCount: tracks.length + playlists.length,
          itemBuilder: (context, index) {
            if (index < playlists.length) {
              final playlist = playlists[index];
              return SearchResultRow.staged(
                key: ValueKey('lib-pl:${playlist.id}'),
                index: index,
                track: Track(
                  id: playlist.id,
                  trackName: playlist.name,
                  artistName: '',
                  albumName: '',
                  previewUrl: '',
                  albumArt: playlist.imageUrl,
                  source: 'local',
                  durationMs: 0,
                ),
                subtitle: 'Playlist • ${playlist.tracks.length} tracks',
                onTap: () => onPushDetail(ThemedPlaylistDetailScreen(
                  playlistId: playlist.id,
                  playlistName: playlist.name,
                  playlistImage: playlist.imageUrl,
                  cachedTracks: playlist.tracks,
                )),
              );
            }
            final track = tracks[index - playlists.length];
            final isPlaying = track.isSameTrackAs(provider.currentTrack) &&
                provider.isPlaying;
            return SearchResultRow.staged(
              key: ValueKey('lib-tr:${track.id}'),
              index: index,
              track: track,
              isPlaying: isPlaying,
              onTap: () => provider.playTrack(track, playlistTracks: tracks),
              onMore: () => ThemedOptionsSheet.show(context, track: track),
            );
          },
        );
      },
    );
  }
}

/// Loading state with typeahead: suggestion rows when available (BitChord
/// suggest parity — first row echoes the typed query), spinner otherwise.
class _SuggestionOrSpinner extends StatelessWidget {
  final String query;
  final ValueChanged<String> onSuggestionSelected;
  final bool circular;
  final bool isVideo;

  const _SuggestionOrSpinner({
    required this.query,
    required this.onSuggestionSelected,
    this.circular = false,
    this.isVideo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        final suggestions = provider.searchSuggestions;
        if (suggestions.isEmpty) {
          return _SearchLoadingView(
            circular: circular,
            isVideo: isVideo,
          );
        }
        final trimmed = query.trim();
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          physics: const BouncingScrollPhysics(),
          itemCount: suggestions.length + 1,
          itemBuilder: (context, index) {
            final term = index == 0 ? trimmed : suggestions[index - 1];
            final isTypedRow = index == 0;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSuggestionSelected(term),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20.0, vertical: 12.0),
                  child: Row(
                    children: [
                      Icon(
                        isTypedRow
                            ? Icons.search_outlined
                            : Icons.north_west_rounded,
                        color: Colors.white.withValues(alpha: 0.45),
                        size: 20,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          isTypedRow ? 'Search "$term"' : term,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFont.style(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 15,
                            fontWeight:
                                isTypedRow ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class SearchTabContent extends StatelessWidget {
  final List<SearchHistoryEntry> recentSearches;
  final ValueChanged<SearchHistoryEntry> onEntryTapped;
  final VoidCallback onClearHistory;
  final ValueChanged<String> onRemoveHistoryItem;
  final VoidCallback onRetry;
  final ValueChanged<String> onSuggestionSelected;
  final void Function(Track track)? onResultTapped;

  const SearchTabContent({
    super.key,
    this.recentSearches = const [],
    required this.onEntryTapped,
    required this.onClearHistory,
    required this.onRemoveHistoryItem,
    required this.onRetry,
    required this.onSuggestionSelected,
    this.onResultTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final searchResults = musicProvider.searchedTracks;
        final phase = musicProvider.searchPhase;
        final kindMatches = musicProvider.activeSearchKind == SearchKind.songs;
        final activeQuery = musicProvider.activeSearchQuery;

        // A session for another kind (e.g. user flipped chips mid-flight):
        // show this kind's cached results, never another kind's spinner.
        if (phase == SearchPhase.loading && !kindMatches) {
          if (searchResults.isEmpty) {
            return const _SearchIdleView(
              icon: Icons.search_rounded,
              message: 'Search for tracks, artists, or albums.',
            );
          }
        } else {
          switch (phase) {
            case SearchPhase.loading:
              return _SuggestionOrSpinner(
                query: activeQuery,
                onSuggestionSelected: onSuggestionSelected,
              );

            case SearchPhase.error:
              if (kindMatches) {
                return _SearchErrorView(
                  message: musicProvider.errorMessage ??
                      "Couldn't complete the search.",
                  onRetry: onRetry,
                );
              }
              break;

            case SearchPhase.empty:
              if (kindMatches) {
                return _SearchEmptyView(
                    message: 'No results for "$activeQuery"');
              }
              break;

            case SearchPhase.idle:
              break;

            case SearchPhase.results:
              break;
          }
        }

        if (searchResults.isNotEmpty) {
          return ListView.builder(
            key: ValueKey('songs:$activeQuery'),
            padding: EdgeInsets.fromLTRB(
                0, 8, 0, 100 + MediaQuery.viewInsetsOf(context).bottom),
            physics: const BouncingScrollPhysics(),
            itemCount: searchResults.length,
            itemBuilder: (context, index) {
              final track = searchResults[index];
              final isPlaying = musicProvider.currentTrack?.id == track.id &&
                  musicProvider.isPlaying;

              return SearchResultRow.staged(
                key: ValueKey(track.id),
                index: index,
                track: track,
                isPlaying: isPlaying,
                onTap: () {
                  onResultTapped?.call(track);
                  musicProvider.playTrack(track, playlistTracks: searchResults);
                },
                onMore: () => ThemedOptionsSheet.show(context, track: track),
              );
            },
          );
        }

        // Idle: history if available; otherwise the quiet discovery hint.
        if (recentSearches.isNotEmpty) {
          return ListView(
            // Vertical only, deliberately. This used to be EdgeInsets.all(16)
            // on top of each row's own 16dp horizontal padding, so every
            // history row was indented a full gutter further than the result
            // rows directly above it and the header sat at a third position
            // again. The row owns its gutter, exactly as SearchResultRow does,
            // so history and results now share one left edge.
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 8.0, 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Recent Searches",
                      style: AppFont.style(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18),
                    ),
                    TextButton(
                      onPressed: onClearHistory,
                      child: Text("Clear All",
                          style: AppFont.style(
                              color: Theme.of(context).colorScheme.primary)),
                    ),
                  ],
                ),
              ),
              ...recentSearches.map((entry) => _RecentSearchRow(
                    entry: entry,
                    onTap: () => onEntryTapped(entry),
                    onRemove: () => onRemoveHistoryItem(entry.id),
                  )),
            ],
          );
        }
        return const _SearchIdleView(
          icon: Icons.search_rounded,
          message: 'Search for tracks, artists, or albums.',
        );
      },
    );
  }
}

/// Quiet, shared search-state views. One visual language: icon + one line,
/// no cards, no decoration.

/// The wireframe shown while a search is in flight and no typeahead has arrived
/// yet.
///
/// Was a centred 22dp spinner, which said "something is happening" and nothing
/// about what was coming back. A skeleton says both: it shows the shape of the
/// answer, and because the placeholders are metric-matched to the real rows,
/// the list does not jump when the results land.
///
/// The shape follows the tab - a circle for artists, a 16:9 tile for videos -
/// so switching tabs mid-search does not show square tiles for rows that are
/// about to be circular.
class _SearchLoadingView extends StatelessWidget {
  final bool circular;
  final bool isVideo;

  const _SearchLoadingView({this.circular = false, this.isVideo = false});

  @override
  Widget build(BuildContext context) {
    return SearchSkeletonList(
      circular: circular,
      isVideo: isVideo,
      bottomInset: MediaQuery.viewInsetsOf(context).bottom,
    );
  }
}

/// One "Recent searches" row.
///
/// Laid out to the same metrics as a [SearchResultRow] - 64dp artwork at radius
/// 12, a 14dp gap, the same type sizes - so the list reads as one continuous
/// set of rows whether it is showing history or results, and the transition
/// between the two states has nothing to jump.
///
/// A track entry shows its cover. A query entry has nothing to show, so it falls
/// back to the clock glyph rather than an empty box: an empty 64dp square reads
/// as a failed image load, not as "this one is text".
class _RecentSearchRow extends StatelessWidget {
  final SearchHistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentSearchRow({
    required this.entry,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // Left 16 to match SearchResultRow's gutter; 8 at the end so the
          // remove button's 48dp target stops short of the screen edge instead
          // of centring its 18dp glyph on it.
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 8.0, 8.0),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: entry.hasArtwork
                      ? Image.network(
                          entry.artworkUrl,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          cacheWidth:
                              (64 * MediaQuery.of(context).devicePixelRatio)
                                  .round(),
                          cacheHeight:
                              (64 * MediaQuery.of(context).devicePixelRatio)
                                  .round(),
                          errorBuilder: (_, __, ___) => const _QueryGlyphBox(),
                        )
                      : const _QueryGlyphBox(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.style(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (entry.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: Colors.white30),
                splashRadius: 18,
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The stand-in for a query row's leading slot.
class _QueryGlyphBox extends StatelessWidget {
  const _QueryGlyphBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.06),
      child: const Center(
        child: Icon(Icons.history_rounded, size: 22, color: Colors.white38),
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
            style: AppFont.style(
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
              style: AppFont.style(
                  color: Colors.white.withValues(alpha: 0.65), fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different search.',
              style: AppFont.style(
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
              style: AppFont.style(
                  color: Colors.white.withValues(alpha: 0.65), fontSize: 15),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Try again',
                  style: AppFont.style(
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
