# Liked Songs — plan

Scope: the glass `LikedSongsScreen` (`lib/screens/liked_songs_screen.dart`, reached via
`ThemedLikedSongsScreen`). Material You variant is NOT touched (it is being rebuilt in M3
Expressive).

## 1. What the references show

Two variants of one layout, both on a black canvas with a crimson accent:

- Nav row: back arrow + "Library" breadcrumb, overflow (⋮) on the right.
- Hero: a glass tile with a glossy heart; title "Liked Songs", subtitle, song count.
  Variant A puts a large title above the hero; variant B puts title + Play/Shuffle beside it.
- Primary actions: Play (filled pill) and Shuffle (glass pill). Variant B tints Play in the accent.
- "Find in Liked Songs" search pill.
- Sort row: "Recently added ⌄" on the left, filter button (sliders) on the right.
- Rows: square art (rounded), title, artist, hairline separators inset to the text,
  ⋮ per row; the playing row shows an accent equalizer glyph instead of/next to ⋮.
- Mini player and nav bar float over the list (content must clear them).

Chosen direction: variant B's compact hero (title + actions beside the art, saves ~120 dp so
more songs show above the fold), with an Apple-style large title that collapses into the
nav row on scroll. Play is white (primary, highest contrast); the accent is reserved for
"what is playing" (equalizer, row title) so it always means one thing.

## 2. Feature set (what Spotify / Apple Music users expect here)

Researched: Spotify Liked Songs (search within, sort, genre/mood filter chips, swipe right to
queue, bulk edit 2026), Apple Music Favourite Songs (large title, play/shuffle, download all).

Must have (this pass):
1. Live list: likes/unlikes anywhere in the app show up immediately (no snapshot).
2. Play / Shuffle the current *visible* list (sorted + filtered + searched). Play becomes
   Pause/Resume when this collection is what is playing.
3. Search within: title, artist, album; case- and diacritic-insensitive; result count;
   clear; "No songs match "x"" state.
4. Sort: Recently added (default), Title, Artist, Album, Most played (from ListeningStats);
   persisted (`liked_sort_v1`).
5. Filters: "Downloaded" chip, plus artist chips for artists with ≥ 2 liked songs (top 8),
   plus genre chips only when tracks carry `genre`. Single-select, toggle off to clear.
6. Rows: tap plays within the visible list (context `liked_songs`); ⋮ opens
   `ThemedOptionsSheet`; playing row = accent title + animated equalizer (static when paused);
   downloaded badge.
7. Swipe right → add to queue (feedback toast). Swipe left → unlike with **Undo**
   (restores to the same position and timestamp).
8. Long-press → selection mode: "N selected" bar, Select all, actions Play, Add to queue,
   Download, Remove from Liked (one Undo for the batch). Back/system back leaves selection.
9. Overflow ⋮: Download all (skips downloaded), Add all to queue, Select songs, Sort.
10. Hero meta: "128 songs · 7 hr 12 min" (duration only when known for most tracks).
11. Empty state: glass heart, "Songs you like live here", "Tap ♥ on any song to save it.",
    button "Find music" → pops to the shell and requests the Explore tab.
12. Date added recorded from now on (`liked_added_at_v1`: id → epoch ms). Older likes keep
    their order (list order is the recently-added order) and simply have no date.

Not now (stated): YouTube Music like sync (no rating endpoint in the client yet), smart
shuffle / generated genre mixes, drag reorder (liked is chronological by definition).

## 3. Motion

- Large title → nav-row title: driven by scroll offset (no ticker), fade + 0.92 scale.
- Hero art: press scale via `PressableScale`; nothing loops.
- First load: rows stagger in once (first 12 only), 40 ms step, `Curves.easeOutCubic`.
- Unlike / batch remove: row collapses (size + fade, 240 ms) — `SliverAnimatedList` or
  equivalent; Undo re-inserts with the reverse.
- Sort / filter / search change: list cross-fades (200 ms), no per-row animation.
- Equalizer: 3 bars, animates only while the row's track is playing; parks otherwise.
- Selection mode: checkboxes slide in from the art edge (180 ms); bar slides from top.
- All of it collapses to instant under `MediaQuery.disableAnimations`.

## 4. Tokens

Canvas `#000` (AmoledTheme-aware), accent `#FF3B5C` (= `ReplayStyle.rankOne`, one crimson
app-wide), row art 56 dp radius 10, row height 72, separators white 8% inset 84 dp,
pills height 52 radius full, search 48 dp. Type: Plus Jakarta Sans — large title 34/w800,
hero title 26/w800, row title 16/w700, row meta 13.5/w500 white 55%.

## 5. Architecture

- `lib/presentation/liked/liked_songs_query.dart` — PURE: `LikedSort`, `LikedFilter`,
  `LikedQuery`, `applyLikedQuery(tracks, query, {addedAt, playCounts, isDownloaded})`,
  `likedFilterChips(tracks)`, `normalizeForSearch`, `formatCollectionDuration`.
- `MusicProvider`: `likedAddedAt(id)`; `likeSong` stamps time; `unlikeSongs(ids)` returns the
  removed `(index, track, addedAt)` list; `restoreLikedSongs(removed)`; persistence keys above.
- `ListeningStats`: `playCounts()` → id → counted plays (for Most played).
- Screen: `CustomScrollView` of slivers; state = query + selection set; all data read via
  `context.select`.
- Library: Liked tile always opens `ThemedLikedSongsScreen` (empty included).

## 6. Gates

`flutter analyze --no-pub` ≤ 186 issues, full suite green, `flutter build apk --debug`.
Tests: query logic (every sort, filter, search incl. diacritics), provider undo/timestamps
persistence, widget tests (play visible list, search, sort sheet, swipe-unlike + undo,
selection batch, empty state, no overflow at 360 dp and text scale 1.3).
