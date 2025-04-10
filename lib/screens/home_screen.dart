import 'package:connectivity_plus/connectivity_plus.dart'; // For bitrate dropdown
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../services/api_service.dart' show ApiService; // Keep for top artists for now
// Import screen for Genre navigation
// Assume GenreSongsScreen is in its own file now, or adjust import if needed
// import 'genre_songs_screen.dart'; // If separated
import '../widgets/track_tile.dart'; // Import the standard TrackTile
import '../home_tab_content.dart'; // Import content for the first tab

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Use listen: false if only using methods, true if UI depends on state changes here
    final musicProvider = Provider.of<MusicProvider>(context);

    return DefaultTabController(
      length: 2, // For "Home" and "Explore" tabs
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1D1D1D), // Darker AppBar
          title: const Text(
            'Music Streaming', // Or your app name
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          actions: [
            // --- Recommendation: Remove this Bitrate Dropdown ---
            // This is better placed in a dedicated settings screen.
            FutureBuilder<List<ConnectivityResult>>(
              future: Connectivity().checkConnectivity(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(width: 48); // Placeholder space
                }
                final bool isWifi = snapshot.data!.contains(ConnectivityResult.wifi);
                // Use watch here if you want the dropdown value to react immediately
                // If only setting, listen: false in the main build method is fine.
                final currentBitrate = isWifi ? musicProvider.wifiBitrate : musicProvider.cellularBitrate;

                // Ensure the current value exists in the items
                final items = isWifi
                    ? [64, 128, 256] // Example bitrates for WiFi
                    : [32, 64, 128]; // Example bitrates for Cellular
                final validValue = items.contains(currentBitrate) ? currentBitrate : items.first;

                return DropdownButton<int>(
                  value: validValue,
                  dropdownColor: const Color(0xFF282828), // Darker dropdown
                  icon: const Icon(Icons.signal_cellular_alt, color: Colors.white70, size: 20), // Generic icon
                  underline: const SizedBox(), // Remove default underline
                  items: items.map((bitrate) {
                    return DropdownMenuItem(
                      value: bitrate,
                      child: Text('$bitrate kbps', style: const TextStyle(color: Colors.white, fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      if (isWifi) {
                        musicProvider.setWifiBitrate(value);
                      } else {
                        musicProvider.setCellularBitrate(value);
                      }
                    }
                  },
                );
              },
            ),
            const SizedBox(width: 16),
            // --- End Recommendation ---
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.deepPurpleAccent, // Match theme accent
            indicatorWeight: 3.0,
            tabs: [
              Tab(text: 'Home'),
              Tab(text: 'Explore'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Content for the first tab ("Home")
            const HomeTabContent(),
            // Content for the second tab ("Explore")
            _buildExploreTab(context),
          ],
        ),
      ),
    );
  }

  // Builds the content for the "Explore" tab
  Widget _buildExploreTab(BuildContext context) {
    // No need for provider reference here if passing down
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(), // Nice scroll physics
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          // Pass provider down to avoid multiple lookups
          _buildNewReleasesSection(context, Provider.of<MusicProvider>(context, listen: false)),
          const SizedBox(height: 24),
          _buildGenresSection(context, Provider.of<MusicProvider>(context, listen: false)),
          const SizedBox(height: 24),
          // Pass context needed for provider lookup if fixing ApiService call
          _buildTopArtistsSection(context),
          const SizedBox(height: 20), // Padding at the bottom
        ],
      ),
    );
  }

  // Builds the "New Releases" horizontal list
  Widget _buildNewReleasesSection(BuildContext context, MusicProvider musicProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'Popular Tracks', // Changed title slightly
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 190, // Increased height slightly for padding/text
          child: FutureBuilder<List<Track>>(
            // Fetch general tracks - assume fetchTracks gets popular/new
            future: musicProvider.fetchTracks(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && musicProvider.tracks.isEmpty) {
                // Show loader only if no cached data is available
                return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
              } else if (snapshot.hasError && musicProvider.tracks.isEmpty) {
                // Show error only if no cached data
                return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white70)));
              }

              // Use provider's data if available (handles cache display while refreshing)
              final tracks = musicProvider.tracks;

              if (tracks.isEmpty) {
                return const Center(child: Text('No popular tracks found.', style: TextStyle(color: Colors.white70)));
              }

              // Use ListView.separated for spacing
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16.0), // Add padding
                scrollDirection: Axis.horizontal,
                itemCount: tracks.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12), // Spacing between items
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
                  // Use the standard TrackTile inside a SizedBox for layout control
                  return SizedBox(
                      width: 130, // Width for horizontal tile layout
                      child: Column( // Column for image + text below
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Use AspectRatio for consistent image size
                          AspectRatio(
                            aspectRatio: 1.0, // Square image
                            child: TrackTile( // Call standard TrackTile
                              track: track,
                              isPlaying: isPlaying,
                              // Use default onTap (playTrack)
                            ),
                          ),
                          // Removed the text part from here, as TrackTile now handles title/subtitle
                        ],
                      )
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // Builds the Genres grid
  Widget _buildGenresSection(BuildContext context, MusicProvider musicProvider) {
    // Consider fetching genres dynamically if they change
    final genres = [
      {'name': 'Pop', 'color': Colors.pinkAccent},
      {'name': 'Rock', 'color': Colors.lightBlueAccent},
      {'name': 'Hip-Hop', 'color': Colors.tealAccent},
      {'name': 'Jazz', 'color': Colors.orangeAccent},
      {'name': 'Classical', 'color': Colors.deepPurpleAccent},
      {'name': 'Electronic', 'color': Colors.cyanAccent},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'Explore Genres',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: GridView.builder(
            shrinkWrap: true, // Important inside SingleChildScrollView
            physics: const NeverScrollableScrollPhysics(), // Disable GridView's own scrolling
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // Two columns
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 16 / 7, // Adjust aspect ratio for desired height
            ),
            itemCount: genres.length,
            itemBuilder: (context, index) {
              final genre = genres[index];
              final genreName = genre['name'] as String;
              final genreColor = genre['color'] as Color;
              return GestureDetector(
                onTap: () async {
                  // Fetch tracks for the genre first
                  await musicProvider.fetchGenreTracks(genreName);
                  // Then navigate to the screen which will display musicProvider.genreTracks
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      // Ensure GenreSongsScreen exists and takes genre name
                      builder: (context) => GenreSongsScreen(genre: genreName),
                    ),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: genreColor,
                    borderRadius: BorderRadius.circular(8), // Slightly rounded corners
                    gradient: LinearGradient( // Add subtle gradient
                      colors: [genreColor.withOpacity(0.7), genreColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      genreName,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 2, color: Colors.black45)]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Builds the Top Artists horizontal list
  Widget _buildTopArtistsSection(BuildContext context) {
    // --- Recommendation: Fix direct ApiService call ---
    // Ideally, MusicProvider should have a method `fetchTopArtists`
    // that internally calls `_apiService.fetchTopArtists()`.
    // For now, leaving the direct call but it's not best practice.
    final apiService = ApiService(); // Creates a new instance - not ideal

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'Top Artists',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 150, // Height for avatar + text
          child: FutureBuilder<List<Map<String, String>>>(
            future: apiService.fetchTopArtists(), // Direct call
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
              } else if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white70)));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No top artists found.', style: TextStyle(color: Colors.white70)));
              }

              final artists = snapshot.data!;
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16.0), // Add padding
                scrollDirection: Axis.horizontal,
                itemCount: artists.length,
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  final imageUrl = artist['image'] ?? ''; // Handle potential null
                  final artistName = artist['name'] ?? 'Unknown Artist'; // Handle potential null

                  return Padding(
                    padding: const EdgeInsets.only(right: 16.0), // Spacing between artists
                    child: GestureDetector(
                      onTap: () {
                        // TODO: Navigate to Artist Detail Screen
                        print("Tapped Artist: $artistName");
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min, // Fit content
                        children: [
                          CircleAvatar(
                            radius: 50, // Size of the avatar
                            backgroundColor: Colors.grey[800], // Background if image fails
                            backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                            child: imageUrl.isEmpty ? const Icon(Icons.person, size: 40, color: Colors.white70) : null, // Placeholder icon
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 100, // Limit text width
                            child: Text(
                              artistName,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

// Private _buildTrackTile helper is REMOVED
}


// --- GenreSongsScreen Widget ---
// Keep this separate or move to its own file (e.g., lib/screens/genre_songs_screen.dart)
class GenreSongsScreen extends StatelessWidget {
  final String genre;

  const GenreSongsScreen({required this.genre, super.key});

  @override
  Widget build(BuildContext context) {
    // Use Consumer to listen for changes in genreTracks
    return Consumer<MusicProvider>(
        builder: (context, musicProvider, child) {
          final genreTracks = musicProvider.genreTracks;

          return Scaffold(
            backgroundColor: const Color(0xFF121212),
            appBar: AppBar(
              backgroundColor: const Color(0xFF1D1D1D),
              title: Text(
                genre, // Just show genre name
                style: const TextStyle(color: Colors.white),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white), // Use iOS style back arrow
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: genreTracks.isEmpty
            // Check if loading or truly empty
                ? musicProvider.errorMessage != null && musicProvider.errorMessage!.contains(genre) // Check if error relates to this genre fetch
                ? Center(child: Text('Error loading tracks for $genre', style: const TextStyle(color: Colors.redAccent)))
                : const Center(child: Text('No songs found for this genre.', style: TextStyle(color: Colors.white70)))
                : ListView.builder(
              itemCount: genreTracks.length,
              itemBuilder: (context, index) {
                final track = genreTracks[index];
                final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
                // Use the standard TrackTile
                return TrackTile(
                  track: track,
                  isPlaying: isPlaying,
                );
              },
            ),
          );
        }
    );
  }
}