import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../theme/app_font.dart';
import '../models/track.dart';
import '../presentation/explore/explore_screen.dart';
import '../providers/music_provider.dart';
import '../services/innertube/innertube_service.dart';
import '../widgets/glass_surface.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_options_sheet.dart';

/// Discover screen with Muzo-style section layout.
///
/// Shows curated sections: Trending, Recently Played, New Releases, Top Artists.
/// Replaces the old swipe-deck approach with horizontal scrolling cards.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _innerTube = InnerTubeService.instance;
  List<Track>? _newReleases;
  String? _error;
  DateTime _lastExplorePushAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _openExplore() {
    final now = DateTime.now();
    if (now.difference(_lastExplorePushAt) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastExplorePushAt = now;
    ExploreScreen.open(context,
        seed: context.read<MusicProvider>().currentTrack);
  }

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<MusicProvider>();
      if (provider.trendingTracks.isEmpty) {
        provider.fetchTrendingTracks();
      }
    });
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final releases = await _innerTube.getNewReleases(limit: 14);
      if (!mounted) return;
      setState(() => _newReleases = releases);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'discover_failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final musicProvider = Provider.of<MusicProvider>(context);

    return RefreshIndicator(
      color: accent,
      onRefresh: _load,
      child: _error != null
          ? _buildErrorState()
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 8)),

                // Explore Stream entry (immersive vertical discovery).
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: GlassSurface(
                      tier: GlassTier.floating,
                      borderRadius: 20,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _openExplore,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 20),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('Explore',
                                        style: AppFont.style(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text('Swipe through new music',
                                        style: AppFont.style(
                                            fontSize: 13,
                                            color: Colors.white
                                                .withValues(alpha: 0.6))),
                                  ],
                                ),
                              ),
                              Icon(Icons.keyboard_arrow_up_rounded,
                                  size: 26,
                                  color: Colors.white.withValues(alpha: 0.7)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Trending Now section
                if (musicProvider.trendingTracks.isNotEmpty) ...[
                  _buildSectionHeader(context, 'Trending Now'),
                  _buildTrendingSection(context, musicProvider),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ],

                // Recently Played section
                if (musicProvider.recentlyPlayed.isNotEmpty) ...[
                  _buildSectionHeader(context, 'Recently Played'),
                  _buildRecentlyPlayedSection(context, musicProvider),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ],

                // New Releases section
                if (_newReleases != null && _newReleases!.isNotEmpty) ...[
                  _buildSectionHeader(context, 'New Releases'),
                  _buildNewReleasesSection(context),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ],

                // Top Artists section
                if (musicProvider.trendingTracks.isNotEmpty) ...[
                  _buildSectionHeader(context, 'Top Artists'),
                  _buildTopArtistsSection(context, musicProvider),
                ],

                // Bottom padding for mini player + nav bar
                const SliverPadding(padding: EdgeInsets.only(bottom: 140)),
              ],
            ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      children: [
        const SizedBox(height: 140),
        const Icon(Icons.explore_off_rounded, size: 48, color: Colors.white24),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Could not load Discover',
            style: AppFont.style(color: Colors.white54),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(onPressed: _load, child: const Text('Retry')),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Text(
          title,
          style: AppFont.style(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildTrendingSection(BuildContext context, MusicProvider provider) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 200,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          itemCount: provider.trendingTracks.length.clamp(0, 10),
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, index) {
            final track = provider.trendingTracks[index];
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ThemedCard(
                imageUrl: track.albumArtUrl,
                title: track.trackName,
                subtitle: track.artistName,
                width: 150,
                height: 150,
                onTap: () => provider.playTrack(
                  track,
                  playlistTracks: provider.trendingTracks,
                ),
                onLongPress: () => ThemedOptionsSheet.show(context, track: track),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecentlyPlayedSection(BuildContext context, MusicProvider provider) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 200,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          itemCount: provider.recentlyPlayed.length.clamp(0, 10),
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, index) {
            final track = provider.recentlyPlayed[index];
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ThemedCard(
                imageUrl: track.albumArtUrl,
                title: track.trackName,
                subtitle: track.artistName,
                width: 150,
                height: 150,
                onTap: () => provider.playTrack(track),
                onLongPress: () => ThemedOptionsSheet.show(
                  context,
                  track: track,
                  isRecentlyPlayedContext: true,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNewReleasesSection(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 200,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          itemCount: _newReleases!.length.clamp(0, 10),
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, index) {
            final track = _newReleases![index];
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ThemedCard(
                imageUrl: track.albumArtUrl,
                title: track.trackName,
                subtitle: track.artistName,
                width: 150,
                height: 150,
                onTap: () => context.read<MusicProvider>().playTrack(
                  track,
                  playlistTracks: _newReleases!,
                ),
                onLongPress: () => ThemedOptionsSheet.show(context, track: track),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopArtistsSection(BuildContext context, MusicProvider provider) {
    // Extract unique artists from trending tracks
    final uniqueArtists = <String, Track>{};
    for (final track in provider.trendingTracks) {
      if (!uniqueArtists.containsKey(track.artistName)) {
        uniqueArtists[track.artistName] = track;
      }
    }
    final artists = uniqueArtists.values.toList();

    return SliverToBoxAdapter(
      child: SizedBox(
        height: 120,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          itemCount: artists.length.clamp(0, 8),
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, index) {
            final track = artists[index];
            return Padding(
              padding: const EdgeInsets.only(right: 16),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  provider.fetchArtistTracks(track.artistName);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.grey[850],
                        backgroundImage: track.albumArtUrl.isNotEmpty
                            ? NetworkImage(track.albumArtUrl)
                            : null,
                        child: track.albumArtUrl.isEmpty
                            ? const Icon(Icons.person, size: 36, color: Colors.white54)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 80,
                      child: Text(
                        track.artistName,
                        style: AppFont.style(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
