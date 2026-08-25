import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/discover_models.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../services/innertube/innertube_service.dart';
import '../widgets/swipe_deck.dart';
import '../widgets/themed_playlist_detail_screen.dart';

/// Curated-content tab: charts heroes, new releases and moods & genres.
/// All data comes from InnerTube browse endpoints cached at service level.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _innerTube = InnerTubeService.instance;
  List<Track>? _newReleases;
  List<DiscoverMood>? _moods;
  String? _error;

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
    setState(() {
      _error = null;
    });
    try {
      final releases = await _innerTube.getNewReleases(limit: 14);
      final moods = await _innerTube.getMoodsAndGenres();
      if (!mounted) return;
      setState(() {
        _newReleases = releases;
        _moods = moods;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'discover_failed');
    }
  }

  void _openItem(Track item) {
    final provider = context.read<MusicProvider>();
    final id = item.id;
    final isBrowse =
        id.startsWith('VL') || id.startsWith('PL') || id.startsWith('OLAK');
    if (isBrowse) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ThemedPlaylistDetailScreen(
            playlistId: id.startsWith('VL') ? id.substring(2) : id,
            playlistName: item.trackName,
            playlistImage: item.albumArtUrl,
          ),
        ),
      );
      return;
    }
    provider.playTrack(item);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: _load,
      child: _error != null
          ? ListView(
              children: [
                const SizedBox(height: 120),
                const Icon(Icons.explore_off_rounded,
                    size: 48, color: Colors.white24),                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Could not load Discover',
                    style: GoogleFonts.outfit(color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: FilledButton(onPressed: _load, child: const Text('Retry')),
                ),
              ],
            )
          : CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
              _buildChartsSliver(context),
              _buildShelfHeader('New Releases'),
              _buildNewReleasesSliver(),
              _buildShelfHeader('Moods & Genres'),
              _buildMoodsSliver(),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
    );
  }

  SliverToBoxAdapter _buildShelfHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Text(
          title,
          style: GoogleFonts.splineSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildChartsSliver(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        final pool = <Track>{
          for (final t in provider.trendingTracks.take(10)) t,
          if (_newReleases != null)
            for (final t in _newReleases!.take(10)) t,
        }.toList();
        if (pool.isEmpty) {
          return const _SectionSkeleton(height: 480);
        }
        return SliverToBoxAdapter(
          child: SwipeDeck(
            tracks: pool,
            onAction: (track, action) {
              switch (action) {
                case SwipeAction.like:
                  provider.recommendationService.recordSwipeOutcome(
                    artistName: track.artistName,
                    wasAccepted: true,
                  );
                  provider.playTrack(track);
                  break;
                case SwipeAction.skip:
                  provider.recommendationService.recordSwipeOutcome(
                    artistName: track.artistName,
                    wasAccepted: false,
                  );
                  break;
                case SwipeAction.queue:
                  provider.addToQueue(track);
                  break;
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildNewReleasesSliver() {
    final releases = _newReleases;
    if (releases == null) return const SliverToBoxAdapter(child: _SectionSkeleton(height: 190));
    if (releases.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 190,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: releases.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final item = releases[index];
            return RepaintBoundary(
              child: _ReleaseCard(item: item, onTap: () => _openItem(item)),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMoodsSliver() {
    final moods = _moods;
    if (moods == null) return const SliverToBoxAdapter(child: _SectionSkeleton(height: 120));
    if (moods.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 3.4,
        ),
        delegate: SliverChildBuilderDelegate(
          childCount: moods.take(24).length,
          (context, index) {
            final mood = moods[index];
            return _MoodChip(
              mood: mood,
              onTap: () => _openMood(context, mood),
            );
          },
        ),
      ),
    );
  }

  void _openMood(BuildContext context, DiscoverMood mood) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MoodTracksScreen(mood: mood),
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.item, required this.onTap});

  final Track item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CachedNetworkImage(
                imageUrl: item.albumArtUrl,
                width: 140,
                height: 140,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 200),
                errorWidget: (_, __, ___) =>
                    Container(width: 140, height: 140, color: Colors.grey[900]),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.trackName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                  fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            Text(
              item.artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(fontSize: 11.5, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({required this.mood, required this.onTap});

  final DiscoverMood mood;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        splashColor: accent.withValues(alpha: 0.15),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            mood.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionSkeleton extends StatefulWidget {
  const _SectionSkeleton({required this.height});

  final double height;

  @override
  State<_SectionSkeleton> createState() => _SectionSkeletonState();
}

class _SectionSkeletonState extends State<_SectionSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.25, end: 0.6).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

/// Track list behind a Moods & Genres chip.
class MoodTracksScreen extends StatefulWidget {
  const MoodTracksScreen({super.key, required this.mood});

  final DiscoverMood mood;

  @override
  State<MoodTracksScreen> createState() => _MoodTracksScreenState();
}

class _MoodTracksScreenState extends State<MoodTracksScreen> {
  late final Future<List<Track>> _future =
      InnerTubeService.instance.getMoodTracks(widget.mood.params);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.mood.title)),
      body: FutureBuilder<List<Track>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? const <Track>[];
          if (items.isEmpty) {
            return Center(
              child: Text('Nothing here yet',
                  style: GoogleFonts.outfit(color: Colors.white54)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            physics: const BouncingScrollPhysics(),
            itemExtent: 72,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final track = items[index];
              final playable =
                  track.id.length == 11 && !track.id.contains(' ');
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: track.albumArtUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Container(width: 48, height: 48, color: Colors.grey[900]),
                  ),
                ),
                title: Text(track.trackName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(track.artistName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: playable
                    ? const Icon(Icons.play_arrow_rounded)
                    : const Icon(Icons.playlist_play_rounded),
                onTap: () => playable
                    ? provider.playTrack(track, playlistTracks: items)
                    : Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ThemedPlaylistDetailScreen(
                            playlistId: track.id.startsWith('VL')
                                ? track.id.substring(2)
                                : track.id,
                            playlistName: track.trackName,
                            playlistImage: track.albumArtUrl,
                          ),
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
