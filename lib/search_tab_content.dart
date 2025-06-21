// lib/search_tab_content.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Import Provider
import '../models/track.dart';
import '../providers/music_provider.dart'; // Import MusicProvider
import '../services/api_service.dart'; // Keep ApiService for now
import '../widgets/track_tile.dart';

class SearchTabContent extends StatefulWidget {
  final String searchQuery; // Accept search query as a parameter

  const SearchTabContent({required this.searchQuery, super.key});

  @override
  State<SearchTabContent> createState() => _SearchTabContentState();
}

class _SearchTabContentState extends State<SearchTabContent> {
  // Removed _searchController as search is now driven by widget.searchQuery
  List<Track> _searchResults = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _currentSearchQuery = ''; // To track the query this state is for

  @override
  void initState() {
    super.initState();
    _currentSearchQuery = widget.searchQuery;
    if (_currentSearchQuery.isNotEmpty) {
      _fetchResultsForQuery(_currentSearchQuery);
    }
  }

  @override
  void didUpdateWidget(SearchTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery && widget.searchQuery.isNotEmpty) {
      _currentSearchQuery = widget.searchQuery;
      _fetchResultsForQuery(_currentSearchQuery);
    } else if (widget.searchQuery.isEmpty && _searchResults.isNotEmpty) {
      // Clear results if search query becomes empty
      setState(() {
        _searchResults = [];
        _errorMessage = null;
        _isLoading = false;
        _currentSearchQuery = '';
      });
    }
  }

  Future<void> _fetchResultsForQuery(String query) async {
    if (query.trim().isEmpty) {
       if (mounted) {
        setState(() {
          _searchResults = [];
          _errorMessage = null;
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      // Use Provider to get MusicProvider instance for API calls
      final musicProvider = Provider.of<MusicProvider>(context, listen: false);
      // Assuming MusicProvider has a method that uses ApiService
      // If not, ApiService instance needs to be accessible here.
      // For now, let's assume MusicProvider handles this.
      final results = await musicProvider.fetchTracksByQuery(query.trim());

      if (mounted && query == _currentSearchQuery) { // Ensure results are for the current query
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && query == _currentSearchQuery) {
        setState(() {
          _errorMessage = 'Search failed: ${e.toString()}';
          _searchResults = [];
          _isLoading = false;
        });
      }
      print("SearchTabContent error for '$query': $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // The main search TextField is now in SearchScreen's AppBar.
    // This widget just displays results based on widget.searchQuery.
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0), // Adjust padding as TextField is removed
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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