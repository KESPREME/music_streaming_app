import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../services/innertube/innertube_service.dart';
import '../widgets/swipe_deck.dart';

/// Discover = pure swipe-discovery (dating-style deck).
///
/// Every card decision feeds the taste engine: right = like + play,
/// left = skip, play button = queue. Pool mixes trending + fresh releases.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _innerTube = InnerTubeService.instance;
  List<Track>? _newReleases;
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

    return RefreshIndicator(
      color: accent,
      onRefresh: _load,
      child: _error != null
          ? ListView(
              children: [
                const SizedBox(height: 140),
                const Icon(Icons.explore_off_rounded,
                    size: 48, color: Colors.white24),
                const SizedBox(height: 12),
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
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 2),
                    child: Row(
                      children: [
                        Icon(Icons.style_rounded,
                            size: 18, color: accent.withValues(alpha: 0.8)),
                        const SizedBox(width: 8),
                        Text(
                          'SWIPE TO DISCOVER',
                          style: GoogleFonts.splineSans(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildDeckSliver(context),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
    );
  }

  Widget _buildDeckSliver(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        final pool = <Track>{
          for (final t in provider.trendingTracks.take(12)) t,
          if (_newReleases != null)
            for (final t in _newReleases!.take(12)) t,
        }.toList();
        if (pool.isEmpty) {
          return const SliverToBoxAdapter(child: _DeckSkeleton());
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
}

class _DeckSkeleton extends StatefulWidget {
  const _DeckSkeleton();

  @override
  State<_DeckSkeleton> createState() => _DeckSkeletonState();
}

class _DeckSkeletonState extends State<_DeckSkeleton>
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
        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 16),
        child: Container(
          height: 440,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),
    );
  }
}
