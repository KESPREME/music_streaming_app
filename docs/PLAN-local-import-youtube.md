# Local Files, Import, YouTube Music playlists, and two bugs — plan

## 0. Bugs (root causes read from the code)

**Delete playlist "does nothing" when it has songs.** `MusicProvider.deletePlaylist` (used by the
Library long-press menu) removed the playlist, then `await stopTrack()` if that playlist was the
playback context, and only THEN `notifyListeners()`. A playlist with songs is the one you were
playing; while `stopTrack` was in flight (or if it threw) the screen was never told, so the row
stayed. An empty playlist cannot be playing, so it vanished at once. Fix: one delete path for every
screen (`deletePlaylistWithUndo`): notify first, never stop playback (the queue holds its own
copy), Undo.
Second bug on the same path: deleting from a playlist's own screen popped twice - once by the
action, once by the screen noticing its playlist was gone - which also popped the screen *under*
it. Fix: the screen only pops itself while it is the current route.

**Back goes to the wrong place.** The shell's `PopScope` read "can the inner navigator pop?" once
per build, but MainScreen does not rebuild when a page is pushed onto its nested navigator. So on
Library > Your Playlists, back saw a stale "nothing to pop" and jumped to Home (or, on the Home
tab, let the system close the app). It also used `pop()`, which bypasses the inner page's own
`PopScope` (selection mode, reorder mode). Fix: read the nested navigator live inside the handler,
rebuild the shell's `canPop` from a route observer on that navigator, and forward with
`maybePop()` so the page under your finger decides.

## 1. YouTube Music playlists (signed-in)

Source: InnerTube browse `FEmusic_liked_playlists` (the YTM "Library > Playlists" page) through the
existing session-bound `browseJson`. A pure parser walks `musicTwoRowItemRenderer` items with a
`VL…` browse id, title, subtitle ("Playlist • 32 songs"), thumbnail; the "New playlist" tile has no
browse id and is skipped.

Where: Your Playlists gets a "YouTube Music" chip and, under All, a separate section headed "From
YouTube Music" with a small YouTube badge on each cover. Library's playlists shelf appends them after
yours with the same badge. Tap opens the existing YouTube playlist page (`ThemedPlaylistDetailScreen`,
which fetches by browse id). Menu: Play, Save a copy to your playlists (imports the tracks so you
can edit them).
States: signed out → one line "Sign in to see your YouTube Music playlists"; loading → skeleton
rows; error → "Couldn't load YouTube Music playlists · Retry". Cached per account in memory; refresh
on pull and when the account changes.

## 2. Import (Spotify only, as asked)

- One screen: hero ("Bring your Spotify playlists"), **Connect Spotify** (OAuth, existing service),
  then your Spotify playlists in-screen with checkboxes (cover, name, song count), "Import N".
- **Paste a link** field (spotify.com/playlist/…) as the second route.
- Progress per playlist while songs are matched on YouTube Music ("Matching 34 of 120"), cancellable
  between songs. Result: "Imported 'Chill' · 118 matched, 2 will be looked up when played".
- Fixes in the service: follow `next` pages (it stopped at 100 songs), report progress, stamp
  created/updated on import. Songs not matched are kept (playback already resolves them by search).
- If this build has no Spotify credentials, the screen says so up front instead of failing after a
  tap.
- YouTube / Amazon tiles removed.

## 3. Local Files

- Collection kit: title "Local Files", "182 songs · 11 hr", Play / Shuffle.
- Views (chips): Songs · Albums · Artists · Folders. Albums/Artists/Folders list groups; tapping one
  drills in (same screen, back returns to the groups).
- Search (title, artist, album, folder), sort sheet with all existing criteria, remembered.
- Rows: on-device artwork (MediaStore, cached), tap plays offline in the visible order, swipe right
  queues, long-press selects (Play, Queue, Add to playlist). No swipe-to-remove: these are the
  listener's files.
- States: loading skeleton, permission denied ("Allow access to your music" + Allow / Open
  settings), empty ("No music on this device" + Rescan, Add a folder), pull to rescan.

## 4. Gates

analyze ≤ 186, full suite green, debug APK. Tests: back resolution with a live navigator, delete
from every path, parser fixture, import progress/pagination with a fake HTTP layer, local grouping
and search, widget tests at 360 dp / text ×1.3. Material You screens untouched.
