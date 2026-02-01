import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../widgets/material_you_elevated_card.dart';
import '../widgets/material_you_tonal_button.dart';
import '../widgets/themed_options_sheet.dart';
import '../widgets/themed_trending_now_screen.dart';
import '../widgets/themed_all_genres_screen.dart';
import '../widgets/themed_all_artists_screen.dart';
import '../widgets/themed_genre_songs_screen.dart';
import '../theme/material_you_typography.dart';
import '../theme/material_you_tokens.dart';
import '../widgets/themed_settings_screen.dart';
import '../widgets/material_you_options_sheet.dart';

/// Material You Home Screen - COMPLETELY DIFFERENT from glassmorphism
/// Features:
/// - Large "Good evening" greeting (32sp bold)
/// - 2-column grid layout (not horizontal scroll)
/// - Elevated cards with shadows
/// - Prominent Shuffle FAB (bottom right)
/// - Vibrant dynamic colors
/// - Material 3 components throughout
class MaterialYouHomeScreen extends StatefulWidget {
  const MaterialYouHomeScreen({super.key});

  @override
  State<MaterialYouHomeScreen> createState() => _MaterialYouHomeScreenState();
}

class _MaterialYouHomeScreenState extends State<MaterialYouHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    // FIX 7: Changed from time-based greeting to static "Discover"
    return 'Discover';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildMaterialYouHeader(context),
            _buildMaterialYouTabBar(context),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildFeedTab(context),
                  _buildExploreTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialYouHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Large greeting - 32sp bold
          Text(
            _getGreeting(),
            style: MaterialYouTypography.displayLarge(colorScheme.onSurface),
          ),
          // Settings button
          MaterialYouTonalIconButton(
            icon: Icons.settings_outlined,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ThemedSettingsScreen()),
            ),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialYouTabBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildTabItem(0, "Feed"),
          _buildTabItem(1, "Explore"),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, String title) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final selected = _tabController.index == index;
        return Expanded(
          child: GestureDetector(
            onTap: () => _tabController.animateTo(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                title,
                style: MaterialYouTypography.labelLarge(
                  selected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeedTab(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () async {
        await musicProvider.fetchTracks(forceRefresh: true);
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 180),
        physics: const BouncingScrollPhysics(),
        children: [
          // Recently Played (Horizontal List)
          if (musicProvider.recentlyPlayed.isNotEmpty) ...[
            _buildSectionHeader("Jump Back In", null),
            SizedBox(
              height: 220, // Increased height to prevent text clipping
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                scrollDirection: Axis.horizontal,
                itemCount: musicProvider.recentlyPlayed.length,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  final item = musicProvider.recentlyPlayed[index];
                  return MaterialYouAlbumCard(
                    imageUrl: item.albumArtUrl,
                    title: item.trackName,
                    subtitle: item.artistName,
                    width: 140, // Match glassmorphism dimensions
                    height: 140,
                    onTap: () => musicProvider.playTrack(
                      item,
                      playlistTracks: musicProvider.recentlyPlayed,
                    ),
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      musicProvider.setHideMiniPlayer(true);
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => MaterialYouOptionsSheet(
                          track: item,
                          isRecentlyPlayedContext: true,
                        ),
                      ).whenComplete(() {
                        musicProvider.setHideMiniPlayer(false);
                      });
                    },
                  );
                },
              ),
            ),
          ],

          // For You - Vertical List (No top padding)
          const SizedBox(height: 10), // Reduced gap
          _buildSectionHeader("For You", null, removeTopPadding: true),
          if (musicProvider.recommendedTracks.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: CircularProgressIndicator(color: colorScheme.primary),
              ),
            ),
          ...musicProvider.recommendedTracks.map((track) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: MaterialYouListCard( // Ensure this widget exists and is correct
                imageUrl: track.albumArtUrl,
                title: track.trackName,
                subtitle: track.artistName,
                onTap: () => musicProvider.playTrack(
                  track,
                  playlistTracks: musicProvider.recommendedTracks,
                ),
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  musicProvider.setHideMiniPlayer(true);
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => MaterialYouOptionsSheet(track: track), // Use the specific MY sheet
                  ).whenComplete(() {
                    musicProvider.setHideMiniPlayer(false);
                  });
                },
                trailing: Icon(
                  Icons.play_circle_filled,
                  color: colorScheme.primary,
                  size: 32,
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildRecentlyPlayedGrid(BuildContext context, MusicProvider musicProvider) {
    // Deprecated: replaced by horizontal list inside _buildFeedTab
    return const SizedBox.shrink();
  }

  Widget _buildExploreTab(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () async {
        await musicProvider.fetchTrendingTracks(forceRefresh: true);
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 180),
        physics: const BouncingScrollPhysics(),
        children: [
          // Trending Now - Horizontal scroll (keep this one)
          _buildSectionHeader("What's Hot", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ThemedTrendingNowScreen()),
            );
          }),
          SizedBox(
            height: 240,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: musicProvider.trendingTracks.length,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (context, index) {
                final track = musicProvider.trendingTracks[index];
                return MaterialYouAlbumCard(
                  imageUrl: track.albumArtUrl,
                  title: track.trackName,
                  subtitle: track.artistName,
                  width: 160,
                  height: 160,
                  onTap: () => musicProvider.playTrack(
                    track,
                    playlistTracks: musicProvider.trendingTracks,
                  ),
                );
              },
            ),
          ),

          // Genres - Grid layout
          const SizedBox(height: 24),
          _buildSectionHeader("Vibe Check", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ThemedAllGenresScreen()),
            );
          }),
          _buildGenresGrid(context, musicProvider),

          // Top Artists - Horizontal scroll
          const SizedBox(height: 24),
          _buildSectionHeader("Top Artists", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ThemedAllArtistsScreen()),
            );
          }),
          _buildTopArtistsSection(context),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback? onViewAll, {bool removeTopPadding = false}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, removeTopPadding ? 0 : 12, 24, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: MaterialYouTypography.headlineMedium(colorScheme.onSurface),
          ),
          if (onViewAll != null)
            MaterialYouTonalButton(
              label: "SEE ALL",
              onPressed: onViewAll,
              isCompact: true,
            ),
        ],
      ),
    );
  }

  Widget _buildGenresGrid(BuildContext context, MusicProvider musicProvider) {
    final colorScheme = Theme.of(context).colorScheme;
    final genres = [
      {'name': 'Pop', 'color': colorScheme.primary, 'icon': Icons.music_note},
      {'name': 'Hip-Hop', 'color': colorScheme.secondary, 'icon': Icons.mic},
      {
        'name': 'Rock',
        'color': colorScheme.tertiary,
        'icon': Icons.electric_bolt
      },
      {
        'name': 'Chill',
        'color': colorScheme.primary,
        'icon': Icons.nightlight_round
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.5,
        ),
        itemCount: genres.length,
        itemBuilder: (context, index) {
          final genre = genres[index];
          return MaterialYouElevatedCard(
            elevation: 2,
            borderRadius: 20,
            onTap: () {
              musicProvider.fetchGenreTracks(genre['name'] as String);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ThemedGenreSongsScreen(genre: genre['name'] as String),
                ),
              );
            },
            backgroundColor: (genre['color'] as Color).withOpacity(0.2),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  genre['icon'] as IconData,
                  color: genre['color'] as Color,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  genre['name'] as String,
                  style: MaterialYouTypography.titleLarge(
                      colorScheme.onSurface),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopArtistsSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 160,
      child: FutureBuilder(
        future: Provider.of<MusicProvider>(context, listen: false)
            .fetchTrendingTracks(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(color: colorScheme.primary),
            );
          }
          final tracks = snapshot.data as List<Track>;
          final uniqueNames = <String>{};
          final uniqueTracks =
              tracks.where((t) => uniqueNames.add(t.artistName)).toList();

          if (uniqueTracks.isEmpty) return const SizedBox.shrink();

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            scrollDirection: Axis.horizontal,
            itemCount: uniqueTracks.length,
            physics: const BouncingScrollPhysics(),
            separatorBuilder: (ctx, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final artistName = uniqueTracks[index].artistName;
              final imageUrl = uniqueTracks[index].albumArtUrl;

              return MaterialYouAlbumCard(
                imageUrl: imageUrl,
                title: artistName,
                subtitle: '',
                width: 120,
                height: 120,
                isCircle: true,
                onTap: () {
                  Provider.of<MusicProvider>(context, listen: false)
                      .fetchArtistTracks(artistName);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Loading $artistName..."),
                      duration: const Duration(seconds: 1),
                      backgroundColor: colorScheme.surfaceVariant,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
