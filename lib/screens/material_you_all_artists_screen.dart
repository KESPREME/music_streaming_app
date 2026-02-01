import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../services/innertube/innertube_service.dart';
import '../models/track.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';
import '../widgets/material_you_elevated_card.dart';

class MaterialYouAllArtistsScreen extends StatefulWidget {
  const MaterialYouAllArtistsScreen({super.key});

  @override
  State<MaterialYouAllArtistsScreen> createState() => _MaterialYouAllArtistsScreenState();
}

class _MaterialYouAllArtistsScreenState extends State<MaterialYouAllArtistsScreen> {
  late Future<List<Track>> _artistsFuture;
  final InnerTubeService _innerTubeService = InnerTubeService();

  @override
  void initState() {
    super.initState();
    _artistsFuture = _innerTubeService.searchArtists('Popular Music Artists', limit: 30);
  }

  Future<void> _refreshArtists() async {
    setState(() {
      _artistsFuture = _innerTubeService.searchArtists('Popular Music Artists', limit: 30);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      body: SafeArea(
        child: RefreshIndicator(
          color: MaterialYouTokens.primaryVibrant,
          backgroundColor: MaterialYouTokens.surfaceContainerDark,
          onRefresh: _refreshArtists,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(context, colorScheme),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                sliver: FutureBuilder<List<Track>>(
                  future: _artistsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return SliverFillRemaining(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: MaterialYouTokens.primaryVibrant,
                          ),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return SliverFillRemaining(
                        child: Center(
                          child: Text(
                            'Could not load artists',
                            style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return SliverFillRemaining(
                        child: Center(
                          child: Text(
                            'No artists found',
                            style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
                          ),
                        ),
                      );
                    }

                    final artists = snapshot.data!;
                    
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final artistTrack = artists[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildArtistTile(context, artistTrack, colorScheme),
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

  Widget _buildAppBar(BuildContext context, ColorScheme colorScheme) {
    return SliverAppBar(
      backgroundColor: MaterialYouTokens.surfaceDark,
      surfaceTintColor: Colors.transparent,
      pinned: true,
      expandedHeight: 120,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: MaterialYouTokens.surfaceContainerDark,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final double percentage = ((constraints.maxHeight - kToolbarHeight) / 
                                     (120 - kToolbarHeight)).clamp(0.0, 1.0);

          return FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
            title: Text(
              'Top Artists',
              style: MaterialYouTypography.headlineSmall(colorScheme.onSurface)
                  .copyWith(fontSize: 20 + (8 * percentage)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildArtistTile(BuildContext context, Track artistTrack, ColorScheme colorScheme) {
    final artistName = artistTrack.trackName;
    
    return MaterialYouElevatedCard(
      elevation: 1,
      borderRadius: MaterialYouTokens.shapeMedium,
      onTap: () {
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
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Hero(
            tag: 'artist_${artistTrack.id}',
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: MaterialYouTokens.primaryVibrant.withOpacity(0.3), 
                  width: 2
                ),
              ),
              child: CircleAvatar(
                radius: 35,
                backgroundColor: MaterialYouTokens.surfaceContainerDark,
                backgroundImage: artistTrack.albumArtUrl.isNotEmpty 
                    ? NetworkImage(artistTrack.albumArtUrl) 
                    : null,
                child: artistTrack.albumArtUrl.isEmpty 
                    ? Icon(Icons.person, color: colorScheme.onSurfaceVariant) 
                    : null,
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
                  style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  "Artist",
                  style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MaterialYouTokens.primaryVibrant.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_forward_ios_rounded, 
              color: MaterialYouTokens.primaryVibrant, 
              size: 16
            ),
          ),
        ],
      ),
    );
  }
}
