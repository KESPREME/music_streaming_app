# Explore Stream Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Discover into an immersive, vertical-swipe Explore Stream — artwork-driven glass, autoplay-on-settle, recommendation-ranked infinite queue — reusing the existing engine v2 + player, with zero new dependencies.

**Architecture:** `ExploreController` (ChangeNotifier, lazily owned by MusicProvider for session persistence) drives `ExploreSession` (queue/dedupe/refill) fed by `ExploreEngine` (source pools → `RichCandidate`s → existing `DeterministicRanker` with an Explore-tilted `RankingConfig`). UI is a single pushed route with `PageView.builder` over `GlassSurface` layers and an artwork-derived animated ambient background from `palette_generator`.

**Tech Stack:** Flutter 3.47.1, provider, palette_generator (already in pubspec), cached_network_image, existing liquid glass widgets (`GlassSurface`, `GlassCircleButton`, `GlassTokens`), existing engine (`lib/services/recommendation/*`), existing `MusicProvider.playTrack` playback.

## Global Constraints

- NO `Random()` anywhere — deterministic sort only (ranker already guarantees; engine must not re-sort randomly).
- NO random/generic search fallback — refill stops when sources exhaust.
- NO new recommendation engine — reuse `DeterministicRanker`, `TasteProfile`, `RichCandidate`, `ExposureLedger`, `SearchFollowupGraph`.
- NO new playback system — route through `MusicProvider.playTrack(track, playlistTracks: …, setContext: true, clearQueue: true)`.
- NO new glass package — reuse `GlassSurface`/`GlassCircleButton`/`GlassTokens`.
- NO MusicProvider refactor — controller holds references, calls existing methods.
- 11-char videoId + `MPREb|OLAK|VL|PL|UC` prefix gate on every candidate (reuse engine's `QuickPicksEngine._isInvalid` logic — copy as `ExploreEngine._isInvalid`, 6 lines).
- Test IDs must be 11-char lowercase-alnum.
- Do not `dart format` the whole tree — only touched files.
- Existing tests must stay green (196 baseline).
- Diagnostics: `EXPLORE_SESSION`, `EXPLORE_ITEM`, `EXPLORE_PREFETCH`, `EXPLORE_THEME` via `debugPrint`, following existing `RECOMMENDATION_UI` style.
- Frozen: `material_you_*` files, `po_token_webview.dart`, player contexts' static clientVersion.

---

## Verified contracts (audit results — executor may trust these)

- `DeterministicRanker.rank({required List<RichCandidate> candidates, required TasteProfile profile, required RankingConfig config, required int limit, ExposureLedger? exposure, required int generation, Map<String,double> searchGraphAffinity = const {}, Map<String,double> personalFloor = const {}}) → List<ScoredCandidate>` (ranker.dart:160). `ScoredCandidate{candidate, score, features, confidence, isExploration}`.
- `RankingConfig.forConfidence(double)` exists; `personalFloor` lifts `personalAffinity` (ranker.dart:177).
- `RichCandidate.fromTrack({trackId, title, artistName, source, genre, albumName, durationMs, chartRank, chartSize, releaseYear, playlistId, albumArt, editorialRank})`; `SourceTrust.trustFor`: `chart|local_history|local_favorites|search_followup`→high, `native_home`→medium, else low.
- `CandidateReason` enum: `favoriteArtist, recentlyPlayed, frequentArtist, searchFollowup, relatedToListening, regionalTrending, globalTrending, newReleaseArtist, nativeRecommendation, genreAffinity, exploration`.
- `TasteProfile.build({events, favoriteArtists, searchQueries, …})`, `.personalizationConfidence`, `.artistAffinity(name)`, `.searchAffinityFor(candidate)`.
- `MusicProvider`: `playTrack(Track, {playlistId, playlistTracks, setContext, clearQueue})`, `currentTrack`, `queue`, `isSongLiked(id)`, `toggleLike(Track)`, `quickPicks`, `trendingTracks`, `recentlyPlayed`, `recommendationService` (→ `recordSwipeOutcome({artistName, wasAccepted})`, `eventViews()`, `topArtistsForPicks()`, `topGenres()`), `searchGraph` (→ `affinityFor(trackId, activeQuery:)` — via engine's existing graph field), `fetchTrendingTracks()`, `fetchNewReleases`? (Discover uses `InnerTubeService.instance.getNewReleases(limit:14)` directly), `_prefs` (SharedPreferences, private — controller gets prefs passed in).
- `InnerTubeService.instance`: `getSuggestions(String videoId, {int limit=10})` (related songs via /next), `getNewReleases({int limit=20})`, `getTrendingTracks({int limit=20})`, `getMoodTracks(params, {limit:30})`.
- `Track{id, trackName, artistName, albumName, albumArtUrl, previewUrl, source, durationMs, genre, copyWith}` — id is the videoId for youtube source.
- Glass: `GlassSurface({child, tier, borderRadius, padding, accent, selected})`, `GlassCircleButton({icon, onTap, size=54, iconSize=24, glow, semanticLabel})`, `GlassTokens.blur/radii/opacity`, `ColorUtils.getVibrantAccent(PaletteGenerator?, fallback)`.
- `PaletteGenerator.fromImageProvider(ImageProvider, size: Size(100,100), maximumColorCount: 15)` pattern from palette_service.dart:101.
- Navigation: screens pushed on root stack via `Navigator.of(context).push`; pill mini-player lives in `GlobalMusicOverlay` above root navigator (Hero removed in cff11bd — do NOT re-add).
- `ThemedOptionsSheet.show(context, track:)` — existing track options sheet (used by Discover long-press).
- `share_plus` available (`Share.share`).
- Discover tab = index 1 in `main.dart` `_screens`; `discover_screen.dart` has Trending/Recent/NewReleases rails + Top Artists.

---

### Task 1: Explore policy + engine (candidate generation & ranking)

**Files:**
- Create: `lib/services/explore/explore_policy.dart`
- Create: `lib/services/explore/explore_engine.dart`
- Test: `test/explore_engine_test.dart`

**Interfaces (produces):**
```dart
// explore_policy.dart
class ExplorePolicy {
  static const int initialBatch = 8;
  static const int refillBatch = 8;
  static const int refillThreshold = 3;
  static const int prefetchAhead = 3;
  static const int relatedLimit = 10;
  static RankingConfig ranking(TasteProfile profile); // discovery tilt
  static CandidateReason reasonFor(String source);
  static const Map<String, CandidateReason> _reasonMap; // tested in Task 1
}
// explore_engine.dart
class ExploreSources { // plain data bag, all optional-empty
  final List<Track> seedRelated;   // source 'native_home' (YTM related = trusted medium)
  final List<Track> quickPicks;    // 'quick_picks' → mapped reason recentlyPlayed-ish
  final List<Track> favorites;     // 'local_favorites'
  final List<Track> recentlyPlayed;// 'local_history'
  final List<Track> regionalChart; // 'chart_regional'
  final List<Track> globalChart;   // 'chart_global'
  final List<Track> newReleases;   // 'new_release'
}
class ExploreItem {
  final Track track; final CandidateReason reason; final List<CandidateReason> secondaryReasons;
  final double score; final String source; final bool isExploration;
}
class ExploreEngine {
  ExploreEngine({this.ranker = const DeterministicRanker(), SearchFollowupGraph? searchGraph});
  Future<List<ExploreItem>> generate({
    required TasteProfile profile, required ExploreSources sources,
    Track? seed, Set<String> exclude = const {}, required int limit,
    required int generation, ExposureLedger? exposure, Map<String,double> searchGraphAffinity = const {},
  }); // sync-friendly core; async only for graph affinity lookup
}
```

**Behavior spec (engine.generate):**
1. Filter each pool through `_isInvalid` (empty title / len≠11 / forbidden prefix) AND `exclude` set. First-wins dedupe across pools in order: seedRelated → quickPicks → favorites → recentlyPlayed → regionalChart → globalChart → newReleases.
2. Convert to `RichCandidate.fromTrack(source: poolTag, …)`.
3. `personalFloor = {seed.track.id: 0.9}` when seed non-null (anchor current context, spec #94/#13).
4. Rank via `ranker.rank(config: ExplorePolicy.ranking(profile), limit: limit, exposure: exposure, generation: generation, personalFloor: floor, searchGraphAffinity: searchGraphAffinity)`.
5. Map `ScoredCandidate → ExploreItem`: reason = `ExplorePolicy.reasonFor(source)`; secondaryReasons from features (`favorite`>0→favoriteArtist, `searchFollowup`>0→searchFollowup, `freshness`>0→newReleaseArtist, exploration flag→exploration).
6. `ExplorePolicy.ranking(profile)`: `RankingConfig.forConfidence((profile.personalizationConfidence * 0.75).clamp(0.15, 0.60))` — discovery tilt: cap personal weight below Quick Picks' warm blend (spec #11/#18), so popularity/freshness still matter for active users. Cold start (confidence≈0) → near-cold config → popularity dominates → chart/newReleases carry the session (spec #58, no fake personalization).
7. Reason map: `native_home→nativeRecommendation, quick_picks→recentlyPlayed, local_favorites→favoriteArtist, local_history→recentlyPlayed, chart_regional→regionalTrending, chart_global→globalTrending, new_release→newReleaseArtist`, default `exploration`.
8. Deterministic: NO sort after rank; preserve ranker order.

- [ ] Step 1: Write failing tests `test/explore_engine_test.dart`:
  - builds candidates only from valid 11-char tracks; invalid filtered.
  - exclude set removes shown ids across pools.
  - seed floor: with equal pools, seed-related track ranks before chart track when profile has affinity for seed artist (verify personalFloor effect: seed track id in personalFloor 0.9 wins).
  - reason mapping per source tag.
  - cold profile (no events): chart tracks dominate over quickPicks-sourced unknowns (popularity weight).
  - deterministic: same inputs → identical order, twice.
  - `ExplorePolicy.ranking(cold)` weights popularity ≈ high; `ranking(warm)` personalAffinity > cold's.
- [ ] Step 2: Run — expect compile errors (files missing).
- [ ] Step 3: Implement both files (minimal, spec above).
- [ ] Step 4: Run test file — green.
- [ ] Step 5: Commit `feat(explore): policy + candidate engine on existing ranker`.

### Task 2: ExploreSession (queue, dedupe, refill trigger, diversity)

**Files:**
- Create: `lib/services/explore/explore_session.dart`
- Test: `test/explore_session_test.dart`

**Interfaces:**
```dart
class ExploreSession {
  ExploreSession({required this.sessionId, required this.startedAt, this.seed});
  final int sessionId; final DateTime startedAt; final Track? seed;
  final List<ExploreItem> items = [];        // full served stream
  final Set<String> shownItemIds = {};       // ever served (session dedupe, spec #21)
  final Set<String> playedItemIds = {};
  int currentIndex = -1;
  int generation = 0;                        // bumped per refill
  List<ExploreItem> get remaining;           // items.sublist(currentIndex+1)
  bool get needsRefill;                      // remaining.length <= ExplorePolicy.refillThreshold
  void appendBatch(List<ExploreItem> batch); // dedupe against shownItemIds, append, mark shown
  ExploreItem? get active;                   // items[currentIndex]
  void advanceTo(int index);                 // clamps, marks played, returns via active
}
```
- `appendBatch` also enforces **artist-run diversity**: when appending, skip a candidate if it would make >`ExplorePolicy.maxArtistRun`(=2) consecutive items share `primaryArtist` (normalized lower/trim) — stash skipped candidates in `_deferred` and retry insertion after the next append (never silently drop; spec #20 soft diversity). Primary artist = first comma-segment of `track.artistName`, lowercased.
- Same-title dedupe too: normalized `title+primaryArtist` set `shownKeys` (song-identity dedupe parity with composer).

Tests:
- initial append marks shown; second append of same id dropped.
- cross-refill dedupe: A B C A D B E → A B C D E.
- artist run cap: pool [X1 X2 X3] same artist → order interleaves/defers, ≤2 consecutive.
- needsRefill thresholds (0,3,4 remaining).
- advanceTo clamps and marks played.

- [ ] Steps: failing tests → run (fail) → implement → green → commit `feat(explore): session queue + dedupe + artist-run diversity`.

### Task 3: ExploreController (autoplay, generation race, prefetch, feedback)

**Files:**
- Create: `lib/services/explore/explore_controller.dart`
- Test: `test/explore_controller_test.dart`

**Interfaces:**
```dart
typedef ExploreSourceFetcher = Future<ExploreSources> Function(Track? anchor);
typedef ExplorePlayer = Future<void> Function(Track track, List<Track> upcoming);

class ExploreController extends ChangeNotifier {
  ExploreController({
    required ExploreEngine engine,
    required ExploreSourceFetcher fetchSources,
    required ExplorePlayer play,
    required TasteProfile Function() profileProvider,
    required ExposureLedger? exposure,
    required void Function(String artistName, {required bool wasAccepted}) recordSwipeOutcome,
    required SharedPreferences prefs,
    ExploreSession? existingSession, // restore (spec #122)
  });
  ExploreSession? session;
  bool autoplayEnabled;      // pref key 'explore_autoplay_enabled', default true
  bool get isLoading; String? error; bool get exhausted; // sources empty twice in a row
  int get playbackGeneration;
  Future<void> start({Track? seed});   // fetch initial batch, settle(0) if autoplay
  Future<void> settle(int index);      // THE hot path, see behavior
  Future<void> refresh();              // new session, same seed anchor = active track
  void toggleAutoplay();               // persists; if turning ON mid-session, play current if idle
  void dislikeCurrent();               // recordSwipeOutcome(false); auto-advance to next page
  Future<void> prefetchMedia(int index); // called by UI ahead of settle
}
```

**settle(index) behavior (critical, spec #5/#8/#90):**
```
gen = ++playbackGeneration
if index == session.currentIndex → return (rebuild/no-op, no restart)
session.advanceTo(index)
item = session.active; if null → return
// implicit feedback (spec #52): previous item dwell = now - _settledAt
if previous dwell < 8s → recordSwipeOutcome(prev.artist, wasAccepted: false)  // only if it was actually playing
_settledAt = now
if !autoplayEnabled → notify; return
if playGuard(item.track.id) → return   // injected: provider.currentTrack?.id == id → don't restart (spec #5)
// race: capture gen; after awaits, bail if playbackGeneration != gen
schedule playback: await play(item.track, upcomingTracks)  → on success _lastPlayedItemId = item.track.id
notify
// prefetch + refill (never blocks playback: unawaited)
if session.needsRefill → _refill()  (gen-guarded; two consecutive empty batches → exhausted=true)
prefetch artworks for index+1..+prefetchAhead (ExploredImages precache — UI side, controller just calls hook)
EXPLORE_SESSION / EXPLORE_ITEM / EXPLORE_PREFETCH debugPrints
```
- Rapid swipes 0→1→2: each settle bumps generation; the `gen` captured before `await play` invalidates earlier in-flight calls. Also `playGuard` prevents double-start of same id.
- `start()`: gen bump; fetch initial `ExploreSources`; `session = existingSession ?? new(sessionId: millisecondstamp, seed: seed)`; `appendBatch(engine.generate(...))`; activate index 0 via same settle path. Existing non-exhausted session with seed null → restore, do not refetch (spec #67/#122).

Tests (fake fetcher returns queued ExploreSources batches; fake play appends to list):
- settle sequence plays correct tracks; same-index settle no-op (no play call).
- rapid 0→1→2 with delayed fake play: only track 2 played (generation race).
- autoplayEnabled=false: no play calls, index advances.
- playGuard true (current track == item): no play call.
- refill: initial batch 8, settle to index 5 (remaining 3 ≤ threshold) → second fetch happens; batches dedupe (source returns overlapping ids).
- two empty refill batches → exhausted=true, no infinite fetch (fetch count asserted).
- dislikeCurrent: outcome(false) recorded + index advances.
- toggleAutoplay persists to prefs and turns off auto-play.

- [ ] Steps: failing tests → implement → green → commit `feat(explore): playback controller with generation races + refill`.

### Task 4: Explore palette (cache + ambient colors)

**Files:**
- Create: `lib/services/explore/explore_palette.dart`
- Test: `test/explore_palette_test.dart`

**Interfaces:**
```dart
class ExplorePalette {
  final Color background;  // dominant darkened: HSL lightness clamped 0.08–0.16, sat *0.85 (spec #31)
  final Color accent;      // ColorUtils.getVibrantAccent(palette, fallback)
  final bool isBright;     // dominant luminance > 0.5 → glass adds dark tint (spec #34)
}
class ExplorePaletteCache {
  static final _cache = <String, ExplorePalette>{}; // itemId → palette, cap 30 (spec #87)
  static ExplorePalette? cached(String itemId);
  static Future<ExplorePalette> resolve(String itemId, String artworkUrl);
  // uses CachedNetworkImageProvider(imageUrl).obtainKey? NO —
  // PaletteGenerator.fromImageProvider(CachedNetworkImageProvider(url), size: Size(100,100), maximumColorCount: 15)
  // empty artworkUrl → neutral palette (background #101018, accent grey).
  // failure → neutral; never throws (spec #64 graceful).
}
```
Tests: resolve caches (second call no second decode — count via spy on a custom ImageProvider? simpler: expose `@visibleForTesting decodeCount`); bright artwork → isBright; empty url → neutral; dark artwork lightness clamp bounds.

- [ ] Steps: tests → implement → green → commit `feat(explore): palette cache + ambient tone mapping`.

### Task 5: Explore screen UI (the immersive surface)

**Files:**
- Create: `lib/presentation/explore/explore_tokens.dart`
- Create: `lib/presentation/explore/explore_screen.dart` (single file, private widgets)
- Modify: `lib/screens/discover_screen.dart` (entry point)
- Test: none for pure layout (golden-lite: widget test for state rendering — playing label, autoplay-off banner, empty state — with FakeMusicProvider pattern from `test/player_flow_widget_test.dart`)

**explore_tokens.dart:**
```dart
abstract class ExploreTokens {
  static const artworkFraction = 0.84;      // spec #36
  static const artworkMaxWidth = 440.0;
  static const artworkRadius = 24.0;        // spec #38
  static const pagePadding = 24.0;
  static const metadataGap = 14.0;
  static const titleSize = 28.0;            // spec #41
  static const artistSize = 17.0;
  static const metaSize = 14.0;
  static const ambientTransition = Duration(milliseconds: 500);  // spec #32
  static const blurSigma = 40.0;
  static const backgroundStrength = 0.55;   // ambient layer opacity
  static const scrimTop = 0.50, scrimBottom = 0.85;
}
```

**explore_screen.dart structure:**
```
ExploreScreen(controller) → ChangeNotifierProvider.value →
Scaffold(backgroundColor: transparent, extendBody: true) →
AnimatedContainer(500ms, decoration: LinearGradient([palette.background, darken])) →   // ambient (spec #29/#32)
  Stack:
   - blurred artwork layer: ImageFiltered(blur 40, Transform.scale 1.25, Opacity(backgroundStrength)) keyed on current art (AnimatedSwitcher 500ms)
   - SafeArea → Column:
       _ExploreHeader (GlassSurface tier chrome, height 56): "Explore" 18w600, autoplay toggle icon, queue icon
       Expanded → PageView.builder(scrollDirection: Axis.vertical, controller: _pageCtrl, allowImplicitScrolling: true,
         onPageChanged: (i) { _firstSwipeHint=false; controller.settle(i); _updatePalettes(i); },
         itemCount: items.length + (exhausted ? 0 : 1))   // last page = loading stub
         → _ExplorePage(item, active: i == controller.currentIndex)
   - bottom swipe hint: AnimatedOpacity tiny Icons.keyboard_arrow_down + "Swipe for more" 12sp, fades out after first swipe (spec #43)
```
**_ExplorePage** (RepaintBoundary):
```
Padding(pagePadding) → Column(mainAxisAlignment: center):
  artwork: LayoutBuilder → width = min(constraints.maxWidth * 0.84, 440) →
    Container(decoration: borderRadius 24 + BoxShadow(glow accent 0.25, blur 40)) →
      ClipRRect(24) → AspectRatio(1) → CachedNetworkImage(memCacheWidth: 720, fadeIn 250ms, errorWidget → glass placeholder with Icons.music_note)
  SizedBox(24)
  GlassSurface(tier: card, radius 20, padding 18):   // metadata glass (spec #40)
    title 28 w700 maxLines 2 · artist 17 w500 accent-ish · album 14 dim
    + reason chip row (tiny 11sp, from reason → label map: RELATED_TO_CURRENT etc., spec #71, max 1 chip)
  SizedBox(14)
  _ExploreControls (GlassSurface tier floating, radius 30, h 72):   // spec #45
    Row(spaceEvenly): GlassCircleButton favorite (icons.favorite/favorite_border, semanticLabel 'Like'),
      LiquidPlayButton or GlassCircleButton play/pause primary (glow: true, larger) ,
      GlassCircleButton add-to-queue (Icons.playlist_add → provider.addListToQueue([track]) + GlassSnackBar),
      GlassCircleButton share (Share.share('song — artist')),
      GlassCircleButton more (Icons.more_horiz → showModalBottomSheet: ThemedOptionsSheet.show(context, track))
  Dislike: small TextButton 'Not interested' under controls → controller.dislikeCurrent() (spec #46)
```
- Play/pause reflects provider playback state via `context.watch<MusicProvider>()` play/pause getters (existing `isPlaying`-style getters — verify names at impl from mini_player.dart usage).
- Tap artwork → opens now-playing via nested player navigator pattern (reuse how mini_player opens: `musicProvider.playerNavigatorKey` push or the same call mini_player.dart uses — copy its exact call at impl time).
- Page indicator: header right shows `n+1 · remaining` tiny text (spec #44).
- Empty/exhausted: centered glass panel "Nothing new right now" + retry GlassCircleButton refresh + back (spec #65).
- Error while playing: keep current page, GlassSnackBar, auto-advance only via user swipe (spec #66).
- Autoplay OFF: small persistent chip near hint "Autoplay off — tap play".
- Loading stub page (last item when !exhausted): subtle CircularProgressIndicator + "Finding more".
- Semantics: every GlassCircleButton gets semanticLabel; artwork Semantics(label: 'title by artist') (spec #85).
- Page keys: `ValueKey(item.track.id)` per page (spec: stable page keys).

**Palettes:** `_updatePalettes(i)` = resolve palette for page i and i+1 (cache hit most times), setState targetPalette → AnimatedContainer interpolates; hysteresis: only on page change (spec #33).

**MusicProvider wiring (new file `lib/services/explore/explore_bootstrap.dart` or inside controller ctor call in screen):**
```dart
// In ExploreScreen initState or static factory:
final controller = MusicProvider.instance? — no: resolve via context.read<MusicProvider>()
ExploreController(
  engine: ExploreEngine(searchGraph: provider.searchGraph),   // verify graph getter name at impl; if private, pass affinity via existing public quickPicks path — fallback: skip searchGraphAffinity (const {})
  fetchSources: (anchor) async {
    final suggestions = anchor != null && anchor.id.length == 11
        ? await InnerTubeService.instance.getSuggestions(anchor.id, limit: ExplorePolicy.relatedLimit) : <Track>[];
    final charts = provider.trendingTracks.isEmpty ? await provider.fetchTrendingTracks() : provider.trendingTracks;
    // regional/global split: reuse provider's two chart lists if exposed (verify getters); else split fetched list in halves deterministically by index
    final newReleases = await InnerTubeService.instance.getNewReleases(limit: 10);
    return ExploreSources(seedRelated: suggestions, quickPicks: provider.quickPicks, favorites: likedSongsAsTracks, recentlyPlayed: provider.recentlyPlayed, regionalChart: firstHalf, globalChart: secondHalf, newReleases: newReleases);
  },
  play: (track, upcoming) => provider.playTrack(track, playlistTracks: upcoming, setContext: true, clearQueue: true),
  profileProvider: () => provider.buildTasteProfilePublic? — verify: _buildTasteProfile private → use provider.recommendationService.eventViews() + favoriteArtists() to build TasteProfile.build directly,
  exposure: null (first version; engine tolerates null),
  recordSwipeOutcome: (a, {required wasAccepted}) => provider.recommendationService.recordSwipeOutcome(artistName: a, wasAccepted: wasAccepted),
  prefs: SharedPreferences.getInstance() cached,
)
```
Executor note: several MusicProvider internals are private (`searchGraph`, `_buildTasteProfile`, likedSongs getter name, chart split getters). At implementation: read music_provider.dart for existing public accessors and use the closest public one; where nothing exists, compute locally from `recommendationService` public API. Do NOT add new public API to MusicProvider except ONE lazily-cached `ExploreController explore` getter (session persistence, spec #67) — single 8-line addition, documented.

**discover_screen.dart entry:** insert as first sliver a `SliverToBoxAdapter` immersive entry card (GlassSurface, height ~120): subtle blurred art strip of first trending item (or static glass if none), "Explore" 20w700 + "Swipe through new music" 13sp + chevron. onTap → `Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExploreScreen(controller: …)))` with 600ms local debounce guard (copy `_pushGuarded` 10-line pattern). Keep ALL existing sections untouched below (spec: Discover remains active destination, #115).

- [ ] Steps: tokens → screen skeleton with fake controller (test fake) rendering pages → wire real controller → entry card → widget test (autoplay-off chip, empty state, page key stability, reason chip) → analyze → commit `feat(explore): immersive explore stream UI + discover entry`.

### Task 6: Full verification + final commit

- [ ] `flutter analyze` → 0 errors.
- [ ] `flutter test` → all green (196 + new ~20 = 216±).
- [ ] Commit remaining wiring; update `CONTEXT.md` Explore section (brief — new file map rows, invariants: no Random, generation race, session persistence).
- [ ] Do NOT commit unless green.

---

## Deliberate simplifications (ponytail, upgrade paths marked)

1. **Refill chain = seed-related only from suggestions** (no getWatchPlaylist/RDAMVM radio — InnerTube service has none; adding `/next` playlistId param is a bigger change). `# ponytail: /next radioId support would give true YTM radio; suggestions cover seed-chaining for now`.
2. **ExposureLedger omitted in v1 wiring** (engine accepts null; session shownItemIds already prevents repeats). Add generation-window exposure if repeats across sessions annoy.
3. **Time-of-day context (spec #54) skipped** — weak signal, no data yet.
4. **Palette via single 100px decode per artwork, cache cap 30** — palette cost bounded; upgrade to isolate pool only if jank measured.
5. **Golden tests (spec #110) → light widget tests instead**; goldens need baseline infra project lacks.

## Execution

Plan saved. Executing inline (executing-plans style, batched with checkpoints) — same session, full context already loaded.
