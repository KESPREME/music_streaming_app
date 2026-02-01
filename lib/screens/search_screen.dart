import 'dart:async'; 
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../providers/theme_provider.dart';
import '../search_tab_content.dart'; 
import '../models/track.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/themed_playlist_detail_screen.dart';

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
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
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
      color: colorScheme.surfaceContainerHighest ?? colorScheme.surfaceVariant,
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
                color: Colors.black.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: isGlass
                  ? const Color(0xFFFF1744).withOpacity(0.3)
                  : colorScheme.primary.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: CircleAvatar(
            radius: 30,
            backgroundColor: isGlass ? Colors.grey[850] : colorScheme.surfaceVariant,
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
                style: GoogleFonts.splineSans(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: isGlass ? Colors.white : colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "Artist",
                style: GoogleFonts.splineSans(
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
              : colorScheme.onSurfaceVariant.withOpacity(0.5),
        ),
      ],
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); 
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
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
        // FIX: Always trigger search if text is not empty
        // Use forceRefresh when searching same query again (user wants fresh results)
        final bool isSameQuery = newQuery == _searchQuery;
        setState(() {
          _searchQuery = newQuery;
        });
        if (_searchQuery.isNotEmpty) {
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
        musicProvider.fetchArtistTracks(query);
    } else if (_tabController.index == 2) {
        musicProvider.searchPlaylists(query);
    }
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
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent, // Fix purple tint
                elevation: 0,
                floating: true,
                pinned: true,
                toolbarHeight: 90, 
                flexibleSpace: ClipRRect( 
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), // Reduced to match "Liquid Pill"
                    child: Container(
                      color: Colors.black.withOpacity(0.5), // Unified tint, no gradient
                    ),
                  ),
                ),
                title: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.splineSans(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Search songs, artists...',
                      hintStyle: GoogleFonts.splineSans(color: Colors.white.withOpacity(0.4)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05), // Ultra-translucent glass
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)), // Subtle glass border
                      ),
                      enabledBorder: OutlineInputBorder( // Explicit border state
                         borderRadius: BorderRadius.circular(30),
                         borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide(color: const Color(0xFFFF1744).withOpacity(0.5), width: 1), // Accent on focus
                      ),
                      prefixIcon: const Icon(Icons.search, color: Colors.white54),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white54),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 20.0),
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
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(50),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2), // More subtle container
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.white.withOpacity(0.1)), // Sharper glass edge
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: const Color(0xFFFF1744).withOpacity(0.15), // Softer accent fill
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.3)), // Crisp accent border
                      ),
                      labelColor: const Color(0xFFFF1744),
                      unselectedLabelColor: Colors.white.withOpacity(0.5),
                      labelStyle: GoogleFonts.splineSans(fontWeight: FontWeight.bold),
                      unselectedLabelStyle: GoogleFonts.splineSans(fontWeight: FontWeight.w500),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Tracks'),
                        Tab(text: 'Artists'),
                        Tab(text: 'Playlists'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                const SearchTabContent(), // Needs similar glass update in its own file
                _buildArtistsTab(context, _searchQuery),
                _buildPlaylistsTab(context, _searchQuery),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtistsTab(BuildContext context, String query) {
    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        if (query.trim().isEmpty && provider.artistTracks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_search_outlined, size: 60, color: Colors.white.withOpacity(0.1)),
                const SizedBox(height: 16),
                Text(
                  'Search for your favorite artists',
                  style: GoogleFonts.splineSans(color: Colors.white.withOpacity(0.4), fontSize: 16),
                ),
              ],
            ),
          );
        }

        if (provider.artistTracks.isEmpty && query.trim().isNotEmpty) {
           return Center(
            child: Text(
              'No artists found.',
              style: GoogleFonts.splineSans(color: Colors.white.withOpacity(0.4)),
            ),
          );
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
            final artistDescription = artistTrack.artistName; // Subtitle info

            return ArtistSearchTile(
              artistName: artistName, 
              artistImageUrl: artistTrack.albumArtUrl,
              onTap: () {
                 // Use robust navigation
                 provider.navigateToArtistObject(artistTrack);
                 Navigator.push(
                   context,
                   MaterialPageRoute(
                     builder: (_) => ThemedArtistDetailScreen(
                       artistId: artistTrack.id,
                       artistName: artistName,
                       artistImage: artistTrack.albumArtUrl,
                     ),
                   ),
                 );
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
        if (query.trim().isEmpty && provider.playlistSearchResults.isEmpty) {
             return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.queue_music_rounded, size: 60, color: Colors.white.withOpacity(0.1)),
                const SizedBox(height: 16),
                Text(
                  'Search for playlists',
                  style: GoogleFonts.splineSans(color: Colors.white.withOpacity(0.4), fontSize: 16),
                ),
              ],
            ),
          );
        }
        
        if (provider.playlistSearchResults.isEmpty && query.trim().isNotEmpty) {
           return Center(
            child: Text(
              'No playlists found.',
              style: GoogleFonts.splineSans(color: Colors.white.withOpacity(0.4)),
            ),
          );
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
                style: GoogleFonts.splineSans(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Playlist • ${playlist.artistName}', // Owner/Artist
                style: GoogleFonts.splineSans(color: Colors.white54),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ThemedPlaylistDetailScreen(
                      playlistId: playlist.id,
                      playlistName: playlist.trackName,
                      playlistImage: playlist.albumArtUrl,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}