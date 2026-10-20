# Plan: covers that always load, sheets that know where they were opened, a profile on Search

Asked: (1) the artist cover does not load when you open the artist from Now Playing after playing through Explore, and
sometimes song/album covers too; (2) the album/playlist play button + sheet should also cover PLAYLISTS on Home and in
Library; (3) every sheet should offer what the place it opened from actually needs (Home vs Search vs ...); (4) a
downloaded song's row should offer to DELETE it, not just say "already downloaded"; (5) redesign the old song sheet (flow,
options, UI, motion, morphing); (6) replace the equalizer button next to Search's scope switch with the profile (or
something more useful).

## 1. Findings (code read + a traced investigation; nothing guessed)

### 1a. The covers
- **Artist page, from Now Playing / Explore**: `ArtistPickerSheet._navigateToArtist` pushes
  `ThemedArtistDetailScreen(artistId: 'artist_<name>', searchByName: true)` with NO image. `Track` has no artist browse id
  (only `albumId`), so the page has to find the artist by NAME first. The hero then depends on: a search succeeding (it
  `rethrow`s, the page turns that into "Failed to load"), the browse returning a header photo, and the image host serving
  the rewritten URL. The search avatar is assigned OUTSIDE `setState`, so it can sit unpainted. Every failure ends in the
  same place: `errorWidget: ColoredBox(wash)` - a blank hero, no retry, no fallback. The page already knows a good picture
  - the song's own cover, loaded and cached on Now Playing - and is never given it.
- **Intermittent covers**, three real defects:
  1. `ImageQualityUtils` rewrites every `i.ytimg.com` thumbnail to `/maxresdefault.jpg` and KEEPS the signed `?sqp=...&rs=...`
     query. `maxresdefault` does not exist for many videos, and a signed URL edited after signing is refused. Video-sourced
     rows (Explore uses them) go blank. There is no fallback to the original URL.
  2. `exploreBackdropUrl` has a regex bug: `mqdefault.jpg` becomes `mqmqdefault.jpg`, `sddefault` becomes `sdmqdefault`. Explore's
     blurred backdrop goes blank for those.
  3. Now Playing decodes with BOTH `memCacheWidth` and `memCacheHeight`: a 16:9 thumbnail is squashed to a square before the crop
     (a distortion, not a failure).
- The artist, album and Now Playing covers all share the same shape: upgraded URL -> error -> a flat box.

### 1b. The sheets
- The song sheet (`GlassOptionsSheet`) is ONE flat list of up to 13 rows for every origin. Only five of ~47 call sites pass any
  context flag. So Home offers "Sleep Timer", Search offers "Song Info", a local file offers "Download" (which answers
  "Cannot download local files") and "Go to album" (a YouTube search for a tag), the Queue header offers "Remove from Queue" for the
  song that is playing (a no-op), and Search's ALBUM and PLAYLIST results open the SONG sheet on a pseudo-track.
- Download row: downloaded -> a snackbar "already downloaded"; no way to delete from here, no cancel while it runs.
- Library's playlist long-press offers Rename and Delete - not even Play. Home's own-playlists strip has no long-press at all.

## 2. Research
- **Apple Music** (iOS context menu): header with art and title; then Add to Library, Add to a Playlist..., Play Next, Play Last,
  Share, Go to Album / Artist; destructive ("Remove from Library", "Delete from Library") last, in red. Menus are revealed by
  touch-and-hold and keep the actions that matter to THIS place only (Apple's menu guidance: the most-used first, destructive last).
- **Spotify** (song sheet): cover/title/artist, then Like, Add to playlist, Add to queue, Share, Go to album, Go to artist;
  "Remove from this playlist" only inside an owned playlist; Sleep timer lives on the Now Playing sheet, not on Home.
- **YouTube Music**: Play next, Add to queue, Save to library, Add to playlist, Download (and "Remove download" once downloaded),
  Go to album/artist; a play button in the corner of every collection card.
- Rule they all follow: a row appears only if it can do something useful HERE. Destructive actions are separate and confirmed.

## 3. Design

### 3.1 Covers that always load (one tool, used three times)
`FallbackNetworkImage`: tries the upgraded URL, then the ORIGINAL URL, then a quiet placeholder. Used by the artist hero, the album
cover and Now Playing. `ImageQualityUtils` stops forcing `maxresdefault` on signed URLs and fixes `//` links. The artist page takes a
`fallbackImage` (the song's cover) and uses it only when the page has found nothing better, and assigns the search avatar inside
`setState`. `exploreBackdropUrl` is fixed. Now Playing decodes by width only.

### 3.2 A sheet that knows where it is
`SongSheetOrigin` (home, search, explore, liked, downloads, device, history, playlist, remotePlaylist, album, artist, nowPlaying, queue,
lyrics, generic) and a PURE `planSongSheet(...)` that returns what to show. The matrix:

| Row | Home / Search / Explore | Library, Liked, Playlist | Downloads | Device file | History | Album page | Artist page | Now Playing / Lyrics | Queue |
|---|---|---|---|---|---|---|---|---|---|
| Play next / Add to queue | yes | yes | yes | yes | yes | yes | yes | no (it is playing) | Play next no (playing); queue only if it is upcoming |
| Add to a playlist | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| Download | yes | yes | Remove download | no | yes | yes | yes | yes | yes |
| Share (+ code) | yes | yes | yes | no | yes | yes | yes | yes | yes |
| Go to album | yes | yes | yes | no | yes | NO (you are there) | yes | yes | yes |
| Go to artist | yes | yes | yes | no | yes | yes | NO (you are there) | yes | yes |
| Song Info | NO | yes | yes | yes | yes | yes | yes | yes | yes |
| Sleep Timer | NO | NO | NO | NO | NO | NO | NO | yes | yes |
| Not interested | only where the origin supplies it (Explore) | | | | | | | | |
| Remove from ... | | playlist (its own) | | | history | | | | queue (only if it IS upcoming) |

`generic` (an unknown caller, and the old tests) keeps everything, so nothing regresses where nobody has said where it is.

### 3.3 The redesign (same sheet, one GlassSurface, same strings the tests pin)
1. **Header**: cover, title, artist, and the like star as a jelly circle that morphs (scale + colour) when toggled.
2. **Quick tiles** (up to four glass tiles with the jelly press): Play next, Add to queue, Download (live: arrow -> progress ring
   -> check), Share. A tile that completes an instant action morphs to a check with its past tense ("Added") for a beat, then the
   sheet closes - the answer happens where the finger is, not in a toast behind a closing sheet.
3. **Grouped list** (inset rounded groups, hairlines): Add to a playlist... / Go to album (with the album's name) / Go to artist /
   Mine Music Code, Song Info, Sleep Timer, Not interested. Destructive rows sit last, in their own red group.
4. **Motion**: tiles pop in with a stagger, groups fade up, the Download tile morphs between its states, Like bounces. Reduce
   motion: no stagger, instant morphs.
5. **Downloaded?** The tile reads "Downloaded" with a check; tapping it asks "Remove this download?" (same words as the Downloads
   screen) and deletes on confirm. In the Downloads screen the tile is a red "Remove". The Downloads list reloads when the sheet closes.

### 3.4 Collections (the album/playlist sheet and disc, generalised)
`CollectionPlayDisc` (any title + any loader) replaces the Home-only disc. It now appears on: Home feed albums and playlists (done),
Home "Your playlists", Library "Your playlists" (own + From YouTube Music) and the Library playlists grid. The collection sheet takes
extra rows, so a USER playlist gets Pin, Edit details and Delete (confirmed, with Undo) beside Play, Shuffle, Play next, Add to queue,
Add to a playlist, Download; a remote one gets Save as playlist and Share. Search's album and playlist results open this sheet,
not the song sheet.

### 3.5 Search's top-right
The equalizer circle (it only opened the player, which the mini player already does) becomes the account avatar - the same
`AccountButton` as Home, same behaviour (sign in / quick-switch / swipe between channels).

## 4. Phases (one commit each)
| # | Work | Proof |
|---|---|---|
| H1 | FallbackNetworkImage, ImageQualityUtils, artist fallback image, exploreBackdropUrl, Now Playing decode | unit tests for URL rules; widget test: failing primary URL falls through; artist page shows the fallback |
| H2 | `SongSheetOrigin` + `planSongSheet`, redesigned sheet, download prompt, origins at the call sites | the matrix as a table test; widget tests: Home hides Sleep Timer, Downloaded asks before deleting |
| H3 | `CollectionPlayDisc`, extra rows, user-playlist sheet, Library + Home playlists, Search album/playlist results | widget tests per surface |
| H4 | Search profile | updated `search_glass_pills_test` |
| H5 | analyzer <= 186, full suite, APK, CONTEXT.md | gates |

## 5. Risks
- Cannot feel the motion here (no device). Proven: the planning matrix, the state transitions, the fallback chain, the confirmations.
- The sheet is pinned by ~8 tests (exact strings, one `GlassSurface`, title/artist once, `Muzo Code` hidden duplicate). Kept; the
  album's name is shown under "Go to album", never the artist's.
- Material You stays untouched (own sheets, own artist page).
