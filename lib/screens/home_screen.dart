// import 'package:cached_network_image/cached_network_image.dart'; // Commented out
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../services/api_service.dart' show ApiService;
import '../widgets/track_tile.dart';
import '../home_tab_content.dart';
import 'trending_now_screen.dart'; // Import new screen
import 'all_genres_screen.dart';   // Import new screen
import 'all_artists_screen.dart';  // Import new screen
import 'settings_screen.dart';     // Import new screen


// GenreSongsScreen is defined in this file for now, but could be moved.

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<ConnectivityResult>> _connectivityFuture;
  late Future<List<Map<String, String>>> _topArtistsFuture;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _connectivityFuture = Connectivity().checkConnectivity();
    _topArtistsFuture = _apiService.fetchTopArtists();
  }

  @override
  Widget build(BuildContext context) {
    // This provider call is only used for the bitrate dropdown, which is a small part of the UI.
    // It's better to use a Consumer for that specific widget if it needs to rebuild.
    // For now, keeping it here but noting it as an optimization point.
    // final musicProvider = Provider.of<MusicProvider>(context);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2, // "Home" and "Explore"
      child: Scaffold(
        // backgroundColor is handled by theme
        appBar: AppBar(
          // backgroundColor and elevation are handled by theme's appBarTheme
          title: Text(
            'Discover', // More engaging title
            style: theme.textTheme.headlineSmall,
          ),
          actions: [
            // Consider moving bitrate settings to a dedicated settings screen for cleaner UI
            // For now, let's style it minimally if kept.
            Consumer<MusicProvider>(
              builder: (context, musicProvider, child) {
                return _buildBitrateDropdown(context, musicProvider, theme);
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: "Settings",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            // Styling from theme.tabBarTheme
            tabs: const [
              Tab(text: 'Feed'), // Renamed for a more modern feel
              Tab(text: 'Explore'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // "Feed" tab content (previously HomeTabContent)
            // This likely needs significant redesign for a modern look.
            // For now, let's assume HomeTabContent will be updated or replaced.
            RefreshIndicator(
              onRefresh: () async {
                await musicProvider.fetchTracks(forceRefresh: true);
                await musicProvider.fetchTrendingTracks(forceRefresh: true);
                // Add other data fetching logic as needed for the Feed
              },
              backgroundColor: theme.colorScheme.surface,
              color: theme.colorScheme.primary,
              child: const HomeTabContent(), // This will be the main focus for "Feed"
            ),
            // "Explore" tab content
            _buildExploreTab(context, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildBitrateDropdown(BuildContext context, MusicProvider musicProvider, ThemeData theme) {
    return FutureBuilder<List<ConnectivityResult>>(
      future: _connectivityFuture, // Use state variable
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(width: 40); // Placeholder
        }
        final bool isWifi = snapshot.data!.contains(ConnectivityResult.wifi);
        final currentBitrate = isWifi ? musicProvider.wifiBitrate : musicProvider.cellularBitrate;
        final items = isWifi ? [64, 128, 256, 320] : [32, 64, 128]; // Added 320 for WiFi
        final validValue = items.contains(currentBitrate) ? currentBitrate : items.first;

        return Theme(
          data: theme.copyWith(
            canvasColor: theme.colorScheme.surface, // Dropdown background
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: validValue,
              icon: Icon(Icons.speed_outlined, color: theme.iconTheme.color?.withOpacity(0.7), size: 20),
              items: items.map((bitrate) {
                return DropdownMenuItem(
                  value: bitrate,
                  child: Text(
                    '$bitrate kbps',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface),
                  ),
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildExploreTab(BuildContext context, ThemeData theme) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    // Using RefreshIndicator for pull-to-refresh functionality
    return RefreshIndicator(
      onRefresh: () async {
        // Add logic to refresh data for the Explore tab
        await musicProvider.fetchTracks(forceRefresh: true); // Example: refresh popular tracks
        // await musicProvider.fetchTopArtists(); // If you have such a method
        // await musicProvider.fetchGenres(); // If you have a method to fetch genres
      },
      backgroundColor: theme.colorScheme.surface,
      color: theme.colorScheme.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle("What's Hot", theme, onViewMore: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const TrendingNowScreen()));
            }),
            Consumer<MusicProvider>(
              builder: (context, provider, child) {
                // This consumer rebuilds the carousel when trendingTracks changes
                return _buildHorizontalTrackCarousel(context, provider.trendingTracks, theme, itemWidth: 160, imageHeight: 160);
              }
            ),
            const SizedBox(height: 24),
            _buildSectionTitle("Browse Genres", theme, onViewMore: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AllGenresScreen()));
            }),
            _buildGenresSection(context, musicProvider, theme),
            const SizedBox(height: 24),
            _buildSectionTitle("Top Artists", theme, onViewMore: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AllArtistsScreen()));
            }),
            _buildTopArtistsSection(context, theme),
            const SizedBox(height: 20), // Bottom padding
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, ThemeData theme, {VoidCallback? onViewMore}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge,
          ),
          if (onViewMore != null)
            TextButton(
              onPressed: onViewMore,
              child: Text('View More', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
            ),
        ],
      ),
    );
  }

  Widget _buildHorizontalTrackCarousel(
    BuildContext context,
    // Future<List<Track>> Function({bool forceRefresh}) fetchFunction, // No longer need to pass the function
    List<Track> tracks, // Pass the track list directly
    ThemeData theme, {
    double itemWidth = 140,
    double imageHeight = 140,
  }) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false); // For actions only
    return SizedBox(
      height: imageHeight + 70, // Image height + text space + padding
      child: Builder( // Use Builder to get a new context if needed, though not strictly necessary here
        builder: (context) {
          // If the list is empty, it might be because it's loading or there's an error.
          // The Consumer in the parent widget will handle rebuilding when the list populates.
          if (tracks.isEmpty) {
            // We can show a loading indicator or an empty message.
            // A simple loading indicator is fine as the parent RefreshIndicator can handle errors.
            return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
          }
          if (tracks.isEmpty) {
            return Center(child: Text('Nothing to show here.', style: theme.textTheme.bodyMedium));
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            scrollDirection: Axis.horizontal,
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return InkWell(
                onTap: () {
                  musicProvider.playTrack(track, playlistTracks: tracks);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: itemWidth,
                  margin: const EdgeInsets.only(right: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12.0),
                        child: track.albumArtUrl.isNotEmpty
                            ? Image.network( // Replaced CachedNetworkImage
                                track.albumArtUrl,
                                height: imageHeight,
                                width: itemWidth,
                                cacheWidth: (itemWidth * MediaQuery.of(context).devicePixelRatio).round(),
                                cacheHeight: (imageHeight * MediaQuery.of(context).devicePixelRatio).round(),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  height: imageHeight,
                                  width: itemWidth,
                                  color: theme.colorScheme.surfaceVariant,
                                  child: Center(child: Icon(Icons.broken_image, color: theme.colorScheme.onSurfaceVariant, size: 40)),
                                ),
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    height: imageHeight,
                                    width: itemWidth,
                                    color: theme.colorScheme.surfaceVariant,
                                    child: Center(child: CircularProgressIndicator(value: loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : null)),
                                  );
                                },
                              )
                            : Container( // Placeholder if no albumArtUrl
                                height: imageHeight,
                                width: itemWidth,
                                color: theme.colorScheme.surfaceVariant,
                                child: Center(child: Icon(Icons.music_note, color: theme.colorScheme.onSurfaceVariant, size: 40)),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track.trackName,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        track.artistName,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.7)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildGenresSection(BuildContext context, MusicProvider musicProvider, ThemeData theme) {
    final genres = [
      {'name': 'Pop', 'color': theme.colorScheme.primary.withOpacity(0.8), 'icon': Icons.music_note},
      {'name': 'Rock', 'color': theme.colorScheme.secondary.withOpacity(0.8), 'icon': Icons.album }, // Replaced Icons.electric_guitar
      {'name': 'Hip-Hop', 'color': Colors.orangeAccent.withOpacity(0.8), 'icon': Icons.mic_external_on},
      {'name': 'Electronic', 'color': Colors.cyanAccent.withOpacity(0.8), 'icon': Icons.headphones},
      {'name': 'Jazz', 'color': Colors.blueAccent.withOpacity(0.8), 'icon': Icons.speaker},
      {'name': 'Classical', 'color': Colors.purpleAccent.withOpacity(0.8), 'icon': Icons.piano},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 16 / 6, // Adjusted for better look
        ),
        itemCount: genres.length,
        itemBuilder: (context, index) {
          final genre = genres[index];
          final genreName = genre['name'] as String;
          final genreColor = genre['color'] as Color;
          final genreIcon = genre['icon'] as IconData?;

          return InkWell(
            onTap: () async {
              await musicProvider.fetchGenreTracks(genreName);
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GenreSongsScreen(genre: genreName),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [genreColor.withOpacity(0.7), genreColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    if (genreIcon != null)
                      Icon(genreIcon, color: Colors.white.withOpacity(0.9), size: 24),
                    if (genreIcon != null)
                      const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        genreName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopArtistsSection(BuildContext context, ThemeData theme) {
    // final apiService = ApiService(); // Now using state variable _apiService

    return SizedBox(
      height: 170, // Avatar + text + padding
      child: FutureBuilder<List<Map<String, String>>>(
        future: _topArtistsFuture, // Use state variable
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: theme.textTheme.bodyMedium));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No top artists found.', style: theme.textTheme.bodyMedium));
          }

          final artists = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            scrollDirection: Axis.horizontal,
            itemCount: artists.length,
            itemBuilder: (context, index) {
              final artist = artists[index];
              final imageUrl = artist['image'] ?? '';
              final artistName = artist['name'] ?? 'Unknown Artist';

              return InkWell(
                onTap: () {
                  // TODO: Navigate to Artist Detail Screen
                  // Example: Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(artistName: artistName)));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Tapped Artist: $artistName (not implemented)")),
                  );
                },
                borderRadius: BorderRadius.circular(65), // Half of width + padding
                child: Container(
                  width: 110, // Fixed width for consistent layout
                  margin: const EdgeInsets.only(right: 16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: ClipOval(
                          child: imageUrl.isNotEmpty
                              ? Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  width: 100,
                                  height: 100,
                                  cacheWidth: (100 * MediaQuery.of(context).devicePixelRatio).round(),
                                  cacheHeight: (100 * MediaQuery.of(context).devicePixelRatio).round(),
                                  errorBuilder: (context, error, stackTrace) => Container(color: theme.colorScheme.surfaceVariant, child: Icon(Icons.person, size: 50, color: theme.colorScheme.onSurfaceVariant)),
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(color: theme.colorScheme.surfaceVariant, child: Center(child: CircularProgressIndicator(value: loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : null)));
                                  },
                                )
                              : Container(color: theme.colorScheme.surfaceVariant, child: Icon(Icons.person, size: 50, color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        artistName,
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// --- GenreSongsScreen Widget (Placeholder) ---
// This should be in its own file and styled according to the new theme.
class GenreSongsScreen extends StatelessWidget {
  final String genre;
  const GenreSongsScreen({required this.genre, super.key});

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final theme = Theme.of(context);
    // Ensure fetchGenreTracks was called before navigating here.
    // Data is expected to be in musicProvider.genreTracks

    return Scaffold(
      appBar: AppBar(
        title: Text(genre, style: theme.textTheme.headlineSmall),
        // Back button is added automatically by Navigator
      ),
      body: Consumer<MusicProvider>(
        builder: (context, provider, child) {
          if (provider.genreTracks.isEmpty) {
            // Could be loading, error, or truly empty. Provider should have flags for this.
            // For now, a simple check.
            if (provider.errorMessage != null && provider.errorMessage!.contains(genre)) {
               return Center(child: Text('Error loading tracks for $genre.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)));
            }
            return Center(child: Text('No songs found for $genre.', style: theme.textTheme.bodyMedium));
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            itemCount: provider.genreTracks.length,
            itemBuilder: (context, index) {
              final track = provider.genreTracks[index];
              final isPlaying = provider.currentTrack?.id == track.id && provider.isPlaying;
              return TrackTile(
                track: track,
                isPlaying: isPlaying,
                // onTap will be handled by TrackTile's default or can be overridden if needed
              );
            },
          );
        },
      ),
    );
  }
}