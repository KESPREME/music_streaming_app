import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../widgets/material_you_elevated_card.dart';
import '../widgets/themed_playlist_detail_screen.dart';
import '../theme/material_you_typography.dart';
import '../theme/material_you_tokens.dart';

class MaterialYouLocalSearchScreen extends StatefulWidget {
  const MaterialYouLocalSearchScreen({super.key});

  @override
  State<MaterialYouLocalSearchScreen> createState() => _MaterialYouLocalSearchScreenState();
}

class _MaterialYouLocalSearchScreenState extends State<MaterialYouLocalSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _searchQuery = "";
  final List<String> _recentSearches = []; 
  
  List<Track> _filteredTracks = [];
  List<Playlist> _filteredPlaylists = [];

  @override
  void initState() {
    super.initState();
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

    final allPlaylists = musicProvider.userPlaylists;
    _filteredPlaylists = allPlaylists.where((p) => 
        p.name.toLowerCase().contains(lowerQuery)
    ).toList();
    
    final recentTracks = musicProvider.recentlyPlayed;
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(colorScheme),
            Expanded(
              child: _searchQuery.isEmpty 
                  ? _buildHistory(colorScheme)
                  : _buildResults(colorScheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
            IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
                onPressed: () => Navigator.pop(context),
            ),
            Expanded(
                child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                        color: MaterialYouTokens.surfaceContainerHighestDark,
                        borderRadius: BorderRadius.circular(28),
                    ),
                    child: TextField(
                        controller: _searchController,
                        focusNode: _focusNode,
                        style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
                        decoration: InputDecoration(
                            hintText: "Search in Library...",
                            hintStyle: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant.withOpacity(0.7)),
                            border: InputBorder.none,
                            prefixIcon: Icon(Icons.search_rounded, color: colorScheme.onSurfaceVariant),
                            suffixIcon: _searchQuery.isNotEmpty 
                                ? IconButton(
                                    icon: Icon(Icons.close_rounded, color: colorScheme.onSurfaceVariant),
                                    onPressed: () {
                                        _searchController.clear();
                                        _onSearchChanged("");
                                    },
                                ) 
                                : null,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
        ],
      ),
    );
  }

  Widget _buildHistory(ColorScheme colorScheme) {
      if (_recentSearches.isEmpty) {
          return Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                      Icon(Icons.history_rounded, size: 60, color: colorScheme.onSurfaceVariant.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      Text(
                          "Search your playlists and songs",
                          style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
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
                  leading: Icon(Icons.history_rounded, color: colorScheme.onSurfaceVariant),
                  title: Text(query, style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
                  onTap: () {
                      _searchController.text = query;
                      _onSearchChanged(query);
                  },
                  trailing: IconButton(
                      icon: Icon(Icons.close_rounded, size: 18, color: colorScheme.onSurfaceVariant),
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

  Widget _buildResults(ColorScheme colorScheme) {
      if (_filteredPlaylists.isEmpty && _filteredTracks.isEmpty) {
          return Center(
              child: Text("No library results found", style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant)),
          );
      }
      
      return ListView(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(),
          children: [
              if (_filteredPlaylists.isNotEmpty) ...[
                  Text("Playlists", style: MaterialYouTypography.labelLarge(colorScheme.primary)),
                  const SizedBox(height: 10),
                  ..._filteredPlaylists.map((playlist) => _buildPlaylistTile(playlist, colorScheme)),
                  const SizedBox(height: 20),
              ],
              
              if (_filteredTracks.isNotEmpty) ...[
                   Text("Songs (Recently Played)", style: MaterialYouTypography.labelLarge(colorScheme.primary)),
                  const SizedBox(height: 10),
                  ..._filteredTracks.map((track) {
                      final musicProvider = Provider.of<MusicProvider>(context, listen: false);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: MaterialYouListCard(
                          imageUrl: track.albumArtUrl,
                          title: track.trackName,
                          subtitle: track.artistName,
                          onTap: () => musicProvider.playTrack(track, playlistTracks: _filteredTracks),
                        ),
                      );
                  }),
              ]
          ],
      );
  }

  Widget _buildPlaylistTile(Playlist playlist, ColorScheme colorScheme) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: MaterialYouListCard(
          imageUrl: playlist.imageUrl,
          title: playlist.name,
          subtitle: "${playlist.tracks.length} tracks",
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
        ),
      );
  }
}
