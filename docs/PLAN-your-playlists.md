# Your Playlists — plan (and what it needs from other screens)

Status: IMPLEMENTED (see commits `feat(playlists)` / `feat(history)`), with these deliberate
differences from the plan as first written:

- `origin` is not stored: a playlist is "created" when its id starts with `pl_`, otherwise
  imported - nothing to migrate and nothing that can go stale.
- "Recently played" sort uses a small `playlist_last_played_v1` map written when a playlist is
  started from a Library screen; plays started elsewhere do not count.
- "Suggested" in Add songs is the app's ranked lists (For you, Quick picks, chart), labelled as
  such - it is not generated from the playlist's own songs.
- History holds the last 20 songs (an existing provider limit), grouped by the play log.
- Downloaded does not show storage used (no size is tracked) and removal always asks first.
- Still not done: downloads progress inside the playlist rows, "Save as playlist" from album and
  artist pages, drag reorder of Liked/History (chronological by definition).

## 1. What the references say

Reference 1 (Your Playlists index): back + "Library" breadcrumb, `+` and search circles; large
title "Your Playlists" + "12 playlists"; search pill; chips **All / Downloaded / Created by you**;
sort "Recently updated ⌄" with a **list / grid** toggle; rows = 84 dp cover, name, **pin badge**,
"32 songs · Updated yesterday", a green **Downloaded** line, ⋮.

References 2-4 (Dribbble, cassette set): the playlist *detail* and its two flows —
- detail: centred cover, description, "Made for / owner", "30 songs · 4 hr 31 min", a row of
  download (left), shuffle + big Play (right), an **"Explore this playlist"** colour card that
  leads to recommendations, then the track list with `E` badges and durations;
- **Add to playlist** sheet: "New Playlist" first, existing playlists with radio/check, one
  primary **Create / Done** button;
- **Create / Edit** sheet: Cancel · title · Save, a big cover with **Change image**, the name
  set large, a Description field.

What to take: the index structure from ref 1; the action hierarchy (Play dominant, Shuffle and
Download secondary) and the two sheets from refs 2-4. What not to take: the cassette skin and
orange accent - this app is black glass with one crimson, and the playlist's own cover colour
(already extracted by `ArtworkPaletteResolver`) is the per-playlist tint, as on the detail screen.

## 2. What exists today (read from the code)

- `Playlist` = `id, name, imageUrl, tracks`. No description, created/updated time, pin, origin
  (created vs imported), or download state.
- Provider: `createPlaylist`, `renamePlaylist`, `deletePlaylist`, `addTrackToPlaylist` (prefs).
  There is **no remove-track, no reorder, no batch add, no cover/description edit, no undo**.
- `UserPlaylistScreen` (423 lines): plain list. Library cards open `ThemedPlaylistDetailScreen`
  with `cachedTracks` - a **snapshot**: removing a song inside it is not possible, and an empty
  user playlist has no tracks to pass, so the detail screen tries to fetch it from YouTube by a
  local id.
- Add-to-playlist is two dialogs (`playlist_selection_dialog.dart` glass, Material You copy).

## 3. Your Playlists — feature set

Index (must have):
1. Large title that collapses into the nav row (same component as Liked Songs), count line.
2. `+` → Create sheet (§4). Search circle focuses the search pill.
3. Search by playlist name **and** by songs inside ("which playlist has Borderline?") - the
   match line says "Contains 'Borderline'".
4. Chips: All · Downloaded (every track downloaded) · Created by you · Imported (only shown when
   any exist). Liked Songs is pinned as the first row (it is a playlist to the listener).
5. Sort: Recently updated (default) · Recently played (from the play log) · Name · Most songs ·
   Custom (drag to reorder, persisted). List / grid toggle, persisted.
6. Row: cover (own image, else 2x2 collage, else gradient + initial), name, pin glyph,
   "32 songs · Updated yesterday", downloaded line with progress while downloading, playing
   equalizer when the playlist is the current context, ⋮.
7. Swipe left → delete with Undo; long-press → pin/unpin, play, shuffle, download, rename, delete.
8. Empty state: "Make your first playlist" + Create; and a second action "Import from Spotify or
   YouTube" (the import screen exists).

Detail for a user playlist (must have — new `UserPlaylistDetailScreen`, live, not a snapshot):
9. Header from the reference: cover (tinted canvas from its palette), name, description,
   "N songs · 4 hr 31 min", Download · Shuffle · **Play** (Pause while it is the context).
10. Edit mode: drag reorder, remove with Undo, rename, description, cover (pick from device via
    `file_picker`, or "use a song's cover"), delete playlist.
11. "Add songs": search sheet + "From your Liked Songs" + "Suggested" (recommendation engine,
    seeded by the playlist's tracks) - the reference's "Explore this playlist" card, made useful.
12. Same row behaviours as Liked Songs (shared row widget): tap plays in context, swipe right
    queue, swipe left remove (Undo), multi-select.

## 4. Shared flows that other screens need

| Flow | Used from | Today | Change |
|---|---|---|---|
| **Add to playlist sheet** | song options, Now Playing, Liked/History selection bars, album pages | two dialogs, one song at a time | one glass sheet: New playlist first, search, multi-check, "Added to 3 playlists", shows "Already in" per playlist, accepts many tracks |
| **Create / edit sheet** | `+`, Add-to-playlist "New", Liked "Save as playlist" | rename dialog only | name, description, cover, "Start with these N songs" |
| **Shared track row** | Liked, playlist detail, History, Downloads | each screen its own | extract `_LikedRow` → `CollectionTrackRow` (swipe, select, equalizer, badges) |
| **Selection bar** | same | Liked only | extract with configurable actions (adds "Add to playlist") |

Additions in other screens (small, high value):
- **Liked Songs**: selection bar gets "Add to playlist"; ⋮ gets "Save as playlist" (snapshot of
  the visible list).
- **History** (Recently Played): same live screen pattern as Liked (search, swipe remove,
  "Clear history", select → add to playlist); grouped Today / Yesterday / This week from the
  play log.
- **Downloaded**: live; storage used and "Remove downloads" in selection; filter by playlist.
- **Now Playing** ⋮ and **song options**: "Add to playlist" opens the new sheet; when a song is
  in N of your playlists show "In 2 playlists".
- **Album / artist pages**: "Add all to playlist".
- **Library**: playlist cards show the downloaded badge and the playing equalizer; the shelf
  sort follows "Recently updated".
- **Replay**: "Save top songs as a playlist" (month / year).

## 5. Data model and provider (needed first)

`Playlist` gains (all optional in JSON, so existing saves load unchanged): `description`,
`createdAt`, `updatedAt`, `pinned`, `origin` (`created | imported:spotify | imported:youtube`),
`customOrder` index. Provider gains: `addTracksToPlaylist(id, tracks)` (skips duplicates,
returns how many were added), `removeTracksFromPlaylist(id, ids)` → undo token,
`restorePlaylistTracks`, `reorderPlaylistTrack(id, from, to)`, `updatePlaylist(id, {name,
description, imageUrl})`, `setPlaylistPinned`, `restorePlaylist` (undo delete),
`playlistsContaining(trackId)`. Every mutation stamps `updatedAt`, saves once, notifies once.
Writes debounced (playlists are one prefs blob today; at hundreds of playlists move to a file in
app documents - noted, not needed yet).

## 6. Mini pill in front of sheets — FIXED in this change

Cause (two, both structural): the floating pill is painted in `MaterialApp.builder`, above the
root navigator, so no modal on it could cover the pill; and the nav bar (which hosts the pill on
the shell) is painted over the shell's nested navigator, where `showModalBottomSheet` opens by
default (nearest navigator). On top of that `AppRouteObserver.isAtRoot` counted a *sheet* as
leaving the shell, so a sheet opened on the root navigator from Home (the sign-in sheet) made the
overlay draw its floating pill over it.

Fix: `ModalRouteTracker` (root + shell navigators) reports open `PopupRoute`s; the nav bar and
the floating pill wrap in `StepAsideForModals` (slide down + fade, 220 ms, instant under reduce
motion, untappable while hidden); `isAtRoot` counts only page routes. Per-sheet
`setHideMiniPlayer` calls keep working and are now redundant. Covered by
`test/modal_step_aside_test.dart`. Not yet seen on a device.

## 7. Build order (proposed)

1. Model + provider (§5) with tests.
2. Shared row + selection bar extracted from Liked (no visual change to Liked - its tests guard it).
3. Add-to-playlist sheet + Create/Edit sheet; wire into song options, Now Playing, Liked.
4. Your Playlists index (§3.1-8).
5. User playlist detail (§3.9-12), Library opens it instead of the snapshot.
6. History and Downloaded on the same pattern; Replay "Save as playlist".

Gates per step: analyze ≤ 186, full suite green, `flutter build apk --debug`, widget tests at
360 dp / text ×1.3, reduce-motion paths. Material You screens untouched.
