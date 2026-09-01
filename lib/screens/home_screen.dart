import 'dart:async';

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

/// Home: one continuous, artwork-driven listening surface.
///
/// Hierarchy — hero (continue listening) dominates; rails and rows support;
/// genres/artists stay quiet. No internal tabs: Discover lives in the bottom
/// navigation, not duplicated here. Playback always flows through the global
/// MusicProvider; Home only observes.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    value: 0,
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
    super.dispose();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Late night listening';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
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
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 130),
            children: [
              _buildHeader(context),
              const SizedBox(height: 16),
              StaggerIn(
                controller: _entry,
                interval: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
                child: _buildHeroSection(context),
              ),
              StaggerIn(
                controller: _entry,
                interval: const Interval(0.25, 0.75, curve: Curves.easeOutCubic),
                child: _buildJumpBackIn(context),
              ),
              StaggerIn(
                controller: _entry,
                interval: const Interval(0.4, 0.9, curve: Curves.easeOutCubic),
                child: _buildForYou(context),
              ),
              StaggerIn(
                controller: _entry,
                interval: const Interval(0.55, 1.0, curve: Curves.easeOutCubic),
                child: _buildWhatsHot(context),
              ),
              const SizedBox(height: 8),
              StaggerIn(
                controller: _entry,
                interval: const Interval(0.65, 1.0, curve: Curves.easeOutCubic),
                child: _buildArtists(context),
              ),
              const SizedBox(height: 4),
              StaggerIn(
                controller: _entry,
                interval: const Interval(0.75, 1.0, curve: Curves.easeOutCubic),
                child: _buildGenres(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_greeting(), style: type_tokens.Type.title(context)),
          GlassCircleButton(
            icon: Icons.settings_outlined,
            iconSize: 22,
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

  // ── Hero: continue listening ─────────────────────────────────────────────

  Widget _buildHeroSection(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final Track? heroTrack = provider.currentTrack ??
        (provider.recentlyPlayed.isNotEmpty ? provider.recentlyPlayed.first : null) ??
        (provider.recommendedTracks.isNotEmpty ? provider.recommendedTracks.first : null) ??
        (provider.trendingTracks.isNotEmpty ? provider.trendingTracks.first : null);

    if (heroTrack == null) return const _HeroSkeleton();

    final fromHistory = provider.recentlyPlayed.any((t) => t.id == heroTrack.id);
    final eyebrow = fromHistory ? 'Jump back in' : 'Picked for you';

    final size = MediaQuery.sizeOf(context);
    final heroHeight = (size.height * 0.46).clamp(300.0, 400.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GlassTokens.hMargin),
      child: _HeroCard(
        track: heroTrack,
        eyebrow: eyebrow,
        height: heroHeight,
        onPlay: () => _play(context, heroTrack, _heroContextList(provider)),
        onOverflow: () => ThemedOptionsSheet.show(context, track: heroTrack),
      ),
    );
  }

  List<Track> _heroContextList(MusicProvider provider) {
    if (provider.recentlyPlayed.isNotEmpty) return provider.recentlyPlayed;
    if (provider.recommendedTracks.isNotEmpty) return provider.recommendedTracks;
    return provider.trendingTracks;
  }

  void _play(BuildContext context, Track track, List<Track> contextList) {
    HapticFeedback.lightImpact();
    context.read<MusicProvider>().playTrack(track, playlistTracks: contextList);
  }

  // ── Jump Back In rail ────────────────────────────────────────────────────

  Widget _buildJumpBackIn(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final recents = provider.recentlyPlayed
        .where((t) => t.id != provider.currentTrack?.id)
        .toList();
    if (recents.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const HomeSectionHeader(title: 'Jump back in'),
        SizedBox(
          height: 176,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: recents.length,
            itemBuilder: (context, index) {
              final track = recents[index];
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: RailCard(
                  artUrl: track.albumArtUrl,
                  title: track.trackName,
                  subtitle: track.artistName,
                  size: 132,
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

  // ── For You rows ─────────────────────────────────────────────────────────

  Widget _buildForYou(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final recs = provider.recommendedTracks.isNotEmpty
        ? provider.recommendedTracks
        : provider.trendingTracks.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        const HomeSectionHeader(title: 'For you'),
        if (recs.isEmpty)
          const _RowsSkeleton()
        else
          ...recs.map((track) {
            final isPlaying = provider.currentTrack?.id == track.id &&
                provider.isPlaying;
            return ForYouRow(
              artUrl: track.albumArtUrl,
              title: track.trackName,
              subtitle: track.artistName,
              isPlaying: isPlaying,
              onTap: () => _play(context, track, recs),
              onLongPress: () =>
                  ThemedOptionsSheet.show(context, track: track),
            );
          }),
      ],
    );
  }

  // ── What's Hot rail ──────────────────────────────────────────────────────

  Widget _buildWhatsHot(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final trending = provider.trendingTracks;
    if (trending.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        HomeSectionHeader(
          title: "What's hot",
          onViewAll: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ThemedTrendingNowScreen()),
          ),
        ),
        SizedBox(
          height: 196,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: trending.length,
            itemBuilder: (context, index) {
              final track = trending[index];
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: RailCard(
                  artUrl: track.albumArtUrl,
                  title: track.trackName,
                  subtitle: track.artistName,
                  size: 152,
                  onTap: () => _play(context, track, trending),
                  onLongPress: () =>
                      ThemedOptionsSheet.show(context, track: track),
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
    for (final track
        in [...provider.recentlyPlayed, ...provider.trendingTracks]) {
      if (track.artistName.isEmpty) continue;
      if (seen.add(track.artistName)) artists.add(track);
      if (artists.length >= 10) break;
    }
    if (artists.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        HomeSectionHeader(
          title: 'Artists',
          onViewAll: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ThemedAllArtistsScreen()),
          ),
        ),
        SizedBox(
          height: 104,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: artists.length,
            itemBuilder: (context, index) {
              final artist = artists[index];
              return Padding(
                padding: const EdgeInsets.only(right: 16),
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

  // ── Genres ───────────────────────────────────────────────────────────────

  Widget _buildGenres(BuildContext context) {
    final provider = context.read<MusicProvider>();
    const genres = [
      (name: 'Pop', icon: Icons.music_note_rounded),
      (name: 'Hip-Hop', icon: Icons.mic_rounded),
      (name: 'Rock', icon: Icons.electric_bolt_rounded),
      (name: 'Chill', icon: Icons.nightlight_round),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        HomeSectionHeader(
          title: 'Moods',
          onViewAll: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ThemedAllGenresScreen()),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: genres.length,
            itemBuilder: (context, index) {
              final genre = genres[index];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GenreChip(
                  label: genre.name,
                  icon: genre.icon,
                  onTap: () {
                    provider.fetchGenreTracks(genre.name);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ThemedGenreSongsScreen(genre: genre.name),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Hero card ────────────────────────────────────────────────────────────────

class _HeroCard extends StatefulWidget {
  const _HeroCard({
    required this.track,
    required this.eyebrow,
    required this.height,
    required this.onPlay,
    required this.onOverflow,
  });

  final Track track;
  final String eyebrow;
  final double height;
  final VoidCallback onPlay;
  final VoidCallback onOverflow;

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
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
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Artwork carries the visual weight.
                if (widget.track.albumArtUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: widget.track.albumArtUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 720,
                    fadeInDuration: const Duration(milliseconds: 250),
                    errorWidget: (_, __, ___) =>
                        Container(color: Colors.white.withValues(alpha: 0.04)),
                  )
                else
                  Container(color: Colors.white.withValues(alpha: 0.04)),
                // Legibility scrim, grounded and quiet.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.30, 1.0],
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.86),
                      ],
                    ),
                  ),
                ),
                // Bottom content layer.
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 18,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.eyebrow.toUpperCase(),
                              style: type_tokens.Type.caption(context)
                                  .copyWith(letterSpacing: 1.2),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.track.trackName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: type_tokens.Type.title(context)
                                  .copyWith(fontSize: 25),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.track.artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: type_tokens.Type.metadata(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Glass play control (tier 5: active control).
                      GlassSurface(
                        tier: GlassTier.floating,
                        borderRadius: 30,
                        padding: EdgeInsets.zero,
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Icon(Icons.play_arrow_rounded,
                              size: 32,
                              color: accent.withValues(alpha: 0.95)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Skeletons (geometry-matched, no spinner) ─────────────────────────────────

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({this.width, required this.height, this.radius = 14});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
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
    final heroHeight = (size.height * 0.46).clamp(300.0, 400.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GlassTokens.hMargin),
      child: _SkeletonBox(height: heroHeight, radius: 24),
    );
  }
}

class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Row(
              children: [
                const _SkeletonBox(width: 52, height: 52, radius: 10),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonBox(
                          height: 13,
                          width: (180.0 - i * 30).clamp(80.0, 180.0),
                          radius: 6),
                      const SizedBox(height: 6),
                      const _SkeletonBox(height: 11, width: 110, radius: 6),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
