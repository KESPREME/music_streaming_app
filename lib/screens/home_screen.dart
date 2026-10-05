import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../services/home/home_models.dart';
import '../services/auth_service.dart';
import '../services/innertube/innertube_service.dart';
import '../services/recommendation/quick_picks_engine.dart'
    show QuickPickCandidate, kCandidateVersion, kRankerVersion;
import '../presentation/home/home_playback.dart'
    show HomePlaybackController, HomePlayAction;
import '../presentation/home/home_presentation.dart';
import '../design/tokens/motion.dart';
import '../design/tokens/space.dart';
import '../presentation/home/home_tokens.dart' as t;
import '../presentation/home/home_view_mode.dart';
import '../screens/account_switcher_sheet.dart';
import '../screens/login_screen.dart';
import '../theme/glass_tokens.dart';
import '../widgets/account_button.dart';
import '../widgets/glass_surface.dart';
import '../widgets/section_view_toggle.dart';
import '../widgets/home_layout_switch.dart';
import '../widgets/home_sections.dart';
import '../widgets/home_sign_in_prompt.dart';
import '../widgets/home_skeleton.dart';
import '../widgets/track_list_column.dart';
import '../widgets/themed_all_genres_screen.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/themed_options_sheet.dart';
import '../widgets/themed_playlist_detail_screen.dart';
import '../widgets/themed_settings_screen.dart';
import '../widgets/themed_trending_now_screen.dart';
import '../core/navigation/root_navigator.dart';

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
            final provider = context.read<MusicProvider>();
            final previous = provider.homeFeed;
            await provider.refreshHomeFeed();
            // Also refresh trusted discovery sources in background.
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
              // First thing under the title, above the feed: the request is
              // about what the feed IS, so it belongs before the feed rather
              // than at the end of a scroll the user may never reach.
              if (!context.watch<AuthService>().isLoggedIn)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        t.HomeTokens.contentPadding, Spacing.md, 16, 0),
                    child: SignInPrompt(
                      // aboveShell: sign-in is full-bleed. Pushed into the
                      // nested navigator it renders under the tab bar, which
                      // is exactly why this entry point looked different from
                      // the account sheet's.
                      onSignIn: () => _pushGuarded(
                        context,
                        (_) => LoginScreen(addAnotherAccount: false),
                        aboveShell: true,
                      ),
                    ),
                  ),
                ),
              // One placeholder for the whole body: the hero, the lower
              // sections, or the retry. Keeping them in one sliver is what lets
              // the placeholder reserve exactly the space the real content will,
              // so the swap does not shift the header or the scroll extent.
              SliverToBoxAdapter(
                child: _HomeBody(
                  bottomInset: bottomInset,
                  entryController: _entry,
                  heroBuilder: _buildTopPicks,
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
    final auth = context.watch<AuthService>();
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(t.HomeTokens.contentPadding, 12, 16, 0),
      child: Row(
        children: [
          Expanded(child: Text('Home', style: t.HomeTokens.homeTitle(context))),
          AccountButton(
            auth: auth,
            // Signed out, the avatar goes straight to Settings, which is where
            // sign-in lives. Signed in, it opens the quick-switch. Either way
            // the button is doing the thing its icon advertises.
            onTap: () {
              if (auth.isLoggedIn) {
                AccountSwitcherSheet.show(context);
              } else {
                // aboveShell for the same reason as sign-in: Settings is a
                // full-screen page, not a detail screen.
                _pushGuarded(context, (_) => const ThemedSettingsScreen(),
                    aboveShell: true);
              }
            },
          ),
        ],
      ),
    );
  }

  /// Avatar that opens the account quick-switch.
  ///
  /// Replaces the gear that used to sit here. Settings is still one tap away -
  /// it is the last row of the sheet - but the button now answers the question a
  /// header button is usually for, which is "who am I and how do I change that".
  ///
  /// Vertical swipe cycles channels within the active account. The gesture is
  /// here because the header is always reachable, whereas the sheet is one tap
  /// away, and switching is something people do repeatedly.

  // ── Hero ─────────────────────────────────────────────────────────────────

  /// Hero eligibility (spec #28): source-nominated candidate from a strong
  /// SONG shelf — every item must carry a real videoId (11-char), because
  /// the hero play button routes through playTrack. Live-run fix: the
  /// enriched "New releases" shelf contains album items (MPREb ids) that
  /// previously passed this filter via _trackFromHomeItem nulls being
  /// dropped unevenly, then failed at play time. The filter is now strict
  /// AND the semantic type is checked — an album grid must never become
  /// the "Picked for you" hero.
  static (HomeSection, List<Track>)? _heroCandidate(MusicProvider provider) {
    final feed = provider.homeFeed;
    if (feed == null) return null;
    final shelves = <(HomeSection, List<Track>)>[];
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
      if (picks.length >= 3) shelves.add((section, picks));
    }
    if (shelves.isEmpty) return null;
    // Refresh rotates deterministically between valid song shelves
    // (spec #36: variation from structure, not randomization). First
    // load keeps the first shelf.
    final gen = provider.quickPicksGeneration;
    final offset = (gen > 0 && shelves.length > 1) ? gen % shelves.length : 0;
    return shelves[offset];
  }

  static List<Track> _topPicksList(MusicProvider provider) {
    if (provider.recommendedTracks.isNotEmpty) {
      return provider.recommendedTracks.take(8).toList();
    }
    if (provider.quickPicks.isNotEmpty) {
      return provider.quickPicks.take(8).toList();
    }
    if (provider.trendingTracks.isNotEmpty) {
      return provider.trendingTracks.take(8).toList();
    }
    return const [];
  }

/// Whether the hero carousel will render rather than collapse.
///
/// Answering that by building the carousel and inspecting its type would
/// construct the whole widget - artwork sizing, palette, the lot - on every frame
/// just to ask a yes/no question.
///
/// Static, and read from the watched provider rather than captured once. It used
/// to be sampled by the screen's first build, which happens before the chart has
/// finished loading, so the hero stayed hidden for the whole session and only
/// appeared once something unrelated - playing a track - happened to rebuild
/// the screen.
static bool _hasHero(MusicProvider provider) =>
      _topPicksList(provider).isNotEmpty || _heroCandidate(provider) != null;

  Widget _buildTopPicks(BuildContext context) {
    final provider = context.watch<MusicProvider>();

    // 1. Personalized recommendations from engine / radio / Jump Back In take priority
    final personalizedPicks = _topPicksList(provider);
    if (personalizedPicks.isNotEmpty) {
      return _buildHeroCarousel(
        context,
        personalizedPicks,
        // "For you", not "Quick Picks". This carousel and the compact Quick picks
        // list are different surfaces on the same screen, and both were called
        // Quick Picks - two identically-titled blocks down one page. It also
        // describes the content honestly: by the time this branch is reached the
        // source is history-seeded suggestions, the engine's picks, or the chart.
        'For you',
        'personalized_quick_picks',
      );
    }

    // 2. If no personalized engine picks exist yet, fall back to curated feed hero
    final hero = _heroCandidate(provider);
    if (hero != null) {
      final (section, picks) = hero;
      return _buildHeroCarousel(context, picks, section.title, section.id);
    }

    return const SizedBox.shrink();
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
        // Quieter than a rail's heading. The carousel is 280-380dp of artwork;
        // a 24dp bold title above it competes with the thing it is labelling,
        // and "Quick Picks" also duplicated the name of the compact Quick picks
        // list further down the same screen - two identically-titled blocks
        // reading as one glitch. This is the app's own recommendation surface, so
        // it says so, in fewer words and quieter.
        HomeSectionHeader(
          title: title,
          style: t.HomeTokens.heroSectionTitle(context),
        ),
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
                  sectionTitle: title,
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
  _pushGuarded(
    context,
    (_) => ThemedArtistDetailScreen(
      artistId: artistTrack.id,
      artistName: artistTrack.artistName,
      artistImage: artistTrack.albumArtUrl,
    ),
  );
}

/// Rapid double-taps during a route transition hit the navigator's debug
/// lock (`!navigator._debugLocked` assertion, seen live) and can corrupt
/// the stack ("album not opening", black screen). One guarded choke point
/// for every Home push: 600ms debounce + assertion suppression.
///
/// [aboveShell] picks WHICH navigator. `false` (the default) pushes into
/// [mainNavigatorKey], the nested navigator inside MainScreen that keeps the tab
/// bar and mini-player visible - correct for artist, album, playlist, moods and
/// genres, which are pages you navigate *within* the app.
///
/// `true` pushes onto the ROOT navigator instead, as a sibling of the whole
/// shell. Required for anything full-bleed: sign-in and settings. Pushed into
/// the nested one, they render as a CHILD of MainScreen and the floating tab
/// bar sits on top of them. That is not a cosmetic difference - it is why
/// signing in from the Home prompt looked different from signing in from the
/// account sheet.
DateTime _lastHomePushAt = DateTime.fromMillisecondsSinceEpoch(0);
void _pushGuarded(
  BuildContext context,
  Widget Function(BuildContext) builder, {
  bool aboveShell = false,
}) {
  final now = DateTime.now();
  final sinceLast = now.difference(_lastHomePushAt);
  if (sinceLast < const Duration(milliseconds: 250)) {
    if (kDebugMode) {
      debugPrint('HOME_NAV debounced (${sinceLast.inMilliseconds}ms since '
          'last push) — double-tap swallowed');
    }
    return;
  }
  _lastHomePushAt = now;
  try {
    if (aboveShell) {
      pushAboveShell<void>(context, builder(context));
      return;
    }
    final navigator = mainNavigatorKey.currentState ?? Navigator.of(context);
    final pushed = navigator.push(MaterialPageRoute(builder: builder));
    if (kDebugMode) {
      debugPrint('HOME_NAV pushed route');
      pushed.whenComplete(() {
        if (kDebugMode) debugPrint('HOME_NAV route completed');
      });
    }
  } on FlutterError catch (e) {
    debugPrint('HOME_NAV SUPPRESSED: ${e.message}');
  } catch (e) {
    // Non-FlutterError throws (asserts, poisoned state) must not crash
    // the tap handler.
    debugPrint('HOME_NAV SUPPRESSED: $e');
  }
}

/// One curated-feed shelf rendered through the presentation planner
/// (spec #3/#41): semantic classification → layout kind → geometry.
/// The section's own title displays verbatim; provenance never re-titles.
/// Whether a feed section will render anything.
///
/// Defined once and consulted twice: by `_LowerSections` before adding the
/// section, and by `_FeedSection.build` when deciding what to return. The
/// parent has to know because a section that collapses to zero still occupies
/// its slot in the list - and therefore its inter-section gap - unless the
/// parent declines to add it. Keeping one definition is what stops the two
/// from drifting, which is how a "collapsed" shelf kept its gap for so long.
bool _feedSectionRenders(HomeSection section) {
  switch (planPresentation(section).layoutKind) {
    case HomeLayoutKind.compactList:
      // Playable rows only: collection items carry no videoId, so they cannot
      // become a row, and a shelf of them is not a list.
      final rows = section.items.map(homeItemToTrack).whereType<Track>().length;
      return rows >= 3;
    case HomeLayoutKind.artistRail:
    case HomeLayoutKind.landscapeRail16x9:
    case HomeLayoutKind.playlistRail:
      return true;
    case HomeLayoutKind.squareGrid:
      return section.items.isNotEmpty;
    case HomeLayoutKind.squareRail:
    // heroCarousel and portraitRail have no dedicated branch and fall through
    // to the square rail, so they collapse on the same condition.
    case HomeLayoutKind.heroCarousel:
    case HomeLayoutKind.portraitRail:
      return section.items.length >= 3;
  }
}

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
    //
    // The parent already declined to add a section that fails
    // `_feedSectionRenders`, so reaching shrink here means the section list
    // changed under us. Keep the guard rather than trust that.
    if (!_feedSectionRenders(section)) return const SizedBox.shrink();

    // History shelves get a layout toggle before the planner's kind is
    // consulted: switching to rows replaces the grid wholesale, so which grid
    // it was is irrelevant once the user has chosen rows.
    if (tracks.length > 1 &&
        SectionIdentity.semanticSlug(section) == 'recent') {
      return _HistoryFeedSection(section: section, tracks: tracks);
    }

    if (plan.layoutKind == HomeLayoutKind.compactList) {
      return _CompactListSection(section: section, tracks: tracks);
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
      return _AlbumGridSection(section: section);
    }
    // squareRail fallback — per-item dispatch (mixed shelves may contain
    // songs, videos AND playlist/album cards).
    return _SquareRailSection(section: section);
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
    final cardW = t.HomeTokens.contentWidth(MediaQuery.sizeOf(context).width) *
        t.HomeTokens.squareCardFraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title: section.title),
        SizedBox(
          height: cardW + homeRailTextBlockHeight(context) + 12,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: t.HomeTokens.contentPadding),
            physics: const BouncingScrollPhysics(),
            itemCount: section.items.length,
            itemBuilder: (context, index) {
              final item = section.items[index];
              return Padding(
                key: ValueKey('rail_${item.id}'),
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
/// Mine Music-style editorial block for trending/chart content. Height derives
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
          height: homeArtistPortraitHeight(context),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: t.HomeTokens.contentPadding),
            physics: const BouncingScrollPhysics(),
            itemCount: section.items.length,
            itemBuilder: (context, index) {
              final item = section.items[index];
              return Padding(
                key: ValueKey('rail_${item.id}'),
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
                    _pushGuarded(
                      context,
                      (_) => ThemedArtistDetailScreen(
                        artistId: browseId,
                        artistName: item.title,
                        artistImage: item.artworkUrl,
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
                  onTap: () => _pushGuarded(
                    context,
                    (_) => ThemedPlaylistDetailScreen(
                      playlistId: item.browseId ?? item.id,
                      playlistName: item.title,
                      playlistImage: item.artworkUrl,
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
                key: ValueKey('rail_${item.id}'),
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
                      _pushGuarded(
                        context,
                        (_) => ThemedPlaylistDetailScreen(
                          playlistId: item.browseId ?? item.id,
                          playlistName: item.title,
                          playlistImage: item.artworkUrl,
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
/// Hero, lower sections, or a retry - whichever the load state calls for.
///
/// A cold start with nothing cached shows [HomeSkeleton]; the same screen with a
/// feed shows the content, and a load that settled with nothing shows a retry the
/// user can actually press.
///
/// The bounded wait is the part that matters. The provider reports a settled
/// failure, but a request that never returns at all - a socket parked open, a
/// request that never times out - would leave the skeleton running for ever. A
/// placeholder that cannot resolve is worse than an honest one, because it tells
/// the listener to keep waiting when nobody is going to arrive. So the skeleton
/// also gives up on its own after [_kSkeletonGiveUpAfter].
class _HomeBody extends StatefulWidget {
  const _HomeBody({
    required this.bottomInset,
    required this.entryController,
    required this.heroBuilder,
  });

  final double bottomInset;

  /// Owned by the screen: the entry choreography controller must outlive any
  /// swap between placeholder and content, so the skeleton cannot own it.
  final AnimationController entryController;
  final WidgetBuilder heroBuilder;

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  /// Long enough for a cold start on a slow connection - the feed request plus
  /// the InnerTube warm-up it waits on routinely runs several seconds - and short
  /// enough that a hung request does not strand the listener on a shimmer.
  static const Duration _kSkeletonGiveUpAfter = Duration(seconds: 12);

  bool _gaveUp = false;
  Timer? _gaveUpTimer;
  bool _wasLoading = false;

  @override
  void initState() {
    super.initState();
    // Evaluated once so the first build can decide from it rather than starting
    // from a stale default.
    _wasLoading = context.read<MusicProvider>().isHomeLoading;
    if (_wasLoading) _armGiveUpTimer();
  }

  void _armGiveUpTimer() {
    _gaveUpTimer?.cancel();
    _gaveUpTimer = Timer(_kSkeletonGiveUpAfter, () {
      if (!mounted) return;
      setState(() => _gaveUp = true);
    });
  }

  void _cancelGiveUpTimer() {
    _gaveUpTimer?.cancel();
    _gaveUpTimer = null;
  }

  /// Arms or cancels the give-up timer on the loading *transition*.
  ///
  /// Doing this from [build] looked harmless and was quietly fatal: this widget
  /// watches the provider, so it rebuilds on every playback tick, and
  /// re-arming on each rebuild reset the countdown forever. The twelve seconds
  /// could never elapse, so a request that hung - which is the only case the
  /// timer exists for - left the shimmer on screen permanently. That is the one
  /// failure the timer was added to prevent.
  void _syncGiveUpTimer(bool loading) {
    if (loading == _wasLoading) return;
    _wasLoading = loading;
    if (loading) {
      if (_gaveUp) setState(() => _gaveUp = false);
      _armGiveUpTimer();
    } else {
      _cancelGiveUpTimer();
    }
  }

  @override
  void dispose() {
    _cancelGiveUpTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    _syncGiveUpTimer(provider.isHomeLoading);

    final showSkeleton = provider.isHomeLoading && !_gaveUp;
    if (showSkeleton) {
      return HomeSkeleton(
        bottomInset: widget.bottomInset,
        withHero: _HomeScreenState._hasHero(provider),
      );
    }

    // Only when nothing at all can be rendered. A null feed still leaves the
    // local-signal sections on screen, and covering those with an error takes
    // away content the listener could actually use.
    if (provider.isHomeLoadExhausted || _gaveUp) {
      return _HomeRetry(
        bottomInset: widget.bottomInset,
        onRetry: () {
          setState(() => _gaveUp = false);
          _armGiveUpTimer();
          context.read<MusicProvider>().refreshHomeFeed();
        },
      );
    }

    return _RealHomeBody(
      bottomInset: widget.bottomInset,
      entryController: widget.entryController,
      heroBuilder: widget.heroBuilder,
    );
  }
}

/// The screen's real content: hero plus lower sections.
class _RealHomeBody extends StatelessWidget {
  const _RealHomeBody({
    required this.bottomInset,
    required this.entryController,
    required this.heroBuilder,
  });

  final double bottomInset;
  final AnimationController entryController;
  final WidgetBuilder heroBuilder;

  @override
  Widget build(BuildContext context) {
    // Watched, not captured. This is the fix for the hero only appearing after a
    // track had been played: both of these were sampled once by the screen's
    // first build, before the chart arrived, and nothing recomputed them until
    // an unrelated rebuild. Reading them here - from a provider this widget
    // already watches - means the carousel appears the moment there is something
    // to put in it, which is at start-up rather than after listening.
    final provider = context.watch<MusicProvider>();
    final hasHero = _HomeScreenState._hasHero(provider);

    // A feed shelf promoted to the hero must not also render below itself.
    final excludeHeroSectionId =
        _HomeScreenState._topPicksList(provider).isEmpty
            ? _HomeScreenState._heroCandidate(provider)?.$1.id
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: hasHero ? 12.0 : t.HomeTokens.headerToContent),
        if (hasHero)
          StaggerIn(
            controller: entryController,
            interval: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
            child: heroBuilder(context),
          ),
        Selector<MusicProvider, int>(
          selector: (_, p) => p.homeContentVersion,
          child: _LowerSections(
            bottomInset: bottomInset,
            // The hero is its own block here, so the section gap has to be
            // applied across that boundary explicitly.
            topGap: hasHero ? t.HomeTokens.sectionGap : 0.0,
            excludeHeroSectionId: excludeHeroSectionId,
          ),
          builder: (context, version, lower) => lower!,
        ),
      ],
    );
  }
}

/// The load settled with nothing to show, and a retry is the honest response.
class _HomeRetry extends StatelessWidget {
  const _HomeRetry({required this.bottomInset, required this.onRetry});

  final double bottomInset;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(t.HomeTokens.contentPadding, 48,
          t.HomeTokens.contentPadding, 100 + bottomInset),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 34,
            color: Colors.white.withValues(alpha: 0.28),
          ),
          const SizedBox(height: 16),
          Text(
            "Couldn't load your Home",
            style: t.HomeTokens.sectionTitle(context)
                .copyWith(fontSize: 20, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Check your connection and try again.',
            style: t.HomeTokens.cardMetadata(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          GlassSurface(
            tier: GlassTier.card,
            borderRadius: GlassTokens.radiusButton,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                onRetry();
              },
              borderRadius: BorderRadius.circular(GlassTokens.radiusButton),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 26, vertical: 13),
                child: Text('Try again',
                    style: t.HomeTokens.cardTitle(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LowerSections extends StatelessWidget {
const _LowerSections({
      required this.bottomInset,
      required this.topGap,
      this.excludeHeroSectionId,
    });

    final double bottomInset;

    /// Space between a rendered hero carousel and the first section below it.
    /// The hero is a separate sliver, so the inter-section gap does not reach
    /// across that boundary.
    final double topGap;
    final String? excludeHeroSectionId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    // Watched so a mode change repaints the section that owns the toggle, and
    // no other. Without the watch the button would flip its icon and nothing
    // else would move.
    final viewModes = context.watch<HomeViewModeStore>();
    final sections = <Widget>[];
    final renderedKinds = <String>[];

    // Local overlay — continue listening.
    final recents = provider.recentlyPlayed
        .where((t) => t.id != provider.currentTrack?.id)
        .toList();
    if (recents.isNotEmpty) {
      sections.add(_JumpBackInSection(
        recents: recents,
        // The recents list is the ordered context for this tap. Without it playback
        // starts with no list at all, so the window is one item: the track ends
        // with nothing to advance into and the lock screen has no prev/next.
        onPlay: (track) => context.read<MusicProvider>().playTrack(
              track,
              playlistTracks: recents,
              playlistId: 'jump_back_in',
            ),
        onOptions: (track) => ThemedOptionsSheet.show(
          context,
          track: track,
          isRecentlyPlayedContext: true,
        ),
        viewMode: viewModes.modeOf(HomeViewSection.jumpBackIn),
        onToggleView: () =>
            viewModes.toggle(HomeViewSection.jumpBackIn),
      ));
    }

    // Quick Picks (spec #2A/#61): deterministic personalized picks, high
    // on the page. Always shown when candidates exist (cold start uses
    // chart/trending as popularity prior).
    final quickPicks = provider.quickPicks;
    if (quickPicks.isNotEmpty) {
      sections.add(_QuickPicksSection(
        candidates: provider.quickPickCandidates,
        onPlay: (track) => _play(context, track, quickPicks),
        onOptions: (track) => ThemedOptionsSheet.show(context, track: track),
        viewMode: viewModes.modeOf(HomeViewSection.quickPicks),
        onToggleView: () => viewModes.toggle(HomeViewSection.quickPicks),
      ));
    }

    final feed = provider.homeFeed;
    if (feed != null) {
      // Curated shelves in source order — titles come from the source.
      final feedSections = feed.sections
          .where((s) => s.id != excludeHeroSectionId)
          .toList();

      for (final section in feedSections) {
        final plan = planPresentation(section);
        if (kDebugMode) renderedKinds.add(plan.semanticType.name);
        if (!_feedSectionRenders(section)) {
          if (kDebugMode) {
            debugPrint('HOME_UI collapsed section="${section.title}" '
                'kind=${plan.layoutKind.name} items=${section.items.length}');
          }
          continue;
        }
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

      final trending = provider.trendingTracks;
      if (trending.isNotEmpty) {
        sections.add(_WhatsHotSection(
          tracks: trending,
          onPlay: (track) => _play(context, track, trending),
          onOptions: (track) => ThemedOptionsSheet.show(context, track: track),
          onSeeAll: () => _pushGuarded(
            context,
            (_) => const ThemedTrendingNowScreen(),
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

    // EXPLORATION — moods: real Moods & Genres discovery from InnerTube
    sections.add(const _MoodsSection());

    // `_MoodsSection` is always last, so a gap after it when it collapses to
    // nothing just merges into the tail spacer below and is never seen.
    //
    // There is deliberately no `is SizedBox` filter here any more. It looked
    // right and never fired: `sections` holds `_FeedSection` and friends, and
    // a section that collapses returns `SizedBox.shrink()` from its own build.
    // The instance in this list is still the section widget, so the test was
    // always false and every collapsed shelf still consumed a full gap - which
    // is the giant-gap bug the comment claimed to be preventing. Feeds gate on
    // `_feedSectionRenders` before they are added instead, so a section that
    // will not render is never in the list.
    if (kDebugMode) {
      // UI accounting (spec #25/#44): composer count vs rendered count —
      // presentation-level loss is never silent.
      final composerCount = provider.homeFeed?.sections.length ?? 0;
      debugPrint('HOME_UI composerSections=$composerCount '
          'rendered=${sections.length} '
          'kinds=${renderedKinds.isEmpty ? "" : renderedKinds.join(",")}');
      // Section visibility diagnostics (spec #78).
      debugPrint(
          'RECOMMENDATION_UI quickPicks=${provider.quickPicks.isEmpty ? "SKIPPED reason=NO_CANDIDATES" : "VISIBLE"} '
          'newReleases=${provider.newReleases.isEmpty ? "SKIPPED reason=NO_VALID_CANDIDATES" : "VISIBLE"} '
          'trending=${provider.trendingTracks.isEmpty ? "SKIPPED reason=NO_VALID_CANDIDATES" : "VISIBLE"} '
          'profileVersion=${provider.tasteProfileVersion} rankerVersion=$kRankerVersion candidateVersion=$kCandidateVersion');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (topGap > 0) SizedBox(height: topGap),
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: t.HomeTokens.sectionGap),
          sections[i],
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
    required this.viewMode,
    required this.onToggleView,
  });

  final List<Track> recents;
  final void Function(Track) onPlay;
  final void Function(Track) onOptions;
  final HomeSectionViewMode viewMode;
  final VoidCallback onToggleView;

  bool get _isCard => viewMode == HomeSectionViewMode.card;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Jump back in',
          trailing: SectionViewToggle(
            mode: viewMode,
            onToggle: onToggleView,
          ),
        ),
        // Height is animated because the two layouts are wildly different sizes
        // (a 178dp card rail versus a multi-row column). Without this the whole
        // page below jumps the instant the mode changes, which reads as a
        // scroll glitch rather than as a layout choice.
        HomeLayoutSwitch(
          isCard: _isCard,
          card: _cardRail(context),
          list: _rowColumns(context),
        ),
      ],
    );
  }

  Widget _cardRail(BuildContext context) {
    return SizedBox(
      height: 178 + homeRailTextBlockHeight(context),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: t.HomeTokens.contentPadding),
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
    );
  }

  Widget _rowColumns(BuildContext context) {
    return SizedBox(
      height: trackListColumnsHeight(context, recents.length),
      child: TrackListColumns(
        tracks: recents,
        onPlay: onPlay,
        onOptions: onOptions,
      ),
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

/// Quick Picks: deterministic picks from the local recommendation engine.
///
/// Two layouts. It opens on CARDS by default (see
/// [HomeViewModeStore.defaultFor]): this is a discovery shelf, and a column of
/// 52dp rows reads as a queue to work through rather than as things to pick
/// from. The compact list is still one tap away for someone who wants to
/// recognise a track by its row rather than its cover.
class _QuickPicksSection extends StatelessWidget {
  const _QuickPicksSection({
    required this.candidates,
    required this.onPlay,
    required this.onOptions,
    required this.viewMode,
    required this.onToggleView,
  });

  final List<QuickPickCandidate> candidates;
  final void Function(Track) onPlay;
  final void Function(Track) onOptions;
  final HomeSectionViewMode viewMode;
  final VoidCallback onToggleView;

  /// Subtitle = artist name (user preference: reason labels are noise in the
  /// list; engine reasoning lives in the RECOMMENDATION_ITEM debug traces).
  static String _subtitleOf(Track track) {
    final firstArtist = track.artistName.split(',').first.trim();
    return firstArtist.isEmpty ? track.artistName : firstArtist;
  }

  List<Track> get _tracks =>
      candidates.take(6).map((c) => c.track).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final isCard = viewMode == HomeSectionViewMode.card;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Quick picks',
          trailing: SectionViewToggle(
            mode: viewMode,
            onToggle: onToggleView,
          ),
        ),
        HomeLayoutSwitch(
          isCard: isCard,
          card: _cards(context),
          list: _rows(context),
        ),
      ],
    );
  }

  Widget _cards(BuildContext context) {
    final tracks = _tracks;
    return SizedBox(
      height: 178 + homeRailTextBlockHeight(context),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: t.HomeTokens.contentPadding),
        physics: const BouncingScrollPhysics(),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: RailCard(
              artUrl: track.albumArtUrl,
              title: track.trackName,
              subtitle: _subtitleOf(track),
              size: 178,
              onTap: () => onPlay(track),
              onLongPress: () => onOptions(track),
            ),
          );
        },
      ),
    );
  }

  Widget _rows(BuildContext context) {
    return SizedBox(
      height: trackListColumnsHeight(context, _tracks.length),
      child: TrackListColumns(
        tracks: _tracks,
        onPlay: onPlay,
        onOptions: onOptions,
      ),
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
        _albumGridBody(context, section),
      ],
    );
  }
}

/// The square grid itself, without its header.
///
/// Extracted so a shelf that can switch between this and a row list owns its
/// header once and animates only the body. Two copies of this grid would drift
/// the first time a card's radius or spacing changed.
Widget _albumGridBody(BuildContext context, HomeSection section) {
  return Padding(
    padding:
        const EdgeInsets.symmetric(horizontal: t.HomeTokens.contentPadding),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Tablet/landscape: 3 columns above 600dp content width
        // (spec: landscape/tablet adaptation). Phone keeps 2.
        final columns = constraints.maxWidth > 600 ? 3 : 2;
        final gap = 16.0;
        final tileW = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
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
                      _pushGuarded(
                        context,
                        (_) => ThemedPlaylistDetailScreen(
                          playlistId: item.browseId ?? item.id,
                          playlistName: item.title,
                          playlistImage: item.artworkUrl,
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
                                      color: Colors.white.withValues(alpha: 0.05),
                                      child: const Icon(Icons.album_rounded,
                                          color: Colors.white24)),
                                )
                              : Container(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  child: const Icon(Icons.album_rounded,
                                      color: Colors.white24)),
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
  );
}

/// A feed shelf the parser classified as listening history, which can lay its
/// items out as a card grid or as paging rows.
///
/// Eligibility comes from [SectionIdentity.semanticSlug] == 'recent', which the
/// parser derives from the shelf's own title. Matching on the title here instead
/// would hard-code "Listen again" and stop working the moment the source, the
/// locale, or the account changed the wording; matching on the slug also means
/// this picks up "Recents" and "Jump back in" from the feed for free.
class _HistoryFeedSection extends StatelessWidget {
  const _HistoryFeedSection({required this.section, required this.tracks});

  final HomeSection section;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final viewModes = context.watch<HomeViewModeStore>();
    final isCard = viewModes.isCard(HomeViewSection.listenAgain);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: section.title,
          trailing: SectionViewToggle(
            mode: viewModes.modeOf(HomeViewSection.listenAgain),
            onToggle: () => viewModes.toggle(HomeViewSection.listenAgain),
          ),
        ),
        HomeLayoutSwitch(
          isCard: isCard,
          card: _albumGridBody(context, section),
          list: SizedBox(
            height: trackListColumnsHeight(context, tracks.length),
            child: TrackListColumns(
              tracks: tracks,
              onPlay: (track) =>
                  _LowerSections._play(context, track, tracks),
              onOptions: (track) =>
                  ThemedOptionsSheet.show(context, track: track),
            ),
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
                  onTap: () => _pushGuarded(
                    context,
                    (_) => ThemedPlaylistDetailScreen(
                      playlistId: playlist.id,
                      playlistName: playlist.name,
                      playlistImage: playlist.imageUrl,
                      cachedTracks: playlist.tracks,
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
          height: homeArtistPortraitHeight(context),
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
          onViewAll: () => _pushGuarded(
            context,
            (_) => const ThemedAllGenresScreen(),
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
                          .fetchMoodTracks(mood.params as String,
                              genre: mood.title as String)
                          .then((tracks) {
                        if (!context.mounted || tracks.isEmpty) return;
                        _pushGuarded(
                          context,
                          (_) => _MoodTracksScreen(
                            title: mood.title as String,
                            tracks: tracks,
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
    required this.sectionTitle,
    this.parallaxFactor = 0.16,
  });

  final Track track;
  final double pageOffset;
  final VoidCallback onPlay;
  final VoidCallback onOverflow;

  /// The source shelf's real title — never a fabricated label (spec #5).
  final String sectionTitle;
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
                            widget.sectionTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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

