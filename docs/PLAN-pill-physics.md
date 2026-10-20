# Plan: one touch language - pill physics everywhere it is missing

Material You screens stay untouched (they import none of the shared widgets below; checked).
One commit per phase; gates per phase: analyzer <= 186 (now 181), targeted tests green, and at the end
the full suite + debug APK. No device is available: every claim below says "measured", "tested" or
"reasoned".

## 0. What was asked
Give pill / circle / chip / toggle controls the bottom bar's touch physics wherever they do not have it.
Analyse every component and screen first; research the interaction design; plan before building.

## 1. What the audit found (317 files, ~255 raw tap handlers, three parallel catalogues)

### 1a. The app has ~9 hand-rolled press effects and they disagree
| where | effect | scale | release |
|---|---|---|---|
| `SquishOnPress` (stagger_in) | AnimatedScale | 0.96 | tween, no overshoot |
| `PressableScale` (home_sections) | unbounded ctrl + spring | 0.97 | spring |
| `SearchPillPressable` | AnimatedScale | 0.94 | tween |
| `_SquishButton` (action bar), `_Press` (release header) | AnimatedScale | 0.94 | tween |
| `_PressSquish` (mini player) | AnimatedScale | 0.97 | tween |
| `SectionViewToggle` | AnimatedScale | 0.90 | tween |
| now-playing play/pause | AnimatedScale + `_isPlayPressed` state | 0.90 | tween |
| Explore `_PillIconButton`, `_PressableSegment` | AnimatedScale | 0.86 | tween |
| `LiquidGlassSegmented` | package flex + `_JiggleWrap` + per-segment | 0.97 / 0.86 | easeOutBack |

### 1b. MEASURED: the "house spring" does not wobble
`Motion.spring` (k520, zeta .78) released from 0.94 peaks at **1.0012**: a 0.12% overshoot, invisible.
So `PressableScale` springs back but never has the give the bottom bar has. A visible jelly needs 2-5%
overshoot (probe: peak - 1 is about 0.010 + 0.0147 x kick for k520 zeta .55). Constants below are chosen
by measurement, not by feel.

### 1c. Controls with NO feedback at all (the real gaps)
Now Playing: Favorite / Options circles (bare GestureDetector, size animates 42 -> 36), pull handle.
Queue: Favorite / Pronunciation / Options circles, TransitionChip, clear chip, remove X, Autoplay row.
Mini player: prev / play / next (IconButton ink only). Lyrics chrome: circles, Play, handle.
Library: filter-bar segments, "See all" pills, grid cards. Home: "See all" link. Explore: bottom tab bar,
header "...". Settings: Quick tiles, `LiquidSwitch` (no press, thumb never reacts), Stream/Local
segmented, font-weight segments, accent dots, style cards. Detail: top-songs cells, shelf cards, About
"More". Playlist detail page: old action bar, old seam.

### 1d. Two defects found on the way (both in code I wrote or touched)
- **Double haptics.** `DetailGlass*` plays a touch-down tick AND `lightImpact` on tap; `AccountButton` and
  `LibraryHeader` call `lightImpact` and then `GlassCircleButton` calls it again. Two buzzes per tap.
- **The playlist detail page still has the OLD header stack** (`MergeBand` + `ArtworkFootFade` +
  `BitchordSliverAppBar` + `BitchordActionBar`): the dark band you reported on artist/album is still there.

### 1e. Dead code (do NOT spend effort or risk on it)
`CanvasVideoScreen`, `GlassPlaybackBar`, `ExploreWheel`, `DiscoverScreen`, `LibraryActionCard`,
`LibraryBrandPromoCard` are never mounted. Listed so nobody "fixes" them.

## 2. Research
- Apple WWDC25 "Meet Liquid Glass": glass "responds to interaction by instantly flexing and energizing with
  light"; it has "gel-like flexibility ... as it moves in tandem with your interaction"; elements "lift up
  into Liquid Glass temporarily ... the resting state stays visually quiet"; interaction glow "starting
  right under your fingertips, spreads throughout the element". **Glass is for the navigation layer that
  floats above content; never on content; never glass on glass.** Reduced Motion "disables any elastic
  properties". => The jelly is a property of FLOATING CONTROLS. Cards and rows stay quiet.
- Squash and stretch (animation principles; Flutter rubber-band menus): keep VOLUME constant (compress Y,
  widen X), micro-interactions 100-200 ms, 5-10% deformation, 2-5% overshoot, "keep subtle - this is UI,
  not cartoon".
- Material 3 Expressive: spring-based press, shape morph on press; same conclusion: springs, not tweens.

## 3. Design: three tiers, one primitive

| tier | what | physics |
|---|---|---|
| A. Floating glass chrome | detail pages (done: package `GlassButton`), `GlassCircleButton` (18 uses), top pills, mini player, nav bar | JellyPress `chrome`: press, hold, finger-follow stretch, **glow under the finger**, wobble on release |
| B. Controls in content | filter/sort chips, "See all", collection pills, toggles, segmented, tabs, transport glyphs, queue/lyrics circles, dots | JellyPress `pill` / `circle` / `icon`: same spring and stretch, **no glow** (content layer) |
| C. Cards and rows | rail cards, list rows, sheet rows | unchanged: `PressableScale` 0.97 (tests pin it) / ink. Large surfaces do not jelly |

### JellyPress (`lib/widgets/jelly_press.dart`) - one primitive replacing the nine
- **Physics** (`JellySpring`, pure Dart, unit-tested): three springs (scale, stretch-x, stretch-y) on ONE
  ticker that runs only while something is away from rest.
  press -> pressScale (0.88 icon / 0.92 circle / 0.95 pill) ; HOLD -> stays ; DRAG on the control ->
  volume-preserving stretch toward the finger (rubber-band damped, max 6-8%) ; RELEASE -> spring with a
  velocity kick so it passes rest by 2-5% and settles inside ~450 ms.
- **Touch plumbing**: a passive `Listener` (no gesture arena, so it never competes with drags, Dismissible,
  PageView, the mini player's pull) OUTSIDE the transform (stable coordinates), plus a `GestureDetector`
  only for tap / long-press. Taps fire on tap-up immediately (never deferred: tests and users both need it).
- **ONE haptic per touch**: on tap-confirm. `light` for buttons, `selection` for chips/toggles/tabs, `none`
  where the call site already plays its own (so nothing buzzes twice). Long-press keeps its own.
- **Reduce motion**: no transform, no ticker; the tap still works.
- Wrapper adds no semantics (call sites keep theirs); optional `semanticLabel` for controls that had none.
- Tokens live in `Motion` (`jelly*`), not in call sites.

### Upgrade the shared primitives so every user gets it at once (least churn, least risk)
`GlassCircleButton` -> JellyPress chrome. `SquishOnPress` -> JellyPress (now-playing side buttons).
`SearchPillPressable`, `_SquishButton`, `_Press` -> JellyPress pill. Detail kit: remove the extra tick.
`PressableScale` is NOT touched (skeleton_and_press_test and track_list_row_test read its ScaleTransition).

## 4. Phases (one commit each)
| # | Commit | Proof |
|---|---|---|
| P1 | `JellySpring` + `JellyPress` + tokens; fix detail-kit double haptic | numerics: overshoot band, settle time, volume, no NaN; widget: tap once, long-press, hold, drag-off, reduce motion, child not rebuilt, haptic count |
| P2 | Shared primitives upgraded (GlassCircleButton, SquishOnPress, SearchPillPressable, _SquishButton, _Press); remove double haptics | the existing 20+ tests that find these by type/label |
| P3 | Player surfaces: Now Playing, queue, mini player, lyrics chrome | now_playing / queue / mini / lyrics tests |
| P4 | Browse: library, home, collections, explore tabs, replay | their tests |
| P5 | Settings and sheets: LiquidSwitch (thumb grows + stretches), segmented, quick tiles, weight/font controls, accent dots | settings tests |
| P6 | Playlist detail page onto ImmersiveHeader + DetailTopBar + glass row (kills the third dark band) | the 13 playlist tests + pixel seam test |
| P7 | Full suite, analyzer, APK, CONTEXT.md | gates |

## 5. Risks stated up front
- Cannot FEEL it here. Proven: numeric overshoot/settle/volume, tap/hold/drag routing, reduce motion,
  haptic counts, no test regressions. Not proven: how it looks and feels on the phone.
- Growth past 1.0 is clipped by horizontal rails; chips there get headroom or stay at <= 1.03.
- `LiquidGlassSegmented` and the Explore top pill already stack package flex + wrappers; they are left alone
  (a fourth effect would compound).
- Rows (settings / sheets / lists) keep Material ink. A highlight-fade row response is a separate follow-up.

## 6. Outcome (what shipped)
| Phase | Commit |
|---|---|
| P1 JellySpring + JellyPress | `146522e` |
| P2 shared primitives | `b41a129` |
| P3 Now Playing, mini player, queue, lyrics chrome | `31d4f28`, `3bbf13d` |
| P4 browse: See all, view toggles, filter chips, Library segments, grid cards | `5f2e693` |
| P5 LiquidSwitch thumb, settings segments/tiles, accent dots, weight segments, every bare `IconButton` -> `JellyIconButton` | `1d11ef3` |
| P5b Explore Play + options, lyric discs, shelf cards, About toggle, option tiles | `2e82659` |
| P6 playlist page onto ImmersiveHeader + DetailTopBar + glass row | `eb4a75d` |

Gates at the end: analyzer 181 (limit 186), full suite 2283 pass, `flutter build apk --debug --no-pub` built.

Finding on the way: `LiquidSwitch`'s thumb was always a 24.4 circle (the track clamps the 26dp it asked for); the
stretch keeps that size at rest so the switch looks exactly as before until touched.

Not proven here (no device): the feel on a phone, the glow's look, growth clipped by horizontal rails.
Follow-up: a highlight-fade response for Material-ink rows (settings / sheets / lists).
