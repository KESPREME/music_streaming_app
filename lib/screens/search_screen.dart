// lib/screens/search_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../search_tab_content.dart'; // Content for the 'Tracks' tab
import '../widgets/track_tile.dart'; // Use standard TrackTile
import '../models/track.dart'; // Import Track model

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Using DefaultTabController to manage tabs
    return DefaultTabController(
      length: 2, // Two tabs: Tracks, Artists
      child: Scaffold(
        backgroundColor: const Color(0xFF121212), // App background color
        appBar: AppBar(
          backgroundColor: const Color(0xFF1D1D1D), // Dark AppBar
          // Remove automatic back button if this screen is part of main tabs
          // automaticallyImplyLeading: false, // Uncomment if needed
          title: const Text(
            'Search',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          // Optional: If it's a standalone screen, keep the back button
          leading: Navigator.canPop(context) ? IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ) : null,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.deepPurpleAccent, // Use theme accent
            indicatorWeight: 3.0,
            tabs: [
              Tab(text: 'Tracks'), // First tab label
              Tab(text: 'Artists'), // Second tab label
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Content for the first tab ('Tracks')
            const SearchTabContent(),
            // Content for the second tab ('Artists')
            _buildArtistsTab(context),
          ],
        ),
      ),
    );
  }

  // Builds the UI for the "Artists" search tab
  Widget _buildArtistsTab(BuildContext context) {
    // Use provider for actions and artistTracks state
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    // Controller for the search input field
    // Consider making _ArtistsTab stateful if controller needs disposal or more state
    final TextEditingController searchController = TextEditingController();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children horizontally
        children: [
          // Search input field
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Search for an artist...',
              hintStyle: TextStyle(color: Colors.grey[400]),
              filled: true,
              fillColor: Colors.grey[850], // Slightly lighter fill
              prefixIcon: Icon(Icons.search, color: Colors.grey[400]), // Search icon inside
              // Add a clear button
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, color: Colors.white70),
                tooltip: "Clear",
                onPressed: () {
                  searchController.clear();
                  // Optionally clear results: musicProvider.clearArtistTracks();
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8), // Less rounded
                borderSide: BorderSide.none, // No border
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14.0), // Adjust vertical padding
            ),
            style: const TextStyle(color: Colors.white), // Input text color
            textInputAction: TextInputAction.search, // Show search action on keyboard
            onSubmitted: (value) { // Trigger search on keyboard submit
              if (value.trim().isNotEmpty) {
                musicProvider.fetchArtistTracks(value.trim());
              }
            },
          ),
          const SizedBox(height: 20), // Space below search bar

          // Use Consumer to display results based on provider state
          Expanded(
            child: Consumer<MusicProvider>(
              builder: (context, provider, child) {
                final artistTracks = provider.artistTracks; // Get the list

                // Handle empty state or initial state
                // TODO: Add a loading indicator state from provider if fetchArtistTracks sets one
                if (artistTracks.isEmpty) {
                  return const Center(
                    child: Text(
                      'Search for an artist to see their top tracks.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                  );
                }

                // Display results if tracks are available
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Displaying the searched artist name might be tricky if only tracks are returned
                    // You might need to extract it from the first track or adjust the API/Provider
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        // Use artist name from first track as an approximation
                        'Top Tracks for "${artistTracks.first.artistName}"',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // List of tracks
                    Expanded(
                      child: ListView.builder(
                        itemCount: artistTracks.length,
                        itemBuilder: (context, index) {
                          final track = artistTracks[index];
                          final isPlaying = provider.currentTrack?.id == track.id && provider.isPlaying;

                          // Use the standard TrackTile - remove allowRemove
                          return TrackTile(
                            track: track,
                            isPlaying: isPlaying,
                            // Default onTap plays the track
                            // If you want to set context to these results, override onTap:
                            // onTap: () => provider.playTrack(track, playlistTracks: artistTracks),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}