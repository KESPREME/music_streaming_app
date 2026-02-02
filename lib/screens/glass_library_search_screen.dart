import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../providers/theme_provider.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../widgets/track_tile.dart';
import '../widgets/themed_playlist_detail_screen.dart';

class GlassLibrarySearchScreen extends StatefulWidget {
  const GlassLibrarySearchScreen({super.key});

  @override
  State<GlassLibrarySearchScreen> createState() => _GlassLibrarySearchScreenState();
}

class _GlassLibrarySearchScreenState extends State<GlassLibrarySearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _searchQuery = "";
  final List<String> _recentSearches = []; // Local history for this session
  
  List<Track> _filteredTracks = [];
  List<Playlist> _filteredPlaylists = [];

  @override
  void initState() {
    super.initState();
    // Auto-focus the search bar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
    
    if (query.isNotEmpty) {
      _performLocalSearch(query);
    }
  }

  void _performLocalSearch(String query) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final lowerQuery = query.toLowerCase();

    // 1. Search Playlists
    final allPlaylists = musicProvider.userPlaylists;
    _filteredPlaylists = allPlaylists.where((p) => 
        p.name.toLowerCase().contains(lowerQuery)
    ).toList();

    // 2. Search Downloaded Tracks (Async in provider, but might be cached? 
    // If not cached, we might miss them. Ideally we should fetch them.
    // simpler to search Recently Played for now + maybe Downloads if loaded)
    // Let's search Recently Played as a proxy for "Songs" the user cares about instantly.
    // For a Full Library Search, we'd need to fetch all downloads.
    
    final recentTracks = musicProvider.recentlyPlayed;
    // Also add Liked songs if available in provider? 
    // musicProvider.likedTracks? (Check if exists)
    
    // Combining sources (avoiding duplicates by ID)
    final Set<String> trackIds = {};
    final List<Track> combinedTracks = [];
    
    for (var track in recentTracks) {
        if (trackIds.contains(track.id)) continue;
        if (track.trackName.toLowerCase().contains(lowerQuery) || 
            track.artistName.toLowerCase().contains(lowerQuery)) {
            combinedTracks.add(track);
            trackIds.add(track.id);
        }
    }

    _filteredTracks = combinedTracks;
  }
  
  void _addToHistory(String query) {
      if (!_recentSearches.contains(query)) {
          setState(() {
              _recentSearches.insert(0, query);
              if (_recentSearches.length > 5) _recentSearches.removeLast();
          });
      }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent, // Important for glass effect if stacked
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
          child: Column(
            children: [
              _buildSearchBar(isDark),
              Expanded(
                child: _searchQuery.isEmpty 
                    ? _buildHistory(isDark)
                    : _buildResults(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
            IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : Colors.black),
                onPressed: () => Navigator.pop(context),
            ),
            Expanded(
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
                            ),
                            child: TextField(
                                controller: _searchController,
                                focusNode: _focusNode,
                                style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black),
                                decoration: InputDecoration(
                                    hintText: "Search in Library...",
                                    hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                                    border: InputBorder.none,
                                    prefixIcon: Icon(Icons.search_rounded, color: isDark ? Colors.white54 : Colors.black54),
                                    suffixIcon: _searchQuery.isNotEmpty 
                                        ? IconButton(
                                            icon: Icon(Icons.close_rounded, color: isDark ? Colors.white54 : Colors.black54),
                                            onPressed: () {
                                                _searchController.clear();
                                                _onSearchChanged("");
                                            },
                                        ) 
                                        : null,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onChanged: _onSearchChanged,
                                onSubmitted: (val) {
                                    if (val.trim().isNotEmpty) {
                                        _addToHistory(val.trim());
                                    }
                                },
                            ),
                        ),
                    ),
                ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistory(bool isDark) {
      if (_recentSearches.isEmpty) {
          return Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                      Icon(Icons.history_rounded, size: 60, color: isDark ? Colors.white10 : Colors.black12),
                      const SizedBox(height: 16),
                      Text(
                          "Search your playlists and songs",
                          style: GoogleFonts.splineSans(color: isDark ? Colors.white54 : Colors.black54, fontSize: 16),
                      ),
                  ],
              ),
          );
      }
      return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _recentSearches.length,
          itemBuilder: (context, index) {
              final query = _recentSearches[index];
              return ListTile(
                  leading: Icon(Icons.history_rounded, color: isDark ? Colors.white54 : Colors.black54),
                  title: Text(query, style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black)),
                  onTap: () {
                      _searchController.text = query;
                      _onSearchChanged(query);
                  },
                  trailing: IconButton(
                      icon: Icon(Icons.close_rounded, size: 18, color: isDark ? Colors.white30 : Colors.black26),
                      onPressed: () {
                          setState(() {
                              _recentSearches.removeAt(index);
                          });
                      },
                  ),
              );
          },
      );
  }

  Widget _buildResults(bool isDark) {
      if (_filteredPlaylists.isEmpty && _filteredTracks.isEmpty) {
          return Center(
              child: Text("No library results found", style: GoogleFonts.splineSans(color: isDark ? Colors.white54 : Colors.black54)),
          );
      }
      
      return ListView(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(),
          children: [
              if (_filteredPlaylists.isNotEmpty) ...[
                  Text("Playlists", style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 10),
                  ..._filteredPlaylists.map((playlist) => _buildPlaylistTile(playlist, isDark)),
                  const SizedBox(height: 20),
              ],
              
              if (_filteredTracks.isNotEmpty) ...[
                  Text("Songs (Recently Played)", style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 10),
                  ..._filteredTracks.map((track) {
                      final musicProvider = Provider.of<MusicProvider>(context, listen: false);
                      return TrackTile(
                          track: track,
                          isPlaying: false, // Don't track playing state strictly here to avoid excessive rebuilds or complex logic
                          onTap: () => musicProvider.playTrack(track, playlistTracks: _filteredTracks),
                      );
                  }),
              ]
          ],
      );
  }

  Widget _buildPlaylistTile(Playlist playlist, bool isDark) {
      return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: playlist.imageUrl.isNotEmpty 
                ? Image.network(playlist.imageUrl, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: Colors.grey[800], child: const Icon(Icons.music_note)))
                : Container(color: Colors.grey[800], width: 50, height: 50, child: const Icon(Icons.music_note)),
          ),
          title: Text(playlist.name, style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black)),
          subtitle: Text("${playlist.tracks.length} tracks", style: GoogleFonts.splineSans(color: isDark ? Colors.white54 : Colors.black54)),
          onTap: () {
             Navigator.push(
               context,
               MaterialPageRoute(
                 builder: (_) => ThemedPlaylistDetailScreen(
                   playlistId: playlist.id,
                   playlistName: playlist.name,
                   playlistImage: playlist.imageUrl,
                   cachedTracks: playlist.tracks,
                 ),
               ),
             );
          },
      );
  }
}
