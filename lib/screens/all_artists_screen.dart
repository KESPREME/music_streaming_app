import 'dart:ui';
import 'package:flutter/material.dart';
import '../widgets/jelly_icon_button.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../theme/app_font.dart';
import '../providers/music_provider.dart';
import '../services/innertube/innertube_service.dart';
import '../models/track.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/skeleton.dart';
import '../theme/amoled_theme.dart';

// A simple tile for displaying an artist
class ArtistListTile extends StatelessWidget {
  final String name;
  final String imageUrl;
  final VoidCallback onTap;

  const ArtistListTile({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
          child: imageUrl.isEmpty ? Icon(Icons.person, color: theme.colorScheme.onSurfaceVariant) : null,
        ),
        title: Text(name, style: theme.textTheme.titleMedium),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: theme.iconTheme.color?.withValues(alpha: 0.6)),
        onTap: onTap,
      ),
    );
  }
}


class AllArtistsScreen extends StatefulWidget {
  const AllArtistsScreen({super.key});

  @override
  State<AllArtistsScreen> createState() => _AllArtistsScreenState();
}

class _AllArtistsScreenState extends State<AllArtistsScreen> {
  late Future<List<Track>> _artistsFuture;
  final InnerTubeService _innerTubeService = InnerTubeService();

  @override
  void initState() {
    super.initState();
    // Use searchArtists to get actual artist objects (Track wrapper)
    // Query 'Popular Music Artists' for better relevance/quantity
    _artistsFuture = _innerTubeService.searchArtists('Popular Music Artists', limit: 30);
  }

  Future<void> _refreshArtists() async {
    setState(() {
      _artistsFuture = _innerTubeService.searchArtists('Popular Music Artists', limit: 30);
    });
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
            colors: AmoledTheme.gradient(context, isDark 
              ? [const Color(0xFF141414), const Color(0xFF1E1E1E), const Color(0xFF000000)]
              : [const Color(0xFFF7F7F7), const Color(0xFFFFFFFF)]),
          ),
        ),
        child: RefreshIndicator(
          color: const Color(0xFFFF1744),
          backgroundColor: AmoledTheme.surfaceOf(context, const Color(0xFF1E1E1E)),
          onRefresh: _refreshArtists,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildLiquidAppBar(context, isDark),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                sliver: FutureBuilder<List<Track>>(
                  future: _artistsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SkeletonScope(
                        child: SliverSkeletonRows(art: 70, circle: true, padding: EdgeInsets.zero, gap: 12),
                      );
                    }
                    if (snapshot.hasError) {
                      return SliverFillRemaining(
                        child: Center(
                          child: Text(
                            'Could not load artists',
                            style: AppFont.style(color: Colors.white54),
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return SliverFillRemaining(
                        child: Center(
                          child: Text(
                            'No artists found',
                            style: AppFont.style(color: Colors.white54),
                          ),
                        ),
                      );
                    }

                    // For searchArtists, results are already unique artists
                    // In Artist Search: trackName = Artist Name, artistName = "Artist"
                    final artists = snapshot.data!;
                    
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final artistTrack = artists[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildLiquidArtistTile(context, artistTrack),
                          );
                        },
                        childCount: artists.length,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiquidAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      pinned: true,
      expandedHeight: 120,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: JellyIconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final double percentage = ((constraints.maxHeight - kToolbarHeight) / (120 - kToolbarHeight)).clamp(0.0, 1.0);
          final double blur = (1 - percentage) * 15;
          final double overlayOpacity = (1 - percentage) * 0.5;

          return ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
                title: Text(
                  'Top Artists',
                  style: AppFont.style(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontSize: 20 + (8 * percentage),
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.transparent),
                    Container(color: Colors.black.withValues(alpha: overlayOpacity)),
                    if (percentage < 0.05)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                      ),
                  ],
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildLiquidArtistTile(BuildContext context, Track artistTrack) {
    // In searchArtists result:
    // trackName -> The Artist's Name (e.g. "The Weeknd")
    // artistName -> Subtitle (e.g. "Artist • 35M subscribers")
    // id -> The Browse ID (Artist ID)
    final artistName = artistTrack.trackName;
    
    return InkWell(
      onTap: () {
        // Use the robust Object navigation which uses ID directly
        Provider.of<MusicProvider>(context, listen: false).navigateToArtistObject(artistTrack);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ThemedArtistDetailScreen(
              artistId: artistTrack.id,
              artistName: artistName,
              artistImage: artistTrack.albumArtUrl,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      // No BackdropFilter: it blurred a flat gradient (nothing to see) at a
      // backdrop blur per row per scroll frame.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Hero(
                  tag: 'artist_${artistTrack.id}', // Use ID for unique tag
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 2),
                      boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
                    ),
                    child: CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.grey[900],
                      backgroundImage: artistTrack.albumArtUrl.isNotEmpty
                          ? ResizeImage(CachedNetworkImageProvider(artistTrack.albumArtUrl), width: 224, height: 224)
                          : null,
                      child: artistTrack.albumArtUrl.isEmpty ? const Icon(Icons.person, color: Colors.white54) : null,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artistName,
                        style: AppFont.style(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Artist", // Simple subtitle
                        style: AppFont.style(
                          fontSize: 13,
                          color: Colors.white54,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
                ),
              ],
            ),
          ),
      ),
    );
  }
}


