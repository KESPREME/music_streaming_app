import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../services/home/home_models.dart';
import '../services/home/ytm_home_source.dart' show HomeLoadTrace;
import '../services/innertube/innertube_service.dart';
import '../presentation/home/home_playback.dart'
    show HomePlaybackController, HomePlayAction;
import '../presentation/home/home_presentation.dart';
import '../design/tokens/motion.dart';
import '../presentation/home/home_tokens.dart' as t;
import '../theme/glass_tokens.dart';
import '../widgets/glass_circle_button.dart';
import '../widgets/glass_surface.dart';
import '../widgets/home_sections.dart';
import '../widgets/themed_all_genres_screen.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/themed_options_sheet.dart';
import '../widgets/themed_playlist_detail_screen.dart';
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
    viewportFraction: 0.88,
  );
  late final PageController _whatsHotController = PageController(
    viewportFraction: 0.78,
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
          onRefresh: () async {
            final previous = context.read<MusicProvider>().homeFeed;
            await context.read<MusicProvider>().refreshHomeFeed();
            // Also refresh trusted discovery sources in background.
            final provider = context.read<MusicProvider>();
            unawaited(provider.fetchTrendingTracks(forceRefresh: true));
            if (kDebugMode) {
              debugPrint('Home: pull-to-refresh complete, '
                  'sections=${provider.homeFeed?.sections.length ?? 0} '
                  '(previous: ${previous?.sections.length ?? 0})');
            }
          },
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
              // Second+ tiers: rebuild only when Home content lists change,
              // never on playback ticks or palette updates.
              SliverToBoxAdapter(
                child: Selector<MusicProvider, int>(
                  selector: (_, p) => p.homeContentVersion,
                  child: _LowerSections(
                    bottomInset: bottomInset,
                    excludeHeroSectionId:
                        _heroCandidate(context.read<MusicProvider>())?.$1.id,
                  ),
                  builder: (context, version, lower) => lower!,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header: one title, small utility action ──────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(t.HomeTokens.contentPadding, 12, 16, 0),
      child: Row(
        children: [
          Expanded(child: Text('Home', style: t.HomeTokens.homeTitle(context))),
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

  // ── Hero ─────────────────────────────────────────────────────────────────

  /// Hero eligibility (spec #28): source-nominated candidate from a strong
  /// SONG shelf — every item must carry a real videoId (11-char), because
  /// the hero play button routes through playTrack. Live-run fix: the
  /// enriched "New releases" shelf contains album items (MPREb ids) that
  /// previously passed this filter via _trackFromHomeItem nulls being
  /// dropped unevenly, then failed at play time. The filter is now strict
  /// AND the semantic type is checked — an album grid must never become
  /// the "Picked for you" hero.
  (HomeSection, List<Track>)? _heroCandidate(MusicProvider provider) {
    final feed = provider.homeFeed;
    if (feed == null) return null;
    for (final section in feed.sections) {
      if (section.dominantType != HomeContentType.song) continue;
      if (section.items
          .any((i) => !HomePlaybackController.isPlayableSongItem(i))) {
        continue;
      }
      final picks = section.items
          .map(homeItemToTrack)
          .whereType<Track>()
          .take(8)
          .toList();
      if (picks.length >= 3) return (section, picks);
    }
    return null;
  }

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
    final hero = _heroCandidate(provider);

    // Curated feed hero → render with the source's real shelf title.
    if (hero != null) {
      final (section, picks) = hero;
      return _buildHeroCarousel(context, picks, section.title, section.id);
    }

    // No valid hero: fall back to local data. If that's empty too, collapse
    // the section completely — never reserve a giant blank region.
    final picks = _topPicksList(provider);
    if (picks.isEmpty) return const SizedBox.shrink();
    return _buildTopPicksFallback(context, picks);
  }

  Widget _buildHeroCarousel(
      BuildContext context, List<Track> picks, String title, String sectionId) {
    // Hero height derives from card width × 4:5 aspect ratio (spec #9),
    // not from viewport height — the card must be ~88% content width.
    final contentW =
        t.HomeTokens.contentWidth(MediaQuery.sizeOf(context).width);
    final heroH = (contentW * t.HomeTokens.heroCardFraction * (5 / 4))
        .clamp(280.0, 380.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title: title),
        SizedBox(
          height: heroH,
          child: ParallaxMediaCarousel(
            key: ValueKey('hero_$sectionId'),
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

  /// Top-picks fallback body (recommendation engine / trending).
  Widget _buildTopPicksFallback(BuildContext context, List<Track> picks) {
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

/// One curated-feed shelf rendered through the presentation planner
/// (spec #3/#41): semantic classification → layout kind → geometry.
/// The section's own title displays verbatim; provenance never re-titles.
class _FeedSection extends StatelessWidget {
  const _FeedSection({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    final plan = planPresentation(section);
    final tracks =
        section.items.map(homeItemToTrack).whereType<Track>().toList();

    // Zero-invisible-space (spec #21): unrenderable counts collapse
    // entirely — no reserved rail/grid geometry for absent content.
    if (plan.layoutKind == HomeLayoutKind.compactList) {
      return tracks.length >= 3
          ? _CompactListSection(section: section, tracks: tracks)
          : const SizedBox.shrink();
    }
    if (plan.layoutKind == HomeLayoutKind.artistRail) {
      return _ArtistShelf(section: section);
    }
    if (plan.layoutKind == HomeLayoutKind.landscapeRail16x9) {
      return _VideoShelf(section: section);
    }
    if (plan.layoutKind == HomeLayoutKind.playlistRail) {
      return _PlaylistShelf(section: section, tracks: tracks);
    }
    if (plan.layoutKind == HomeLayoutKind.squareGrid) {
      return section.items.isNotEmpty
          ? _AlbumGridSection(section: section)
          : const SizedBox.shrink();
    }
    // squareRail fallback — per-item dispatch (mixed shelves may contain
    // songs, videos AND playlist/album cards).
    return section.items.length >= 3
        ? _SquareRailSection(section: section)
        : const SizedBox.shrink();
  }
}

/// Square rail with PER-ITEM playback dispatch (spec #29): mixed shelves
/// (songs + videos + playlist/album cards) route each tap through
/// HomePlaybackController — songs/videos play, collections navigate.
/// This is the fix for "other cards don't play": every card gets a valid
/// action contract, never a broken play affordance.
class _SquareRailSection extends StatelessWidget {
  const _SquareRailSection({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title: section.title),
        SizedBox(
          height: 178 + homeRailTextBlockHeight(context),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: t.HomeTokens.contentPadding),
            physics: const BouncingScrollPhysics(),
            itemCount: section.items.length,
            itemBuilder: (context, index) {
              final item = section.items[index];
              return Padding(
                key: ValueKey('rail_{item.id}'),
                padding: const EdgeInsets.only(right: 14),
                child: PressableScale(
                  onTap: () => HomePlaybackController.activate(
                    context,
                    item,
                    sectionTitle: section.title,
                    contextPlaylist: section.items
                        .map(homeItemToTrack)
                        .whereType<Track>()
                        .toList(),
                  ),
                  onLongPress: () {
                    final track = homeItemToTrack(item);
                    if (track != null) {
                      ThemedOptionsSheet.show(context, track: track);
                    }
                  },
                  child: SizedBox(
                    // Responsive square card ~46% content width
                    width: t.HomeTokens.contentWidth(
                            MediaQuery.sizeOf(context).width) *
                        t.HomeTokens.squareCardFraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(t.HomeTokens.cardRadius),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: item.artworkUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: item.artworkUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 240,
                                    fadeInDuration:
                                        const Duration(milliseconds: 200),
                                    errorWidget: (_, __, ___) => Container(
                                        color: Colors.white
                                            .withValues(alpha: 0.06)),
                                  )
                                // PARTIAL support (spec #8): placeholder,
                                // item retained — never a dead card.
                                : Container(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    child: const Icon(Icons.music_note_rounded,
                                        color: Colors.white24),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.HomeTokens.cardTitle(context),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.HomeTokens.cardMetadata(context),
                        ),
                      ],
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
}

/// Dense compact list rows (spec #12): thumbnail + title + artist — the
/// Muzo-style editorial block for trending/chart content. Height derives
/// from row count, never a fixed oversized container.
class _CompactListSection extends StatelessWidget {
  const _CompactListSection({required this.section, required this.tracks});

  final HomeSection section;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title: section.title),
        ...tracks.take(6).map((track) => ForYouRow(
              key: ValueKey('compact_${track.id}'),
              artUrl: track.albumArtUrl,
              title: track.trackName,
              subtitle: track.artistName,
              isPlaying: false,
              onTap: () {
                HapticFeedback.lightImpact();
                context
                    .read<MusicProvider>()
                    .playTrack(track, playlistTracks: tracks);
              },
              onLongPress: () => ThemedOptionsSheet.show(context, track: track),
            )),
      ],
    );
  }
}

/// Artist shelf from curated feed items.
class _ArtistShelf extends StatelessWidget {
  const _ArtistShelf({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title: section.title),
        SizedBox(
          height: 96 + homeRailTextBlockHeight(context),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: t.HomeTokens.contentPadding),
            physics: const BouncingScrollPhysics(),
            itemCount: section.items.length,
            itemBuilder: (context, index) {
              final item = section.items[index];
              return Padding(
                key: ValueKey('rail_{item.id}'),
                padding: const EdgeInsets.only(right: 28),
                child: ArtistPortrait(
                  name: item.title,
                  imageUrl: item.artworkUrl,
                  onTap: () {
                    final browseId = item.browseId;
                    if (browseId == null || !browseId.startsWith('UC')) {
                      return;
                    }
                    HapticFeedback.selectionClick();
                    final provider = context.read<MusicProvider>();
                    provider.navigateToArtistById(browseId).then((_) {
                      final artist = provider.currentArtistDetails;
                      if (artist == null || !context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ThemedArtistDetailScreen(
                            artistId: artist.id,
                            artistName: artist.name,
                            artistImage: artist.imageUrl,
                          ),
                        ),
                      );
                    });
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

/// Playlist shelf from curated feed items (landscape editorial covers).
class _PlaylistShelf extends StatelessWidget {
  const _PlaylistShelf({required this.section, required this.tracks});

  final HomeSection section;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title: section.title),
        SizedBox(
          height: 168 + homeRailTextBlockHeight(context),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: t.HomeTokens.contentPadding),
            physics: const BouncingScrollPhysics(),
            itemCount: section.items.length,
            itemBuilder: (context, index) {
              final item = section.items[index];
              return Padding(
                key: ValueKey('pl_${item.id}'),
                padding: const EdgeInsets.only(right: 12),
                child: PressableScale(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ThemedPlaylistDetailScreen(
                        playlistId: item.browseId ?? item.id,
                        playlistName: item.title,
                        playlistImage: item.artworkUrl,
                      ),
                    ),
                  ),
                  child: SizedBox(
                    width: 168,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(t.HomeTokens.cardRadius),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: item.artworkUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: item.artworkUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 280,
                                    errorWidget: (_, __, ___) => Container(
                                        color: Colors.white
                                            .withValues(alpha: 0.05)),
                                  )
                                : Container(
                                    color:
                                        Colors.white.withValues(alpha: 0.05)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.HomeTokens.cardTitle(context),
                        ),
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.HomeTokens.cardMetadata(context),
                        ),
                      ],
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
}

/// Video shelf: 16:9 wide thumbnails with creator metadata — a distinct
/// grammar from square artwork rails. Valid video-type items get a real
/// presentation path instead of UNSUPPORTED_PRESENTATION.
class _VideoShelf extends StatelessWidget {
  const _VideoShelf({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title: section.title),
        SizedBox(
          height: 124 + homeRailTextBlockHeight(context),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: t.HomeTokens.contentPadding),
            physics: const BouncingScrollPhysics(),
            itemCount: section.items.length,
            itemBuilder: (context, index) {
              final item = section.items[index];
              return Padding(
                key: ValueKey('rail_{item.id}'),
                padding: const EdgeInsets.only(right: 14),
                child: PressableScale(
                  // Unified dispatcher: playable items play (videoId via
                  // song pipeline), collections navigate. No fake affordance.
                  onTap: () {
                    final action = HomePlaybackController.activate(
                      context,
                      item,
                      sectionTitle: section.title,
                      contextPlaylist: section.items
                          .map(homeItemToTrack)
                          .whereType<Track>()
                          .toList(),
                    );
                    if (action == HomePlayAction.navigateCollection) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ThemedPlaylistDetailScreen(
                            playlistId: item.browseId ?? item.id,
                            playlistName: item.title,
                            playlistImage: item.artworkUrl,
                          ),
                        ),
                      );
                    }
                  },
                  child: SizedBox(
                    width: 216,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: item.artworkUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: item.artworkUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 440,
                                    errorWidget: (_, __, ___) => Container(
                                        color: Colors.white
                                            .withValues(alpha: 0.05)),
                                  )
                                : Container(
                                    color:
                                        Colors.white.withValues(alpha: 0.05)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.HomeTokens.cardTitle(context),
                        ),
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.HomeTokens.cardMetadata(context),
                        ),
                      ],
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
}

/// Data-driven lower-Home renderer. Observes only [homeContentVersion], so
/// playback ticks and palette updates never rebuild these sections. Order
/// adapts to available data; empty sections collapse entirely (spacing
/// included).
///
/// Content priority: curated feed shelves (honest source titles) > local
/// overlays (jump back in, playlists, moods) > legacy fallback sections
/// when no feed exists yet.
class _LowerSections extends StatelessWidget {
  const _LowerSections({
    required this.bottomInset,
    this.excludeHeroSectionId,
  });

  final double bottomInset;
  final String? excludeHeroSectionId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final sections = <Widget>[];
    final renderedKinds = <String>[];
    // Local overlay — continue listening, always first when meaningful.
    final recents = provider.recentlyPlayed
        .where((t) => t.id != provider.currentTrack?.id)
        .toList();
    if (recents.isNotEmpty) {
      sections.add(_JumpBackInSection(
        recents: recents,
        onPlay: (track) => _play(context, track, recents),
        onOptions: (track) => ThemedOptionsSheet.show(
          context,
          track: track,
          isRecentlyPlayedContext: true,
        ),
      ));
    }

    // Quick Picks (spec #2A/#61): deterministic personalized picks, high
    // on the page. Always shown when candidates exist (cold start uses
    // chart/trending as popularity prior).
    final quickPicks = provider.quickPicks;
    if (quickPicks.isNotEmpty) {
      sections.add(_QuickPicksSection(
        tracks: quickPicks,
        onPlay: (track) => _play(context, track, quickPicks),
        onOptions: (track) => ThemedOptionsSheet.show(context, track: track),
      ));
    }

    final feed = provider.homeFeed;
    if (feed != null) {
      // Curated shelves in source order — titles come from the source.
      for (final section in feed.sections) {
        if (section.id == excludeHeroSectionId) {
          if (kDebugMode) {
            HomeLoadTrace.loss(
              stage: 'presentation',
              shelf: section.title,
              reason: 'promoted to hero carousel',
            );
          }
          continue;
        }
        final plan = planPresentation(section);
        if (kDebugMode) renderedKinds.add(plan.semanticType.name);
        sections.add(_FeedSection(section: section));
      }
    } else {
      // No feed yet → legacy fallback sections (trusted sources only).
      final recs = provider.recommendedTracks;
      final mfy =
          (recs.length > 5 ? recs.skip(5).take(6) : recs.take(6)).toList();
      final mfyFallback =
          mfy.isEmpty ? provider.trendingTracks.take(6).toList() : mfy;
      if (mfyFallback.isNotEmpty) {
        sections.add(_MadeForYouSection(
          tracks: mfyFallback,
          isPlaying: (t) =>
              provider.currentTrack?.id == t.id && provider.isPlaying,
          onPlay: (track) => _play(context, track, mfyFallback),
          onOptions: (track) => ThemedOptionsSheet.show(context, track: track),
        ));
      }

      final trending = provider.trendingTracks;
      if (trending.isNotEmpty) {
        sections.add(_WhatsHotSection(
          tracks: trending,
          onPlay: (track) => _play(context, track, trending),
          onOptions: (track) => ThemedOptionsSheet.show(context, track: track),
          onSeeAll: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ThemedTrendingNowScreen()),
          ),
        ));
      }

      final newReleases = provider.newReleases;
      if (newReleases.isNotEmpty) {
        sections.add(_AlbumGridSection(
          section: HomeSection(
            id: 'new_releases_fallback',
            title: 'New releases',
            items: newReleases
                .take(6)
                .map((t) => HomeItem(
                      id: t.id,
                      videoId: t.id.length == 11 ? t.id : null,
                      browseId: t.id.length == 11 ? null : t.id,
                      title: t.trackName,
                      subtitle: t.artistName,
                      artworkUrl: t.albumArtUrl,
                      contentType: t.id.length == 11
                          ? HomeContentType.song
                          : HomeContentType.album,
                    ))
                .toList(),
            presentation: HomePresentation.grid,
            provenance: 'new_release',
          ),
        ));
      }

      final artists = _dedupeArtists(provider);
      if (artists.isNotEmpty) {
        sections.add(_ArtistsSection(
          artists: artists,
          onTap: (artist) => _openArtist(context, artist),
        ));
      }
    }

    // COLLECTIONS — user playlists (distinct from external recommendations).
    final playlists = provider.userPlaylists;
    if (playlists.isNotEmpty) {
      sections.add(_PlaylistsSection(playlists: playlists));
    }

    // EXPLORATION — moods: real Moods & Genres discovery from InnerTube,
    // not hardcoded filter pills.
    sections.add(const _MoodsSection());

    // Collapsed sections return SizedBox.shrink() — they must NOT
    // contribute their inter-section spacing (the giant-gap bug).
    final rendered = <Widget>[];
    for (final widget in sections) {
      if (widget is SizedBox) continue; // collapsed section — zero height
      rendered.add(widget);
    }
    if (kDebugMode) {
      // UI accounting (spec #25/#44): composer count vs rendered count —
      // presentation-level loss is never silent.
      final composerCount = provider.homeFeed?.sections.length ?? 0;
      debugPrint('HOME_UI composerSections=$composerCount '
          'rendered=${rendered.length} '
          'kinds=${renderedKinds.isEmpty ? "" : renderedKinds.join(",")}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rendered.length; i++) ...[
          if (i > 0) const SizedBox(height: 30),
          rendered[i],
        ],
        SizedBox(height: bottomInset - 88 + 28),
      ],
    );
  }

  List<Track> _dedupeArtists(MusicProvider provider) {
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
    return artists;
  }

  static void _play(
      BuildContext context, Track track, List<Track> contextList) {
    HapticFeedback.lightImpact();
    context.read<MusicProvider>().playTrack(track, playlistTracks: contextList);
  }
}

// ── Lower sections ───────────────────────────────────────────────────────────

class _JumpBackInSection extends StatelessWidget {
  const _JumpBackInSection({
    required this.recents,
    required this.onPlay,
    required this.onOptions,
  });

  final List<Track> recents;
  final void Function(Track) onPlay;
  final void Function(Track) onOptions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionHeader(title: 'Jump back in'),
        SizedBox(
          height: 178 + homeRailTextBlockHeight(context),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: t.HomeTokens.contentPadding),
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
                  size: 178,
                  onTap: () => onPlay(track),
                  onLongPress: () => onOptions(track),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MadeForYouSection extends StatelessWidget {
  const _MadeForYouSection({
    required this.tracks,
    required this.isPlaying,
    required this.onPlay,
    required this.onOptions,
  });

  final List<Track> tracks;
  final bool Function(Track) isPlaying;
  final void Function(Track) onPlay;
  final void Function(Track) onOptions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionHeader(title: 'Made for you'),
        ...tracks.map((track) => ForYouRow(
              artUrl: track.albumArtUrl,
              title: track.trackName,
              subtitle: track.artistName,
              isPlaying: isPlaying(track),
              onTap: () => onPlay(track),
              onLongPress: () => onOptions(track),
            )),
      ],
    );
  }
}

/// Quick Picks: dense compact list (spec #2A/#75). Each row: 52dp
/// thumbnail + title + artist + play chip. Deterministic picks from
/// the local recommendation engine. No giant cards.
class _QuickPicksSection extends StatelessWidget {
  const _QuickPicksSection({
    required this.tracks,
    required this.onPlay,
    required this.onOptions,
  });

  final List<Track> tracks;
  final void Function(Track) onPlay;
  final void Function(Track) onOptions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionHeader(title: 'Quick picks'),
        ...tracks.take(6).map((track) => ForYouRow(
              key: ValueKey('qp_${track.id}'),
              artUrl: track.albumArtUrl,
              title: track.trackName,
              subtitle: track.artistName,
              isPlaying: false,
              onTap: () {
                HapticFeedback.lightImpact();
                context
                    .read<MusicProvider>()
                    .playTrack(track, playlistTracks: tracks);
              },
              onLongPress: () => onOptions(track),
            )),
      ],
    );
  }
}

/// Trending section (spec #2B).
class _WhatsHotSection extends StatefulWidget {
  const _WhatsHotSection({
    required this.tracks,
    required this.onPlay,
    required this.onOptions,
    this.onSeeAll,
  });

  final List<Track> tracks;
  final void Function(Track) onPlay;
  final void Function(Track) onOptions;
  final VoidCallback? onSeeAll;

  @override
  State<_WhatsHotSection> createState() => _WhatsHotSectionState();
}

class _WhatsHotSectionState extends State<_WhatsHotSection> {
  late final PageController _controller = PageController(
    viewportFraction: 0.78,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title: "What's hot", onViewAll: widget.onSeeAll),
        SizedBox(
          height: 130 + homeRailTextBlockHeight(context) + 16,
          child: ParallaxMediaCarousel(
            controller: _controller,
            count: widget.tracks.length,
            itemBuilder: (context, index, pageOffset) {
              final track = widget.tracks[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: PressableScale(
                  onTap: () => widget.onPlay(track),
                  onLongPress: () => widget.onOptions(track),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      Text(
                        track.trackName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.HomeTokens.cardTitle(context),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.HomeTokens.cardMetadata(context),
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
}

/// Two-up editorial grid — visually distinct from rails and rows.
/// Album grid with per-item dispatch (live-run fix): "New releases" items
/// carry MPREb album identities — taps navigate to the collection detail
/// through the dispatcher instead of hitting playTrack and failing
/// silently ("Skipping non-playable track").
class _AlbumGridSection extends StatelessWidget {
  const _AlbumGridSection({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title: section.title),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: t.HomeTokens.contentPadding),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tileW = (constraints.maxWidth - 16) / 2;
              return Wrap(
                spacing: 16,
                runSpacing: 18,
                children: [
                  for (final item in section.items)
                    SizedBox(
                      width: tileW,
                      child: PressableScale(
                        onTap: () {
                          final action = HomePlaybackController.activate(
                            context,
                            item,
                            sectionTitle: section.title,
                          );
                          if (action == HomePlayAction.navigateCollection) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ThemedPlaylistDetailScreen(
                                  playlistId: item.browseId ?? item.id,
                                  playlistName: item.title,
                                  playlistImage: item.artworkUrl,
                                ),
                              ),
                            );
                          }
                        },
                        onLongPress: () {
                          final track = homeItemToTrack(item);
                          if (track != null) {
                            ThemedOptionsSheet.show(context, track: track);
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: item.artworkUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: item.artworkUrl,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 340,
                                        fadeInDuration:
                                            const Duration(milliseconds: 200),
                                        errorWidget: (_, __, ___) => Container(
                                            color: Colors.white
                                                .withValues(alpha: 0.05)),
                                      )
                                    : Container(
                                        color: Colors.white
                                            .withValues(alpha: 0.05)),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.HomeTokens.cardTitle(context),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.HomeTokens.cardMetadata(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlaylistsSection extends StatelessWidget {
  const _PlaylistsSection({required this.playlists});

  final List playlists;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionHeader(title: 'Your playlists'),
        SizedBox(
          height: 168 + homeRailTextBlockHeight(context),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: t.HomeTokens.contentPadding),
            physics: const BouncingScrollPhysics(),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: PressableScale(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ThemedPlaylistDetailScreen(
                        playlistId: playlist.id,
                        playlistName: playlist.name,
                        playlistImage: playlist.imageUrl,
                        cachedTracks: playlist.tracks,
                      ),
                    ),
                  ),
                  child: SizedBox(
                    width: 168,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(t.HomeTokens.cardRadius),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: playlist.imageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: playlist.imageUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 280,
                                    errorWidget: (_, __, ___) => Container(
                                        color: Colors.white
                                            .withValues(alpha: 0.05)),
                                  )
                                : Container(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    child: const Icon(Icons.queue_music_rounded,
                                        color: Colors.white24)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.HomeTokens.cardTitle(context),
                        ),
                        Text(
                          '${playlist.tracks.length} tracks',
                          style: t.HomeTokens.cardMetadata(context),
                        ),
                      ],
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
}

class _ArtistsSection extends StatelessWidget {
  const _ArtistsSection({required this.artists, required this.onTap});

  final List<Track> artists;
  final void Function(Track) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionHeader(title: 'Artists'),
        SizedBox(
          height: 96 + homeRailTextBlockHeight(context),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: t.HomeTokens.contentPadding),
            physics: const BouncingScrollPhysics(),
            itemCount: artists.length,
            itemBuilder: (context, index) {
              final artist = artists[index];
              return Padding(
                padding: const EdgeInsets.only(right: 28),
                child: ArtistPortrait(
                  name: artist.artistName,
                  imageUrl: artist.albumArtUrl,
                  onTap: () => onTap(artist),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MoodsSection extends StatefulWidget {
  const _MoodsSection();

  @override
  State<_MoodsSection> createState() => _MoodsSectionState();
}

class _MoodsSectionState extends State<_MoodsSection> {
  List? _moods;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final moods = await InnerTubeService.instance.getMoodsAndGenres();
      if (!mounted) return;
      setState(() {
        _moods = moods;
        _failed = moods.isEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final moods = _moods;
    // Honest empty: nothing hardcoded when the source yields nothing.
    if (_failed || (moods != null && moods.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Moods',
          onViewAll: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ThemedAllGenresScreen()),
          ),
        ),
        if (moods == null)
          // Geometry-matched skeleton while loading.
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: t.HomeTokens.contentPadding),
              itemCount: 5,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  width: 90.0 + (i % 3) * 26,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: t.HomeTokens.contentPadding),
              physics: const BouncingScrollPhysics(),
              itemCount: moods.length,
              itemBuilder: (context, index) {
                final mood = moods[index] as dynamic;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: EditorialMoodTile(
                    label: mood.title as String,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context
                          .read<MusicProvider>()
                          .fetchMoodTracks(mood.params as String)
                          .then((tracks) {
                        if (!context.mounted || tracks.isEmpty) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _MoodTracksScreen(
                              title: mood.title as String,
                              tracks: tracks,
                            ),
                          ),
                        );
                      });
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

/// Mood detail: real mood params → tracks, honest source title.
class _MoodTracksScreen extends StatelessWidget {
  const _MoodTracksScreen({required this.title, required this.tracks});

  final String title;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(title, style: t.HomeTokens.homeTitle(context)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 130),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return ForYouRow(
            artUrl: track.albumArtUrl,
            title: track.trackName,
            subtitle: track.artistName,
            isPlaying: false,
            onTap: () {
              HapticFeedback.lightImpact();
              context
                  .read<MusicProvider>()
                  .playTrack(track, playlistTracks: tracks);
            },
            onLongPress: () => ThemedOptionsSheet.show(context, track: track),
          );
        },
      ),
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
          borderRadius: BorderRadius.circular(t.HomeTokens.heroRadius),
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
                            style: t.HomeTokens.heroLabel(context),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.track.trackName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.HomeTokens.heroTitle(context),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.track.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.HomeTokens.cardMetadata(context),
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
                        width: t.HomeTokens.heroPlaySize,
                        height: t.HomeTokens.heroPlaySize,
                        child: Icon(Icons.play_arrow_rounded,
                            size: t.HomeTokens.heroPlayIconSize,
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
    // Skeleton matches real hero geometry (spec #59): width × 4:5.
    final contentW =
        t.HomeTokens.contentWidth(MediaQuery.sizeOf(context).width);
    final heroHeight = (contentW * t.HomeTokens.heroCardFraction * (5 / 4))
        .clamp(280.0, 380.0);
    return _SkeletonBox(height: heroHeight, radius: 20);
  }
}
