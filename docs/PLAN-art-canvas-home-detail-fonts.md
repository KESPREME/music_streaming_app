# Plan: local artwork, Explore canvas, dock from lyrics/queue, Home, artist & album, fonts

Material You screens stay untouched. BitChord (`BitChord-main/`, GPLv3) is a behaviour and numbers
reference only. One commit per phase; gates per phase: analyzer ≤ 186, full suite green, debug APK.

## 1. Local files: artwork everywhere (bug)

Root cause: every "now playing" art site reads `track.albumArtUrl`, which the scanner leaves `''`
for local files (`local_music_service.dart`). Only the Local Files rows ask MediaStore.

- `getTrackArtwork(path, {size})` and `MusicProvider.localArtwork(path, {size})` keyed by size.
- When a local track becomes current (`notifyListeners` hook in the provider, single-flight per id),
  its cover is fetched at 720 px, written once to `<tmp>/local_art/<hash>.jpg`, and the current
  track is replaced by a copy whose `albumArtUrl` is that file path. Every site that already has a
  file branch (Now Playing hero, backdrop wash, queue, palette, ambient) then just works; the mini
  pill gains the file branch it lacked.
- Media session: local tracks wait ≤ 1.5 s for that file when their source is built, and
  `buildSource` gives file paths a `file://` URI (`Uri.parse('/storage/…')` had no scheme).

## 2. Explore: canvas on every card (bug)

Findings (static; the canvas path is disabled in tests):
1. One global FIFO lock in `CanvasResolutionService`; a slow first resolve (Apple → Tidal →
   InnerTube chain, up to ~30 s) holds every later card.
2. Any exception (a timeout while the audio resolves) stores a permanent `null` for the track.
3. The Explore player hard-codes the iOS User-Agent for every URL; googlevideo/Apple URLs that need
   another UA fail silently.
4. A card whose video is ready while the audio is still buffering hides its cover and shows nothing.
5. The previous card stays "current" until `playTrack` lands, so two decoders run.

Fix: latest-first semaphore (2 at a time) instead of the FIFO lock; transient failures retry after
3 min instead of never; `userAgentForStreamUrl`; bad URLs evicted on player error; the cover stays
until the video is actually playing; canvas gated on the settled card only.

## 3. Player → mini player dock from Lyrics and Queue

BitChord docks from the collapsed thumb too (`sleeveRect` → thumb, corner 8, hard edge).
- Lyrics: the hero at `t == 1` *is* the 46 px header; enable `DockPlayerArt` there (corner 8,
  morph-size image) when `_isLyricsOpen` (the morph can be left at 1 after lyrics → queue).
- Queue: wrap the landed header art (`queueHeaderArt`) through a builder hook from Now Playing,
  enabled only once the queue morph has landed (q ≥ 1).
- `softEdge` flag on the attached art: only the full-bleed hero gets the soft bottom edge in flight.

## 4. Home: more categories, cleaner

Why BitChord shows ~14 shelves and we show ~7: it follows FEmusic_home's continuation as you scroll
(our parser records the token and nothing consumes it). It also captures each shelf's strapline
("SIMILAR TO", "From the community").
- `InnerTubeService.browseContinuationJson`, `YouTubeMusicHomeSource.fetchMore(token)` (same
  section-list parser on `continuationContents.sectionListContinuation`), `MusicProvider.loadMoreHome`
  (appends new sections, dedupes by id/title, keeps the next token, stops when a page adds nothing).
  Paged sections live in memory only; the cached snapshot stays the first page.
- Home triggers it when the scroll is within ~1.5 screens of the end, with skeleton rails while it
  loads.
- Straplines: `HomeSection.sourceSubtitle` (field exists, never filled) shown under the title.
- Typography/spacing toward BitChord's calm: section title 20/w700, card title 16/w600, metadata
  14, gutter 16, page title 34/w800.

## 5. Artist & album pages

Album (BitChord release header):
- Framed square sleeve (min(0.76 w, 0.5 h), r12, soft shadow) on the flat palette colour, instead
  of the full-bleed hero.
- Title from the page itself; meta "Album · 2008 · 14 tracks · 59 min" (kind parsed — Album/EP/
  Single; no fake "2024" when the year is unknown; real duration).
- Actions: shuffle circle · white Play pill · download circle (downloads the album; shows progress
  state). Search / more stay in the action bar (tests pin it).
- Track numbers precomputed (was `indexOf` per row, O(n²) and wrong for duplicates).

Artist:
- Action row: shuffle · 70 dp Play circle · share circle (subscribe needs an authenticated write
  path this app does not have yet; not faked).
- Latest release card (the newest item of the first Albums/Singles shelf).
- Top songs capped at 20; "Show all" grid for shelves with more than 5 items.
- About + listener stats move to the end of the page (BitChord order).

## 6. Fonts and weight (Settings)

- `AppFont.style(...)` with the exact `GoogleFonts` signature; codemod of the glass/common files
  (`GoogleFonts.plusJakartaSans(` → `AppFont.style(`); Material You files excluded.
- Curated, screen-first families present in google_fonts 6.3.3: Plus Jakarta Sans (default,
  bundled), Inter, Manrope, Figtree, DM Sans, Onest, Hanken Grotesk, Schibsted Grotesk, Instrument
  Sans.
- Text weight: Lighter / Default / Bolder (one weight step).
- Settings → Appearance: "Font" (sheet with live previews, the face downloaded before it is applied,
  failure reverts) and "Text weight". Applying rebuilds every element in place (no state lost).
- Non-default families download once and are cached on the device.
