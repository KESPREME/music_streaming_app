import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // Import fonts
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart';

class SearchTabContent extends StatelessWidget {
  final List<String> recentSearches;
  final Function(String) onSearchSelected;
  final VoidCallback onClearHistory;
  final Function(String) onRemoveHistoryItem;

  const SearchTabContent({
    super.key,
    this.recentSearches = const [],
    required this.onSearchSelected,
    required this.onClearHistory,
    required this.onRemoveHistoryItem,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final searchResults = musicProvider.searchedTracks;

        if (searchResults.isEmpty) {
            // Show History if available
            if (recentSearches.isNotEmpty) {
                 return ListView(
                   padding: const EdgeInsets.all(16),
                   children: [

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                           Text(
                             "Recent Searches",
                             style: GoogleFonts.splineSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                           ),
                           TextButton(
                             onPressed: onClearHistory,
                             child: Text("Clear All", style: GoogleFonts.splineSans(color: const Color(0xFFFF1744))),
                           )
                        ],
                      ),
                      ...recentSearches.map((query) => ListTile(
                        leading: const Icon(Icons.history_rounded, color: Colors.white54),
                        title: Text(query, style: GoogleFonts.splineSans(color: Colors.white)),
                        onTap: () => onSearchSelected(query),
                        onLongPress: () {
                             showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: const Color(0xFF1E1E1E), // Dark background for Glass UI
                                title: const Text("Remove from history?", style: TextStyle(color: Colors.white)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
                                  TextButton(onPressed: () {
                                    onRemoveHistoryItem(query);
                                    Navigator.pop(context);
                                  }, child: const Text("Remove", style: TextStyle(color: Color(0xFFFF1744)))),
                                ],
                              ),
                            );
                        },
                      )).toList(),
                   ],
                 );
            }

          return Center(
            child: Text(
              'Search for tracks, artists, or albums.', // Updated to match screenshot
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6)),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          itemExtent: 72.0, 
          itemCount: searchResults.length,
          itemBuilder: (context, index) {
            final track = searchResults[index];
            final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;

            return TrackTile(
              track: track,
              isPlaying: isPlaying,
              onTap: () {
                musicProvider.playTrack(track, playlistTracks: searchResults);
              },
            );
          },
        );
      },
    );
  }
}