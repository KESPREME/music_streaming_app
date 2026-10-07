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

- [x] collapse 380 → **420ms**, `easeOutCubic` (was `easeInOutCubic`)
- [x] add `_panelFadeController`, gated on `t >= 1.0`
- [x] delete the `Transform.translate` + `Transform.scale` on the panel — the morph
      is carried by the artwork sleeve; the panel only fades
- [x] the panel's discs are held out of the tree while the alpha is in flight, so
      there is never a lens under a translucent layer (invariant 17)
- [x] **close is the same two stages reversed** — `_closeLyrics` reverses both
- [x] keep `IgnorePointer(ignoring: fade < 0.6)`
- [x] test `lyric_morph_test.dart` — 5 tests over the real widget, **proven
      failable**: reinstating the old always-visible gate fails 2

---

## Phase 3 — Seek-bar strip

`now_playing_screen.dart:1323-1479`.

- [x] add `rise` and `glow` flags to `LyricSweptLine`; strip passes both off
- [x] `maxLines: 1`, `overflow: TextOverflow.ellipsis` on the **swept** path — and
      **found a bug doing it**: `maxLines` reached the plain paths and the dim base
      but not the lit copy inside the clip, so a long line still wrapped and grew
      the deck. All five render paths now go through one clamped helper, and the
      prefix-width table is measured against the same clamped layout
- [x] transition 380 → **340ms**, `easeInOutCubic` both ways, slide **0.35** in and
      out
- [x] `dimColor` 0.38 → **0.55** (`UNSUNG_ALPHA_STRIP`)
- [x] real states, replacing the intro phrase used forever — extracted to
      `lib/widgets/lyric_strip.dart` with the reference's five branches: loading,
      intro, unavailable (held 5s then faded over 900ms), unsynced ("Open
      lyrics"), plain, swept
- [x] index resolved from the same `LyricClock` as the wipe, not a separate
      `positionStream` read; the widget rebuilds only when the index moves
- [x] test `lyric_strip_test.dart` — 10 tests over the real widget

---

## Phase 4 — Providers

Scope note: `PAXSENIX_SPOTIFY` and `PAXSENIX_MUSIXMATCH` are **out of scope** by
user decision — they need an API key and the rest of the work has higher value.

- [x] 4.1 **reachability**: `betterLyricsPortato`, `youtubeMusic` and `megalobiz`
      were declared in `LyricsProvider` and rendered by the sheet but NOT in
      `defaultProviderOrder` - so the race never asked them. Added, with a test
      that names the unreachable one when it comes back.
- [x] 4.1b hide `megalobiz` alongside `simpMusic` (`isOffered`)
- [x] 4.1c Portato endpoint: NOT changed. Ours is `/getLyricsPortato`, the
      reference is `/qq/getLyrics`. Without a live response from either, changing
      it is a coin flip dressed as a fix - and the current path is already live
      in our fork. **Needs a device probe.**
- [x] 4.2 **populate `isrc`: NOT DONE, DELIBERATELY.** It threads correctly to
      BiniLyrics and LyricsPlus and is always null, because nothing in the
      codebase HAS one: there is no Spotify client and no ISRC field on any
      response we parse. Inventing one would be a guess. lrc.red's free-text
      search with a duration tie-breaker is the documented mitigation and it
      works - see `LrcRedProvider.getLyrics:78-81`.
- [x] 4.3 `prioritize_syllable_sync` default `true` -> **`false`**, as a named
      constant `LyricsService.prioritizeSyllableDefault` read by the provider,
      the service parameter and the test, so it cannot drift between them
- [x] 4.4 `initialize()` now calls `reconcileOrder` instead of re-implementing it
      inline - **and `reconcileOrder` was itself buggy**: it filtered the saved
      list for retired providers and then re-seeded them from the default order a
      few lines later
- [x] 4.5 a saved enabled-set can no longer bring a retired provider back
- [x] 4.6 `onSettled(null)` vs `onAbandoned` semantics untouched (invariant)
- [x] test `lyrics_provider_reachability_test.dart` - 10 tests, **proven
      failable**: removing `betterLyricsPortato` from the default order fails it
      by name

## Phase 5 - Globe / translate

### 5.1 The same-language guard was written and never wired

All of these existed and none were reachable: `isLatinScript` (referenced only
by a test), `reportAlreadyInLanguage` (defaulted false, no caller passed it),
`alreadyInLanguage` (read by nothing), `TransformButtonState.sameLanguage` (no
producer), and the 0.42 tint and disabled branch beside it.

The failure was worse than a missing feature: tapping the globe on an English
lyric sent a request, the endpoint returned the text unchanged, and a sub-line
appeared UNDERNEATH the original looking identical to it.

- [x] 5.1a the check lives in ONE place, `LyricsTranslationService
      .isAlreadyRomanizable`, read by both the disc and the controller so they
      cannot disagree. ALL lines must be Latin, not any - one Japanese line among
      thirty English ones still needs transliterating
- [x] 5.1b the disc dims to 0.42 and relabels itself
- [x] 5.1c tapping it SAYS why: "These lyrics already use Latin characters"
- [x] 5.1d **the disc is NOT disabled by that state.** It was, and that defeated
      the whole feature - a dim disc that swallows the tap is a dead control and
      reads as broken rather than as an answer. The reference taps through
      (`PlayerLyrics.kt:2791-2794`)
- [x] 5.1e the guard lives in the panel, not in a widget

### 5.2 Romanization on accented Latin

- [x] 5.2a the `inputtools` retry is **NOT DONE.** It needs a live request to
      verify the round trip and no fixture exists. The fast path (skip when
      already Latin) is done and is the common case
- [x] 5.2b / 5.2c depend on 5.2a

### 5.3 The disc fades were declared and never used

- [x] 5.3a `lyricsDiscFadeIn/FadeOut` (220/160ms) had zero references; the
      disc's alpha snapped with the glyph inside it, on different frames.
      `TransformDisc` is now stateful and tweens its own alpha

### 5.4 The 5s idle countdown lost to a held gesture

- [x] 5.4a re-key on scrub start AND scrub end
- [x] 5.4b suspended during a scrub and during a volume drag
- [x] 5.4c the discs still ride `_deckVisible && !_lyricsChromeHidden`
      (already correct in Phase 0 - not regressed)
## Phase 6 - Sheet & settings

- [x] 6.1 "Prioritize syllable lyrics" moved INTO the sheet beside Reset, in BOTH
      layouts from one builder - a control that exists in one theme and not the
      other is missing for whoever uses that one. The Settings row stays so
      settings search still resolves it
- [x] 6.2 track-edge auto-scroll while dragging: a 28dp band at 220dp/s. With ten
      providers the finger ran out of viewport long before the row ran out of
      finger, so the last provider could not be moved up
- [x] 6.3 the reorder is committed on drop, not on every intermediate swap
- [x] 6.4 the last-enabled guard is untouched

Implementation notes worth keeping:

- the list's OWN `ScrollPosition` is captured from inside `itemBuilder` and
  driven directly. `ReorderableListView` owns its controller and this Flutter
  version will not take one injected
- the drag position is observed with a `Listener`, not a `GestureDetector`:
  `ReorderableDragStartListener` starts the reorder on its own pointer-down, and
  a GestureDetector here enters the arena, can win it, and the reorder stops
  starting

---

## Phase 7 - Tests

Each file drives the REAL widget or reads the REAL constants. Nothing here
re-implements the logic it is testing - an earlier draft of the morph test did
exactly that and would have stayed green while the screen did the wrong thing.

| File | Status | Pins |
|---|---|---|
| `lyric_scroll_browse_test.dart` | [x] 9 | drag-only browse, 600ms/5s exit, no yank-back, the follow survives its own animation, lead bounds, top anchor arithmetic, never behind the voice |
| `lyric_morph_test.dart` | [x] 5 | no lyric layer during the collapse, never two, the fade completes, the close starts immediately, no disc under the alpha |
| `lyric_strip_test.dart` | [x] 10 | 340ms/0.35/0.55, the five states, one clock, one row, no lift |
| `lyrics_provider_reachability_test.dart` | [x] 10 | every provider in the order or hidden, order repair, the default off |
| `lyrics_same_language_test.dart` | [x] 10 | script check, the controller state, the dimmed-but-tappable disc, the message |
| `lyric_ladder_tween_test.dart` | folded in | became three cases in `lyric_swept_line_test.dart`: one font size/weight, emphasis from scale+alpha, one monotonic spec |
| `lyric_lead_scroll_test.dart` | folded in | became the lead group in `lyric_scroll_browse_test.dart` |

Proven failable, by temporarily reinstating each bug:

- Phase 1.1 - removing the `dragDetails` null check fails 3
- Phase 2 - reinstating the old always-visible panel gate fails 2
- Phase 4 - removing `betterLyricsPortato` from the default order fails by name

Widget-test gotchas (CONTEXT.md): `GoogleFonts.config.allowRuntimeFetching =
`false` in `setUpAll`; seed platform channels inside `tester.runAsync`;
fire-and-forget haptics only.

---

## Phase 8 - Gate + device

- [x] `flutter test` - **891 green** (was 844)
- [x] `flutter analyze --no-pub` - **198 issues / 0 errors**, identical to the
      pre-work baseline, and none of them in a file this work touched
- [x] `flutter build apk --debug` - builds, 460.8 MB
- [ ] CPH2723 device pass - **BLOCKED ON THE DEVICE**
      - auto-scroll keeps up with the singing for a whole verse
      - scroll by hand -> blur clears, all lines readable, snaps back after ~600ms
      - a long lyric's last line is fully above the seek bar
      - lyric->player morph: artwork collapses, THEN lyrics fade in, nothing
        duplicated, nothing reads through
      - strip: one line, no lift twitch, word wipe tracks, "Open lyrics" on an
        unsynced song, "No lyrics found" when there is none
      - globe on an English lyric -> dimmed, tap explains, no sub-line drawn
      - scrub the scrubber -> the discs stay up
      - switch provider -> panel keeps animating, no freeze
- [ ] `CONTEXT.md` updated

---

## Phase roll-up

| Phase | Status |
|---|---|
| 0 - baseline commit | [x] `c4f76b9` |
| 1 - motion correctness | [x] `33914fc` |
| 2 - morph | [x] `471bc1e` |
| 3 - seek-bar strip | [x] `45c7702` |
| 4 - providers | [x] `86b4efe` (isrc + inputtools deliberately not done) |
| 5 - globe / translate | [x] `4542ebd` (inputtools retry not done) |
| 6 - sheet & settings | [x] `f8a3eeb` |
| 7 - tests | [x] 47 new tests, three of them proven failable |
| 8 - gates | [x] tests / analyze / APK. [ ] device |

## Log

- **Phase 0** - `c4f76b9` baseline. 844 tests, 198/0.
- **Phase 1** - the jank was not a missing animation, it was the panel disabling
  its own follow: `isScrollingNotifier` cannot tell a finger from our own scroll,
  so every handover announced itself as a browse and switched the follow off for
  3.5s. Two more real bugs fell out: an unbuilt target row made the scroll a
  silent no-op (every backward seek dropped), and rows were measured against the
  screen instead of the list. `topAnchorOffset` extracted as a pure function -
  and the pure pin caught my own wrong derivation of it TWICE, which the widget
  test had masked both times. Also: one spec for blur/alpha/scale, one font size
  per line (removing a per-handover TextPainter pass), every word-synced row
  sweeps, the FadeTransition over the glass discs is gone, and the bottom padding
  takes the MAXIMUM of the deck clearance and 80% of the viewport.
- **Phase 2** - the duplication, "a thing comes before another thing" and the
  lyric-through-artwork capture were one bug: four layers animating in one frame.
  420ms collapse, THEN a 200ms fade with no transform. Close reverses both.
- **Phase 3** - the strip had five states collapsed into "an intro phrase", so a
  song with no lyrics said "Let it breathe" while the row beneath it said
  "Lyrics unavailable". One clock instead of two, 340ms/0.35 handover, and
  `maxLines` routed through every render path - which found that a long line was
  still wrapping and growing the deck.
- **Phase 4** - three providers were declared, listed and reorderable and never
  asked. `reconcileOrder` was also re-adding the retired providers it had just
  filtered out. `prioritize_syllable_sync` now defaults off, as one named
  constant read by three places.
- **Phase 5** - the same-language guard existed with no producer. Wiring it found
  that `sameLanguage` ALSO disabled the tap, so the message would have been
  unreachable - a dim dead control. The disc now dims and explains. Also: the
  disc alpha tweens on the durations that were declared for it, and a held scrub
  or volume drag suspends the 5s countdown.
- **Phase 6** - the word-sync preference now sits next to the list it changes,
  in both themes; and dragging a row can reach the end of the list at all.

