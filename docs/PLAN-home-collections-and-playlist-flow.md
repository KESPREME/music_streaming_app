# Plan: Home album cards that answer, and "Add to playlist > New playlist" that works

Two reports: (1) the Home "New releases" shelf does nothing on tap, nothing on touch-and-hold - no play, no
options; (2) song options > "Add to a playlist..." > "New playlist" closes the sheet and nothing happens. Plus: find
any other option that silently does nothing.

## 1. Findings (read from the code, then reproduced in tests - no guessing)

### 1a. New releases is dead because three cases are dropped on the floor
"New releases" arrives from the feed as ALBUM cards (`MPREb_...` browse ids, no videoId). The planner puts the shelf
on the square rail (`HomeSemanticType.newReleases -> squareRail`).
- `_SquareRailSection` (the rail) calls `HomePlaybackController.activate(...)` and throws the result away. The
  dispatcher's contract is "I classify, the widget navigates" - for an album it returns `navigateCollection` and the
  rail never navigates. `_VideoShelf` and the grid DO navigate; the rail was the odd one out.
- Touch-and-hold calls `homeItemToTrack(item)`, which is null for an album (no videoId), so nothing opens.
- An artist card in a mixed shelf returns `navigateArtist`, also dropped. A card the dispatcher cannot act on
  (`none`) is silent: a dead tap.
- Long-press is missing entirely on the playlist shelf, the video shelf and (for albums) the album grid.

### 1b. "New playlist" is dead because the flow keeps a context that no longer exists
`GlassOptionsSheet` closes itself, waits 100 ms, then opens the add sheet with ITS OWN context. The add sheet
remembers that context (`outer`) and, after the listener taps "New playlist" a few seconds later, checks
`outer.mounted` - which is false, the options sheet was removed ~300 ms after it closed - and returns without a word.
Reproduced: `test/options_to_playlist_flow_test.dart` fails on both "New playlist opens the editor" and "adding to an
existing playlist confirms it" (the "Added to ..." confirmation was being dropped by the same line).

### 1c. Audit of the other options (looked at every row of the song sheet and the playlist sheet)
| Option | Verdict |
|---|---|
| Play next / Add to queue / Song info / Code / Sleep timer | work (they use their context synchronously, while it is alive) |
| Go to album / artist | work (use the originating context) |
| Add to a playlist... | BROKEN after the second tap (1b) |
| Share (song) | "works" but shares an EMPTY link: it sends `previewUrl`, which is '' for every YouTube track |
| Playlist sheet > Select to Download | works only while the closing animation lasts (same 100 ms trick as 1b) |
| Home: playlist / video / artist cards, album long-press | no touch-and-hold at all |

## 2. Research (what the references do)
- YouTube Music (web release notes): every song / album / playlist card on Home, Explore and Library shows a play
  button in the card's bottom-right corner; tapping the card opens it. Touch-and-hold / the menu offers Play next and
  Add to queue.
- Apple Music: tap opens the album; touch-and-hold gives the context menu (Add to Library, Play Next, Play Last,
  Share, Go to Artist). Apple's menu guidance: the most-used actions first, anything destructive last, and a menu is
  revealed by touch-and-hold (the same gesture is expected everywhere a thing is a thing).
- Spotify: a card tap opens; a long-press sheet shows the cover and title, then Save, Add to queue, Share, Go to artist.
- Common rule: a card is NEVER inert. If it cannot do the thing, it says so.

## 3. Design
1. **One place decides what a Home card does** (`_activateHomeItem`): song/video play; album/playlist open their page;
   artist opens the artist page; anything else answers with a short toast. Every shelf uses it.
2. **Touch-and-hold on any card**: a song opens the song options (unchanged); an album or playlist opens a NEW
   collection sheet - cover, title, "Album . Artist", then Play, Shuffle, Play next, Add to queue, Add to a playlist...,
   Download, Share, Go to artist. The songs load once, when the sheet opens, so by the time a row is tapped they are
   usually there; a row tapped early shows a spinner and then acts. A failed load says so.
3. **A quick-play disc** on album and playlist cards (bottom-right of the artwork, YouTube Music's pattern): a 34 dp
   glass disc with the jelly press; it spins while the songs load, then plays from the first song. No backdrop blur
   (a rail of blurred discs is the GPU cost this app keeps avoiding).
4. **Stable context for multi-step sheets**: `showAddToPlaylistSheet` holds the NAVIGATOR's context (it outlives any
   sheet), not the caller's. The options sheet does the same for "Select to Download". No more `outer.mounted` that can
   only be false.
5. **Share a real link**: songs share `https://music.youtube.com/watch?v=<id>` when the id is a video id.

## 4. Phases (one commit each)
| # | Work | Proof |
|---|---|---|
| F1 | Stable context in add-to-playlist (+ playlist sheet), real song share link | `options_to_playlist_flow_test` goes green; share text unit test |
| F2 | Home: `_activateHomeItem`, collection sheet, play disc, long-press on every shelf | widget tests per shelf: tap navigates, hold opens the sheet, rows act |
| F3 | Audit net: walk every row of the song sheet, assert a visible effect | `options_sheet_rows_test` |
| F4 | Full analyzer, full suite, debug APK, CONTEXT.md | gates |

## 5. Risks
- Cannot feel it here (no device). Proven by tests: the routing, the context lifetime, the sheet's actions.
- The disc sits inside a card that is itself pressable: both press on touch (card 0.97, disc jelly); the inner tap wins.
- Loading an album's songs is a network call; the sheet and the disc both have a loading and a failed state.
- Material You files stay untouched (they have their own options sheet and dialog).

## 6. Outcome
| Phase | Result |
|---|---|
| F1 | `showAddToPlaylistSheet` and the options sheet hold the navigator's context; the repro test (2 failures) is green. Share sends a real link. |
| F2 | New releases (and every album / playlist card): tap opens the page, touch-and-hold opens the collection sheet, a quick-play disc plays it. Artist cards in mixed shelves open the artist; a card that can do nothing answers with a toast. 12 tests on the real Home screen. |
| F3 | The audit net found one more of the same bug: Sleep Timer's "set for N minutes" confirmation was dropped (it used the closed options sheet's context). Fixed and pinned, with Play next, Add to queue, Song Info and the code dialog. |

Found by the tests, not by reading: the play disc's label merged into its card's semantics (`container: true`
fixes it), and a rail with fewer than three cards renders nothing.

Not done on purpose: Material You (own options sheet and dialog, frozen); touch-and-hold on artist portraits and on
the user's own playlists strip (no menu exists for them yet - a follow-up); a "See all" for New releases (no
page exists for it).
