import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../design/tokens/motion.dart';
import '../design/tokens/type.dart' as type_tokens;
import '../theme/glass_tokens.dart';
import '../widgets/glass_circle_button.dart';
import '../widgets/glass_surface.dart';
import '../widgets/home_sections.dart';
import '../widgets/themed_all_artists_screen.dart';
import '../widgets/themed_all_genres_screen.dart';
import '../widgets/themed_genre_songs_screen.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/themed_options_sheet.dart';
import '../widgets/themed_settings_screen.dart';
import '../widgets/themed_trending_now_screen.dart';

/// Home: a curated listening environment.
///
/// One primary carousel (top picks), then increasingly quiet sections.
/// Distinct presentations per content type — no card wall, no repeated
/// poster. Playback flows through the global MusicProvider; Home only
/// observes. Glass is reserved for interactive controls.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: 0,
  );
  late final PageController _topPicksController = PageController(
    viewportFraction: 0.86,
  );
  late final PageController _whatsHotController = PageController(
    viewportFraction: 0.52,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entry.forward();
    });
  }

  @override
  void dispose() {
    _entry.dispose();
    _topPicksController.dispose();
    _whatsHotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Bottom inset derived from the actual persistent surfaces: mini-player
    // inset token + navigation bar + breathing gap + system gesture area.
    final bottomInset = GlassTokens.playerBottomInset +
        88 +
        MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent, // Ambient canvas behind
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          backgroundColor: const Color(0xFF141414),
          onRefresh: () => context
              .read<MusicProvider>()
              .fetchTrendingTracks(forceRefresh: true),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: StaggerIn(
                  controller: _entry,
                  interval:
                      const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
                  child: _buildTopPicks(context),
                ),
              ),
              SliverToBoxAdapter(
                child: StaggerIn(
                  controller: _entry,
                  interval:
                      const Interval(0.2, 0.65, curve: Curves.easeOutCubic),
                  child: _buildJumpBackIn(context),
                ),
              ),
              SliverToBoxAdapter(
                child: StaggerIn(
                  controller: _entry,
                  interval:
                      const Interval(0.35, 0.8, curve: Curves.easeOutCubic),
                  child: _buildMadeForYou(context),
                ),
              ),
              SliverToBoxAdapter(
                child: StaggerIn(
                  controller: _entry,
                  interval:
                      const Interval(0.5, 0.9, curve: Curves.easeOutCubic),
                  child: _buildWhatsHot(context),
                ),
              ),
              SliverToBoxAdapter(
                child: StaggerIn(
                  controller: _entry,
                  interval:
                      const Interval(0.6, 1.0, curve: Curves.easeOutCubic),
                  child: _buildArtists(context),
                ),
              ),
              SliverToBoxAdapter(
                child: StaggerIn(
                  controller: _entry,
                  interval:
                      const Interval(0.7, 1.0, curve: Curves.easeOutCubic),
                  child: _buildMoods(context),
                ),
              ),
              SliverPadding(padding: EdgeInsets.only(top: bottomInset - 88)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header: one title, small utility action ──────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
      child: Row(
        children: [
          Expanded(child: Text('Home', style: type_tokens.Type.title(context))),
          GlassCircleButton(
            icon: Icons.settings_outlined,
            iconSize: 20,
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ThemedSettingsScreen()),
              );
            },
            semanticLabel: 'Settings',
          ),
        ],
      ),
    );
  }

  // ── Top Picks carousel ───────────────────────────────────────────────────

  List<Track> _topPicksList(MusicProvider provider) {
    if (provider.recommendedTracks.isNotEmpty) {
      return provider.recommendedTracks.take(5).toList();
    }
    if (provider.trendingTracks.isNotEmpty) {
      return provider.trendingTracks.take(5).toList();
    }
    return const [];
  }

  Widget _buildTopPicks(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final picks = _topPicksList(provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionHeader(title: 'Top picks for you'),
        if (picks.isEmpty)
          const _HeroSkeleton()
        else
          SizedBox(
            height:
                (MediaQuery.sizeOf(context).height * 0.40).clamp(280.0, 360.0),
            child: ParallaxMediaCarousel(
              controller: _topPicksController,
              count: picks.length,
              itemBuilder: (context, index, pageOffset) {
                final track = picks[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _TopPickCard(
                    track: track,
                    pageOffset: pageOffset,
                    parallaxFactor: 0.16,
                    onPlay: () => _play(context, track, picks),
                    onOverflow: () =>
                        ThemedOptionsSheet.show(context, track: track),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _play(BuildContext context, Track track, List<Track> contextList) {
    HapticFeedback.lightImpact();
    context.read<MusicProvider>().playTrack(track, playlistTracks: contextList);
  }

  // ── Jump back in: compact continuation rail ──────────────────────────────

  Widget _buildJumpBackIn(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final recents = provider.recentlyPlayed
        .where((t) => t.id != provider.currentTrack?.id)
        .toList();
    if (recents.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const HomeSectionHeader(title: 'Jump back in'),
        SizedBox(
          height: 148,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: recents.length,
            itemBuilder: (context, index) {
              final track = recents[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: RailCard(
                  artUrl: track.albumArtUrl,
                  title: track.trackName,
                  subtitle: track.artistName,
                  size: 116,
                  onTap: () => _play(context, track, recents),
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
      ],
    );
  }

  // ── Made for you: compact open rows (grounded, not cards) ────────────────

  Widget _buildMadeForYou(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final recs = provider.recommendedTracks.isNotEmpty
        ? provider.recommendedTracks.skip(5).take(6).toList()
        : provider.trendingTracks.take(6).toList();
    if (recs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const HomeSectionHeader(title: 'Made for you'),
        ...recs.map((track) {
          final isPlaying =
              provider.currentTrack?.id == track.id && provider.isPlaying;
          return ForYouRow(
            artUrl: track.albumArtUrl,
            title: track.trackName,
            subtitle: track.artistName,
            isPlaying: isPlaying,
            onTap: () => _play(context, track, recs),
            onLongPress: () => ThemedOptionsSheet.show(context, track: track),
          );
        }),
      ],
    );
  }

  // ── What's hot: editorial parallax rail ──────────────────────────────────

  Widget _buildWhatsHot(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final trending = provider.trendingTracks;
    if (trending.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        HomeSectionHeader(
          title: "What's hot",
          onViewAll: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ThemedTrendingNowScreen()),
          ),
        ),
        SizedBox(
          height: 224,
          child: ParallaxMediaCarousel(
            controller: _whatsHotController,
            count: trending.length,
            itemBuilder: (context, index, pageOffset) {
              final track = trending[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: PressableScale(
                  onTap: () => _play(context, track, trending),
                  onLongPress: () =>
                      ThemedOptionsSheet.show(context, track: track),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Artwork = the card's dominant object, open (no chrome).
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ParallaxArtwork(
                            artUrl: track.albumArtUrl,
                            pageOffset: pageOffset,
                            parallaxFactor: 0.12,
                            memCacheWidth: 420,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Metadata anchored to the card, calm hierarchy.
                      Text(
                        track.trackName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type_tokens.Type.label(context),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type_tokens.Type.metadata(context),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Artists ──────────────────────────────────────────────────────────────

  Widget _buildArtists(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final seen = <String>{};
    final artists = <Track>[];
    for (final track in [
      ...provider.recentlyPlayed,
      ...provider.trendingTracks
    ]) {
      if (track.artistName.isEmpty) continue;
      if (seen.add(track.artistName)) artists.add(track);
      if (artists.length >= 10) break;
    }
    if (artists.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        HomeSectionHeader(
          title: 'Artists',
          onViewAll: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ThemedAllArtistsScreen()),
          ),
        ),
        SizedBox(
          height: 132,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: artists.length,
            itemBuilder: (context, index) {
              final artist = artists[index];
              return Padding(
                // Spacious: each portrait independent, next one peeks.
                padding: const EdgeInsets.only(right: 28),
                child: ArtistPortrait(
                  name: artist.artistName,
                  imageUrl: artist.albumArtUrl,
                  onTap: () => _openArtist(context, artist),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openArtist(BuildContext context, Track artistTrack) {
    HapticFeedback.selectionClick();
    final provider = context.read<MusicProvider>();
    provider.navigateToArtistObject(artistTrack);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ThemedArtistDetailScreen(
          artistId: artistTrack.id,
          artistName: artistTrack.artistName,
          artistImage: artistTrack.albumArtUrl,
        ),
      ),
    );
  }

  // ── Moods: editorial text-led tiles, lowest on the page ──────────────────

  Widget _buildMoods(BuildContext context) {
    final provider = context.read<MusicProvider>();
    const moods = [
      'Pop',
      'Hip-Hop',
      'Rock',
      'Chill',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        HomeSectionHeader(
          title: 'Moods',
          onViewAll: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ThemedAllGenresScreen()),
          ),
        ),
        // Wrap: widths follow labels, reads as a word cloud not filter pills.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final mood in moods)
                EditorialMoodTile(
                  label: mood,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    provider.fetchGenreTracks(mood);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ThemedGenreSongsScreen(genre: mood),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        // Deliberate quiet ending before mini-player/navigation.
        const SizedBox(height: 28),
      ],
    );
  }
}

// ── Top pick carousel card ───────────────────────────────────────────────────

class _TopPickCard extends StatefulWidget {
  const _TopPickCard({
    required this.track,
    required this.pageOffset,
    required this.onPlay,
    required this.onOverflow,
    this.parallaxFactor = 0.16,
  });

  final Track track;
  final double pageOffset;
  final VoidCallback onPlay;
  final VoidCallback onOverflow;
  final double parallaxFactor;

  @override
  State<_TopPickCard> createState() => _TopPickCardState();
}

class _TopPickCardState extends State<_TopPickCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPlay,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onLongPress: widget.onOverflow,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: Motion.fast,
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Layer 1-2: artwork + parallax (oversized, clipped inside).
              ParallaxArtwork(
                artUrl: widget.track.albumArtUrl,
                pageOffset: widget.pageOffset,
                parallaxFactor: widget.parallaxFactor,
                memCacheWidth: 640,
              ),
              // Layer 3: readability scrim — anchored to the CARD, not the
              // moving artwork, so text stays stable during the drag.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.32, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.84),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Picked for you',
                            style: type_tokens.Type.caption(context)
                                .copyWith(letterSpacing: 1.1),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.track.trackName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type_tokens.Type.title(context)
                                .copyWith(fontSize: 23),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.track.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type_tokens.Type.metadata(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    GlassSurface(
                      tier: GlassTier.floating,
                      borderRadius: 30,
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        width: 50,
                        height: 50,
                        child: Icon(Icons.play_arrow_rounded,
                            size: 28, color: accent.withValues(alpha: 0.95)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Skeletons (geometry-matched, no spinner) ─────────────────────────────────

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height, this.radius = 14});

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final heroHeight = (size.height * 0.40).clamp(280.0, 360.0);
    return _SkeletonBox(height: heroHeight, radius: 22);
  }
}
