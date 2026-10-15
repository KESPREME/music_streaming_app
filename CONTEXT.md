# CONTEXT.md — MineMusic Session Continuity

> This file preserves critical context for AI-assisted development sessions.
> If compacting or starting a new session, READ THIS FIRST.

---

## PROJECT

**MineMusic** — Flutter music streaming app (YouTube Music client).
Path: `D:\Projects\music_streaming_app` · Branch: `refactor/liquid-glass` · 812/812 tests green.

> **GATE (current):** `flutter analyze` = **195 issues, zero errors** (195 is the
> baseline; several commits have moved it DOWN by removing dangling exports).
> `flutter test` = **812 passing**. Debug APK builds. Treat 195 as the baseline —
> a rise means something new was introduced, not that the file grew.

- Flutter 3.47.1 / Dart 3.13.1 / Android target (CPH2723 test device, Android 16)
- State management: `provider` (NOT Riverpod — immutable PlaybackState projection used instead)
- Min Android: gesture nav, Impeller/Vulkan rendering
- Dev machine: Windows, adb at `C:\Users\nipun\AppData\Local\Android\Sdk\platform-tools\adb.exe`

---

## CURRENT STATE (commit 7f6777a)

### Lyrics v2 (plan: docs/PLAN-lyrics-v2.md — 1463 tests, 186 analyzer issues / 0 errors; device pass PENDING)

The old per-section notes (parity plan, SweptLine, old clock) are superseded; git history has them.

**Renderer** (`lib/widgets/lyric_line/`). ONE `RenderLyricLine` per line, repainting from the clock. Geometry is per VISUAL ROW
(`LyricLineGeometry`) so wrapped lines sweep row by row and never overlap. Paragraphs have fixed colours (changing a TextPainter
colour re-lays-out). Alpha and blur ride ONE `saveLayer`; the active line at alpha 1 / blur 0 takes none. Feather (30dp, CENTRED on the voice - 3/4 behind, 1/4 ahead, shrinking to 0 at both row ends via `lyricFeatherZone`, so there is no lag and no pop when a line finishes) and the
held-word bloom are extra layers on the active line only. Blur sigma = `0.57735*r + 0.5/dpr` (Skia's conversion) — a recollection,
CHECK ON DEVICE; if it looks too weak set sigma = ladder dp (`LyricLineStyle.sigmaFor`). Font: Plus Jakarta Sans BUNDLED in
`assets/google_fonts/` (32sp / h1.22 / w800 / -0.64) so it never arrives mid-sweep. Scroll stagger: `lyric_stagger.dart`. Held-word swell (`lyric_growth.dart`) is ONE asymmetric wave whose crest rides the voice: the letter being sung rises over `growCrest`=0.9 letters, the letters behind fall away over a much longer cosine tail (follow-through), C1 everywhere. The WHOLE held word is drawn by the swell from its first moment (holes in the plain passes cover the whole word; there is no per-letter hand-over, which popped by the flat lift), rides ON the word's flat lift (`wordLiftPx`), uses the plain pass's own edge/feather (`_fillEdges`), its glow is ONE blur layer per word, and every letter is its OWN glyph painter (`_letterPainter`) with NO caret-box clip — tracking/kerning make ink spill past the caret box, so the old clip cut glyphs flat and let neighbours' overhang ride on the wrong letter's lift (device screenshots 2026-10-13). The lean is limited to the row (`clampLean`). The soft edge's profile is a SMOOTHSTEP (`lyricFeatherAlpha`), not a linear ramp: a linear ramp ends in a corner and the eye draws a thin vertical "seam" through the next letter ahead of the voice (found by sampling pixel rows of a rendered fill: slope -1.5/px straight into 0), most visible on slow fills. A held letter is cut by ONE mask gradient (opaque / ramp / transparent) with no clip. The swell's scale is quantised to 1/200 so the glyph cache reuses ~16 strikes instead of rasterising a new one every frame. After the word ends the voice is accelerated (constant accel, C1) through the tail so it runs out within 1.5s.

**Clock** (`services/lyrics/lyric_clock.dart`). Port of BitChord LyricClock. `LyricPlayhead` is pure; `LyricClock` is demand-driven:
a vsync Ticker ONLY while a painter holds `retainFrames` (word-synced line in its window, or gap dots), a 100ms Timer for the
strip/index, nothing when paused. Readings are dated when TAKEN; only announced jumps (`MusicProvider.seekEvents`, `reset`) move
words backwards. One clock owned by `_NowPlayingScreenState`, fed by `LyricClockFeed`. NO stall detector (it caused the freeze).

**Panel/player.** Panel stays mounted after first open (Offstage + TickerMode). Close order: panel fades FIRST, then artwork.
Deck = `SizeTransition` + 24dp slide (no alpha over glass); `_controlsShown` is the single source for deck AND discs; user scroll
20dp hides/reveals, lower-half tap reveals (`lower_half_tap.dart`). Caption (`lyric_caption.dart`): underlined, no icon, priority
Translating > Translated/Romanized > Lyrics by X > No lyrics found. Strip: "unsynced" = NO timestamp at all.

**Providers/race** (`services/lyrics/`). `lyrics_service.dart` = `lookup()` (returns provider + fromCache + isFallback). Query cleaned
ONCE (`lyrics_query.dart`); real album only (`cleanAlbum`). Bini `identify` runs concurrently under 2.5s; its ISRC feeds
lrc.red/LyricsPlus/Bini; `_SharedDocuments` fetches a shared TTML once; 100-entry ISRC LRU. `provider_race.dart`: all providers
start at once, answers consumed in PRIORITY order; word-synced accepted; line-synced HELD (prioritize ON = default, key
`prioritize_syllable_sync_v2`; the old key was an accident, never read); plain text ranks last; 4s grace after the first hold,
10s overall deadline; at the stop, already-settled answers are re-judged. Losers keep running and report late through
`onResult` (that is how the sheet fills in); only a hung source is `onCancelled` at the deadline. Genius is lazy. Keyed PaxSenix
Spotify/Musixmatch are listed but never raced without a key (`flutter_secure_storage`, `PaxSenixKeyStore`). Callbacks are
PER LOOKUP (`LyricsRaceCallbacks`), replayed to a joiner of an in-flight lookup; dedup key = (track, onlyProvider).
UA is OUR OWN (`LyricsHttp.agent`) — deliberately not BitChord's. Musixmatch live token returned 403 from the dev IP: UNVERIFIED.

**Cache.** `LyricsCacheSchema` (v3) creates AND upgrades the `timings` column (fresh installs used to cache nothing); v3 drops old
rows. Read path = `decodeCachedLyrics` (1:1 with what was stored — `parseLrc` added a head entry and the positional timings were
discarded). Disk only when TIMED; plain text is memory-only; prefetch never leaves an unsynced answer. `parseLrc` no longer
invents word timings (LRCLIB/KuGou are line-synced); `parsePlainText` stamps 0.

**Selection model** (`MusicProvider`). Per track: generation, `states`, `results` (every answer kept), `selected`. Switch =
found → apply now; fetching → apply on landing; not fetched → dedicated single fetch; not found → no-op. NEVER nulls
`currentLyrics` for a switch (only a track change does). A manual pick is cached (`rememberChoice`). Lookup waits for a known
track length (3s patience). Settings sheet re-runs the lookup on close if anything changed.

**Sheets/back.** Live sheet stays on the PLAYER's navigator (a root-navigator sheet would open UNDER the player card, which the
global overlay draws above the root navigator); it is a `DraggableScrollableSheet` (drag anywhere; pops once; snap-at-50% not
BitChord's 25%). Back is `resolveShellBack` in `main.dart`: player routes close before the player. Settings sheet: root navigator,
mini player hidden meanwhile, max 0.85 height, PaxSenix key dialog (opens empty). Edge-autoscroll Ticker KEPT (unverified that
ReorderableListView's own reaches the ends).

**Translate/romanize.** Port of LyricsTranslation.kt: real responses split by SENTENCE, markers come back as their own segments —
parse by joining then splitting on markers (the old one-segment-per-line reading failed every batch). 3500-char batches, 2 in flight,
inputtools retry for Latin-script Hindi, gzip disk cache `lyrics_translation_v3`, target = setting → locale base language → en.

**Gotchas.** `str_replace`/`grep_search` are UNRELIABLE on CRLF files (many lib files are CRLF) — use a line-ending-aware helper.
`List.sort` is not stable (parseLrc now sorts stably). Never `.Replace("\n", …)` over a whole file.
### Auth / session (c12c63a — the session used to be forgotten every restart)
`AuthService.init()` had **ZERO call sites**: cookies were written to
`SharedPreferences['youtube_cookies']` and the read path was dead code. `main()`
now awaits `init()` **before** `runApp`. Ordering is load-bearing:
`MusicProvider`'s `AuthSessionReset` samples `isLoggedIn` in its constructor
(during `runApp`), so a restore issued after that reads as a login and resets the
InnerTube session + refetches the feed on every cold start. `init()` is idempotent
(`_restored` flag) so a second call cannot fake a flip; `debugResetRestoreFlag()`
is test-only. 10 tests in `test/auth_session_persistence_test.dart`, including two
that pin the ordering in BOTH directions.

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
  cache key = home_feed_snapshot_v5_<identity>_primary_<locale>,
  schema+parser+ctx version-validated; section memory persisted to
  home_section_memory_v1; isColdStarting / isColdStartExhausted exposed]
  ↓ MusicProvider._homeFeed + .homeFeed + .quickPicks + _bumpHomeContent()
  ↓ HomeScreen: _HomeBody (loading gate) → _RealHomeBody → Selector → _LowerSections
  ↓ _FeedSection → _feedSectionRenders() gate → planPresentation() → widget
```

### Home loading states (NEW 964a787 — the screen had NO loading state at all)
- `HomeRepository.isColdStarting` = `_current == null && _inFlight != null &&
  !_firstFetchSettled`. ONLY true on a cold start with nothing cached. A refresh
  over a cached feed is deliberately NOT loading — flashing a skeleton over good
  content reads as the app discarding work it had done.
- `isColdStartExhausted` = settled with nothing. `MusicProvider.isHomeLoadExhausted`
  = `!hasHomeContent && _homeLoadFailed`.
- **`hasHomeContent` is the important one.** A null feed still renders the local
  fallback sections (Jump back in, Quick Picks, Trending, New releases,
  playlists). Gating "Couldn't load Home" on the feed alone covered a WORKING
  screen with an error and made those sections unreachable. Retry requires that
  nothing at all can render.
- `awaitFirstFetchSettled()`: `load()` deliberately doesn't block on network, so
  a caller with an empty screen had no way to learn the outcome. Provider awaits
  it when `feed == null` and sets `_homeLoadFailed` + `_bumpHomeContent()`.
- A successful `refreshHomeFeed()` clears `_homeLoadFailed` — otherwise the flag
  survives and keeps the message up over a feed that is plainly there.
- `_HomeBody` gives up on its own after 12s. **The timer must be armed on the
  loading TRANSITION, not from `build()`** — the widget watches the provider, so
  re-arming every build resets the countdown forever and the shimmer never gives
  up. That was a real bug.
- `HomeSkeleton` (lib/widgets/home_skeleton.dart) reserves exactly what the real
  sections do: hero clamp expression repeated, rail = card + text block + the same
  12dp slack, artist = portrait metric + 28dp gap. Skeletons must pixel-match
  their content or they cause the jump they exist to prevent.
- Shimmer primitives are public in `search_skeleton.dart` (`ShimmerBlock`,
  `ShimmerPainter`) and shared by both screens. `kShimmerBandFraction` 0.42
  (search) vs `kHomeShimmerBandFraction` 0.5 (home — a narrow band over a
  screen-long distance reads as a scanning line).

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

### Home gaps — FOUR defects fixed (47ebe1f)
1. **The collapse filter was DEAD CODE.** It tested `widget is SizedBox` against a
   list of section *widgets*; the instance is always `_FeedSection`, never the
   `SizedBox.shrink()` its build returns. So every collapsed shelf still ate a
   30dp gap — the exact "giant-gap bug" the comment claimed to prevent. Feeds are
   now gated by `_feedSectionRenders()` before being added; `_FeedSection.build`
   calls the same predicate so the two cannot drift.
2. Hero→lowerSections gap was **zero** (hero is a separate sliver). Now applied
   across the boundary via `_LowerSections.topGap`.
3. The 24dp spacer under "Home" was unconditional → hole on every cold start when
   the hero collapsed. Now conditional on `_hasHero`.
4. Artist rails reserved `96 + homeRailTextBlockHeight` (a TWO-line block) for
   99dp of content → ~76dp dead band under every artist rail. New
   `homeArtistPortraitHeight()` (104dp: 72 circle + 8 + 20 line + 4 slack) lives
   NEXT TO the widget so rail and portrait cannot disagree.
   **Do not derive that line as `fontSize * 1.2`** — it came out 3px short and
   overflowed the Column. The font really produces ~20dp for a 13px line.

### Card / list layouts per section (NEW 7f6777a)
Three history/recommendation shelves can each switch between artwork cards and
paging rows. Persisted per section, one key each.

```
lib/presentation/home/home_view_mode.dart
  HomeSectionViewMode { list, card }   + .toggled
  HomeViewSection { jumpBackIn, quickPicks, listenAgain }
  HomeViewModeStore  — ChangeNotifier, keys home_view_<section>
    initialize() read in main.dart alongside ThemeProvider/AccentController
    modeOf/isCard/toggle; defaultFor() owns every default
    toggle() swallows a prefs write failure (see gotcha below)
lib/widgets/section_view_toggle.dart  — glass circular toggle, destination icon
lib/widgets/track_list_column.dart     — TrackListRow + TrackListColumns
lib/widgets/home_layout_switch.dart    — HomeLayoutSwitch + sectionLayoutTransition
```
- **Which feed shelves qualify** comes from `SectionIdentity.semanticSlug(section)
  == 'recent'`, which the parser ALREADY derives from the shelf's own title
  (home_models.dart: "listen again" | "recent" | "jump back"). **Do not
  hardcode a title string** — that is what BitChord does (`RECENTS_TITLE`, plus
  `index == 0`, which never matches in our tree since Jump back in is a local
  overlay). The slug matches in any locale/account and covers "Recents" for free.
  It had ZERO test coverage until now; `test/home_convergence_test.dart` pins it
  both ways (history titles match, non-history shelves must NOT).
- **"Listen again" is a NATIVE FEED SHELF, not `FEmusic_history`.** It arrives
  with its real source title and renders as `_AlbumGridSection` (squareGrid,
  2 columns, 6 rows = 12 items). The grid body was extracted to
  `_albumGridBody()` so the plain and toggleable versions share one grid —
  two copies would drift on the first radius change.
- Defaults: ALL THREE open on **card**. Quick picks + jump back in as before;
  listen again defaults to card because that is how it has always rendered, so
  upgrading does not silently restyle the feed.
- Row metrics are exact BitChord parity (`RECENT_TRACKS_PER_COLUMN = 4`,
  `TRACK_COLUMN_FRACTION = 0.88f`, max 400, art 48/r7/gap 12/pad 4/overflow 36).
  The 0.88 width is **intentional peek**, not a bug — the next column peeks in.
  Do not "fix" it.
- **THE GAP BUG — read before touching `trackListColumnsHeight`.** It reserved
  `ceil(count/4)*4` rows, as if the columns STACKED. They scroll sideways, so
  10 tracks are 3 columns of 4/4/2 and still **4 rows** tall; the old math left
  a screen-tall hole under a four-row list. Now `min(count, 4)`, matching
  BitChord's `chunked(4)` inside a wrap-content row. `count <= 0` still reserves
  ONE full column so the skeleton keeps its shape while loading.
  The first version of the fix was pinned by a test that derived its
  expectation FROM the implementation — it passed while the UI was visibly
  broken. Derive expectations from correct behaviour, never from the code.
- `HomeLayoutSwitch` replaced an `AnimatedSize`+`AnimatedSwitcher` block that
  had been **copy-pasted into all three sections**; the same class of bug now
  has one home.

### Layout-swap motion — three defects, all found by MEASURING (7f6777a)
- **`AnimatedSwitcher` reports the SAME `AnimationStatus` for both roles.** It
  drives the arriving child 0 → 1 and the departing child 1 → 0, so you **cannot
  infer the role from the animation**. Guessing backwards is worse than not
  animating: measured, the arriving layout shrank to nothing while the departing
  one sat at 94% fully painted on top of it. That is exactly the reported
  "the next thing comes before the animation completes".
  **The role now travels WITH the child** — compared by key against the layout
  currently on screen (`arrivingKey`). Deterministic, no inference.
- **One monotonic tween cannot both arrive gently and leave completely.** A
  shared `0.94 → 1.0` ends the departing body at 0.94 (a ghost); a shared
  `0 → 1` makes the arriving body pop from nothing. Hence: arriving settles
  `0.94 → 1`, departing shrinks `1 → 0` (gone by ~160ms of 220ms).
- **`Curves.easeOutBack` (`Motion.springCurve`) is WRONG for a state change.**
  It passes its target at ~60% of the clock — measured **1.086 at 132ms of
  220ms** — then spends the rest unwinding, which reads as arriving early. Use
  monotonic curves (`Motion.enter`/`Motion.exit`/`Motion.standard`).
- **Height landed in two beats.** A `Stack` sizes to its TALLEST child, so a
  tall departing body (listen again's ~1446dp grid vs a 224dp list) held the box
  open for the whole swap, then collapsed. `Positioned` takes the departing body
  out of the size calculation → `AnimatedSize` animates in ONE pass. A
  `ClipRect` around it is required or it paints over the section below.
- No opacity anywhere in the swap: the nav bar and mini-player are backdrop
  lenses, and a translucent layer between a lens and its content flattens the
  glass (same rule as the account switcher).
- Pinned by `test/home_layout_switch_test.dart` — per-frame scale sampling, both
  directions, height monotonicity, no overflow, glyph morph, one glyph at rest.

### Presentation (STABLE)
- `HomeTokens`: **contentPadding 10** (matches the floating chrome gutter so card
  edges line up with the nav bar), **sectionGap 26**, **headerToContent 10**,
  cardGap 12, heroCardFraction 0.88, squareCardFraction 0.46; hero 4:5, square
  1:1; heroRadius 20, cardRadius 12; heroPlay 56/30.
- **headerToContent is a deliberate DEPARTURE from BitChord**, which uses 0. Their
  section title is a 22sp display face that carries its own air; ours is 24sp bold
  on a tighter line and with no gap the title read as FUSED to the first card
  (user feedback: "almost joined, separated by a thin sliver").
- Typography: homeTitle 32 bold, sectionTitle 24 bold (`sectionTitleSize`), hero
  **section** title — see below, heroTitle 26 bold 2-line (the CARD's own title —
  different token, don't confuse), cardTitle 15.5 semibold, cardMetadata 13.5,
  compactTitle 15, compactMetadata 13.
- **`heroSectionTitle` == `sectionTitle` (7f6777a).** It used to be 19/w600 on the
  reasoning that a 24dp bold heading competes with 280-380dp of artwork beneath
  it. Measured against BitChord, that reasoning does not hold: every section
  heading there is one size and one weight and the lead shelf is not a special
  case. `heroSectionTitleSize` was **DELETED** — if you find a reference to it
  (e.g. an old test) it is stale. Hierarchy on this screen comes from `homeTitle`
  above it. `heroSectionHeader` still accepts a `style` override; nothing uses it
  that way now.
- `homeRailTextBlockHeight()` = 46dp base (LIVE-CALIBRATED: 33 was too small,
  caused 9px overflow). All square-rail heights = card + this + 12 slack.

### Hero carousel (f10bb10)
- Was titled **'Quick Picks'** — same name as the compact Quick picks list on the
  same screen, so the page read as glitched. Now **'For you'**, which also
  describes the source honestly (history-seeded suggestions / engine picks /
  chart).
- **It only appeared after playing a track.** Root cause: `hasHeroHint` and
  `excludeHeroSectionId` were sampled ONCE via `context.read` in the screen's
  first build — before the chart landed — and passed as constructor args. Nothing
  recomputed them until an unrelated rebuild. Both are now read inside
  `_RealHomeBody`, which `context.watch`es the provider. The three helpers are
  `static` for exactly this reason.
- Hero source order: recommendedTracks → quickPicks → trendingTracks → feed
  shelf. **The guest curated-hits pool was DELETED** (47ebe1f): 6 of its 16 hardcoded
  video IDs were 404 and 2 more resolved to a different song than labelled.
- **Cold start Quick Picks are therefore honestly weak** — real chart + native
  feed only. The skeleton covers the window before they arrive. Do not "fix" this
  by re-adding hardcoded tracks; that violates invariant 5.

### Quick Picks artwork (47ebe1f)
Three independent causes, all real:
1. `music_provider.dart` new-release → `RichCandidate.fromTrack` dropped `albumArt`.
2. `section_engines_v2.dart` `_toTrack` hardcoded `albumArt: ''`, ignoring
   `release.artworkUrl`. Together these made EVERY new-release track artless.
3. `ForYouRow`/`RailCard` `errorWidget` had no icon, so a 404 read as a deliberate
   blank while an absent URL showed a music note. Both now paint the same glyph.

### Playback equalizer — DEVICE HAZARD (1a53ce1)
`audio_service.dart` put `AndroidEqualizer` in `androidAudioEffects`
unconditionally. `AudioEffect._activate` runs on EVERY audio activation and the
equalizer reads its band count from the platform there. On hardware that cannot
create the effect (log: `EqualizerBundle id: -1 status 0 enabled 0`) the read
throws a NullPointerException out of BOTH `play()` and `pause()` — the app skipped
every track. `AudioEffect._activate` is **library-private**, so it cannot be
overridden from another package; the only fix is to keep the effect out of the
pipeline. It is now `enableEqualizer: false` by default.
**Do not re-add it without a working UI AND a device-support check.**
`EqualizerService` refuses to enable when `!isPlatformAvailable`, and bounds its
`parameters` read with a 2s timeout (that Completer never completes when the
effect is not in the pipeline, which would hang init forever).

### Glass setup (c12c63a)
- `lgw.LiquidGlassWidgets.initialize()` + `wrap(brightnessResolver: Theme.maybeBrightnessOf)`
  in `main.dart`. Both were NEVER called: no shader pre-warm, no Reduce Motion /
  High Contrast bridge, and glass shadows/borders vanish when app theme ≠ OS
  theme. With no `theme:`/`adaptiveQuality:`, `wrap()` returns its child unchanged
  (verified in the package source) — no Navigator/Directionality injected.
- `MaterialApp.builder` wraps in `Material(type: transparency)`: lgw ships no
  Material ancestor and under MaterialApp its `Text` renders with debug underlines.
- `pubspec.lock` already had liquid_glass_widgets **1.8.1** / easy **4.3.4**; only
  the constraint strings were stale. The "bump" was a no-op — verified against HEAD.
- `adaptiveQuality` is deliberately OFF (experimental 3s benchmark, can shift
  quality mid-session).

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
  quiet ending. Inter-section gap: `SizedBox(height: HomeTokens.sectionGap)` = 26.
- **There is no collapse filter any more** — feeds are gated by
  `_feedSectionRenders()` BEFORE being added, so a collapsed shelf is never in the
  list and never takes a gap. The old `widget is SizedBox` test was dead code.
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
9. **Schema versions**: kHomeFeedSchemaVersion=5, kHomeParserVersion=6,
   kHomeRequestContextVersion=3. Bump ALL THREE when parser/context changes;
   old caches invalidate via fromJson null checks. v5/ctx v3 because the request
   context now carries `context.user` and the cache key gained an identity
   discriminator — a personalized snapshot must not be served to an anonymous
   app. Parser stays at v6 on purpose: no parsing rule moved, so bumping it
   would invalidate good caches for a version describing identical behaviour.
10. **Section memory persists** (home_section_memory_v1 key) and is TTL-swept
   on load. clearHomeCache() also clears memory.
11. **Stagger/hero/mini-player/nav are user-approved** — don't redesign without ask.
12. **MY variant (material_you_*) is FROZEN** — 28 files untouched by agreement.
13. **Playlist/mood covers are SQUARE** (user: collages were too small landscape).
14. **New releases = squareRail** not grid (user: "make slider like others").
15. **NEVER `dart format` innertube_service.dart / home_screen.dart /
    home_tokens.dart wholesale.** It causes 200+/100- churn AND *creates* lint
    findings by splitting pre-existing one-line `if`s. Also: `git checkout -- <f>`
    restores from the INDEX — if edits are staged it silently re-applies them. Use
    `git restore --source=HEAD --staged --worktree -- <f>`.
16. **NO overshooting curve for a state change or layout swap.** `Motion.springCurve`
    is `Curves.easeOutBack`: it clears its target at ~60% of the clock and unwinds
    for the rest, so the motion finishes before the animation does and reads as
    "it jumped early". Reserve it for something that genuinely wants overshoot.
    See "Layout-swap motion" above.
17. **NEVER `Opacity`/`AnimatedOpacity` anywhere above or around a glass lens.**
    The nav bar and mini-player are backdrop lenses; a translucent layer between
    a lens and its content isolates the backdrop it samples and the glass goes
    flat for the duration. Reveal by scale/slide. Never stretch-overscroll under a
    lens either (black scroll-edge artefacts on Android).

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

### Card/list capture (CPH2723, 2026-10-05 — drove 7f6777a)
- Screenshots of Home confirmed the toggles render, the persisted choice is
  honoured per section, and card mode was unaffected by the list work.
- **The list-mode gap was visible on-device**, which is how the
  `ceil(count/4)*4` reservation bug was found — arithmetic, not layout.
- **"Listen again" EXISTS on Home** as a native feed shelf, 2-column grid,
  6 rows = 12 items. It was never built by us under that name; the title comes
  from the source. Earlier CONTEXT claimed it was missing and needed
  `FEmusic_history` — that was wrong.
- Row rail measured on device: 48dp art, ~62dp pitch, and the second column
  is a deliberate 12% peek at the right edge (0.88 width parity), NOT a
  rendering fault.

---

## ACCOUNT FLOW (c1685b6 + 429e9db + 9b53508 + 4d60b87 + 7ca553f)

Rebuilt to match the reference app's flow. Read this before touching auth UI.

- **Nested-navigator trap.** `MainScreen` hosts a nested `Navigator`
  (`mainNavigatorKey`) so detail screens keep the tab bar and mini-player up.
  `Navigator.push(context, ...)` resolves to that NEAREST navigator, so a
  full-screen page becomes a CHILD of MainScreen and the chrome floats over it.
  **Two entry points to the SAME screen can therefore look different** — that is
  not a styling inconsistency, it is two different navigators.
  - Detail screens (artist/album/playlist/moods/genres/trending): push normally.
  - Full-bleed surfaces (sign-in, settings, account): `pushAboveShell()`.
  - From Home, `_pushGuarded(..., aboveShell: true)` — the flag keeps the
    double-tap debounce and only changes the target navigator. Nine detail-screen
    call sites pass no flag and are unchanged.
  - `LoginScreen` is ALSO opaque internally, so an unpainted WebView never lets
    the shell through — belt and braces for any future inward push.
  - Material You was unfrozen for ROUTING ONLY (user approved): its Settings
    and Login now use `pushAboveShell` too. Its *look* is still frozen.
- **Status bar inset on the login WebView.** A full-bleed WebView puts
  YouTube's own header (hamburger/logo/"Open App"/search/avatar) under the clock
  and notification icons — two overlapping bars of system chrome. The page is
  inset by `MediaQuery.padding.top`; the close button sits just below it; the
  bottom inset is applied by the `Positioned`, NOT also inside the panel (doing
  both doubles the gap). The opaque base must cover the inset bands too, or an
  unpainted WebView lets the shell show through the status bar.
- **Nothing is captured on sign-in automatically.** Auto-capture on page-finish
  is a race: the jar settles after the page does. The screen only READS the jar
  to decide whether to OFFER "Use this profile"; nothing is written until tapped.
- **Validated before stored.** `AccountIdentityService` signs the candidate jar
  into a PRIVATE header set, calls `account/account_menu` (20s cap, one retry at
  750ms), and persists nothing until it passes. Never applies the candidate
  app-wide first.
  **The candidate headers are MERGED over the standard set, never used as a
  replacement.** A jar only contributes Cookie + Authorization; replacing the
  map dropped User-Agent / X-YouTube-Client-Name / Origin / Referer, Google
  answered 200 with no `activeAccountHeaderRenderer`, and a signed-in user was
  told the sign-in could not be verified (live log, fixed in 489b004). Use
  `mergeAuthHeaders()`.
- **Identity** comes only from `account/account_menu` (name/email/avatar) and
  channels from `account/accounts_list` (pageId + datasyncIdToken). Parsers scan
  for a RENDERER by name, and find tokens by key name inside `supportedTokens` —
  a positional read of that list would be a guess about an unordered structure.
- **GoogleCookieCleaner** expires only Google's identity cookies, per origin, in
  all THREE domain forms (host-only, `Domain=host`, `Domain=.host`). Not
  `deleteAllCookies()`, not a server logout. Sign-out leaves the WebView jar alone.
- **Header avatar replaces the gear** on Home, opening `AccountSwitcherSheet`
  (glass sheet, `useRootNavigator: true`). Signed out it goes to Settings.
  `AccountButton` adds vertical-swipe channel cycling with elastic overshoot, and
  reuses `adjacentIdentity()` which declines to wrap.
- **Two glass rules**, both learned the hard way:
  - **NEVER `Opacity` above glass.** A translucent layer isolates the backdrop the
    lens samples, so the glass goes flat for the duration. Reveal by scale/slide.
    (The package's own dialog transition is scale-only for this reason.)
  - **NEVER stretch overscroll under a lens.** A backdrop-filter lens in a
    scrollable with overscroll renders BLACK at both scroll edges on Android, and
    we are Android-only. The switcher list is shrink-wrapped + Clamping instead.
- `Image.network` in this Flutter takes **`errorBuilder`**, not `errorWidget`.
- **Settings search** is `widgets/settings/settings_search.dart`: index + gate +
  field, applied to existing groups rather than restructuring the screen. Hidden
  keywords are the point ("mobile data" finds Cellular Quality). An unregistered
  row stays VISIBLE — failing open beats holes in the screen.

---

The flat `youtube_cookies` jar is gone. `AuthService` now holds a registry of
`GoogleAccountSession`, each with domain- and expiry-aware `AuthCookie`s plus
its `YouTubeProfile` channels.

- **Storage** is `flutter_secure_storage`, with a SharedPreferences mirror that
  is *read* as well as written. A device with an unusable keystore degrades to
  less-protected, not to signed-out. Legacy `youtube_cookies` migrates lazily
  and is dropped only after a successful save in the new format.
- **Account id derives from SSID/SID/HSID**, never the whole jar. Google rotates
  SAPISID and rewrites expiry metadata every sign-in, so hashing the jar minted
  a new id per login and forked duplicate accounts. Falls back to the signing
  cookie alone, then to one `acct_unknown` bucket.
- **Signing cookie** is name-exact: `SAPISID`, `__Secure-3PAPISID`,
  `__Secure-1PAPISID`. A substring test for "SAPISID" also matches SAPISIDHASH,
  which is derived FROM the cookie and cannot sign with. An account with no
  unexpired signing cookie is not loaded at all — reporting signed-in while
  sending rejected cookies is worse than reporting signed-out.
- **`context.user`** now carries `lockedSafetyMode` and, only when the shell
  reported one, `onBehalfOfUser` (dataSyncId). Never inferred. Previously sent as
  `{}`, which mis-attributes brand-channel sessions.
- **`identityKey`** = `anon` or `<accountId>[_<profileId>]`. Never cookie
  material — it becomes a preferences key and preferences are plaintext. Home
  cache keys carry it, so a personalized feed is never served anonymously.
- **`logout()` notifies before persisting.** Fail-closed: a keystore write that
  never lands must not resurrect a session the user removed. Also stops the UI
  sitting on a stale account for a keystore round trip.
- **Login never calls `deleteAllCookies()`** — it tore down every saved account
  on open and made "add another account" impossible. Uses
  `prompt=select_account`. Visits the music origin once before capturing
  (ytcfg + music-scoped cookies do not exist on accounts.google.com).
- **Equalizer tile removed**, not wired: the platform effect is deliberately out
  of the audio pipeline (see playback hazard), so there is no surface to open.
  Do not re-add without a device-support check.

---

## PLAYER HEAT / BATTERY (perf plan, docs/PLAN-perf-battery.md)

Root cause: Impeller (the Android default) has NO raster cache, so a
`RepaintBoundary` saves Dart paint time and no GPU time. Every frame the player
draws replays the whole scene, and a word-synced lyric makes that 60-120 fps.
So the fixes remove work from the scene rather than caching it.

- `lib/widgets/covered_gate.dart`. `PanelCover` (value true once the player
  panel has been fully open AND still for 250ms; false in the very frame it
  moves). `CoveredGate` mutes tickers and skips paint + hit-test under the page
  and the floating mini - layout is NOT touched (a custom `RenderProxyBox`, not
  `Offstage`, which would collapse the size and re-lay out the glass tab bar).
  `CoveredScope.of(context)` lets descendants stop what a gate cannot: the mini
  pill's position subscription, Explore's canvas video, the album header video.
  Wired in `global_music_overlay.dart` only.
- `lib/widgets/blurred_backdrop.dart`. The Now Playing wash (blur 60, 1.6x about
  top-centre) and the standalone queue wash (blur 65, 1.25x) are baked ONCE per
  track into a ~1/16-pixel image (`bakeBlurredBackdrop`, 4 logical px per baked
  px) and drawn as one `RawImage`. Same ops as the live tree, smaller scale;
  `test/blurred_backdrop_test.dart` renders both and compares (mean 0.7-1.2 of
  255, max 4). Source is decoded at 256px (was the 800px hero decode, or a
  full-resolution local file). A new track cross-fades 450ms; the old wash stays
  up until the new one is baked, so there is never an empty frame.
- `AnimatedEqualizerIcon` is a `CustomPainter` (`EqualizerBarsPainter`) inside a
  `RepaintBoundary`, repainting off the controller: no build/layout per tick.
  Compared pixel-for-pixel with the Row-of-Containers it replaced.
- The deck scrubber sits in its own `RepaintBoundary` (a position tick no longer
  re-records the whole player card's layer); its label style is hoisted.
- `LyricStrip` listens to the `LyricClock` only when it has TIMED lyrics. The
  clock is demand-driven, so a listener is what makes it tick.
- `LyricClockFeed` is a `WidgetsBindingObserver`: paused/hidden/detached stops
  the clock (its coarse timer is a plain `Timer.periodic` the scheduler does not
  mute); resume does `clock.jump(provider.position)` BEFORE `setPlaying(true)` so
  the first frame back shows the right line. `inactive` is NOT background.
- `lib/services/window_filler.dart`. The player window is filled one resolve at
  a time, in playback order, each appended as soon as ready (was `Future.wait`
  over up to 4). Serialised; latest request wins; abandoned when the current
  track changes.
- `AudioService`: the unused `AndroidLoudnessEnhancer` is gone from the
  pipeline (nothing could ever enable it; an attached effect also blocks offload).
- `PerfTrace` prints a rolling `PERF_WINDOW` (fps, build/raster p50/p90) every
  5s. `flutter build apk --profile --dart-define=PERF_TRACE=true`.

Deliberately NOT done (and why) is recorded in docs/PLAN-perf-battery.md.

## SONG TRANSITIONS (crossfade + AutoMix; docs/PLAN-transitions-automix.md)

Off by default. Settings > Player & Playback > Song Transitions, or the chip in the
queue heading (tap cycles Off, Crossfade, AutoMix; long-press opens the screen).

- Playback is two `AudioPlayer`s (`DeckPair`, `services/playback/decks.dart`) under one
  `audio_service` handler (`MineAudioHandler.shared`, set in `main.dart`). This REPLACED
  `just_audio_background`, which cannot host two players. The standby deck carries the
  INCOMING song only; at progress 0.5 the roles swap (no seek), and
  `_onTransitionHandoff` refills the window around the new head.
- `services/transition/`: `transition_settings` (prefs), `fade_curves`,
  `transition_planner` (pure), `transition_engine` (sleeps between songs; `poke()` wakes
  it), `audio_service_decks` + `provider_hooks` (glue), `track_analysis` (value type),
  `audio_analyzer` (pure-Dart DSP, isolate entry `analyzeInput`), `analysis_service`.
- The incoming song never writes the shared cache file: `buildSource(cacheWrites: false)`.
- `MusicProvider`: `transitions`, `transitionState`, `transitionContext()`,
  `windowedTrack(id)`, `analysisService`, `_analysisSourceFor`. Lock-screen transport
  goes through the same entry points as the on-screen buttons (`_bindMediaSession`).
- Analyser: tempo = autocorrelation of onset strength with harmonic voting, kick band
  weighted (`kickWeight`); confidence = agreement across 25 s stretches x pulse contrast;
  absolute activity gate. Planner acts only above `minBeatConfidence` 0.55. See
  the calibration notes in the plan, section 11, before touching any threshold.
- Android-only analysis: `AudioDecoder.java` via `MethodChannel('mine_music/audio_decode')`.
- Gotchas: `poke()` must stay asleep when idle (a pending timer fails widget tests);
  `pumpAndSettle` never settles on `TransitionDiagram` while enabled (use `pump(Duration)`);
  the queue's `LiquidGlassSegmented` thumb only highlights the FIRST active segment, which
  is why the transition toggle is a chip, not a 4th segment.
- Quality pass (plan section 12): `loudness.dart` (BS.1770 meter, mid+side, validated against
  ffmpeg), `level_plan.dart` (pair balancing; `mixGains` is the one gain law, used by the
  engine AND the lab), `phase_lock.dart` (speed-trim beat lock), `MixTrace` / `UpcomingMix` on
  the engine, `test/lab/mix_lab_test.dart` (renders real songs; `MIX_LAB_SONGS=<folder>`).
  The decoder returns STEREO now (`channels: 2`); `TrackAnalysis` is version 2.
- Level compared over the MIDDLE HALF OF THE OVERLAP of each song - not song averages, not the
  stretch before the fade (both were wrong on real music; a test pins the case).
- `settleActive(resetSpeed:)`: a stretched incoming song must not be snapped to normal speed
  before the ease-back (it caused two tempo jumps).
- `_applyGains` is single-flight, latest wins. Do not make it queue again.
- Do not attach an AudioEffect to the players to "add DJ filters": see plan section 12 verdict.
- NOT verified on a device: any audio behaviour, the decoder on real cache files, the
  handoff, lock-screen controls, whether the beat lock lands on the beat the listener hears.
  Checklist: plan sections 11 and 12.
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
| lib/presentation/home/home_view_mode.dart | HomeSectionViewMode / HomeViewSection / HomeViewModeStore (persisted per-shelf layout) |
| lib/screens/home_screen.dart | HomeScreen + _LowerSections + all section widgets (~2190 lines) |
| lib/widgets/home_sections.dart | HomeSectionHeader (has `trailing`), RailCard, ForYouRow, ArtistPortrait, ParallaxArtwork, ParallaxMediaCarousel, EditorialMoodTile, StaggerIn, homeRailTextBlockHeight |
| lib/widgets/home_layout_switch.dart | HomeLayoutSwitch + sectionLayoutTransition — the ONE card⇄list swap, used by all three shelves |
| lib/widgets/section_view_toggle.dart | SectionViewToggle — glass circular toggle, destination icon, selection haptic |
| lib/widgets/track_list_column.dart | TrackListRow / TrackListColumns / trackListColumnsHeight (paging rows) |
| lib/providers/music_provider.dart | God-object facade (~3850 lines) — home feed, quick picks, search attribution, playback |
| lib/services/auth_models.dart | AuthCookie (domain+expiry) / YouTubeProfile / GoogleAccountSession / AccountIdentity / AccountChannel / id derivation / isSigningCookieName |
| lib/services/auth_service.dart | Secure multi-account session registry; getHeaders, identityKey, selectIdentity, removeAccount, logout |
| lib/services/login_session_probe.dart | Pure sign-in rules: cookie construction, coalesce, hasSigningCookie, profileFromYtcfg |
| lib/services/account_identity_service.dart | validateAndDescribe: account_menu validation + channels BEFORE persisting |
| lib/services/innertube/account_parser.dart | Pure parsers for account_menu / accounts_list renderers |
| lib/services/google_cookie_cleaner.dart | Name-scoped Google cookie expiry, 3 domain forms, never deleteAllCookies |
| lib/screens/login_screen.dart | WebView sign-in, manual "Use this profile" confirm, honest phases |
| lib/screens/account_screen.dart | Full account + channel management page |
| lib/screens/account_switcher_sheet.dart | Header quick-switch sheet (root navigator, no Opacity over glass) |
| lib/widgets/account_button.dart | Header avatar + vertical-swipe channel cycling |
| lib/widgets/home_sign_in_prompt.dart | Home signed-out prompt (whole row is the target) |
| lib/widgets/settings/settings_search.dart | Settings search index + gate + field + empty state |
| lib/core/navigation/root_navigator.dart | rootNavigatorKey + pushAboveShell() for full-screen surfaces |
| lib/services/recommendation_service.dart | TrackSignal DB + rankTracks + signalFor/topArtistsForPicks |
| lib/services/explore/explore_policy.dart | ExplorePolicy: batch/refill constants + discovery-tilt ranking config |
| lib/services/explore/explore_engine.dart | ExploreEngine: pool mapping onto SHARED DeterministicRanker |
| lib/services/explore/explore_session.dart | ExploreSession: stream, shown-set dedupe, artist-run cap, identity dedupe |
| lib/services/explore/explore_controller.dart | ExploreController: autoplay-on-settle, generation races, refill, feedback |
| lib/services/explore/explore_palette.dart | ExplorePaletteCache: 100px decode, cap 30, tone-mapped ambient colors |
| lib/presentation/explore/explore_screen.dart | ExploreScreen: wheel snap/debounce/haptics, mesh, tab bar |
| lib/presentation/explore/explore_tokens.dart | ExploreTokens: arc/pill/vinyl/tab constants |
| lib/presentation/explore/explore_layout.dart | ExploreWheelMath: cosine arc (center-rightmost), anchor curves |
| lib/presentation/explore/explore_wheel_physics.dart | SnapScrollPhysics: magnetic snap-to-row |
| lib/presentation/explore/explore_wheel.dart | ExploreWheel + bare rows + LiquidGlassPill |
| lib/presentation/explore/explore_vinyl.dart | VinylDisc (grooves, spindle, 6s spin) + MicroEqualizer |
| lib/presentation/explore/explore_mesh.dart | Mesh: blurred vibrant glow + deep base + luminance scrim |

### Tests
| File | Covers |
|---|---|
| test/home_convergence_test.dart | SectionIdentity, convergence merge, ratchet sequence, playback routing matrix, semanticSlug 'recent' both ways |
| test/home_pipeline_test.dart | Composer, quality gate, cache roundtrip, degradation, metadata, quality dims |
| test/lyric_sweep_test.dart | Fractional reveal, inter-word gap creep, focus/scroll lead, clock drift correction, no full-list rebuild |
| test/lyrics_provider_race_test.dart | Concurrent ask + priority-ordered consume, three-valued verdict, lazy Genius, settled-vs-abandoned reporting |
| test/lyric_growth_test.dart | Held-note thresholds per word length, three beats, stagger, decay, lean, script exclusions, no NaN |
| test/lyric_sub_line_test.dart | The original text is never replaced, timings keep indexing it, reveal collapses to no height, wrong-track transform refused |
| test/lyrics_panel_bounds_test.dart | MeasureSize reporting + de-jitter + no mid-frame build; the list reserves the deck's height |
| test/lyric_swept_line_test.dart | Per-line RepaintBoundary isolation, CustomClipper prefix width, alpha/blur readability ladder, no ShaderMask, growth overlay present/absent, ONE font size/weight for every line, emphasis from scale+alpha, one monotonic spec |
| test/lyric_scroll_browse_test.dart | A browse is a FINGER: the follow survives its own animation, 600ms/5s exit, no yank-back; the lead bounds, the top-anchor arithmetic, and never sitting behind the voice |
| test/lyric_morph_test.dart | No lyric layer during the collapse, never two, the fade completes on its own window, the close starts immediately, no disc under the alpha |
| test/lyric_strip_test.dart | The five strip states, one clock for index and wipe, one row with an ellipsis, no lift or bloom, 340ms/0.35/0.55 |
| test/lyrics_provider_reachability_test.dart | Every enum member is in the default order or explicitly hidden; order repair; the word-sync default is off |
| test/lyrics_same_language_test.dart | The script check, the controller state, and the dimmed-but-tappable disc that explains itself |
| test/lyric_syllable_parsing_test.dart | TTML run gluing (Japanese + English apostrophes), enhanced-LRC syllable tags, plain-LRC heuristic |
| test/lyric_timings_cache_test.dart | Word/syllable timings survive the disk round trip; schema v2 migration |
| test/lyrics_translation_test.dart | Batching under the char cap, batch-to-reply pairing, short/long reply handling, Latin detection, timestamp preservation, display-mode fallback + stale-answer rejection |
| test/home_view_mode_test.dart | Store defaults + independence, prefs roundtrip, corrupt-value fallback, toggle semantics/icon, header trailing slot, row-rail height (the gap bug) |
| test/home_layout_switch_test.dart | Per-frame scale sampling: departing reaches ~0, arriving 0.94→1, BOTH directions, height monotonic (one beat), no overflow, glyph morph |
| test/auth_session_persistence_test.dart | Secure store, legacy migration, expiry, domain scoping, multi-account, SAPISIDHASH |
| test/auth_channel_identity_test.dart | browseUserContext, identityKey isolation (no cookie leakage) |
| test/login_session_probe_test.dart | Signing-cookie names, jar coalesce, ytcfg → profile, no-guess rule |
| test/account_screen_test.dart | Signed-out, unnamed account, channel switch, removal confirm, sign out |
| test/account_parser_test.dart | account_menu / accounts_list shapes, token order, blank-token trap |
| test/home_sign_in_prompt_test.dart | Prompt copy, two-line subtitle, whole-row target, cookie-cleaner plan |
| test/settings_search_test.dart | Index matching, fail-open on unknown row, gate, field, empty state, REAL registry incl. the group-gate bug |
| test/ytm_home_parser_test.dart | Parser fixtures (shelves, identity, types, unsupported) |
| test/home_presentation_test.dart | Classifier + planner matrix |
| test/recommendation_engine_test.dart | QuickPicks + SearchFollowupGraph |
| test/player_flow_widget_test.dart | Player widget flows (FakeMusicProvider pattern) |
| test/explore_engine_test.dart | Pool validation, seed floor, cold/warm ranking, determinism, policy |
| test/explore_session_test.dart | Dedupe, artist-run cap + starvation yield, thresholds |
| test/explore_controller_test.dart | Autoplay settle, rapid-swipe race, refill, exhaust, restore, feedback |
| test/explore_palette_test.dart | Cache, neutral fallback, no-decode paths |
| test/explore_screen_widget_test.dart | Wheel states (rows/snap/eq/spin/expand), FakeExploreProvider |
| test/explore_layout_test.dart | Wheel math (extent/arc/curves/tForIndex), reason gate |
| test/explore_wheel_physics_test.dart | Snap target/index rounding |
| lib/widgets/glass_options_sheet.dart | +onDislike row (Explore-only, null-hidden) |
| lib/providers/music_provider.dart | +requestedTab plumbing (Explore tab bar → MainScreen) |
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
7ad97fb docs: refresh CONTEXT for home, auth and glass
2e105a1 auth: secure multi-account sessions with channel profiles
0d71aba auth: channel identity in InnerTube context, identity-scoped caches
ee1b98e settings: account and channel management screen
76fc0c9 settings: remove tiles that could only say "coming soon"
c1685b6 fix(nav): full-screen auth/account/settings routes go above the shell
429e9db feat(auth): account identity from account_menu, channels from accounts_list
9b53508 feat(auth): manual profile confirmation before a session is committed
4d60b87 feat(account): avatar quick-switch, Home sign-in prompt, no opacity over glass
7ca553f feat(settings): keyword search over the settings list
6b13605 docs: record the account flow, glass rules and new gates
489b004 fix(auth): merge candidate session headers instead of replacing them
0486d5f docs: record the header-merge rule and the errorBuilder gotcha
ee25374 fix(login): consistent route target from Home, and a real status-bar inset
44cb1e9 docs: record the route-target flag, the WebView inset rule, and the MY gap
79fabf6 fix(nav): Material You full-screen routes go above the shell too
7f6777a feat(home): per-section card/list layouts for the history shelves
c4f76b9 feat(lyrics): BitChord-parity kinetic lyric engine
33914fc fix(lyrics): the panel was disabling its own auto-follow
471bc1e fix(lyrics): split the player morph into two stages
45c7702 feat(lyrics): the strip has real states and one clock
86b4efe fix(lyrics): three providers were visible, reorderable and never asked
4542ebd fix(lyrics): the globe said nothing when it had nothing to do
f8a3eeb feat(lyrics): the word-sync preference lives next to the list it changes
```

---

## NEXT STEPS (if resuming)

0. **Lyrics - device verification, the ONLY thing left.** All of the lyrics work
   is unit-tested and gated (891 tests, 198/0, APK builds) but has never been
   watched. On CPH2723, in this order:
   - auto-scroll keeps up with the singing for a whole verse (Phase 1 - this was
     the reported jank and the fix is only proven in a widget test)
   - scroll by hand -> blur clears, every line readable, snaps back ~600ms later
   - a long lyric's last line is fully above the seek bar
   - lyric->player: artwork collapses, THEN lyrics fade in. Nothing duplicated,
     nothing readable through the artwork (Phase 2)
   - the strip: one line, no lift twitch, word wipe tracks, "Open lyrics" on an
     unsynced song, "No lyrics found" when there is none
   - globe on an English lyric -> dimmed, tap explains, no sub-line drawn
   - scrub the scrubber or drag the volume -> the discs stay up
   - switch provider -> the panel keeps animating, no freeze
   - the provider sheet: scroll it, drag a row to the end, tap "Prioritize
     syllable lyrics"
   - confirm the position stream still does NOT rebuild the list
0. **Card/list toggle - device verification outstanding.** 7f6777a is unit-tested
   but the morph has never been watched on hardware. Install on CPH2723 and
   capture the swap in BOTH directions on all three shelves; check the departing
   body is gone before the arriving one settles, the height moves in one beat,
   nothing clips the section below, and the choice survives a cold restart.
   The row rail in particular has only been seen in screenshots, not measured.
1. **Phase 4 home sections — `FEmusic_history` still BLOCKED ON A DEVICE PROBE.**
   BitChord also uses `FEmusic_explore` and `FEmusic_history`; we use home /
   new_releases / moods_and_genres / charts. Do NOT add either blind:
   - **CORRECTION to the older note here: "Listen again" is ALREADY on Home and
     is NOT `FEmusic_history`.** It arrives as a native `musicShelf` from the
     home browse with its real title, and now carries the card/list toggle. So
     the long-standing claim that "Listen again" was missing and needed
     `FEmusic_history` was wrong — the title was there all along.
   - `FEmusic_history` as an extra *source* still needs a probe to confirm which
     renderers it returns and that our staged walker handles them. Low value now
     that a real history shelf renders.
   - `FEmusic_explore` likely **duplicates the existing Explore tab** (wheel,
     engine, palette). Adding it to Home is a product decision, not a parity fix.
   Without live fixture evidence this violates invariant 5 and risks
   convergence churn on a feed that is currently stable.
1. **Explore live verification (device)**: build+install, open Discover →
   Explore card, swipe; capture `EXPLORE_LOAD` / `EXPLORE_PLAY` /
   `EXPLORE_SKIP` / `EXPLORE_PREFETCH` traces; verify deck peeks render,
   pill hidden on-route and restored on exit, artist tap opens detail,
   autoplay-on-settle, refill before exhaustion, ambient color shifts.
2. **Explore polish from live run**: wheel arc feel (k=72, θmax=1.2),
   snap spring tension, debounce 180ms feel, mesh drift layouts,
   vinyl spin speed (9s), eq bar motion, autoplay toggle persistence
   (currently session-only).
   NOTE (2026-09-07 fidelity pass): arc is now cosine center-rightmost
   (A=32), vinyl 6s + grooves + white spindle, pill is bespoke glass
   (80px, gradient border, bevel), header 28 without toggle, slim tab
   bar with provider tab plumbing, actions re-homed (heart in pill,
   rest in More sheet + Not-interested row). Awaited-HapticFeedback
   hangs in widget tests — always fire-and-forget haptics; modal
   sheets need providers ABOVE MaterialApp in test trees; dispose()
   must not notify during pop finalization (post-frame restore).
3. **Explore seed entry points**: open Explore from artist/album/mood with
   explicit seed (screen already accepts `ExploreScreen.open(seed:)`).
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
- **Widget tests + platform channels**: `AuthService.init()` reaches for
  `flutter_secure_storage`, and awaiting a real channel reply inside
  `testWidgets` (fake-async zone) HANGS with no error rather than failing.
  Seed inside `tester.runAsync(() async { ... })`.
- **Widget tests + GoogleFonts**: the `Type.*` tokens render through
  GoogleFonts, which fetches the font at runtime when unloaded and also hangs.
  Set `GoogleFonts.config.allowRuntimeFetching = false` in `setUpAll`.
- `AuthCookie` serialises `expiresAt` as **epoch milliseconds (a number)**. An
  ISO-8601 string parses as "no expiry" and a stale jar looks live.
- The inappwebview `Cookie.expiresDate` is **milliseconds** while our probe
  takes seconds; Android reports `domain`/`expiresDate` only when the WebView
  supports `GET_COOKIE_INFO`, so fall back to the host you read from.
- `Motion.springSoft`/`springSnappy` are `SpringDescription`s, NOT `Curve`s —
  they cannot be passed to implicit animation curves. Use `Motion.settle` /
  `Motion.springCurve` there — but see invariant 16: `springCurve` is
  `easeOutBack`, which overshoots, so it is WRONG for a state change or layout
  swap. Prefer `Motion.enter`/`exit`/`standard` unless overshoot is the point.
- **NEVER edit `now_playing_screen.dart` or `lyrics_service.dart` with a scripted
  `python`/`Select-String` bulk rewrite.** Both were mangled twice this session:
  one script stripped closing braces it read as separators and left the file
  unparseable; a later one cut a range by two string anchors and silently removed
  ~130 lines of unrelated State fields, because the anchor it searched for had
  moved. Recovery took restoring the region from `git show HEAD:<file>` — which
  works only for tracked files, and `lib/widgets/lyric_swept_line.dart` was new
  and had no git copy. **Use the `edit` tool for these files, one exact block at
  a time**, and re-run `flutter analyze` after every single edit. If a script must
  be used, assert on every anchor and verify the brace delta before writing.
- **A probe that cannot fail is worse than no probe.** The first attempt to
  measure the swap read a constant `1.000` and looked clean: it was walking
  `visitAncestorElements` (parent → root) and keeping the LAST match, i.e. the
  app-root transform, not the local one. When measuring an ancestor property,
  take the FIRST match, and make the test assert something that would actually
  break. That misreading nearly shipped a "fix" that inverted the animation.
- **A timer armed inside a scroll-notification dispatch never fires under
  `flutter test`.** It is scheduled outside the binding's fake-async zone. The
  lyric browse resume was written that way and simply never ended in a test. Count
  idle time on a tick you already own instead.
- **Extract pure geometry before pinning it through a layout.** `topAnchorOffset`
  is two lines of arithmetic that took three widget-test debugging rounds to pin
  and still only caught the sign error once it was free of the fake clock and the
  lazy list. The pure version caught my own wrong derivation twice.
- **`ReorderableListView` owns its ScrollController** and this Flutter version
  will not take one injected. Capture its `ScrollPosition` from inside
  `itemBuilder` if you need to drive it.
- **A `Listener` reports pointer moves without winning the arena.** A
  `GestureDetector` wrapped around `ReorderableDragStartListener` can win the
  gesture and stop the reorder from starting at all.
- **`AnimatedSwitcher` reports the same `AnimationStatus` for both roles** (it
  drives arriving 0→1 and departing 1→0). Do not infer which child you are
  looking at from the animation — carry the role on the child (key compare)
  instead. Getting it backwards is worse than not animating.
- `SharedPreferences.getInstance()` throws `MissingPluginException` in a widget
  test with no mock set up. Any store that may touch it should catch and
  degrade (a layout preference is not worth failing a tap over) — and `toggle`
  needs the same guard as `initialize`, or the first tap throws.
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
