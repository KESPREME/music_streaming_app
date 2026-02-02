import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../widgets/material_you_filter_chip.dart';
import '../widgets/material_you_elevated_card.dart';
import '../widgets/material_you_options_sheet.dart';
import '../theme/material_you_typography.dart';
import '../theme/material_you_tokens.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/themed_playlist_detail_screen.dart';

/// Material You Search Screen - COMPLETELY DIFFERENT from glassmorphism
/// Features:
/// - Rounded search bar (28dp corners)
/// - Material 3 filter chips below search
/// - Recent searches section
/// - List items with proper spacing
/// - Circular artist images
/// - 3-dot menus
class MaterialYouSearchScreen extends StatefulWidget {
  const MaterialYouSearchScreen({super.key});

  @override
  State<MaterialYouSearchScreen> createState() => _MaterialYouSearchScreenState();
}

class _MaterialYouSearchScreenState extends State<MaterialYouSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _selectedFilter = "Songs";
  Timer? _debounce;
  final List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        final newQuery = _searchController.text;
        final bool isSameQuery = newQuery == _searchQuery;
        setState(() {
          _searchQuery = newQuery;
        });
        if (_searchQuery.isNotEmpty) {
          _performSearch(_searchQuery, forceRefresh: isSameQuery);
          // Add to recent searches
          if (!_recentSearches.contains(_searchQuery)) {
            setState(() {
              _recentSearches.insert(0, _searchQuery);
              if (_recentSearches.length > 5) {
                _recentSearches.removeLast();
              }
            });
          }
        } else {
          Provider.of<MusicProvider>(context, listen: false).clearSearchResults();
        }
      }
    });
  }

  void _performSearch(String query, {bool forceRefresh = false}) {
    if (query.trim().isEmpty) return;
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    
    switch (_selectedFilter) {
      case "Songs":
        musicProvider.searchTracks(query, forceRefresh: forceRefresh);
        break;
      case "Artists":
        musicProvider.fetchArtistTracks(query);
        break;
      case "Albums":
        // TODO: Implement album search
        musicProvider.searchTracks(query, forceRefresh: forceRefresh);
        break;
      case "Playlists":
        musicProvider.searchPlaylists(query);
        break;
      default: // "All"
        musicProvider.searchTracks(query, forceRefresh: forceRefresh);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar - Rounded (28dp corners)
            _buildSearchBar(colorScheme),
            
            // Filter Chips
            _buildFilterChips(colorScheme),
            
            // Content
            Expanded(
              child: _searchQuery.isEmpty
                  ? _buildEmptyState(colorScheme)
                  : _buildSearchResults(colorScheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Material(
        elevation: 2,
        surfaceTintColor: Colors.transparent, // FIX: No white tint
        color: colorScheme.surfaceContainerHighest ?? colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(28), // Highly rounded
        child: TextField(
          controller: _searchController,
          style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Search songs, artists, albums...',
            hintStyle: MaterialYouTypography.bodyLarge(
              colorScheme.onSurfaceVariant.withOpacity(0.6),
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: colorScheme.onSurfaceVariant,
              size: 28,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.clear_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = "";
                      });
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 20,
            ),
          ),
          onSubmitted: (query) {
            _debounce?.cancel();
            if (query != _searchQuery) {
              setState(() => _searchQuery = query);
            }
            _performSearch(query);
          },
          textInputAction: TextInputAction.search,
        ),
      ),
    );
  }

  Widget _buildFilterChips(ColorScheme colorScheme) {
    // Reduced options to match Glass UI as requested
    final filters = ["Songs", "Artists", "Playlists"]; // "All" removed to focus on "Songs" as default
    
    return MaterialYouFilterChipList(
      options: filters,
      selectedOption: _selectedFilter,
      onSelected: (filter) {
        setState(() {
          _selectedFilter = filter;
        });
        if (_searchQuery.isNotEmpty) {
          _performSearch(_searchQuery);
        }
      },
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Recent Searches
        if (_recentSearches.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Searches',
                style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _recentSearches.clear();
                  });
                },
                child: Text(
                  'Clear All',
                  style: MaterialYouTypography.labelLarge(colorScheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._recentSearches.map((search) {
            return MaterialYouElevatedCard(
              elevation: 1,
              borderRadius: 12,
              onTap: () {
                _searchController.text = search;
                _performSearch(search);
              },
              onLongPress: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: colorScheme.surfaceContainer,
                    title: Text("Remove from history?", style: TextStyle(color: colorScheme.onSurface)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: TextStyle(color: colorScheme.onSurfaceVariant))),
                      TextButton(onPressed: () {
                        setState(() {
                          _recentSearches.remove(search);
                        });
                        Navigator.pop(context);
                      }, child: Text("Remove", style: TextStyle(color: colorScheme.error))),
                    ],
                  ),
                );
              },
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      search,
                      style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
                    ),
                  ),
                  Icon(
                    Icons.north_west_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 32),
        ],
        
        // Empty state illustration
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_rounded,
                size: 80,
                color: colorScheme.onSurfaceVariant.withOpacity(0.3),
              ),
              const SizedBox(height: 24),
              Text(
                'Search for music',
                style: MaterialYouTypography.headlineMedium(colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'Find your favorite songs, artists, and albums',
                style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(ColorScheme colorScheme) {
    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        List<dynamic> results = [];
        
        switch (_selectedFilter) {
          case "Songs":
          case "All":
            results = provider.searchedTracks;
            break;
          case "Artists":
            results = provider.artistTracks;
            break;
          case "Playlists":
            results = provider.playlistSearchResults;
            break;
          default:
            results = provider.searchedTracks;
        }

        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 60,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No results found',
                  style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try searching for something else',
                  style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          itemCount: results.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = results[index];
            
            if (_selectedFilter == "Artists") {
              return _buildArtistItem(item, provider, colorScheme);
            } else if (_selectedFilter == "Playlists") {
              return _buildPlaylistItem(item, provider, colorScheme);
            } else {
              return _buildTrackItem(item as Track, provider, colorScheme);
            }
          },
        );
      },
    );
  }

  Widget _buildTrackItem(Track track, MusicProvider provider, ColorScheme colorScheme) {
    return MaterialYouListCard(
      imageUrl: track.albumArtUrl,
      title: track.trackName,
      subtitle: track.artistName,
      onTap: () => provider.playTrack(track, playlistTracks: provider.searchedTracks),
      trailing: IconButton(
        icon: Icon(
          Icons.more_vert_rounded,
          color: colorScheme.onSurfaceVariant,
        ),
        onPressed: () {
          MaterialYouOptionsSheet.show(context, track: track);
        },
      ),
    );
  }

  Widget _buildArtistItem(dynamic artistTrack, MusicProvider provider, ColorScheme colorScheme) {
    final artistName = artistTrack.trackName;
    final artistImageUrl = artistTrack.albumArtUrl;
    
    return MaterialYouListCard(
      imageUrl: artistImageUrl,
      title: artistName,
      subtitle: 'Artist',
      isCircle: true,
      onTap: () {
        provider.navigateToArtistObject(artistTrack);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ThemedArtistDetailScreen(
              artistId: artistTrack.id,
              artistName: artistName,
            ),
          ),
        );
      },
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildPlaylistItem(dynamic playlist, MusicProvider provider, ColorScheme colorScheme) {
    return MaterialYouListCard(
      imageUrl: playlist.albumArtUrl ?? '',
      title: playlist.trackName,
      subtitle: 'Playlist',
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ThemedPlaylistDetailScreen(
              playlistId: playlist.id,
              playlistName: playlist.trackName,
            ),
          ),
        );
      },
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
