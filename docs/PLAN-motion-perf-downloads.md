# Plan: crash fix, Spotify link import, fast downloads, player dock motion, performance

Status: P0 done (`b1aef42`). P1–P6 below are implemented in this order, one commit each.
Material You screens are out of scope (rebuilt later in M3 Expressive).

Evidence used: code read in this repo; BitChord (`BitChord-main/`, GPLv3 — behaviour and numbers
only, no code); live probes of Spotify's public embed endpoints (2026-10-19); yt-dlp's documented
YouTube chunking behaviour.

## P0 — Local Files crash (done)

`on_audio_query` builds `_data like '%<path>/%'` from the `path:` argument with no escaping
(`AudioQuery.kt:54`). A file name with `'` throws `IllegalArgumentException: Invalid token` in a
Kotlin coroutine — uncatchable from Dart, so the process dies. Every row's artwork lookup queried by
path, so opening Local Files with one such song crashed. It also only ever matched folders, so covers
never loaded. Fix: id index from the scan, artwork by MediaStore id, 4 at a time; a source test fails if
anything queries by path again.

## P1 — Spotify: paste a link, no account, no credentials

Today the whole import screen is hidden when the build has no Spotify credentials (most builds).

Spotify's public embed works anonymously (probed):

- `open.spotify.com/embed/playlist/{id}` → `__NEXT_DATA__` JSON: name, cover, up to 100 tracks
  (`title`, `subtitle` = artists joined by `,\u00a0`, `duration` ms, `isExplicit`, `uri`), and an
  anonymous `session.accessToken`.
- `spclient.wg.spotify.com/playlist/v2/playlist/{id}?from=0&length=N` (Bearer anonymous token,
  `Accept: application/json`) → every track URI (`length` = total).
- `open.spotify.com/embed/track/{id}` → one track's title, artists, duration, cover.
- The official Web API with the anonymous token answers 429 — not usable.

Design:

- `SpotifyPublicPlaylists` (new, `lib/services/spotify_public.dart`): `fetch(id)` → embed page; if
  `total > tracks`, the spclient URI list, then track embeds for the rest (6 at a time). Pure parsers
  (`parseEmbedPlaylist`, `parseEmbedTrack`, `parseSpclientUris`) are unit-tested on recorded shapes.
- Matching gets faster and better for both paths: 6 songs at a time (order kept), and the best of the
  top results is chosen by title/artist similarity and duration (±3 s ideal, reject > 25 s off)
  instead of "first result". Unmatched songs are still kept (resolved on play).
- Import screen: the link field is always there. "Connect Spotify" (your private library) only when
  the build has credentials, otherwise one quiet line explains it. A pasted link uses the public path
  first and the credentialed API only if the public path fails and credentials exist.
- Risk: these are Spotify's own web-embed endpoints, not a contracted API, and can change. A failure
  says "Spotify didn't answer" and nothing is saved.

## P2 — Downloads: fast and robust

Today (`download_manager.dart`): one plain `Dio.download()` GET with **no User-Agent** (the resolver
computes it, the manager drops it), no Range, no resume, writes straight to the final path, deletes
partials on any error, 403 not retried, network loss cancels without re-queue, artwork downloaded
before the audio on the same progress slot, a concurrency race on batches.

YouTube serves full speed to ranged requests ≤ ~10 MB and paces larger/unranged ones to about
realtime (yt-dlp FAQ: "YouTube throttles any request with an http chunk size of > 10MB").

Design (`lib/services/downloads/chunked_downloader.dart`, pure Dart `HttpClient`, testable with a
local `HttpServer`):

- Size from `clen=` in the URL, else a `Range: bytes=0-0` probe (`Content-Range` total).
- Split into ≤ 4 MB ranges, 4 connections per file, each `Range: bytes=a-b` with the signing
  client's User-Agent; written at offset into `<id>.part` (RandomAccessFile).
- Resume: completed ranges recorded in `<id>.part.json`; a retry continues instead of restarting.
- Verify size == total, then atomic rename to the final name.
- Per-range retry ×3 with backoff; a 403/410 invalidates the cached URL and re-resolves once.
- Unknown size or no Range support → single streamed GET (still with UA, still `.part` + rename).
- Manager: a played song whose stream cache is complete is **copied** (not re-downloaded); artwork
  runs in parallel and off the progress bar; 3 files at once (× 4 connections); the slot is taken
  synchronously (race fixed); downloads cancelled by a network drop go back to the front of the
  queue; progress throttled to 200 ms.

## P3 — Player ⇄ mini player: the artwork flies home (BitChord's dock)

Today the open player is one opaque card that translates down; the mini cover is simply uncovered.

BitChord (`NowPlayingScreen.kt` sleeve + `PlayerDock.kt` + `PlayerSheetMotion.kt`): progress `t`
(1 open → 0 at the bar). The whole player fades `alpha = clamp((t − 0.15) / 0.85)`; the artwork is
drawn above the fade on its own path `lerp(mini, open + (0, offset·ride), t)` where
`offset = (1 − t)·travel` and `ride = clamp((mini.top − open.top) / travel)` — it follows the sheet
most of the way and lands tangentially on the cover, never past it. Corner `lerp(8, player, t)`,
shadow fades with `t`. The mini cover hides while `t > 0`. Spring: critically damped, stiffness 195
(~0.45 s). Release: a flick ≥ 400 dp/s decides the direction, else 50 %.

Ours (`lib/widgets/player_dock.dart`, overlay changes):

- `PlayerDock`: the mini cover and the player's hero artwork each register their render box
  (`DockMiniArt`, `DockPlayerArt`) and are hidden by a paint-level gate while the sleeve flies
  (`markNeedsPaint`, never a rebuild, so it is legal mid-build and costs nothing).
- The overlay draws the sleeve (the same cached hero image) above the faded player each tick, from
  last frame's rects. Bottom fade of the full-bleed hero firms up as it lands.
- Falls back to today's plain slide when there is nothing to dock to: reduce motion on, mini pill
  hidden, lyrics/queue open (no hero art), a player subroute, Material You.
- Spring 195 / critically damped; flick-or-50 % rule; the nav-bar-hosted pill follows the finger on an
  upward pull (today only a fling opens it).
- Tests: geometry (pure), fallback cases, cover hidden only while docking, spring end states.

## P4 — Performance (120 Hz, battery)

1. **High refresh rate.** Many Android OEMs keep Flutter at 60 Hz unless asked. Native, no new
   dependency: `MainActivity` picks the highest-refresh display mode at the current resolution.
2. **Baked blur.** The ambient backdrop (σ 48, full screen, behind every screen) and every Explore card
   backdrop (σ 26) re-run a full-screen gaussian blur per frame on Impeller. `BakedBlurImage` blurs a
   small decode once into a `ui.Image` and draws it scaled — same look, one blur per artwork, ever.
3. **Rebuild scope.** `LiquidGlassNavBar` listens to all of MusicProvider (every notify rebuilds the
   glass bar and the pill); `MiniPlayer` is a broad `Consumer`. Both narrowed with `select`.
4. **Explore.** Sources fetched in one parallel wave (was up to 3 sequential round trips); equalizer
   ticker stops while the player covers it; precache uses the keys the cards read (800 px art, 300 px
   backdrop) and includes the current card; palette resolves deduped, via the disk cache at 100 px,
   never from `build`; monotonic session ids (fixes the flaky test); hot-path prints debug-only.

## P5 — Skeletons and motion polish

- `SkeletonBox` / `SkeletonList` (one shared shimmer controller, paint-only), replacing spinners in
  Library sections, Trending, All Artists; reduce-motion → static placeholder.
- `PressableScale` becomes a real spring (it says spring, it was a 140 ms ease).
- `StaggerIn` uses `FadeTransition` (no rebuild-driven `Opacity`).

## Verification per phase

`flutter analyze --no-pub` ≤ 186, full suite green, `flutter build apk --debug --no-pub`. Device
checks (frame times, refresh rate, real downloads, Spotify endpoints from the phone's network) need
the user's device and are listed in the final report.
