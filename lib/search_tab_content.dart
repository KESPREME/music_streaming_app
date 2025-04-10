// lib/search_tab_content.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Import Provider
import '../models/track.dart';
import '../providers/music_provider.dart'; // Import MusicProvider
import '../services/api_service.dart'; // Keep ApiService for now
import '../widgets/track_tile.dart'; // Import standard TrackTile

class SearchTabContent extends StatefulWidget {
  const SearchTabContent({super.key});

  @override
  State<SearchTabContent> createState() => _SearchTabContentState();
}

class _SearchTabContentState extends State<SearchTabContent> {
  final TextEditingController _searchController = TextEditingController();
  List<Track> _searchResults = [];
  bool _isLoading = false;
  String? _errorMessage;
  // Keep track of the last successful query for context if needed
  String _lastQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- Recommendation: Move search logic to MusicProvider ---
  // This keeps UI layer cleaner and centralizes data fetching.
  // Provider could hold searchResults, searchLoading, searchError states.
  Future<void> _searchTracks(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      setState(() {
        _searchResults = [];
        _errorMessage = null;
        _isLoading = false;
        _lastQuery = '';
      });
      return;
    }

    // Avoid searching again for the same query if already showing results
    if (trimmedQuery == _lastQuery && _searchResults.isNotEmpty && !_isLoading) {
      return;
    }


    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _lastQuery = trimmedQuery; // Store the query being searched
    });

    try {
      // Creates a new instance every time - see previous recommendation
      final apiService = ApiService();
      final results = await apiService.fetchTracksByQuery(trimmedQuery);
      // Check if the current query is still the one we initiated the search for
      if (_lastQuery == trimmedQuery) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Check if the current query is still the one that failed
      if (_lastQuery == trimmedQuery) {
        setState(() {
          _errorMessage = 'Search failed: ${e.toString()}';
          _searchResults = []; // Clear results on error
          _isLoading = false;
        });
      }
      print("Search error for '$trimmedQuery': $e"); // Log error
    }
  }
  // --- End Recommendation Comment ---

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search input field
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search tracks, artists, albums...', // Broader hint text
              hintStyle: TextStyle(color: Colors.grey[400]),
              filled: true,
              fillColor: Colors.grey[850],
              prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, color: Colors.white70),
                tooltip: "Clear",
                onPressed: () {
                  _searchController.clear();
                  // Clear results when manually cleared
                  setState(() {
                    _searchResults = [];
                    _errorMessage = null;
                    _isLoading = false;
                    _lastQuery = '';
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14.0),
            ),
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.search,
            onSubmitted: _searchTracks, // Call search on submit
            // Optionally search as user types (debounced)
            // onChanged: (value) { /* Implement debouncing logic here */ },
          ),
          const SizedBox(height: 20),

          // Search Results Area
          Expanded(
            child: _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  // Builds the results list or messages
  Widget _buildSearchResults() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding( // Add padding around error
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 15),
          ),
        ),
      );
    }

    // Use _lastQuery to differentiate between initial state and no results found
    if (_lastQuery.isEmpty && _searchResults.isEmpty) {
      return const Center(
        child: Text('Enter a search term to find music.', style: TextStyle(color: Colors.white70)),
      );
    }


    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'No results found for "$_lastQuery"', // Show query in message
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
      );
    }

    // Get provider for isPlaying state inside the builder
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final track = _searchResults[index];
        final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;

        // Use the standard TrackTile - removed allowRemove
        return TrackTile(
          track: track,
          isPlaying: isPlaying,
          // Override onTap if you want to set the search results as the playback context
          // onTap: () => musicProvider.playTrack(track, playlistTracks: _searchResults),
        );
      },
    );
  }
}