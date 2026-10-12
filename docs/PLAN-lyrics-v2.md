# PLAN — Lyrics v2: BitChord parity, done for real

Supersedes `docs/PLAN-lyrics-parity.md`. That plan is marked "done", but the
device showed that several of its "done" items are not done. Read the
**Root-cause ledger** below before touching anything. Every entry in it was
traced in code, and each one names the file and line.

Strategy: **fix forward** from `1e2c470`, the user's decision. Keep the data
layer: the syllable model, the race, the translation service, the provider
classes and the tests. **Replace the line renderer.** Fix the clock, the
plumbing and the broken providers.

Reference repo: `BitChord-main/`. The canonical trees are
`sharedUi/src/jvmSharedMain/kotlin/com/music/bitchord/ui/player/` (UI) and
`shared/src/jvmSharedMain/kotlin/com/music/bitchord/data/lyrics/` (data).
`app/` is an older fork. Only `LyricsSourcesDialog.kt` and `MainViewModel.kt`
are read from there. Abbreviations: **PL** = `PlayerLyrics.kt`,
**NPS** = `NowPlayingScreen.kt`, **LL** = `LyricLine.kt`. PL/NPS line numbers
are approximate (±10); grep for the symbol.

---

## User decisions (binding)

1. **Fix forward.** Do not reset to `b46cc2f`.
2. **Prefer word/syllable timing, and fall back to line timing.**
   "Prioritize syllable lyrics" defaults to **ON**.
   - Line-only lyrics light **the whole line at once**, as BitChord does.
   - Remove the fake per-word timings invented for plain LRC.
3. **PaxSenix Spotify / PaxSenix Musixmatch**: add them, with an **optional**
   API key field.
4. **Font**: the designer's call. See §Typography. In short: **Plus Jakarta
   Sans ExtraBold, bundled**, 32sp / 1.22 / −2% tracking, and one style for
   every line.

## Gates (every phase)

| Gate | Command | Pass |
|---|---|---|
| Analyzer | `flutter analyze --no-pub` | no new finding vs the Phase 0 baseline, 0 errors |
| Tests | `flutter test` | all green; count ≥ baseline (tests are rewritten, never dropped) |
| Build | `flutter build apk --debug` | builds (Phase 8, and any phase touching pubspec/assets) |
| Per edit | `dart analyze <touched files>` | clean |

Commit once per phase, conventional style, matching the history
(`fix(lyrics): …`, `feat(lyrics): …`). Mark a checkbox `[x]` **only** when its
test exists and passes. Do not tick anything to save time.

## Non-negotiables (from CONTEXT.md; re-read it)

1. No `Opacity`/`AnimatedOpacity`/`FadeTransition` above or around a
   **backdrop glass lens** (the deck's liquid-glass pill, glass buttons).
   Reveal those by size, slide or scale. `TransformDisc`
   (`lib/widgets/lyrics_mode_discs.dart`) is **not** glass: it has no
   BackdropFilter, so a fade on it is allowed.
2. No overshooting curve (`easeOutBack`, springs) for a state change or a
   layout swap.
3. `AnimatedSwitcher` reports the same status for both roles. Carry the role
   on the child.
4. The position stream must **not** rebuild the lyric list. Only paint
   listens to the clock (§Phase 2).
5. Never bulk-rewrite `now_playing_screen.dart`, `music_provider.dart` or
   `lyrics_service.dart` by script. Use the edit tool, one block at a time,
   and analyze after each edit.
6. `themed_lyrics_screen.dart` and `material_you_lyrics_screen.dart` are
   **frozen** (invariant 12). Nothing here may change them. The
   Material You layout of the providers sheet must keep working.
7. `LyricsProvider` enum additions must keep the cached-name round-trip safe:
   an unknown name yields null, never `firstWhere(orElse:)`.
8. Widget-test setup: `GoogleFonts.config.allowRuntimeFetching = false` in
   `setUpAll`; seed platform channels inside `tester.runAsync`; haptics
   fire-and-forget.

---

## Root-cause ledger (verified)

| # | User symptom | Root cause | Where |
|---|---|---|---|
| R1 | Glyph overlap on wrapped lines ("ɛme outg  o"); fill lights 2 rows at once | The sweep table stores only the caret **x** (`getOffsetForCaret(...).dx`), so x resets on row 2. There is one full-height clip rect. The lifted word slices and held-letter overlays are `Positioned(top: 0)`, which draws row-2 words over row 1. A word that crosses the wrap gets a negative or narrow `SizedBox` and re-wraps inside itself. The measuring `TextPainter` has **no `textScaler`**, unlike the painted `Text`. | `lib/widgets/lyric_swept_line.dart` ~204-220 (table), ~446/620 (`_LeftWidthClipper`), ~470-500 (`_liftedSlices`), ~540-590 (`_heldWordGrowth`) |
| R2 | Fill snaps word by word, not smoothly | `revealedChars(...).round()` snaps the clip to whole characters | `lyric_swept_line.dart` ~403 |
| R3 | Panel freezes after a provider switch; the strip goes dim or stuck after a pause | `LyricClock._syncTicker` creates a ticker only when `_ticker == null`. After `stop()` the ticker is stopped but non-null, so `start()` never restarts it. Callers that stop it: `_reconcileClock` (lyrics_screen ~299, runs every time `currentLyrics` goes null during a refetch), the stall detector (~513), and the strip clock (now_playing ~340/346). | `lib/services/lyrics/lyric_clock.dart` ~160-165 |
| R4 | Globe/translate appear when the controls HIDE | The lyric panel lives in `_buildMainPlayerPage`, **inside the `Expanded` above the deck** (`now_playing_screen.dart` ~899-1040, Column = `Expanded(page)` + `MeasureSize(deck)`). So its area already ends at the deck. It still gets `bottomInset: deckExtent` (~1184) and places the discs at `bottom: bottomInset + 8` (lyrics_screen ~1204/1215). With the deck shown, the discs sit a deck-height higher, off the top of the panel. With the deck collapsed (extent 0), they sit at the bottom. The inset is double-counted. They also pop in with no animation. | as cited |
| R5 | Lyric→player: lyrics still visible while the artwork expands | `_closeLyrics` calls `_morphController.reverse(); _panelFadeController.reverse();` together, so the panel paints under the expanding artwork. `LyricsScreen` also runs its own entrance `_fadeController` on top of the parent fade. | `now_playing_screen.dart` ~447-448; lyrics_screen `_fadeController` |
| R6 | Lines hard-cut at "Lyrics by …" | The area is bounded but has no fading edge. BitChord masks 28dp top and bottom (`PlayerQueue.kt` `fadingEdges` L125-146). | lyrics_screen list |
| R7 | Blur "doesn't look the same" | We use `sigma = ladder dp` directly. Compose `Modifier.blur(r.dp)` becomes Android RenderEffect radius `r·dpr` px, and Skia converts that to `σ = 0.57735·radius + 0.5` px. In logical px that is `σ ≈ 0.577·r + 0.5/dpr`, so ours is ~1.6× too blurry. | `LyricLineStyle.blurFor` |
| R8 | Dupes during a provider switch or translate | (a) The strip's `AnimatedSwitcher` is keyed on `timeMs`. A provider switch with the same text at a different stamp cross-slides two copies. (b) The sub-line reveal uses `Align(heightFactor)` without a clip plus `Translate(-0.6·fs)`, so the translation slides over the original. (c) `_ensureKeys` regenerates every GlobalKey when the line count changes. | `lyric_strip.dart`, `lyric_swept_line.dart` ~360 |
| R9 | Back gesture closes the player instead of the sheet; no drag-to-dismiss | (a) The sheet is shown with `useRootNavigator: false`. Back is handled by `PlayerAwarePopScope` (`lib/widgets/global_music_overlay.dart` ~558-590), which collapses the player. (b) `_buildLiveLayout` schedules `maybePop` on **every rebuild** once `current == _requested`, and `_requested` is never cleared. The sheet `watch`es MusicProvider, so it pops more than once and takes the player with it. (c) The custom grabber `GestureDetector(onVerticalDragEnd)` wins the drag arena, and the `ListView` absorbs drags. | `lyric_providers_sheet.dart` ~60-88, ~259-264, ~301-305 |
| R10 | Tapping a provider doesn't fetch "alongside"; rows say "not fetched" | `ProviderAttempt.abandon` fires `onAbandoned` for **every** started attempt in `finally`, settled ones included. `music_provider` ~865 then **removes** the state, so after every race all rows revert. A manual pick is also merged into an in-flight automatic lookup by the `cacheKey`-only dedup in `lyrics_service.dart` ~562. | `provider_race.dart` ~259-265 |
| R11 | Settings → lyric providers list won't scroll to the bottom | The sheet uses the nested navigator, so it lays out under the shell's floating nav or mini-player overlay. The list believes it fits, so it has no scroll extent while its last rows are covered. (Likely cause; confirm in Phase 0.) | `lyric_providers_sheet.dart` `show()`; `settings_screen.dart` ~187, ~484-492 |
| R12 | "Many providers don't work" | Live-probed 2026-10-12 (Borderline / Tame Impala 237s; Self Aware / Temper City 180s). **8 of 13 are broken.** See Phase 5 for each provider's cause and fix. | `lib/services/lyrics/*` |
| R13 | LRCLIB shows a fake word sweep; "prioritize syllable" accepts line-only lyrics | `LyricsUtils.parseLrc` invents syllable-weighted `words`/`lyricWords` for every plain LRC line, so `isWordSynced` is true and `_judge` treats KuGou/LRCLIB as word-synced. | `lib/utils/lyrics_utils.dart` ~286-375 |
| R14 | Cache never stores anything on a fresh install | `onCreate` (v2) creates the table **without** `timings`, while every `put` writes `timings`, so the insert fails silently. | `lyrics_cache_db.dart` ~78-90 |
| R15 | Worse lyrics than BitChord for the same track | `prefetchLyrics` runs with no duration or album and caches whatever wins (KuGou `infoList.first`, LRCLIB `results.first`). Playback then hits the memory cache. There is no query cleaning (`(Official Video)`, `- Topic`). Duration can be 0, and `durationMatches(null) == false` rejects everything from the Apple sources. | `lyrics_service.dart` ~1113; `apple_lyrics_common.dart` ~111 |

Dead code confirmed (one reference each = definition only): `AnimatedBlur`
(swept_line ~886-951), `activeWordAt` (word_lift ~126), `isActiveLine`
(lyric_sweep ~148), `LyricClock.clampRevealed/positionMsPrecise/reportedMs`,
and `LyricSweptLine.isActive`. When embedded, `LyricsScreen`'s own
`_discsVisible/_pokeDiscs/_revealDiscsOnTap`, its header, pull handle and
bottom scrubber are dead too.

---

## Typography (design decision)

**Plus Jakarta Sans** stays. It is the app's face (`main.dart:282`), and
switching the lyric screen to another family would break identity on the
most-seen surface. Its ExtraBold has the dense, slightly condensed
display feel of BitChord's screenshots. Jakarta is wider and has a taller
x-height than Roboto/SF, so it reads larger at the same size. 32sp Jakarta
optically matches BitChord's 34sp, and it wraps roughly where BitChord wraps on
a ~440dp-wide phone.

**Bundle it.** Today the face is fetched at runtime. When it arrives, every
line re-lays out mid-sweep: the geometry is invalidated, the text swaps, and
offline there is no face at all. To bundle it, put the static TTFs at
`assets/google_fonts/` with Google Fonts API names:
`PlusJakartaSans-Medium.ttf`, `-SemiBold.ttf`, `-Bold.ttf`, `-ExtraBold.ttf`,
plus `OFL.txt`. Add the folder to `pubspec.yaml` `assets:`. `google_fonts` 6
then resolves the asset automatically: no API change, and the whole app
benefits. Source: the Google Fonts download zip, `static/` folder (OFL-1.1).

| Role | Size / line height | Weight | Tracking | Notes |
|---|---|---|---|---|
| Synced lyric line (every distance) | 32 / 1.22 | w800 | −0.64 (−2%) | **Identical for active and inactive.** Emphasis comes from alpha, blur and scale only. |
| Unsynced (plain) lyrics | 28 / 1.25 | w800 | −0.5 | alpha 0.95, no ladder |
| Translation / romanization sub-line | 19 / 1.3 | w700 | −0.2 | alpha 0.85, tucked up 6dp |
| Background vocal | 22 / 1.3 | w800 | −0.4 | alpha 0.72, no rise or glow (P2) |
| Strip above seek bar | 17 / 1.25 | w600 | −0.2 | maxLines 1, ellipsis; unsung alpha 0.55 |
| "Lyrics by X" caption | 15 / 1.2 | w500 | 0 | white 0.55, underlined at 0.35, **no icon, no chevron** |

Put all of these in one place: `LyricTypography` in
`lib/widgets/lyric_line/lyric_typography.dart`. No other file builds a lyric
`TextStyle`.

---

## Phase 0 — Baseline and fixtures

- [ ] Record `flutter analyze --no-pub` and `flutter test` counts here (Log section).
- [ ] Confirm R11. Find which Navigator `showModalBottomSheet(useRootNavigator:false)`
      resolves to from `settings_screen` and from the player overlay. Find
      what overlays the bottom of the screen in each case. Write the findings
      in the Log.
- [ ] Confirm R9(a). Trace system back while the player is expanded and a
      sheet is open: `main.dart` ~494 `PopScope`, then `PlayerAwarePopScope`.
- [ ] Capture **live fixtures** with `Invoke-WebRequest` into
      `test/fixtures/lyrics/`. Use small, real bodies, trimmed only if they
      exceed 200KB.
  - `lrcred_search_borderline.json` (`https://lrc.red/search.json?q=Borderline Tame Impala`) and `lrcred_AUUM71900956.ttml`
  - `bini_borderline.json` (`https://lyrics-api.binimum.org/?track=Borderline&artist=Tame Impala&duration=237`)
  - `unison_self_aware.json` (`https://unison.boidu.dev/lyrics?song=Self Aware&artist=Temper City&duration=180`)
  - `portato_borderline.json` (`https://lyrics-api.boidu.dev/qq/getLyrics?s=Borderline&a=Tame Impala&d=237`, a QRC payload)
  - `paxsenix_apple_1497230972.json` (`https://lyrics.paxsenix.org/apple-music/lyrics?id=1497230972&ttml=true`)
  - `lyricsplus_borderline.json` (`https://lyricsplus.prjktla.my.id/v2/lyrics/get?title=Borderline&artist=Tame Impala&duration=237`)
  - `ytm_next.json` / `ytm_browse_lyrics.json` (see Phase 5.9)
  - `genius_search.json` and one song page HTML (UA `BitChord`)
  - `musixmatch_richsync_sample.json`, only if `token.get` works from this
    IP. Earlier it returned 403 from nginx. If it does not work, hand-write a
    fixture that follows `Musixmatch.kt` `RichSyncEntry` (`[{ts,te,l:[{c,o}],x}]`).
- [ ] Note in the Log: these fixtures are the contract. Parser tests read
      them; nothing mocks a response shape by hand except where noted.

---

## Phase 1 — One clock that cannot freeze

Port `BitChord-main/sharedUi/.../ui/player/LyricClock.kt` (the engine, all
constants at the bottom of the file) and `rememberLyricClock` (PL ~600-680)
into `lib/services/lyrics/lyric_clock.dart`. Keep the class name. Callers
change (below).

Engine rules (from LyricClock.kt):

- A reading is dated by when it was **sampled**. `just_audio` gives no
  sample stamp, so use the `Stopwatch` time at receipt.
- **Only an announced discontinuity moves the display backwards**: a seek the
  app made, a track change, or an offset change. Call `clock.jump(ms)`.
- **Readings steer; they do not set.**
- Per frame: `advance(dt)`, then `take()` any reading taken at or after the
  anchor.
- `take()`:
  - Tolerance is `250 + |elapsed| · (0.2 if rate settled else 0.75)`.
  - A reading outside tolerance becomes a suspect. A second reading that
    agrees with it re-anchors on the pair. After more than 2 rejections the
    reading is accepted anyway.
- Rate learning:
  - Keep a 16-entry history and measure over the oldest entry within 4000ms
    once the span is ≥ 900ms. Clamp the rate to 0.25–4.
  - Before that, readings ≥ 300ms apart move the rate halfway toward the
    measured value.
  - Seed the rate from `provider.playbackSpeed`.
- `advance()`:
  - `target = anchor + (now − anchorAt)·rate`
  - `err = target − (shown + dt·rate)`
  - `|err| ≥ 3000` → snap.
  - `err ≥ 300` → glide, 260ms smoothstep. Glides cover at most 2000ms; a
    larger jump snaps.
  - Otherwise `shown += step + clamp(err·dt/(dt+600), −0.5·step, +0.25·step)`.
  - The display never stops and never goes backwards.
- Paused or buffering: `hold(pos)`. The display is set directly, so a seek
  while paused still moves the words.

Driving it:

- [ ] **Exactly one clock**, owned by `_NowPlayingScreenState`, created with
      `vsync: this`. It is passed to `LyricsScreen(clock:)` and
      `LyricStrip(clock:)`. Delete the panel's private clock and the strip's
      second clock (now_playing ~260).
- [ ] Inputs:
  - `positionStream` calls `clock.report(ms)`.
  - `playerStateStream`: `playing && processingState == ready` means run;
    anything else means `hold(position)`.
  - App lifecycle: paused or hidden means stop the ticker; resumed means run.
  - Seeks made by the app (`seekTo`, line tap, scrub end) call
    `clock.jump(ms)`. Expose `MusicProvider.seekEvents` if needed, or call it
    at the call sites in the player.
- [ ] The ticker runs **only while** (playing) AND (panel visible OR strip
      visible) AND (app resumed). Ticker handling:
      `_ticker ??= vsync.createTicker(_onTick); if (!_ticker!.isActive) _ticker!.start();`
      and `_ticker?.stop()` otherwise. This is the R3 fix. Pin it with a test.
- [ ] Delete the 250ms stall detector that stops the clock (lyrics_screen
      ~490-520). Holding is now driven by player state, not by a guess.
      **Keep** a 250ms `Timer` only for the browse-idle budget (Phase 3),
      **or** move that budget onto the clock's ticker. Pick one and record it.
- [ ] `notifyListeners` only when the whole-millisecond position changes.
      Expose `ValueListenable<int>`-style access, plus `positionMs` for paint.
- [ ] Delete `clampRevealed`, `positionMsPrecise` and `reportedMs` if they
      are still unused afterwards.

Tests (`test/lyric_clock_test.dart`, rewritten; port cases from
`BitChord-main/sharedUi/src/jvmTest/kotlin/com/music/bitchord/LyricClockTest.kt`):

- [ ] start → stop → start → ticks advance (**the R3 regression**)
- [ ] the display never goes backwards without `jump`; it does with `jump`
- [ ] one outlier reading is ignored; two agreeing readings re-anchor
- [ ] 300–2000ms behind → glides over 260ms; ≥ 3000 → snaps
- [ ] rate learning converges to 1.5 within 2s of 1.5× readings
- [ ] hold while paused applies the reading verbatim

---

## Phase 2 — The line renderer (replaces `LyricSweptLine`)

New directory `lib/widgets/lyric_line/`:

- `lyric_line.dart`: `LyricLine` (a `LeafRenderObjectWidget`) and
  `RenderLyricLine`.
- `lyric_line_geometry.dart`: a pure geometry cache, unit-testable.
- `lyric_typography.dart` (above).

**Why a RenderObject.** Paint is the only thing that changes 60 times a
second. A `RenderLyricLine` holds one `TextPainter`. It lays out once per
(text, style, width, textScaler). It subscribes to the clock in `attach`,
but **only calls `markNeedsPaint()` while `animatesFrom−1 ≤ now ≤ animatesUntil+1`**.
There are no widget rebuilds, no `LayoutBuilder`, no `AnimatedBuilder`, and
no overlay `Text` widgets. This is the whole perf story and invariant 4.

### 2.1 Geometry (computed on layout)

From one `TextPainter` (with `textScaler: MediaQuery.textScalerOf(context)`,
`maxLines` and `ellipsis` as given):

- `computeLineMetrics()` gives each row's `left, top (baseline−ascent), bottom, right (left+width)`.
- `getLineBoundary(TextPosition(offset: o))` gives each row's `[start, end)` character range.
- `getBoxesForSelection(TextSelection(i, i+1))` gives each character's
  left/right and row.
  - Characters with no box (a collapsed space at a wrap, or text past the
    ellipsis) inherit the previous character's right edge, on that row.
- `wordSpans`: walk `text.indexOf(word.text, cursor)` like BitChord's
  `LyricLine.wordSpans`. This is the **one** span finder. Delete
  `_locateWords` and `_indexOfWord`, and make `revealedChars` use these spans.
- `sweepSpans`: syllable ranges where a word has more than one syllable,
  otherwise the word range (LL `sweepSpans`).

### 2.2 Sung position (pure; `lib/services/lyrics/lyric_sweep.dart`)

Verify `revealedChars(entry, ms)` against LL `revealedChars` (~280-310) and
`LyricWord.charsSungAt` (~28-44). It returns a **fractional** character index:

- before a word → its start
- inside a word → start + `charsSungAt` (syllable-aware: a pause rests on a
  syllable boundary; inside a syllable it interpolates linearly)
- between word i and word i+1 → the gap fills linearly over the pause
- an entry with a `timingSource` (a translation) → `source.revealed / source.len · len`

**Never round.** This fixes R2.

### 2.3 Horizontal position of a fractional index on row `l` (PL `horizontalAt` ~1120-1150, `xOn` ~1090)

- `offset ≤ rowStart` → `rowLeft`; `offset ≥ rowEnd` → `rowRight`.
- If the fractional index falls in a `sweepSpan` that lies **entirely on row
  l**, interpolate linearly across that span's pixel width. This gives
  constant speed per syllable, not per glyph.
- Otherwise interpolate between the left and right of character `floor(i)`.

### 2.4 Paint (PL `SweptLyricLine` ~683-850, `sweepTo` ~1170-1238, `riseWith` ~950-1025)

Inputs: `entry`, `clock`, `rowAlpha` (ladder, animated by the parent),
`tailAlpha` (unsung alpha: 0.45 for the panel, 0.55 for the strip),
`feather` (true only on the active line), `rise` (false on the strip and
sub-lines), `glow` (active line, motion allowed),
`reduceMotion = MediaQuery.disableAnimations`.

1. **Not word-synced:** paint the text once in
   `white·rowAlpha·(lit ? 1 : tailAlpha)`. `lit` is animated by the parent
   (row is sung or active), 300ms `easeOut`.
2. **Word-synced:**
   - Before the line: dim only. After `endMs`: lit only. Draw at a fixed time
     so these rows never repaint.
   - **During the line:**
     a. **Lift slices.** Per row, cut the row at word boundaries.
        - Each lifted word is clipped to `[from, top − peak, to, bottom]` and
          translated `−lift·wordRiseDp`. Merge flat runs into one slice.
        - With no lift anywhere, the "slice" list is the whole paragraph, so
          it is a single `paint` call.
        - Lift math is the existing `wordLiftPx`/`wordFall` in
          `lib/services/lyrics/word_lift.dart`. Its constants already equal
          BitChord's: rise over `clamp(dur, 250, 700)`, settle over 700, and
          `liftHeight = 0.25 + 0.75·smooth((held−150)/750)`. Keep it and pin it.
     b. **Dim pass:** the slices in `white·rowAlpha·tailAlpha`.
     c. **Lit pass:** `saveLayer` **only when `feather`**. For each row
        `l` with `rowStart < revealed`:
        - `right = revealed < rowEnd ? horizontalAt(...) : rowRight`
        - `clipRect(rowLeft, rowTop − peak, right, rowBottom)`, then paint the
          slices in `white·rowAlpha`.
        - If `feather` and the row is cut, draw
          `Rect(max(right − 30, rowLeft), rowTop−peak, right, rowBottom)`
          with `LinearGradient(white → transparent)` and `BlendMode.dstIn`.
          `WIPE_FEATHER = 30dp`.
        - `restore`.
     d. **Held-word swell** (only `glow && !reduceMotion`):
        - Eligibility and math come from `lyric_growth.dart`
          (`GrowingWord`, `CharGrowth`); its constants already match LL
          ~370-470.
        - For each sung letter with `scale > 1 || bloom > 0`, clip to that
          letter's box (expanded by 3·wordRiseDp of headroom). Translate by
          `shift·em` and `−rise·wordRiseDp·fall`, scale about the box centre,
          then paint the lit text.
        - **Glow:** a second cached `TextPainter` with
          `foreground: Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0)`
          and `color = white·0.62·bloom`, painted under the grown letter
          inside the same clip. The glow tweens with the active state over
          420ms, owned by the parent row.
   - The row's intrinsic size is the paragraph's size. **Overflow
     painting** (lift/swell headroom) is allowed because the parent
     `ImageFiltered`/list does not clip per row. Report
     `paintBounds = size.inflate(10)` so `RepaintBoundary` layers include it.
3. **Semantics:** `describeSemanticsConfiguration` → `label = text`,
   `textDirection`, `isButton` when tappable. Tap handling stays in a parent
   `GestureDetector`.
4. **Ellipsis (strip):** characters past the ellipsis inherit row 0's right
   edge (2.1), so the wipe ends at the ellipsis and never goes negative.

### 2.5 Sub-line (translation/romanization), as in PL `revealBelow`

- `ClipRect` + `Align(topLeft, heightFactor: open)` +
  `Transform.translate(0, −h·(1−open)·0.6)` + alpha `open²` on the text
  colour. The `ClipRect` fixes R8(b).
- Open: 460ms `lyricEase`. Close: 260ms `Curves.fastOutSlowIn`. Switching
  modes closes the current sub-line first, then opens the new one.
- Rendered by `LyricLine` with an entry whose `timingSource` is the original
  (it sweeps proportionally), `rise:false`, `glow:false`, `feather:false`.
- A sub-line equal to the original (trimmed, case-insensitive) is not drawn.

### 2.6 Delete

`lib/widgets/lyric_swept_line.dart` goes entirely. Move `LyricLineStyle`
(ladders) and `AnimatedLyricRow` into `lib/widgets/lyric_line/`. Also delete
`AnimatedBlur`, `_LeftWidthClipper`, `_liftedSlices`, `_heldWordGrowth`,
`activeWordAt`, `isActiveLine` and `measure_size.dart` (if no other user;
grep first). Update every import.

Tests (`test/lyric_line_geometry_test.dart`, `test/lyric_line_paint_test.dart`;
rewrite `lyric_swept_line_test.dart`):

- [ ] **Wrapped line (the R1 regression).** For a line that wraps to 2 rows
      and a position inside a row-2 word: row 1 is fully lit, row 2 is lit up
      to x within that word's box, and no lit pixels exist on row 1 beyond
      its right edge. Assert this on the recorded clip rects. Expose a
      `@visibleForTesting debugLastClips`.
- [ ] A word crossing the wrap boundary: the x positions are monotonic within
      each row, and there is never a negative width.
- [ ] `textScaler 1.3` gives the same wrap points as a `Text` with the same
      scaler.
- [ ] The fractional reveal is smooth: 60 samples across a 600ms syllable
      give strictly increasing x.
- [ ] The row repaints only inside its window. Count `markNeedsPaint` calls
      over a tick sweep: zero outside the window.
- [ ] Ellipsis: the reveal never exceeds the visible end.
- [ ] Semantics label equals the text.

---

## Phase 3 — The lyric panel (`lib/screens/lyrics_screen.dart`)

- [ ] **Bounds (R4, R6).** Remove `bottomInset` from the embedded path: the
      area already ends at the deck. Bottom content padding becomes
      `viewportHeight · 0.8` (PL ~1796) and top padding 40dp. Wrap the list
      in **one** `ShaderMask(dstIn)` with a vertical gradient: 28dp
      transparent→opaque at the top, opaque→transparent at the bottom.
      Hoist the shader the same way the artwork `_kOpaqueFade` is hoisted.
      Nothing glass sits inside the mask.
- [ ] **One style per line** (`LyricTypography.synced`).
- [ ] **Ladders** (PL ~1855-1880; keep the `LyricLineStyle` values):
  - alpha `[1, .8, .7, .58, .46]` by `min(distance, 4)` from the scroll line
    (the first active row)
  - **blur sigma** = `0.57735·ladderDp + 0.5/dpr` with ladder dp
    `[0, 1, 1, 1.7, 2.4]` (R7)
  - scale: 1.0 active / 0.98 inactive, origin left-centre
  - all on 400ms `Cubic(0.41, 0, 0.12, 0.99)`, continuing from the on-screen
    value (`AnimatedLyricRow`, kept)
  - **Zero blur and alpha 0.8 for every row while browsing.** Blur is also
    zero for the active row, when lyrics are unsynced, and when
    `MediaQuery.disableAnimations` is set.
  - `tailAlpha` per row animates to 1 if the row is above the scroll line
    (already sung), else 0.45. This replaces the hard-coded
    `dimColor 0.45/0.3`.
  - Row alpha is passed **into the painter** (no `DefaultTextStyle` alpha,
    no `Opacity`).
- [ ] **Browse** (PL ~1630-1705). Keep the existing
      `dragDetails != null` start. End only while playing: 600ms after the
      last scroll activity if the focus row is visible (inside 0–80% of the
      viewport), otherwise 5000ms. Delete the duplicated `_activeLineVisible`
      in favour of one `_focusRowVisible()`. The sweep keeps running while
      browsing; only glow and bloom are off.
- [ ] **Auto-scroll** (PL ~1590-1770). Keep the lead and top-anchor logic
      (`scrollLeadMs`, `topAnchorOffset`). Run only when synced and not
      browsing. Duration = the lead span (350–500ms), `lyricEase`.
- [ ] **Scroll stagger** (PL ~2020-2050). During a scroll run of distance
      `Δ` and duration `d`, a row `k` lines below the focus row (k ≤ 3)
      translates by `Δ·(E(t/d) − E((t − 0.06·k·d)/d))`, where E is
      `lyricEase`. Drive it from one `ValueNotifier<_ScrollRun>` and an
      `AnimationController`, with a `Transform.translate` per visible row
      listening to that controller. Rows outside 0..3 are untouched.
- [ ] **Gap rows** (PL ~1880-1960). Instrumental or empty entries render as 3
      dots: 13dp each, 5dp apart, unlit alpha 0.25, filling left to right
      over the gap duration. Row height swells in over 400ms and out over
      350ms (`lyricEase`). Delete `_buildCountdownDots` and the
      `firstVocalIdx` `indexWhere` per row per build (it was O(n²)).
- [ ] **Provider switch (R3/R8c).** When `MusicProvider.currentLyrics`
      changes identity:
  - adopt it, recompute the active index from the clock, and keep the
    scroll offset (no jump to the top)
  - give rows `ValueKey('${entry.timeMs}:${index}')`, not regenerated
    GlobalKeys; measure rows through one `GlobalKey` per **visible** row via
    a small `Map<int, GlobalKey>` pruned on adopt
  - **never show the loading skeleton when lyrics are already on screen**:
    during a manual switch the old lyrics stay until the new ones land
    (Phase 6 guarantees `currentLyrics` is not nulled)
  - swap with a 200ms opacity crossfade on the **list layer only** (it has
    no glass inside)
- [ ] **Loading / empty.** Skeleton bars (26dp high, 15dp apart, 35dp between
      blocks, shimmer 1400ms). On a miss: "No lyrics for this track" at
      alpha 0.6.
- [ ] Delete the inner `_fadeController` entrance (R5) and the dead embedded
      paths listed in the ledger (header, pull handle, bottom scrubber and
      the disc timer when `chromeHidden != null`). Delete
      `_lyricEase`/`_lyricSettle` duplicates in favour of
      `LyricLineStyle.lyricEase/lyricSettle`.
- [ ] **Discs (R4).**
  - `Positioned(left: 24 / right: 24, bottom: 12)` inside the panel, with no
    deck inset.
  - Visible = `panelLanded && controlsShown`, both passed from the player as
    one `ValueListenable<bool>`.
  - Fade 220ms in / 160ms out, plus a 0.92→1 scale. Allowed: the disc is not
    glass (non-negotiable 1). Keep them in the tree once the panel has landed
    so the fade is visible, with `IgnorePointer` when hidden.
- [ ] **Line tap → seek.** Seek to `entry.timeMs` and call `clock.jump`. The
      row press scale is 0.96 over 120ms.

Tests:

- [ ] `lyrics_panel_bounds_test.dart`, rewritten: no deck inset is added to
      an embedded panel; the bottom padding is 0.8 × viewport; the discs sit
      12dp from the panel bottom.
- [ ] `lyric_scroll_browse_test.dart` stays green; adapt it to the new keys.
- [ ] A provider switch keeps the scroll offset, never shows the skeleton,
      and leaves the clock ticking (drive 500ms; position advanced).
- [ ] The blur sigma formula at dpr 2.75 gives `[0, .76, .76, 1.16, 1.57]` (±0.01).
- [ ] Gap row: the dots fill monotonically over the gap.

---

## Phase 4 — Player integration (`lib/now_playing_screen.dart`)

- [ ] **Close order (R5).** BitChord NPS: lyricsOpen=false hides the panel
      immediately, then the sleeve expands over 420ms.
  - `_closeLyrics`: set `_panelFadeController.value = 0` (no reverse), then
    `_morphController.reverse()`.
  - Open stays two-stage: collapse 420ms `Curves.fastOutSlowIn` (now
    `easeOutCubic`; change to match NPS L1127-1131), then a 200ms panel
    fade.
  - Add a test to `lyric_morph_test.dart`: on close, the panel is absent
    from the very first frame.
- [ ] **Keep the panel mounted after first open.** BitChord pre-composes it
      (NPS ~866-876). When it is closed, wrap it in
      `Visibility(visible:false, maintainState:true)` inside
      `TickerMode(enabled:false)`. Re-opening then costs no first-frame
      build. Assert in a test that re-opening does not create a new
      `LyricsScreen` State.
- [ ] **Deck show/hide.** Replace `AnimatedSize` + `AnimatedOpacity`
      (~1776-1787; `AnimatedOpacity` over the glass pill breaks invariant 1)
      with one `AnimationController` (420ms, `Curves.fastOutSlowIn`) driving
      `SizeTransition(axisAlignment: -1)`. The lyric area grows with it
      because it is the `Expanded` above. When returning to the main view
      with the deck hidden, BitChord snaps to full height and fades in over
      700ms. Do that with a slide-up of 24dp instead of an alpha, to respect
      invariant 1.
- [ ] **Controls in lyric mode** (NPS L1119-1123, PL
      `rememberPlayerControlsOnScroll` ~1505-1540, `LyricsControlsGesture.kt`):
  - idle: 5s → hide; re-keyed on every poke; suspended during a scrub or a
    volume drag (exists)
  - **scroll direction, user drags only:** accumulate travel, resetting it on
    a direction flip. Finger moving up 20dp hides; down 20dp reveals.
    Reconcile with the existing `_lyricsCollapse` handler rather than adding
    a second one.
  - **a tap in the bottom half reveals** the controls when hidden. Consume
    only if the release is within `touchSlop·2.5`. There is no tap-to-hide.
  - one `ValueNotifier<bool> _controlsShown` feeds the deck **and** the discs
    (R4).
- [ ] **Status caption** (`_buildLyricSourceRow`, replacing the "Lyrics by"
      row; PL `LyricsStatusWithChange` L461). Priority order:
      Translating… / Romanizing… / Translated to {lang} / Romanized /
      Lyrics by {source} / No lyrics found / {loading}. Use
      `LyricTypography.caption`, underlined, **no icon and no chevron**. It
      opens the provider sheet.
- [ ] **Strip above the seek bar** (`lib/widgets/lyric_strip.dart`; PL
      `CurrentLyricStrip` L509, `CurrentLyricLine` ~2495-2635).
  - Uses the shared clock and `LyricLine` with `rise:false, glow:false,
    feather:false, tailAlpha:0.55, maxLines:1, ellipsis`.
  - Line-synced lines: plain white. Unsynced lyrics: note icon + "Open
    lyrics" + chevron (the one place a chevron stays). Intro: one random
    intro phrase per track. Gap: "Instrumental" at 0.5. Loading: a loading
    phrase at 0.55. Unavailable: 0.55 for 5s, then fade over 900ms (use
    `AnimatedOpacity`, delete the 16ms `Timer.periodic`).
  - Transition: 340ms `fastOutSlowIn`. In: fade + slide from +35% height.
    Out: fade + slide to −35%. Wrap it in `ClipRect` so nothing leaves the
    row. **Key = `'$index|${entry.text}'`**, so a provider switch with the
    same text does not re-animate (R8a).
  - Remove the nested `AnimatedBuilder(clock)`: the strip rebuilds only when
    the index changes.
  - Background vocals are omitted from the strip.

Tests: rewrite `lyric_strip_test.dart` and `lyric_morph_test.dart` to these
contracts. Add a `controls_visibility_test.dart` covering idle, scroll
direction, the bottom-half tap, and discs ≡ deck.

---

## Phase 5 — Providers and the race

### 5.0 Shared plumbing

- [ ] New `lib/services/lyrics/lyrics_http.dart`:
  - one `http.Client` with a **6s** per-request timeout (3s connect, via an
    `IOClient(HttpClient()..connectionTimeout=3s)`)
  - `getText(url, headers)` returns null on non-2xx, timeout or exception
  - `getAuthorized(url, token)` adds `Origin: https://music.apple.com` and
    `Referer: https://music.apple.com/` (BitChord `LyricsHttp.kt` L73-84)
  - default `User-Agent: BitChord/1.7.1 (https://github.com/bitchord)`.
    Several hosts whitelist it in practice (Genius). Override per provider
    where BitChord does.
- [ ] New `lib/services/lyrics/lyrics_query.dart`: port `forLyricsSearch()`
      and `artistForLyricsSearch()` verbatim from `LyricsQuery.kt` L26-59.
      Apply them **once** in the service before any provider is asked.
- [ ] New `lib/services/lyrics/provider_lyrics.dart`: port
      `ProviderLyrics.parse` (`ProviderLyrics.kt`).
  - Unwrap the JSON keys `CONTENT_KEYS` (L68) and reject envelopes with
    `isError`/`ok:false`/`error`.
  - Un-escape `&lt;tt`.
  - Dispatch: TTML → existing TTML parser; QRC/YRC → **new `KaraokeLrc`
    parser** (L76-150; `[start,dur]text(start,dur)` both prefix and suffix,
    and `LyricContent="…"` extraction); enhanced LRC; LRC; plain.
  - Reject plain text matching `lyrics not found|unavailable|error`.
- [ ] `apple_lyrics_common.dart` `durationMatches(hit, wanted)`: **true when
      `wanted` is null or 0** (R15). Distance 0 when unknown, as in
      `LrcRed.best`.
- [ ] **Don't look up before the duration is known** (BitChord
      `MainViewModel.loadLyrics`). `fetchLyrics` waits for `duration > 0`,
      re-triggered by the duration stream, unless the track is local with
      embedded lyrics.
- [ ] Pass `album` from the track to every provider **except BetterLyrics**.
      Live probe: `al=The Slow Rush` downgraded Borderline from Word to Line
      timing. Re-probe once in Phase 0 and record the result in the Log.
- [ ] **ISRC identify step** (`LyricsRepository.kt` `identify` L248-263).
  - Before the race, if Bini is enabled: `BiniLyrics.identify` under a 2.5s
    timeout. Its ISRC goes to lrc.red, LyricsPlus and Bini.
  - Bini reuses the hit's `lyricsUrl`.
  - Remember `videoId → isrc` in a 100-entry LRU in memory.
  - A shared per-lookup document de-dup (`SharedDocuments`): Bini's
    `lyricsUrl` and lrc.red's document are the same file, fetched once.

### 5.1 lrc.red (`lrc_red_provider.dart`); BROKEN: wrong shape and wrong key

- [ ] Search: `GET https://lrc.red/search.json?q={title artist}` returns
      `{hits:[{isrc,title,artist,album,year,duration}]}`.
- [ ] Document `https://lrc.red/s/{ISRC}.ttml`. Validate the ISRC
      `[A-Z]{2}[A-Z0-9]{3}\d{7}`.
- [ ] Try a known ISRC first.
- [ ] Port `best()` (LrcRed.kt L100-119), with every check a requirement:
  - same core title (brackets and the `" - "` suffix removed, NFD, accents
    and punctuation stripped, lowercased)
  - identical `VERSION_WORDS` sets (L155)
  - a shared artist
  - within 3.0s when both durations are known
  - closest wins
- [ ] Fixture test: Borderline gives AUUM71900956 and word-synced lines.

### 5.2 BiniLyrics (`bini_lyrics_provider.dart`); BROKEN: wrong shape

- [ ] `GET https://lyrics-api.binimum.org/`. With an ISRC, send **only**
      `isrc=`. Otherwise send `track, artist, album?, duration?`.
- [ ] Read `results.first.lyricsUrl` and fetch it through the shared
      document cache. Return the ISRC for 5.0. A 404 is a miss.
- [ ] Move `PaxSenixProvider` out of this file into `paxsenix_provider.dart`.

### 5.3 Unison (`unison_provider.dart`); BROKEN: envelope

- [ ] Read `{success, data:{lyrics, format:"ttml"|"lrc", syncType}}`. Parse
      `data.lyrics` by `format`. Plain lines stamp 0, never invented 3s steps.
- [ ] Send `album`. Fixture test: Self Aware gives 49 word-synced lines.

### 5.4 BetterLyrics + Portato (`better_lyrics_provider.dart`)

- [ ] Main endpoint: works. Timeout 6s. Parse via `ProviderLyrics.parse`
      (not a hard `ttml` key).
- [ ] Portato: URL `/getLyricsPortato` → **`/qq/getLyrics`**. The payload is
      `{"lyrics": QRC XML}`, parsed through `KaraokeLrc`. Fixture test:
      word-synced lines.

### 5.5 LyricsPlus (`lyrics_plus_provider.dart`); works, but slow

- [ ] Ask all mirrors **concurrently** (LyricsPlus.kt L33-76). The first
      non-empty answer wins and the rest are cancelled. Remember `lastGood`
      first next time.
- [ ] Send `isrc` when known.
- [ ] Map `element`/singer agents to alignment if alignment is supported
      (P2).

### 5.6 PaxSenix (`paxsenix_provider.dart`, new); BROKEN: token, headers, id type

- [ ] Apple token:
  - `GET https://music.apple.com/us/new`
  - regex `/assets/index~[^"]+\.js`, then fetch the script
  - JWT regex `eyJ[^"]*\.eyJ[^"]*\.[^"]*` (PaxSenix.kt ~349-350)
  - cache it in memory behind a lock
  - Delete the hard-coded token.
- [ ] Search: `amp-api.music.apple.com/v1/catalog/us/search?term=&types=songs&limit=10&l=en-US`
      with `getAuthorized`. Ids are **strings**. Score per
      `bestCandidate` (L312-327); the minimum is 10.
- [ ] Lyrics: `https://lyrics.paxsenix.org/apple-music/lyrics?id={id}&ttml=true`,
      then `content` → TTML.
- [ ] Keyed routes on `https://api.paxsenix.org`, with
      `Authorization: Bearer {key}`:
  - **Spotify:** `/spotify/search?q=`, then `/lyrics/spotify?id=`
  - **Musixmatch:** `/lyrics/musixmatch?t=&a=&d=`
  - both fall back to `/lyrics/lrcget?q=` scored per `parseLrcGet`
    (L141-164)
  - Parse timed JSON via `parseTimedApple` (L210-250; `part=true` joins
    syllables)
- [ ] With no key, these providers are **shown, disabled and labelled "API key
      required"**, and are never raced.
- [ ] Add enum values `paxsenixSpotify`, `paxsenixMusixmatch`, keeping
      non-negotiable 7. Key normalization strips "Bearer ".
- [ ] The key is stored in **`flutter_secure_storage`**, which is already a
      dependency. It is never logged.

### 5.7 Musixmatch (`musixmatch_provider.dart`); BROKEN: needs a rewrite. Port `Musixmatch.kt` (L26-341) 1:1

- [ ] `BASE=https://apic.musixmatch.com/ws/1.1`, `APP_ID=mobile-app-v1.0`, a
      process `guid` (UUID v4), Chrome 131 UA,
      `Accept-Language: en-US,en;q=0.9`, 8s timeout.
- [ ] Secret:
  - `GET https://www.musixmatch.com/search` with `Cookie: mxm_bab=AB`
  - find the `_app-*.js` chunk, then `from\(\s*["']([^"']+)["']\s*\.split`
  - reverse the capture, base64-decode, UTF-8
  - fallback `f09016176ba43a1cfd1031fbd6b3d26c`
- [ ] Sign: normalize `%20`/space → `+`, then `HMAC-SHA256(secret, url + UTC yyyyMMdd)`
      (package `crypto`, present), base64, then append
      `&signature={urlencoded}&signature_protocol=sha256`.
- [ ] `token.get` → `message.body.user_token`. On 401/402 in the body, clear
      the token and secret and retry once.
- [ ] `track.search` → score (title 80/40, artist 40, length 30/15/5/−20) →
      `track.richsync.get` (`parseRichSyncBody`, `spacingIsExplicit`). If
      that is not word-synced, fall back to `track.subtitle.get`
      (`subtitle_format=mxm`) → LRC.
- [ ] Unit-test the signature against a fixed date and secret, and the
      richsync parser against the fixture. If `token.get` is still 403 from
      this IP, record it in the Log as "unverifiable live" and do not fake
      success.

### 5.8 Genius (`genius_provider.dart`); BROKEN: Cloudflare 403

- [ ] UA `BitChord` (Genius.kt L35-53). Search `"artist title"` via the API
      search JSON, then `bestMatch` scoring.
- [ ] Depth-aware extraction of the `data-lyrics-container` divs, dropping
      `[data-exclude-from-selection]` and header elements (Genius.kt
      L216-260).
- [ ] Keep `[Chorus]` headers as section lines (`isGeniusSectionHeader`).
      Stamp lines 0; no invented 4s timings.
- [ ] **Lazy**: asked only if nothing synced has arrived (LyricsRepository
      L159-176).

### 5.9 YouTube Music (`youtube_music_provider.dart`); BROKEN: wrong endpoint

- [ ] InnerTube `music.youtube.com/youtubei/v1/next`, client WEB_REMIX. Find
      the tab titled "Lyrics" and take its
      `browseEndpoint.{browseId, params}`.
- [ ] `browse` → `musicDescriptionShelfRenderer.description.runs[].text`
      joined. Plain, stamp 0 (YouTubeLyrics.kt L15-33). Reuse
      `innertube_service.dart` context builders.
- [ ] YouTube transcript (`innertube_service.dart` ~2543): parse
      `startOffsetMs` as num **or string**, and read `runs[]` as well as
      `simpleText`.

### 5.10 KuGou / LRCLIB (work; harden)

- [ ] KuGou:
  - keyword `stripParenthetical(title) - stripParenthetical(artist) [album]`
  - keep **all** hashes within 8s, sorted by closeness, and try each
  - if every hash misses, fall back to keyword + duration
  - `stripCredits()` (KuGou.kt L24-134)
  - **never** `infoList.first` outside tolerance
- [ ] LRCLIB:
  - 6s timeout via `lyrics_http`
  - `/api/get` is accepted only if `syncedLyrics` is non-blank
  - otherwise `/api/search`, filtered to synced hits, closest duration
  - never `results.first` blindly
  - `<R>` marks right alignment (P2)

### 5.11 No fake word sync (R13)

- [ ] `LyricsUtils.parseLrc`: delete the syllable-weighted estimator. Real
      enhanced-LRC `<mm:ss.xx>` stamps still produce `lyricWords` via
      `wordsFromRuns`. A plain LRC line has `words == null`,
      `lyricWords == null`, `isWordSynced == false`.
- [ ] Grep for consumers of the estimator (`lyric_timings_codec`, strip,
      tests) and update them.
- [ ] Test: LRCLIB/KuGou fixture lines are all `!isWordSynced`; an
      enhanced-LRC fixture is word-synced.

### 5.12 The race (`lyrics_service.dart`, `provider_race.dart`)

- [ ] **Semantics = `LyricsRepository.lyrics` L159-176.** Start every enabled,
      offered provider at once (Genius lazy). Await **in priority order**:
  - a word-synced answer wins immediately
  - with prioritize **OFF**, the first answer with any `timeMs > 0` wins
  - with prioritize **ON (new default)**, hold the first line-synced answer
    and keep going. If nothing word-synced arrives, return the held one.
  - unsynced (all 0) answers are held as the last fallback
  - Genius is skipped once anything is held
- [ ] **Deviation from BitChord, deliberate:** a **4s grace deadline** after
      the first held line-synced answer, then return it. With 13 sources and
      6s timeouts, the ON default would otherwise cost up to ~6s on a song
      nobody has word-synced. Constant `prioritizeGrace = Duration(seconds: 4)`.
- [ ] Overall deadline 10s.
- [ ] `prioritizeSyllableDefault = true`. Move the preference to a **new key**
      `prioritize_syllable_sync_v2` so existing installs get the new default
      once. The old key was never a user decision; it was a silently shipped
      default. Record this in CONTEXT.md.
- [ ] **R10:** `abandon()` fires `onAbandoned` only when
      `wasStarted && !_completer.isCompleted`, checked **before** completing.
      Settled attempts report their real result.
- [ ] Callbacks become the BitChord trio: `onStarted(p)`,
      `onResult(p, entries?)` (null = genuine miss), and `onCancelled(p)`.
- [ ] **In-flight dedup** keys on `(cacheKey, onlyProvider)`. A manual
      single-provider fetch never joins an automatic lookup (R10).
- [ ] `withBackgroundVocals()` pass on the winner (P2, see 5.13).

### 5.13 Background vocals (P2; do after everything else is green)

- [ ] `LyricsEntry.background` (nullable `LyricsEntry`), filled by the TTML
      `x-bg` spans and by the bracket split (`BackgroundVocals.kt`).
- [ ] Rendered under the lead per §Typography, opening at
      `now ≥ bg.timeMs − 250`.
- [ ] If this grows past a day of work, stop and log it as deferred.

### 5.14 Cache (R14, R15)

- [ ] `onCreate` creates `timings TEXT`. Bump `_dbVersion` to 3. `onUpgrade`
      adds the column if it is missing (check with `PRAGMA table_info`), so
      both fresh-v2 and v1 databases heal.
- [ ] Do not re-run `withInstrumentalGaps` on rows already containing gap
      markers.
- [ ] `prefetchLyrics` passes duration and album, and **caches only a
      word-synced or line-synced result whose duration matched**. It never
      caches unsynced results.
- [ ] Cached rows record the provider. A disk hit marks that provider
      `found` in the states map, so the sheet shows the check.

Tests:

- [ ] One parser test per provider against its Phase 0 fixture.
- [ ] Race order and prioritize ON/OFF, including grace and deadline (fake
      async).
- [ ] `abandon` after settle reports nothing.
- [ ] The manual fetch does not dedupe into an automatic lookup.
- [ ] A fresh database round-trips timings.
- [ ] Prefetch never caches unsynced results.
- [ ] Rewrite `lyrics_provider_race_test.dart` and
      `lyrics_provider_reachability_test.dart`; add the new enum values.

---

## Phase 6 — Provider sheet and settings

### 6.1 Selection model (`music_provider.dart`; port `MainViewModel` ~289-502)

- [ ] Per track:
  - `generation`
  - `Map<LyricsProvider, ProviderState> states`, reset to `notFetched` on a
    track change **only**
  - `Map<LyricsProvider, LyricsResult> results`, every hit retained
  - `selected`
- [ ] Callbacks guard on `generation`. Their effects:
  - started → `fetching`
  - result → `found` (stored) or `notFound`; if selected, apply it
  - cancelled → back to `notFetched` **only if** the state is `fetching`;
    and if `selected == p`, start a dedicated single fetch
- [ ] `selectLyricsProvider(p)`, replacing `useLyricsProvider`:
  - **found** → apply the stored result immediately
  - **fetching** → mark selected; it is applied when it lands
  - **notFetched** → mark selected; start a dedicated single fetch
  - **notFound** → no-op (the row is disabled)
- [ ] **Never set `currentLyrics = null` for a provider switch.** Nulling is
      reserved for a track change. This is the second half of R3 and the R8c
      fix.
- [ ] The manual choice is in memory per track (BitChord does not persist
      it). Delete the old "write the winner back as the provider" behaviour if
      it rewrote the order.

### 6.2 Live sheet (`lyric_providers_sheet.dart`, live mode; BitChord `LyricsProviderSheet.kt` + `PlayerDrawer.kt`)

- [ ] Shown with **`useRootNavigator: true`**, so back pops the sheet and not
      the player (R9a). Verify with the Phase 0 trace. If
      `PlayerAwarePopScope` still intercepts, make it check
      `ModalRoute.of(context)?.isCurrent` / the root navigator's `canPop()`
      first.
- [ ] **Drag to dismiss anywhere** (R9c). Use `DraggableScrollableSheet`
      (`expand:false`, `initialChildSize` = content fit (≤ 0.75),
      `minChildSize: 0`, `snap: true`). Hand its `scrollController` to the
      list, so pulling down at the top of the list drags the sheet. When the
      extent drops below 75% of the initial size (release past 25% of the
      height, `PlayerDrawer` L87), pop **once**. Delete the custom grabber
      `GestureDetector`; keep the grabber purely visual.
- [ ] **Pop exactly once** (R9b). A `_closing` bool, cleared nowhere: the
      route is gone. Dismiss-on-land checks
      `_requested != null && current == _requested && !_closing`, sets
      `_closing = true`, then pops. Use `ref`-style
      `context.select<MusicProvider, (LyricsProvider?, Map)>` instead of
      `watch` on the whole provider.
- [ ] Rows (LyricsProviderSheet.kt L55-190):
  - Title "Choose lyrics provider". Order = the saved order. 6dp spacing.
  - Row background white 0.10 if current, else 0.05; padding 14/12.
  - 40dp leading circle (0.16 / 0.08) showing: spinner 20 (fetching), check
    21 (found; alpha 1 current / 0.75), close 20 at 0.4 (not found), search
    20 at 0.7 (not fetched).
  - Label w600 if current; status line below (Fetching… / Found / Not found
    / Tap to search / API key required).
  - `notFound` rows and keyless PaxSenix rows are disabled.
  - Selection haptic.
- [ ] Enter 260ms `fastOutSlowIn` slide; exit 180ms.

### 6.3 Settings sheet (R11; `LyricsSourcesDialog.kt`)

- [ ] `show()` uses `useRootNavigator: true`. Content is constrained to
      `maxHeight = 0.85 × screen`. The reorderable list is `Flexible` with
      `ClampingScrollPhysics`, and bottom padding is
      `MediaQuery.viewPaddingOf(context).bottom + 12`.
- [ ] The header text reads "Sources are tried in this order. Drag to reorder
      them. The first source with lyrics wins unless syllable lyrics are
      prioritized."
- [ ] Rows:
  - tap toggles; the last enabled source cannot be unchecked (it shows at
    0.5); enabled and ordered are independent
  - "Prioritize syllable lyrics" with subtitle "Keep searching past a
    line-synced match for word-by-word lyrics" (checkmark, default ON)
  - **"PaxSenix API key — optional · not configured / configured"**, which
    opens a password field dialog (Save / Cancel / Clear)
  - "Reset to default", which restores all offered enabled, the default
    order and prioritize ON
- [ ] Remove the custom edge-autoscroll `Ticker` **only if**
      `ReorderableListView`'s own autoscroll reaches the ends on device.
      Otherwise keep it (it was added for a reason, plan v1 6.2). Record what
      you did.
- [ ] Changing enabled sources re-runs the lookup for the current track
      (BitChord keys `loadLyrics` on `(videoId, sources)`).

Tests: rewrite `lyric_providers_and_autoplay_test.dart` and
`lyrics_provider_switch_test.dart`. Add `lyric_provider_selection_test.dart`
covering the four selection branches, cancelled-while-selected refetch, and
"no null on switch". Add a sheet widget test: one pop, and back pops the sheet
only.

---

## Phase 7 — Globe (romanize) and Translate

Reference: `LyricsTranslation.kt` (L67-619), PL `rememberLyricsTranslation`
~2705-2970. Our `lyrics_translation_service.dart` and `lyric_sub_line.dart`
exist; align them.

- [ ] **Globe = romanize.**
  - `POST translate.googleapis.com/translate_a/single` with form
    `client=dict-chrome-ex, sl=auto, tl={target}, dt=rm, q=payload`, reading
    `root[0][*][3]`.
  - If no slot has a non-Latin letter → `AlreadyRomanized`: the disc dims to
    0.42 and stays tappable; the tap shows "These lyrics already use Latin
    characters" (exists, keep).
  - An unchanged response for non-Latin input → `Unavailable`.
  - The cache key excludes the target language.
- [ ] **Translate.**
  - Same endpoint with `dt=t`, reading `root[0][*][0]`; the detected language
    is `root[2]`.
  - Batches of ≤ 3500 characters, joined with `\n\uE000NNNN\uE001\n` markers,
    split on `\uE000[^\uE001]*\uE001`; at most 2 requests in flight.
  - Any batch failing → `Unavailable`.
  - The source language is the payload-weighted majority.
  - `sameLanguage(source, target)` compares base subtags (`iw→he`, `in→id`,
    `ji→yi`) → `SameLanguage`, with the toast "Already in {language}".
- [ ] **inputtools retry (plan v1 5.2a, never done).** Retry when the lyrics
      are predominantly Latin (latin ≥ 4× other), at least a third of the
      text came back unchanged, and the source is not `en`.
  - `POST inputtools.google.com/request` with `text, itc={src}-t-i0-und,
    num=1, cp=0, cs=1, ie=utf-8, oe=utf-8`, reading `root[1][0][1][0]` when
    `root[0]=="SUCCESS"`.
  - Re-translate with `sl={src}`.
  - Keep the retry only if it leaves less text unchanged.
  - Fixture test with a hand-captured Hindi-in-Latin response; capture it
    live in Phase 0 if reachable.
- [ ] State machine per `(trackId, language, lyrics identity)`: Idle →
      Loading → Ready | SameLanguage | Unavailable.
  - When Ready, a tap toggles between the original and the mode.
  - Starting one mode cancels the other's in-flight job.
  - Only one mode is shown at a time.
  - Taps are ignored while Loading.
  - Haptic on a successful toggle.
- [ ] Target language = the `translation_language` setting, else the app
      locale's base language, else `en`.
- [ ] Cache: memory LRU of 12 plus disk
      `getApplicationCacheDirectory()/lyrics_translation_v3/<sha256>.json.gz`,
      capped at 2MB newest-first. The cache stores SameLanguage too.
- [ ] The strip shows the active mode's text (BitChord reads
      `displayedLyrics`).
- [ ] Disc: 34dp circle, white 0.34 when active or loading, else 0.18; 19dp
      icon; tint 1.0 / 0.78 / 0.42; the 16dp spinner replaces the glyph.

Tests: extend `lyrics_translation_test.dart` and
`lyrics_same_language_test.dart` with batching/markers, the inputtools
retry, mutual cancellation and the cache key rules.

---

## Phase 8 — Gates, docs, device checklist

- [ ] Full gates (table at the top). Record the numbers in the Log.
- [ ] Run `node C:\Users\nipun\.kiro\skills\impeccable\scripts\detect.mjs --json`
      over the changed UI files once, and fix the findings in one batch.
- [ ] `CONTEXT.md`: replace the "Lyrics rewrite" section. Cover the renderer
      architecture (RenderObject plus a clock that only drives paint), the
      one-clock rule, the deck/panel geometry (no inset; the panel is above
      the deck), the provider selection model, the prioritize v2 key, the
      font bundling, and the new gotchas.
- [ ] Mark `docs/PLAN-lyrics-parity.md` superseded (one line at the top).
- [ ] Hand the user this **device checklist**:
  1. Borderline (Tame Impala): "Lyrics by lrc.red" or "BiniLyrics", word
     sweep with a soft 30dp edge. Wrapped lines fill row 1 then row 2, with
     no overlapping glyphs.
  2. A held note (any ballad): letters swell and glow; quick syllables stay
     flat.
  3. A line-only song (pick LRCLIB in the sheet): the whole line lights at
     once with no fake sweep.
  4. Strip above the seek bar: one line, a smooth hard-edged wipe that tracks
     after pause and resume.
  5. Open lyrics: the artwork shrinks, THEN the lyrics fade in. Close: the
     lyrics vanish at once, THEN the artwork grows. Nothing doubles.
  6. Lines fade into the 28dp edges at the top and above the deck. No
     hard-cut glyphs.
  7. Scroll by hand: blur clears, all rows read at 0.8, the sweep continues,
     and it resumes about 600ms after you stop (if the sung line is visible).
  8. Wait 5s: the deck slides away and the discs fade out **with it**. Tap
     the bottom half: both return. Scroll up 20dp: both hide.
  9. Open the sheet from "Lyrics by X" (no icon on the caption):
     - rows show live states
     - a found row switches instantly; an unfetched row fetches and switches
       while the panel keeps animating
     - drag down anywhere to close
     - back closes only the sheet
  10. Settings → Lyrics sources: scroll to the last provider; the PaxSenix key
      field is present; prioritize is ON.
  11. Globe on English: dim, and a tap explains why. Globe on a Japanese or
      Hindi song: romanized sub-line under each line, no overlap. Translate:
      a sub-line in the device language.
  12. Offline with a cached song: lyrics show in Jakarta with no font swap.

---

## Phase roll-up

| Phase | Status | Commit |
|---|---|---|
| 0 baseline + fixtures | [ ] | |
| 1 clock | [ ] | |
| 2 renderer | [ ] | |
| 3 panel | [ ] | |
| 4 player integration | [ ] | |
| 5 providers + race | [ ] | |
| 6 sheet + settings | [ ] | |
| 7 globe / translate | [ ] | |
| 8 gates + docs | [ ] | device: user |

Recommended order is as listed. Phases 1→2→3→4 are the visible bugs; do not
start 5 before 4 is green on tests. Phase 5 is independent of 2-4 and may be
done by a parallel worker on a separate branch if desired.

## Log

(Append dated entries: baseline numbers, Phase 0 findings, anything
deliberately not done and why. Never delete entries.)
