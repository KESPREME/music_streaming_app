# 🎵 Mine Music — Music Streaming App

A production-grade, cross-platform **Music Streaming App** built with [Flutter](https://flutter.dev/).

Liquid-glass UI, a forensic-grade Home feed engine with section memory and convergence, a deterministic recommendation pipeline with search-followup tracking, and a unified playback dispatcher — all backed by 139+ tests.

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.0-0175C2?style=for-the-badge&logo=dart)
![Tests](https://img.shields.io/badge/Tests-139%2F139-brightgreen?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

---

## 🚀 Features

### 🎧 Audio Engine
- **Multi-provider stream extraction** (InnerTube WEB_REMIX + PoToken, Piped, Cobalt fallbacks)
- **BotGuard-compatible** playback via WEB_REMIX + PoToken web generator (Aug 2026 gating)
- **Background playback** with lock-screen controls via `just_audio_background`
- **Android equalizer** + loudness enhancer built into the audio pipeline
- **Adaptive bitrate** based on network quality (WiFi/cellular, auto-adjust)
- **Sleep timer**, cast support, speed control (Lofi mode: 0.9× + pitch shift)

### 🏠 Home Feed Engine
- **Structured native feed** from YouTube Music `FEmusic_home` with full shelf semantics
- **Section memory**: temporarily omitted categories survive via per-section TTL retention
- **Best-known high-water mark**: degraded responses never poison a good cache
- **Convergence engine**: fresh + remembered + enriched = stable editorial feed
- **Deterministic enrichment** (chart + new_release) when native is sparse
- **Section-local dedupe**: cross-shelf repeats preserved, in-shelf dupes removed
- **Provenance tracking** (native / chart / new_release / local) through every stage
- **Deep parser**: musicCarouselShelfRenderer, musicShelfRenderer, nested sectionListRenderer, continuation capture, unknown-renderer diagnostics
- **Stale-while-revalidate** with exponential backoff, request coalescing, and quality gates

### 🧠 Recommendation Engine
- **Quick Picks**: personalized from listening history + favorites + search-followup graph + chart prior
- **Search-followup graph**: tracks "searched X → played Y" transitions with recency decay, persisted in sqflite
- **Taste profile**: long-term (SQLite) + short-term (session) models blended
- **Trending**: regional + global chart evidence, explicitly NOT personalized
- **New Releases**: native YTM release shelf + artist-affinity boosting
- **Deterministic ranking** with documented signal weights; same inputs → same output
- **Diversity**: artist cap per section, skip penalty, overexposure penalty
- **Explainable**: every pick carries a `CandidateReason` for debugging

### 🎨 Liquid Glass UI
- **Continuous glass platter** navigation with magic-lens indicator (jelly-physics spring)
- **Search morph**: nav pill expands into live TextField via spring layout engine
- **Liquid glass mini-player** with parallax artwork and press compression
- **Semantic presentation planner**: content type → layout kind → geometry
- **Hero carousel** (4:5 portrait, 88% width, next-card peek, parallax)
- **Editorial rails**: square albums, 16:9 videos, compact trending lists, artist circles
- **Adaptive item counts**: 1-item sections collapse, no invisible spacers
- **Ambient backdrop**: blurred album-art canvas with palette-driven accent bloom
- **Responsive**: all geometry derives from `contentWidth × fraction`, textScaler-safe

### 🔍 Search & Deep Links
- **Phase-driven search state machine** (idle/loading/results/empty/error)
- **Generation-based race protection**: superseded queries discard stale results
- **`minemusic://` deep links**: track, album, playlist, artist, search, now-playing
- **Search-followup tracking**: queries attributed to subsequent plays for Quick Picks

### ⬇️ Downloads & Offline
- **DownloadManager**: 6-way concurrent, queue, CancelTokens, progress throttle
- **Smart cache** for offline mode with local track scanning (MediaStore)
- **Offline-aware Home** with graceful degradation

---

## 🏗️ Architecture

```
InnerTube API (FEmusic_home)
        ↓
YouTubeMusicHomeSource (parser + discovery)
        ↓
HomeFeed (sections, items, provenance)
        ↓
HomeComposer (validation, dedupe, diversity)
        ↓
HomeConvergence (section memory merge)
        ↓
HomeQualityGate (structural sanity)
        ↓
HomeRepository (SWR cache, backoff, coalescing)
        ↓
MusicProvider (state, section memory, quick picks)
        ↓
HomePresentationPlanner (semantic → layout)
        ↓
Home UI (FeedSection widgets)
        ↓
HomePlaybackController (routing)
        ↓
Existing Player/Resolver
```

### Key modules

```
lib/
├── presentation/home/
│   ├── home_presentation.dart    # Semantic classifier + layout planner
│   ├── home_playback.dart        # Unified playback dispatcher
│   └── home_tokens.dart          # Design tokens (spacing, typography, ratios)
├── providers/
│   ├── music_provider.dart       # God-object facade (playback, downloads, palette, home feed)
│   ├── playback/
│   │   ├── playback_state.dart   # Immutable projection + RepeatMode
│   │   └── playback_controller.dart # Stream-driven state projection
│   ├── lofi_controller.dart      # Lofi mode (0.9× + pitch)
│   └── accent_controller.dart    # Palette-driven accent
├── services/
│   ├── home/
│   │   ├── home_models.dart      # HomeFeed/Section/Item, SectionIdentity, memory, TTL policy
│   │   ├── ytm_home_source.dart  # YTM parser + fallback + repository
│   │   ├── home_composer.dart    # Validation, dedupe, diversity, accounting
│   │   ├── home_convergence.dart # Section memory merge engine
│   │   └── home_diagnostics.dart # HOME_LOAD/HOME_DIFF/HOME_MEMORY/HOME_PLAY traces
│   ├── recommendation/
│   │   ├── quick_picks_engine.dart      # Multi-signal ranking engine
│   │   ├── search_followup_graph.dart   # Search→play transition graph
│   │   ├── search_followup_store.dart   # sqflite persistence
│   │   ├── section_engines.dart         # TrendingEngine + NewReleasesEngine
│   │   ├── candidate.dart               # Candidate model with reasons
│   │   ├── recommendation_service.dart  # Existing signal DB (TrackSignal, taste models)
│   │   └── user_taste_model.dart        # Long-term + short-term taste models
│   ├── innertube/
│   │   └── innertube_service.dart       # InnerTube client (search, browse, player, PoToken)
│   ├── downloads/
│   │   └── download_manager.dart        # Extracted download manager
│   ├── deep_link_service.dart           # minemusic:// handler
│   └── palette/
│       └── palette_service.dart         # Palette generation + LRU cache
├── screens/
│   ├── home_screen.dart          # Home UI (hero, lower sections, stagger)
│   └── ...
├── widgets/
│   ├── home_sections.dart        # Shared primitives (RailCard, ForYouRow, PressableScale, etc.)
│   ├── ambient_backdrop.dart     # Blurred album-art canvas
│   ├── liquid_glass_nav_bar.dart # GlassTabBar.searchable wrapper
│   ├── glass_surface.dart        # Legacy facade → design/glass/glass_surface.dart
│   └── ...
└── design/
    ├── glass/
    │   ├── glass_surface.dart    # Classic-engine GlassSurface (tiers)
    │   ├── glass_materials.dart  # Tier materials + GlassTier enum
    │   └── lens_surface.dart     # LiquidLens (easy engine, for shell only)
    └── tokens/
        ├── motion.dart           # Motion durations + curves + springs
        ├── space.dart            # Spacing, radii, elevation
        └── type.dart             # Typography tokens
```

---

## 🧪 Testing

```bash
flutter test
```

**139/139 tests** covering:
- Home parser fixtures (shelf discovery, identity, type resolution, unsupported renderers)
- Composer validation, dedupe, diversity, deterministic ordering
- Feed degradation protection (ratchet sequence, quality gates)
- Cache roundtrip + schema invalidation
- Search-followup graph affinity/decay
- Quick Picks engine (favorites, recents, cold start, artist diversity, prefix rejection)
- Playback dispatcher routing matrix
- Presentation classifier + planner
- Player widget flows, search phase machine, deep links

---

## 📊 Diagnostics

Debug builds produce structured traces for every Home load:

```
HOME_LOAD cache=HIT cacheSections=4 cacheItems=42 cacheAgeMin=12
HOME_DIFF added=1 removed=0 retained=3 updated=2
HOME_MEMORY section="Rain Therapy" action=RETAIN ageMin=5
HOME_UI composerSections=4 rendered=6 kinds=moods,trending,moods,newReleases
HOME_PLAY section="New releases" item="…" type=album action=navigateCollection
HOME_PLAY_FAIL section="…" reason="identity→Track failed"
ParseReport: discovered=3 parsed=2 unsupported=1 … | invariants=OK
SEARCH_FOLLOWUP: query="blinding lights" → track="Starboy"
QUICK_PICKS: 6 picks generated from 24 candidates
```

Every removed shelf, rejected item, or playback failure has a logged reason.

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x / Dart 3.x |
| State | `provider` (ChangeNotifier + Selector) |
| Audio | `just_audio`, `just_audio_background`, `audio_session` |
| InnerTube | Custom HTTP client with WEB_REMIX context, PoToken web generator |
| Glass UI | `liquid_glass_widgets` 1.2.1 (GlassTabBar.searchable), custom GlassSurface tiers |
| Images | `cached_network_image` with per-size `memCacheWidth` |
| Persistence | `sqflite` (recommendation signals, search followup), `shared_preferences` (feed cache, section memory) |
| Fonts | Google Fonts (Outfit, Spline Sans, Plus Jakarta Sans) |

---

## 🚦 Getting Started

1. Clone + `flutter pub get`
2. `flutter run` (debug — full diagnostics active)
3. For release builds, `flutter build apk --release`

**Platform**: Android (primary), iOS compatible.

---

## 📄 License

MIT. See `LICENSE`.

---

## 🙋‍♂️ Author

**Nipun Gupta**
[GitHub](https://github.com/KESPREME)
