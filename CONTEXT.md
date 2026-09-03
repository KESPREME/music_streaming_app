# CONTEXT.md — MineMusic Session Continuity

> This file preserves critical context for AI-assisted development sessions.
> If compacting or starting a new session, READ THIS FIRST.

---

## PROJECT

**MineMusic** — Flutter music streaming app (YouTube Music client).
Path: `D:\Projects\music_streaming_app` · Branch: `refactor/liquid-glass` · 235/235 tests green.

- Flutter 3.47.1 / Dart 3.13.1 / Android target (CPH2723 test device, Android 16)
- State management: `provider` (NOT Riverpod — immutable PlaybackState projection used instead)
- Min Android: gesture nav, Impeller/Vulkan rendering
- Dev machine: Windows, adb at `C:\Users\nipun\AppData\Local\Android\Sdk\platform-tools\adb.exe`

---

## CURRENT STATE (commit 105b1a3+)

### Data pipeline (STABLE — do not casually rewrite)
```
InnerTube browseJson(FEmusic_home)  [dynamic clientVersion 1.YYYYMMDD.01.00,
  platform-locale hl, NO gl override (IP-inferred), visitorData session-cached,
  real signatureTimestamp, CONSENT cookie]
  ↓ YouTubeMusicHomeSource._parse  [staged walker: carousel + musicShelf +
  nested musicSectionListRenderer; ShelfReport accounting; continuation capture
  at sectionList level (Metrolist parity)]
  ↓ HomeFeed {sections, heroCandidate, continuationToken}
  ↓ HomeComposer  [validation gate: identity+title only; SECTION-LOCAL dedupe;
  artist cap 2/shelf; maxItems 12; NO section budget (load-all since
  2026-09-03: logged-in feeds run long, budget amputated categories);
  PARTIAL support for missing artwork]
  ↓ HomeConvergence  [SectionIdentity = provenance:semantic:title-slug;
  omitted-but-valid remembered sections retained at PREVIOUS POSITION;
  TTLs: trending 3h, generic 6h, new_release 12h, editorial 24h]
  ↓ HomeQualityGate  [≥2 sections, ≥4 items, all titled, ≥2 items each]
  + isDegraded vs _bestKnown (high-water mark — NOT latest-accepted!)
  + bounded enrichment (chart + new_release) when native <4 sections
  ↓ HomeRepository  [SWR 45min, backoff 30s×2^n max 2h, in-flight coalescing,
  cache key = home_feed_snapshot_v4_primary_<locale>, schema+parser+ctx
  version-validated; section memory persisted to home_section_memory_v1]
  ↓ MusicProvider._homeFeed + .homeFeed + .quickPicks + _bumpHomeContent()
  ↓ HomeScreen: Selector(homeContentVersion) → _LowerSections
  ↓ _FeedSection → planPresentation() → layout kind → widget
```

### Playback (STABLE)
- `HomePlaybackController.activate()` routes ALL Home taps: song+11char-videoId→
  playSong, video→playVideo, album/playlist→navigateCollection, artist→navigateArtist.
- `isPlayableSongItem()` strict: 11-char, no MPREb/OLAK/VL/PL/UC prefix.
- Hero requires ALL items to pass isPlayableSongItem; else collapses to SizedBox.shrink.
- HOME_PLAY / HOME_PLAY_FAIL logged with full identity.

### Recommendation engine (JUST BUILT — commit 105b1a3)
```
lib/services/recommendation/
  quick_picks_engine.dart   — 6 signal pools: recentStrong(0.30), favorites(0.25),
    artistAffinity(0.15), searchFollowup(0.15), chart(0.10), nativeDiscovery(0.05);
    skip penalty −0.20 (skipCount>2 && completion<0.3), overexposure −0.10
    (playCount>10); artist cap 2; 11-char videoId validation; deterministic
    sort (score DESC, id ASC tiebreak — NEVER Random())
  search_followup_graph.dart — query→trackId transitions, affinity = w/(w+2)
    active-query, w/(w+4) cap 0.5 without; sqflite persistence
  search_followup_store.dart — sqflite search_followups_v1, 500-row cap
  section_engines.dart — TrendingEngine (native→regional→global merge) +
    NewReleasesEngine (native 0.6 + affinity 0.4+0.25 boost)
  candidate.dart — CandidateReason enum + Candidate model
```
- Wired: MusicProvider._generateQuickPicks() called from _publishHomeFeed;
  provider.quickPicks exposed; _QuickPicksSection rendered in _LowerSections
  after JumpBackIn before native shelves.
- Search attribution: searchTracks() sets _pendingSearchQuery + _searchQueryAt;
  playTrack calls _recordSearchFollowup(track) — within 10min window records
  query→track transition in graph.
- RecommendationService gained: signalFor(trackId) → RecommendationSignalView,
  topArtistsForPicks(limit) — used via _QuickPicksSignalAdapter.

### Presentation (STABLE)
- `HomeTokens` (lib/presentation/home/home_tokens.dart): contentPadding 16,
  sectionGap 30, cardGap 12, headerToContent 10, heroCardFraction 0.88,
  squareCardFraction 0.46, playlistCardFraction 0.38, videoCardFraction 0.78,
  artistCardFraction 0.28; hero 4:5, square 1:1, video 16:9; heroRadius 20,
  cardRadius 12; heroPlay 56/30.
- Typography: homeTitle 32 bold, sectionTitle 24 bold, heroTitle 26 bold 2-line,
  cardTitle 15.5 semibold, cardMetadata 13.5, compactTitle 15, compactMetadata 13.
- `homeRailTextBlockHeight()` in home_sections.dart = 42dp base (LIVE-CALIBRATED:
  33 was too small, caused 9px overflow). All rail heights = artwork + this.
- `homeRailTextBlockHeight` lives in home_sections.dart — home_screen.dart
  imports it via home_sections.dart.
- `home_presentation.dart`: classifySection() + planPresentation() —
  newReleases/albums → squareRail (NOT grid, user feedback).
- Playlist/mood covers are SQUARE 168×168 (AspectRatio 1), NOT landscape —
  user said collage covers were too small.
- JumpBackIn/square rails 178×178.

### UI wiring in home_screen.dart
- `_buildHeroCarousel`: heroH = contentWidth × 0.88 × 1.25 clamp(280,380).
  viewportFraction 0.88. Uses _heroCandidate() — excludes from _LowerSections
  via excludeHeroSectionId.
- `_LowerSections` order: JumpBackIn → QuickPicks → feed sections (native order,
  hero excluded) → legacy fallback (if no feed) → Your playlists → Moods →
  quiet ending. Inter-section gap: single `SizedBox(height: 30)`.
- Collapsed sections (SizedBox.shrink) filtered BEFORE gap insertion.
- `_AlbumGridSection` (squareGrid) and `_SquareRailSection` (squareRail) both
  route through HomePlaybackController.activate per-item.
- `_PlaylistShelf` routes through dispatcher (navigateCollection → push detail).
- `_VideoShelf` per-item dispatcher too.
- `_MoodsSection`: real InnerTube getMoodsAndGenres, tap → getMoodTracks →
  _MoodTracksScreen (internal screen, honest title).
- Stagger entry: _entry controller 560ms, intervals per section.
- HOME_UI diagnostic: composerSections vs rendered count + kinds.

### Test device workflow
- `flutter build apk --debug` → adb install → `adb shell "logcat -v time
  flutter:V > /data/local/tmp/home_trace.log 2>&1 &"` (on-device capture
  avoids buffer rotation) → drive via `adb shell input tap/swipe` →
  `adb shell "cat /data/local/tmp/home_trace.log"`.
- User may disconnect device; ask before assuming availability.

---

## CRITICAL INVARANTS (never violate)

1. **NO global cross-shelf dedupe** — same entity in different shelves = VALID.
   Only in-shelf dedupe. Reintroducing global dedupe was THE original bug.
2. **NO artwork-based rejection** — missing artwork → PARTIAL support,
   placeholder render. Only identity+title loss is fatal.
3. **bestKnown = high-water mark** — degradation compares vs best-known,
   NOT latest-accepted. Ratchet 10→6→4→3→2 was THE collapse bug.
4. **NO Random() in recommendations** — deterministic sort, id tiebreak.
5. **NO hardcoded fake sections** — titles from source; no "Made for you"
   without evidence.
6. **NO random search fallback** — trending comes from FEmusic_charts browse;
   if fails → empty, pipeline falls to new releases. Never searchSongs as filler.
7. **NO gl override in browse context** — IP-inferred region. Muzo parity.
8. **Player contexts keep frozen static clientVersion** (BotGuard/PO token
   version-sensitive). ONLY browse uses dynamic version.
9. **Schema versions**: kHomeFeedSchemaVersion=4, kHomeParserVersion=6,
   kHomeRequestContextVersion=2. Bump ALL THREE when parser/context changes;
   old caches invalidate via fromJson null checks.
10. **Section memory persists** (home_section_memory_v1 key) and is TTL-swept
    on load. clearHomeCache() also clears memory.
11. **Stagger/hero/mini-player/nav are user-approved** — don't redesign without ask.
12. **MY variant (material_you_*) is FROZEN** — 28 files untouched by agreement.
13. **Playlist/mood covers are SQUARE** (user: collages were too small landscape).
14. **New releases = squareRail** not grid (user: "make slider like others").

---

## KNOWN LIVE-RUN BEHAVIOR (CPH2723 capture, 2026-09-02)

- Anonymous YTM gives 2 native shelves per response (varies: Rain Therapy /
  India's biggest hits / Trending community playlists / Dancing on your own /
  Romance Right Now) + musicTastebuilderShelfRenderer (unsupported, diagnosed).
- Upstream omits different shelves each request → section memory retains →
  converged stays stable. VERIFIED in 5-refresh matrix.
- Quick Picks generated from chart+native even on cold start (popularity prior).
- HOME_MEMORY action=RETAIN fires correctly; expired entries removed.
- Album card tap → HOME_PLAY navigateCollection → playlist detail screen
  (MPREb browseId works there via getPlaylistDetails).
- Song tap → playTrack SUCCESS.

---

## KNOWN LIMITATIONS

- `musicTastebuilderShelfRenderer`: unsupported, diagnosed every response.
- `musicImmersiveHeaderRenderer` / `musicDescriptionShelfRenderer`:
  unsupported, no fixture evidence.
- Continuation token captured for diagnostics only; load-more chain
  (Show-more UI → provider.loadMoreHome → repository.loadMore →
  mergeContinuationSections → fetchContinuation/parseContinuationResponse →
  browseContinuationJson) REMOVED 2026-09-03 per user (dead tap: composer
  budget re-trimmed appended shelves). Re-add only with a plan.
- Auth flips reset the InnerTube session (AuthSessionReset owned by
  MusicProvider): visitorData=null + stream cache clear + feed refresh.
  Without this, /player got login cookies + stale anon visitorData and
  rejected playback while browse worked (2026-09-03 login playback fix).
- Unbounded POSTs now timed: _ensureVisitorData 12s, playerJs 8s, /player
  15s. An un-timed stall held the test isolate open (exit hang).
- dataSyncId not captured (needs live logged-in response).
- Anonymous personalization ceiling: no login → YTM gives non-personalized feed.
- `ListTile ink splash` warnings from PlaylistDetailScreen — pre-existing,
  separate screen.
- TrackSignal/genre field exists but genre affinity NOT yet wired (no genre
  data in signals).
- Lofi reverb deferred (just_audio 0.10 has no reverb node).
- Localization deferred entirely.
- MY variant frozen.

---

## FILE MAP (most-edited, load these first after compaction)

| File | Role |
|---|---|
| lib/services/home/ytm_home_source.dart | YTM source + fallback + repository + HomeLoadTrace |
| lib/services/home/home_models.dart | HomeFeed/Section/Item, SectionIdentity, memory, TTL, ParseReport |
| lib/services/home/home_composer.dart | compose() + REMOVED/TRIMMED logging |
| lib/services/home/home_convergence.dart | convergeWithOrder() merge engine |
| lib/services/home/home_diagnostics.dart | qualityDimensions, isDegraded, logRequestContext/logFeedReport/logProvenance/logRefreshDiff |
| lib/services/recommendation/quick_picks_engine.dart | QuickPicksEngine.generate() |
| lib/services/recommendation/search_followup_graph.dart | SearchFollowupGraph |
| lib/services/recommendation/section_engines.dart | TrendingEngine + NewReleasesEngine |
| lib/presentation/home/home_presentation.dart | classifySection + planPresentation + HomeSemanticType/LayoutKind |
| lib/presentation/home/home_playback.dart | HomePlaybackController + HomePlayAction |
| lib/presentation/home/home_tokens.dart | ALL design tokens |
| lib/screens/home_screen.dart | HomeScreen + _LowerSections + all section widgets (~1620 lines) |
| lib/widgets/home_sections.dart | RailCard, ForYouRow, ArtistPortrait, ParallaxArtwork, ParallaxMediaCarousel, EditorialMoodTile, StaggerIn, homeRailTextBlockHeight |
| lib/providers/music_provider.dart | God-object facade (~3850 lines) — home feed, quick picks, search attribution, playback |
| lib/services/recommendation_service.dart | TrackSignal DB + rankTracks + signalFor/topArtistsForPicks |
| lib/services/explore/explore_policy.dart | ExplorePolicy: batch/refill constants + discovery-tilt ranking config |
| lib/services/explore/explore_engine.dart | ExploreEngine: pool mapping onto SHARED DeterministicRanker |
| lib/services/explore/explore_session.dart | ExploreSession: stream, shown-set dedupe, artist-run cap, identity dedupe |
| lib/services/explore/explore_controller.dart | ExploreController: autoplay-on-settle, generation races, refill, feedback |
| lib/services/explore/explore_palette.dart | ExplorePaletteCache: 100px decode, cap 30, tone-mapped ambient colors |
| lib/presentation/explore/explore_screen.dart | ExploreScreen: stream pages (neighbors/pill/rail), ambient background |
| lib/presentation/explore/explore_tokens.dart | ExploreTokens: stream rows/typography/ambient + chrome constants |
| lib/presentation/explore/explore_layout.dart | ExploreLayout: 5-slot diagonal planner (dx offsets, far-peek gate) |

### Tests
| File | Covers |
|---|---|
| test/home_convergence_test.dart | SectionIdentity, convergence merge, ratchet sequence, playback routing matrix |
| test/home_pipeline_test.dart | Composer, quality gate, cache roundtrip, degradation, metadata, quality dims |
| test/ytm_home_parser_test.dart | Parser fixtures (shelves, identity, types, unsupported) |
| test/home_presentation_test.dart | Classifier + planner matrix |
| test/recommendation_engine_test.dart | QuickPicks + SearchFollowupGraph |
| test/player_flow_widget_test.dart | Player widget flows (FakeMusicProvider pattern) |
| test/explore_engine_test.dart | Pool validation, seed floor, cold/warm ranking, determinism, policy |
| test/explore_session_test.dart | Dedupe, artist-run cap + starvation yield, thresholds |
| test/explore_controller_test.dart | Autoplay settle, rapid-swipe race, refill, exhaust, restore, feedback |
| test/explore_palette_test.dart | Cache, neutral fallback, no-decode paths |
| test/explore_screen_widget_test.dart | Stream states (pill/jump/capsule/rail), FakeExploreProvider |
| test/explore_layout_test.dart | Planner fit on 360/390/tablet, determinism, reason gate |
---

## COMMIT LOG (this branch, newest last)

```
964b4b2 test: align player widget test
55df611 prune dead code, InnerTube singleton
3c34d43 remove firebase deps
eafb053 extract DownloadManager
98c3d38 extract PaletteService
a09e5ea design tokens + glass system
27326c9 playback: kill double-auto-advance; UA fix
7372acf playback: PlaybackState + PlaybackController
c06ee24 queue: v5.2 clear semantics + volume/speed
255c550 shell: ambient backdrop
0416310 home/library transparent scaffolds
2225901 now playing + search transparent
c792868 feature: lofi mode
e794342 feature: minemusic:// deep links
1741a2d search: state machine + bleed-through fix
f4638db nav: search icon fix
bde1e48 home v1: listening surface
684e5d6 home v2: carousel hero + rhythm
afeac1d home lower: parallax rails + mood tiles
dbd3893 home lower: data-driven renderer + new releases + playlists
2338c51 content: structured Home feed pipeline
a87bcc1 feed: request-context parity + search-fallback removal + quality gate
4a62e63 feed v3: forensic parser
8e64ad0 home v4: presentation coverage + spacing collapse + real Moods
644b184 feed: structured metadata + continuation + quality dims
0552be2 feed v5: section-local dedupe + PARTIAL + degradation protection
484575b convergence: best-known + enrichment + HOME_LOAD
6a873d7 presentation planner + overflow fix
3a1c32d dispatcher for all shelves + stable keys + HOME_DIFF
c737dbb nav: GlassTabBar.searchable
3b33098 live-run fixes: MPREb routing + overflow calibration
682f6d5 unified playback dispatcher + memory persistence (LIVE VERIFIED)
18e21b0 design tokens + typography
2d975c9 bigger covers + new releases slider
99e65d9 bigger covers: playlist/mood square
105b1a3 recommendation: Quick Picks engine + search-followup graph
```

---

## NEXT STEPS (if resuming)

1. **Explore live verification (device)**: build+install, open Discover →
   Explore card, swipe; capture `EXPLORE_LOAD` / `EXPLORE_PLAY` /
   `EXPLORE_SKIP` / `EXPLORE_PREFETCH` traces; verify deck peeks render,
   pill hidden on-route and restored on exit, artist tap opens detail,
   autoplay-on-settle, refill before exhaustion, ambient color shifts.
2. **Explore polish from live run**: stream spacing on small screens
   (planner drops far peeks <552dp pages), diagonal dx feel (±56/±28),
   pill entry animation (300ms) feel, ambient tone-map, autoplay toggle
   persistence (currently session-only).
3. **Logged-in renderer coverage (fixture-gated)**: run logged-in, pull
   ParseReport unsupported list + DROPPED/REMOVED/TRIMMED + HOME_UI +
   HOME_LOSS; save redacted JSON as fixture; one parser test per renderer;
   bump parser+schema+ctx versions + cache key per invariant 9.
   Mix-tile identity (`watchEndpoint.playlistId` → playlist type) if shown.
4. **musicTastebuilderShelfRenderer**: capture fixture, decide parse vs skip.
5. **Explore seed entry points**: open Explore from artist/album/mood with
   explicit seed (screen already accepts `ExploreScreen.open(seed:)`).
6. **Recommendation cache**: RECOMMENDATION_LOAD trace exists; add TTL cache
   keyed on taste-profile version if refresh cost matters.
7. **Genre inference**: derive genre/language from artist name patterns or
   YTM category metadata when available.
8. **Landscape/tablet**: contentWidth fraction system already responsive;
   consider 3-col grid at >600dp.

---

## GOTCHAS

- PowerShell on this machine: `rg` NOT installed; use Select-String / Get-Content
  piped grep via `| Where-Object` or `flutter analyze` filters.
- `flutter run` interactive BLOCKS the shell — use `flutter build apk --debug`
  + `adb install` + `adb shell am start` instead, or `flutter run` with output
  redirect via Start-Process if truly needed (user said don't live run without
  asking).
- Log buffer rotates fast on device (DNS spam ~1/s) — ALWAYS use on-device
  file capture (`logcat ... > /data/local/tmp/x.log &`) not `-d` dumps for
  anything >30s.
- `llvm-strip Permission denied` during build → `Remove-Item -Recurse -Force build`
  then rebuild.
- Test ID fixtures MUST be 11-char lowercase-alnum to pass videoId validation
  ('strong12345' etc, NOT 'strong').
- `type_tokens.Type` was replaced by `t.HomeTokens` (import as
  `import '../presentation/home/home_tokens.dart' as t;`).
- ForYouRow and RailCard are in home_sections.dart and use HomeTokens — do not
  re-hardcode sizes there.
- Material's own `RepeatMode` conflicts — home_screen and music_provider
  `hide RepeatMode` from material.dart; the canonical one is in
  lib/providers/playback/playback_state.dart.
- music_provider.dart has a `notifyListeners()` override that calls
  `_playback.projectFromProvider(this)` — do not remove; PlaybackState
  projection depends on it.

---

## USER PREFERENCES

- Caveman mode active (terse responses, drop fluff)
- User disconnects device when not needed — ask before live runs
- User reviews logs from real device and pastes them; analyze logs when given
- User wants Muzo-level quality WITHOUT cloning Muzo
- "Truth > count" — 3 honest sections beats 8 fake ones
- No new dependencies without measured necessity (darttubefix REJECTED:
  stream-extraction only, no Home parsing)
