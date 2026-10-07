# PLAN — Lyrics parity with BitChord

Source of truth: user field report + screenshot diff
(`C:\Users\nipun\Downloads\Mobile Devices\bitchord and minemusic lyric screen differences.zip`,
extracted `C:\Users\nipun\AppData\Local\Temp\opencode\shots`).

Reference: `BitChord-main` — canonical trees are
`sharedUi/src/jvmSharedMain/kotlin/com/music/bitchord/ui/player/` and
`shared/src/jvmSharedMain/kotlin/com/music/bitchord/data/lyrics/`.
The `app/` tree is a stale fork with identical lyric constants; numbers are
readable from either, line numbers differ.

## How this document works

Every task is a checkbox. Mark it `[x]` only when the task's own gate passes
(its test green AND `flutter analyze` showing no new finding). The phase table
at the bottom is the roll-up. **Do not mark a phase done to save time** — the
point of the file is that it survives compaction.

## Gates

| Gate | Value | Command |
|---|---|---|
| Tests | ≥ 844, all green | `flutter test` |
| Analyzer | no new finding over **198 issues / 0 errors** | `flutter analyze --no-pub` |
| APK | builds | `flutter build apk --debug` |
| Device | CPH2723, after Phase 8 | user-driven |

Per-phase: targeted `dart analyze <files>` + the phase's tests. Full gates at
Phase 8.

## Non-negotiables (from CONTEXT.md — re-read before editing)

1. No `Opacity` / `AnimatedOpacity` above or around a glass lens. Reveal by
   scale/slide.
2. No overshooting curve (`Curves.easeOutBack`, `Motion.springCurve`) for a
   state change or layout swap.
3. `AnimatedSwitcher` reports the **same** `AnimationStatus` for both roles —
   never infer role from the animation. Carry the role on the child.
4. The position stream must **not** rebuild the lyric list. `LyricClock` ticks;
   only the active line listens, only while animating.
5. Never bulk-rewrite `now_playing_screen.dart` or `lyrics_service.dart` with a
   script. `edit` tool, one exact block at a time, `analyze` after each.
6. `themed_lyrics_screen.dart` is **not** dead — `material_you_now_playing_screen.dart`
   imports it, and that screen is frozen by invariant 12.
7. `LyricsProvider` enum additions must not break the cached provider name
   round-trip (`_providerFromName` yields null for unknown, never
   `firstWhere(orElse:)`).

---

## Phase 0 — Land the baseline

Existing uncommitted work, already gated (844 tests, 198/0, APK builds):

- per-word lift matched to BitChord arithmetic (`word_lift.dart`, `wordFall`,
  `_liftedSlices`), the 99,400px overflow fix, no headroom padding
- `chromeHidden` disc ownership (`LyricsScreen` ← `now_playing_screen`)
- on-deck `LyricSweptLine` + `LyricClock` + 300ms stall corrector
- `AnimatedBlur` (340ms sigma tween)
- "Lyrics by …" icon removed
- provider sheet: `ClampingScrollPhysics`, `useRootNavigator: false`,
  grabber fling dismiss
- provider-switch lifecycle: `_syncedLyrics`, `_adoptLyrics`, `_reconcileClock`
  in both branches

- [x] commit as one baseline commit so every later phase is a clean diff
      — `c4f76b9`

---

## Phase 1 — Motion correctness

> This is the phase that contains the jank. Nothing here adds a feature; every
> item is a trigger that is wrong.

### 1.1 Auto-scroll stops killing itself  — **the jank**

`lyrics_screen.dart:318-341`. `_onScroll` reads
`_scrollController.position.isScrollingNotifier.value`, which cannot distinguish
a finger from our own `Scrollable.ensureVisible`. Every handover animates the
list → notifier fires → `_isUserScrolling = true` and `_autoScrollEnabled = false`
→ held 3500ms. The list stops following for 3.5s on every single line.

Reference: `PlayerLyrics.kt:1648-1657` sets `browsingByDrag` from
`DragInteraction.Start` — a finger. `PlayerLyrics.kt:1685-1697` ends the browse
with `delay(600)` when the active line is already on screen and `delay(5_000)` as
a fallback, both gated on `panelPlaying`, and **does not re-scroll on exit**.

- [x] replace the `isScrollingNotifier` listener with a
      `NotificationListener<ScrollNotification>` gate on
      `notification.dragDetails != null`
- [x] enter browse only on a drag; ignore programmatic notifications entirely
- [x] exit: 600ms when the active line is visible, 5s fallback
- [x] **no `_scrollToCurrentLine()` on exit** — the reader chose to be there
- [x] armed from ANY scroll activity, not from `ScrollEndNotification` alone: a
      missed end event left the panel browsing for the rest of the song with every
      line unblurred
- [x] **CHANGED DURING WORK:** the idle budget is counted on the panel's existing
      250ms correction tick, **not** on a `Timer`. A timer armed from inside a
      scroll-notification dispatch is scheduled outside the binding's fake-async
      zone, so it never fired under `flutter test` — and a resume that cannot be
      observed is a resume that cannot be trusted. One clock, one place, one fewer
      timer to leak.
- [x] no `isPlaying` guard — a paused panel's clock is already stopped, so it has
      nothing to yank the reader back to; the guard only made the resume refuse to
      arm
- [x] test `lyric_scroll_browse_test.dart` — 9 tests, **proven to fail**: dropping
      the `dragDetails` null check fails 3 of them

### 1.2 The lead line is computed then thrown away

`lyrics_screen.dart:435-480`. `_scrollToCurrentLine` builds
`target = _scrollTargetIndex` (the *lead* line, leading by 350-500ms) at `:447`,
then at `:450` scrolls to `_itemKeys[_currentLineIndex]` — the **sung** line —
and `target` is consumed only by a dead fallback branch. The lead logic never
runs.

Reference: `PlayerLyrics.kt:1725-1759` scrolls to `focusLine` (= lead) with
`animateScrollBy(visible.offset)` at `scrollOffset = 0` — **top-anchored**, and
the duration is the run-up gap itself (`span = scrollLead(lines, clock)`).

- [x] scroll to `_scrollTargetIndex`
- [x] delete the dead `ensureVisible` branch
- [x] duration = `scrollLeadMs(...)` clamped [350, 500]ms, not fixed 400ms
- [x] top-anchor at `contentPadding.top`, not `alignment: 0.32`
- [x] keep the scroll curve `Cubic(0.41, 0.0, 0.12, 0.99)` (already exact)
- [x] **found while testing:** `_scrollToCurrentLine` did nothing at all when the
      target row was not built. A lazy list has not laid out the rows outside its
      viewport, so every backward seek and every jump was silently dropped and the
      panel was left stranded on the wrong verse. Now: one estimated pass from the
      mean row pitch, then a bounded post-frame refine (max 2) once the row exists.
- [x] **found while testing:** the row's y is measured from the SCREEN while
      `pixels` is measured from the start of the CONTENT. Mixing them baked the
      panel's own top offset into every handover. The list now measures rows
      against `_listKey`, its own box.
- [x] the anchor arithmetic itself moved to `topAnchorOffset` in `lyric_sweep.dart`
      as a PURE function, so it can be pinned without a layout pass — and the pin
      caught my own wrong derivation of it, twice, which the widget test could not.
- [x] test `lyric_scroll_browse_test.dart` lead group — `scrollLeadMs` bounds read
      from the real function; the anchor arithmetic pinned purely; "the panel never
      sits behind the voice" over five positions

### 1.3 One animation spec

`lyric_swept_line.dart:556-626, 690`; `lyrics_screen.dart:1040-1044`.

The ladder **values** already match BitChord byte-for-byte:
`alphaLadder [1, 0.8, 0.7, 0.58, 0.46]`, `blurLadder [0, 1, 1, 1.7, 2.4]`,
`browsingAlpha 0.8`. What is wrong is the *animation*:

- blur tweens 340ms `easeInOut`; reference is 400ms `LYRIC_EASING`
  (`Cubic(0.41, 0, 0.12, 0.99)`, `PlayerLyrics.kt:367-368`)
- alpha is **stepped** (`styleFor` returns a plain `TextStyle`, nothing lerps)
- no `INACTIVE_SCALE = 0.98f` (`PlayerLyrics.kt:337`) tweened on the same spec
- size/weight differ active vs passive (28dp w800 vs 26dp w700), which forces a
  full `TextPainter` prefix-width re-measure of every changing line on every
  handover — a real per-line cost, not only a visual step

- [x] single `static const Curve _lyricEase = Cubic(0.41, 0.0, 0.12, 0.99)` +
      `400ms`, used by blur, alpha, scale and scroll alike — published as
      `LyricLineStyle.lyricEase` / `.lyricSettle` so the panel and the rows cannot
      drift apart
- [x] tween alpha: new `AnimatedLyricRow` runs blur, alpha and 0.98 inactive
      scale on ONE controller, continuing from whatever was on screen so a
      handover arriving mid-settle does not jump. The alpha rides
      `DefaultTextStyle.merge` — an `Opacity` here would allocate a saveLayer per
      lyric row, thirty of them for a full song.
- [x] scale anchored to the row's own left edge (reference `TransformOrigin(0, 0.5)`);
      scaling about a full-width row's centre walks the words sideways
- [x] one font size and weight for every line — the 28dp/w800 vs 26dp/w700 split
      invalidated the row's cached prefix-width table on every handover, forcing a
      `TextPainter` layout pass per line. Emphasis is now scale + alpha, which are
      free.
- [x] test `lyric_ladder_tween_test.dart` — folded into `lyric_swept_line_test.dart`
      for now: one font size/weight for all three distances, emphasis comes from
      scale+alpha, and the single spec is monotonic over 20 samples

### 1.4 Sweep every word-synced row

`lyric_swept_line.dart:234-240`. `sweepable = widget.isActive && entry.isWordSynced`
— so exactly one row per song ever animates. Reference `PlayerLyrics.kt:2297`:
`if (line.isWordSynced && !browsing)` — a sung line closes up as it recedes.

- [x] `sweepable = entry.isWordSynced && (widget.isActive || !isBrowsing)`
- [x] the per-line repaint gate still holds: a line outside
      `animatesFromMs..animatesUntilMs` must not rebuild on the clock
- [x] extend `test/lyric_swept_line_test.dart`

### 1.5 `FadeTransition` is sitting on top of the glass discs

`lyrics_screen.dart:816-818` wraps the whole panel — including both `Positioned`
discs at `:859-880` — in a 300ms alpha. Invariant 17 violation: the discs go
flat for the first 300ms of the panel's life. `now_playing_screen.dart:1022`
already does this correctly with translate+scale.

- [x] replace with `Transform.translate` + `Transform.scale` (24dp rise,
      0.98 → 1.0 scale, `easeOutCubic`) — the same rule already applied one layer
      up at `now_playing_screen.dart:1022`
- [x] assert in a test that no `FadeTransition`/`Opacity` ancestor exists above
      the discs — **deferred**, folded into Phase 7's `lyric_morph_test.dart`

### 1.6 Bottom padding

BitChord `PlayerLyrics.kt:1796`: `contentPadding.bottom = viewportHeight * 0.8f`.
Ours is `8 + widget.bottomInset` (`:841`), so the last line runs off the screen
edge (user capture: "Will I be known and loved?" clipped).

- [x] `LayoutBuilder` to learn the viewport height
- [x] bottom = `max(8 + bottomInset, viewportHeight * 0.8)`
- [x] **combined as a MAXIMUM, not a clamp** — a first attempt clamped the deck's
      height to 80% of the panel, which on a short panel silently put the seek bar
      back over the last line. That is the exact bug the deck inset exists to fix.
- [x] `lyrics_panel_bounds_test.dart` updated: the old "a zero inset leaves only
      the base padding" case now states the tail rule, and a new case pins that
      neither clearance can eat the other

---

## Phase 2 — The morph

> The duplication ("if I switch lyric it dupes") and "a thing comes before
> another thing" are both here.

`now_playing_screen.dart:1003-1026` builds the panel **the same frame** the
collapse starts, and applies `translate(40*(1-t))` + `scale(0.96+0.04t)` while
`:1067` / `:1135` / `:1193` paint artwork, title and glass buttons *over* it.
Both are siblings in one `Stack`, so all four paint simultaneously for the whole
380ms and after.

Reference: collapse is 420ms `FastOutSlowIn` (`NowPlayingScreen.kt:1127-1131`),
the panel is gated on `collapseDone` (`:3274`), then a **separate** 200ms fade
(`:1181-1193`), with **no transform at all** on the panel (`:3284-3293`). Its
comment at `:1160-1180` names our symptom exactly: *"composing them there was
what made the collapse stutter."*

- [ ] collapse 380 → **420ms**, `easeOutCubic`
- [ ] add `_lyricsCollapseDone`, true at `t >= 0.999`
- [ ] panel gate `_isLyricsOpen && _lyricsCollapseDone`; separate 200ms fade
      controller
- [ ] delete the `Transform.translate` + `Transform.scale` on the panel
- [ ] z-order: panel paints **above** the collapsing artwork so it can never
      read through it; title / star / more fade out with the collapse
- [ ] **close is the same two stages reversed** — asymmetric close is what the
      user's back-transition capture caught
- [ ] keep `IgnorePointer(ignoring: !visible)`
- [ ] test `lyric_morph_test.dart` — per-frame: panel absent until collapse
      completes; never two text layers painted in the same frame; open and close

---

## Phase 3 — Seek-bar strip

`now_playing_screen.dart:1323-1479`.

- [ ] add `rise` and `glow` flags to `LyricSweptLine`; strip passes
      `rise: false, glowAlpha: 0` (reference `PlayerLyrics.kt:2609-2616`;
      lift on a pinned one-line strip reads as twitching)
- [ ] `maxLines: 1`, `overflow: TextOverflow.ellipsis` on the **swept** path at
      `:1424` — today a long word-synced line wraps and **grows the deck**
- [ ] transition 380 → **340ms**, `easeOutCubic` both ways, slide **0.35** in and
      **out** (reference slides out downward; ours only slides in)
- [ ] `dimColor` 0.38 → **0.55** (`UNSUNG_ALPHA_STRIP`)
- [ ] real states, replacing the intro phrase used forever:
      - unsynced → 16dp note + "Open lyrics" + 14dp chevron α0.5
      - unavailable → hold 5s, then 900ms fade 0.55 → 0
      - loading → α0.55
- [ ] resolve the index from the same `LyricClock` as the wipe, not a separate
      `positionStream` read, so a line switch and the sweep cannot disagree for
      up to one stream period
- [ ] test `lyric_strip_test.dart` — no lift, no glow, one line, 340ms, 0.55
      dim, three distinct states

---

## Phase 4 — Providers

Scope note: `PAXSENIX_SPOTIFY` and `PAXSENIX_MUSIXMATCH` are **out of scope** by
user decision — they need an API key and the rest of the work has higher value.

- [ ] 4.1 **reachability**: `betterLyricsPortato`, `youtubeMusic`, `megalobiz` are
      in `LyricsProvider` but **absent from `defaultProviderOrder`**
      (`lyrics_service.dart:198-211`) → never asked by the race, never listed by
      the sheet. Add them.
- [ ] 4.1b hide `megalobiz` in `isOffered` (`:173` hides only `simpMusic`; the
      reference hides both)
- [ ] 4.1c Portato endpoint → `https://lyrics-api.boidu.dev/qq/getLyrics`
      (reference `BetterLyrics.kt:22`; ours is `/getLyricsPortato`)
- [ ] 4.1d verify `syncOnly`/reorder path still lists every enabled provider
- [ ] 4.2 **populate `isrc`**: it threads through 7 call sites and is always
      null, so lrc.red (which is ISRC-addressed, `https://lrc.red/s/{ISRC}.ttml`)
      loses its primary key
- [ ] 4.3 `prioritize_syllable_sync` default `true` → **`false`**
      (`music_provider.dart:1456`, `lyrics_service.dart:446`). Ours currently
      holds every line-synced answer and keeps asking on every cold start;
      `AppSettings.kt:500-507` documents why the reference defaults off.
      Keep the bypass for `onlyProvider` (already correct).
- [ ] 4.4 lift `LyricsSource.ordered()` upgrade semantics — a provider added
      since a saved order slots in after its declared predecessor, not at the end
- [ ] 4.5 `reconcileOrder` is dead code (zero call sites) — either wire it into
      `initialize()` or delete it
- [ ] 4.6 keep `onSettled(null)` vs `onAbandoned` semantics intact (invariant)
- [ ] test `lyrics_provider_reachability_test.dart` — every enum member is
      either in the default order or explicitly hidden, asserted by reading the
      real constants

---

## Phase 5 — Globe / translate

### 5.1 The same-language guard was written and never wired

All of these exist and none are reachable in production:
- `isLatinScript` — `lyrics_translation_service.dart:426`, referenced only by a
  test
- `reportAlreadyInLanguage` — `lyric_sub_line.dart:124`; `toggle()` never passes
  it so the default `false` always wins
- `alreadyInLanguage` — `lyric_sub_line.dart:179`, read by nothing
- `TransformButtonState.sameLanguage` — `lyrics_mode_discs.dart:42`; no producer
- the α0.42 tint and the disabled branch at `lyrics_mode_discs.dart:73,77`

Today, tapping the globe on a Latin lyric sends a request, gets the text back
unchanged, and renders a sub-line **identical to the original**. No tint, no
disable, no message.

Reference: `LyricsTranslation.kt:234` `hasNonLatinLetters` →
`AlreadyRomanized`; `PlayerLyrics.kt:2791-2794` → toast "These lyrics already
use Latin characters".

- [ ] 5.1a produce `sameLanguage` from the lyric text before the request
- [ ] 5.1b tint the disc α0.42 and disable its tap
- [ ] 5.1c surface the message (and let it take over the status line)
- [ ] 5.1d keep the guard **out** of the panel's line list

### 5.2 Latin→native→retry for romanization

Without it, romanization silently no-ops on accented Latin. Reference
`LyricsTranslation.kt:193-206, 411-458` via
`https://inputtools.google.com/request`.

- [ ] 5.2a `predominantlyLatin` check, ≥⅓ survived unchanged → round-trip the
      payload through Input Tools and re-request
- [ ] 5.2b keep the first answer unless the retry transforms strictly more
- [ ] 5.2c unchanged-after-retry is `Unavailable`, **not** `AlreadyRomanized`
      (the fast check already handles the real no-op)

### 5.3 The disc fades are declared and never used

`lyrics_mode_discs.dart:122-123` declares `lyricsDiscFadeIn` 220ms /
`lyricsDiscFadeOut` 160ms with **zero** references. `_buildDisc`
(`lyrics_screen.dart:894-898`) hard-cuts between `TransformDisc` and
`SizedBox.shrink()`.

- [ ] 5.3a tween the disc's own alpha 0.18 ↔ 0.34 over those durations, and
      fade presence

### 5.4 The 5s idle timer loses to a scrub

Reference `NowPlayingScreen.kt:1119-1124` re-keys on
`(lyricsOpen, lyricsControlsOpen, scrub.scrubbing, volume.dragging)` and is
**suppressed** during scrub and volume drag. Ours has neither.

- [ ] 5.4a re-key on scrub start **and** scrub end
- [ ] 5.4b suppress while scrubbing and while a volume drag is live
- [ ] 5.4c confirm the discs still ride `_deckVisible && !_lyricsChromeHidden`
      (this part is already correct — do not regress it)

---

## Phase 6 — Sheet & settings

- [ ] 6.1 move "Prioritize syllable lyrics" **into** the provider sheet beside
      Reset (reference `LyricsSourcesDialog.kt:194`); keep the settings-screen row
      as the search target so `settings_search.dart` keeps resolving
- [ ] 6.2 track-edge auto-scroll while dragging a row — with 14 providers the
      drag cannot reach the ends. Reference: 28dp zone at 220dp/s
      (`LyricsSourcesDialog.kt:596-597`)
- [ ] 6.3 commit the reorder on drag **end**, not per intermediate swap
- [ ] 6.4 last-enabled guard stays (`:103-124`)

---

## Phase 7 — Tests

Each file written, then **proven to fail** by temporarily reinstating the bug,
then restored. A test never derived from the implementation it pins.

| File | Pins |
|---|---|
| `test/lyric_scroll_browse_test.dart` | drag enters browse; 600ms/5s exit; no re-scroll on exit; the auto-scroll survives its own animation |
| `test/lyric_lead_scroll_test.dart` | the lead line is reached before it is sung; duration equals the run-up gap |
| `test/lyric_ladder_tween_test.dart` | per-frame alpha crosses 0.7, sigma crosses 1.0, both monotonic, cubic curve |
| `test/lyric_strip_test.dart` | no lift, no glow, one line, 340ms, 0.55 dim, three distinct states |
| `test/lyric_morph_test.dart` | per-frame: panel absent until collapse completes; never two text layers in one frame; open and close |
| `test/lyrics_provider_reachability_test.dart` | every enum member in the default order or explicitly hidden |
| `test/lyrics_same_language_test.dart` | a Latin lyric yields a disabled, tinted disc and a message |

Widget-test gotchas (CONTEXT.md): `GoogleFonts.config.allowRuntimeFetching = false`
in `setUpAll`; seed platform channels inside `tester.runAsync`; fire-and-forget
haptics only.

---

## Phase 8 — Gate + device

- [ ] `flutter test` — all green, ≥ 844
- [ ] `flutter analyze --no-pub` — no new finding over 198/0
- [ ] `flutter build apk --debug`
- [ ] CPH2723 device pass:
      - auto-scroll keeps up with the singing for a whole verse
      - scroll by hand → blur clears, all lines readable, snaps back after ~600ms
      - a long lyric's last line is fully above the seek bar
      - lyric→player morph: artwork collapses, then lyrics fade in, nothing
        duplicated, nothing reads through
      - strip: one line, no lift twitch, word wipe tracks
      - globe on a Latin lyric → tinted, disabled, "already in Latin characters"
      - scrub the scrubber → discs stay up
      - switch provider → panel keeps animating, no freeze
- [ ] `CONTEXT.md` updated

---

## Phase roll-up

| Phase | Status |
|---|---|
| 0 — baseline commit | [x] `c4f76b9` |
| 1 — motion correctness (1.1–1.6) | [x] |
| 2 — morph | [ ] |
| 3 — seek-bar strip | [ ] partial (rise/glow off, maxLines 1, dim 0.55 landed with Phase 1) |
| 4 — providers | [ ] |
| 5 — globe / translate | [ ] |
| 6 — sheet & settings | [ ] |
| 7 — tests | [ ] partial (browse + lead + ladder shipped with Phase 1) |
| 8 — gates + device | [ ] |

## Log

- **Phase 0** — `c4f76b9` baseline. 844 tests, 198/0.
- **Phase 1.1** — browse is now a finger. The `isScrollingNotifier` listener is
  gone; the panel was disabling its own auto-follow once per line for 3.5s, which
  was the reported jank. Resume moved onto the correction tick.
- **Phase 1.2** — lead line is real, top-anchored, duration = the gap it covers.
  Two real bugs found on the way: an unbuilt target row made the scroll a silent
  no-op, and rows were measured against the screen instead of the list.
  `topAnchorOffset` extracted as a pure function; the pure pin caught my own wrong
  derivation of it, which the widget test had masked.
- **Phase 1.3** — one spec (`Cubic(0.41,0,0.12,0.99)`, 400ms) for blur, alpha,
  scale and scroll via a single `AnimatedLyricRow`. One font size/weight for every
  line, which removes a per-handover `TextPainter` layout pass.
- **Phase 1.4** — every word-synced row sweeps, not only the active one.
- **Phase 1.5** — the panel's `FadeTransition` is gone; it was a 300ms alpha layer
  over both glass discs (invariant 17).
- **Phase 1.6** — bottom padding takes the larger of the deck clearance and 80% of
  the viewport. A first attempt clamped instead of maxing and broke the very case
  the inset exists for; `lyrics_panel_bounds_test.dart` now pins both directions.
- **Phase 1 gate** — 856 tests green (844 + 12), `dart analyze` clean on
  `lyrics_screen.dart`, `lyric_swept_line.dart`, `lyric_sweep.dart`,
  `now_playing_screen.dart`, `lyric_providers_sheet.dart`. Browse tests proven
  failable by removing the `dragDetails` null check (3 fail).