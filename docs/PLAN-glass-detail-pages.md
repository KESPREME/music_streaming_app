# Plan: seamless full-bleed headers, liquid-glass pills with physics, artist/album function

Material You screens stay untouched. BitChord (`BitChord-main/`, GPLv3) is a behaviour and numbers
reference only. One commit per phase; gates per phase: analyzer <= 186, full suite green, debug APK.
No device is available: everything below says whether it was proven by a test or only reasoned.

## 0. What was asked

1. Local songs must not bring the hidden "Jump back in" shelf back on Home.
2. Artist page: the top-right button does nothing -> real actions in a liquid-glass capsule (BitChord).
3. Album page: liquid-glass pills with real physics (tap AND hold), moving playfully like the bottom bar.
4. Album page: full bleed only, no card/framed sleeve.
5. Artist (and album) full bleed must read as ONE surface: no dark lines.
6. Research the flow and feature set first; design to Apple / Spotify level.

## 1. Diagnosis (measured, not guessed)

### 1a. The "black lines"
Old screenshots (Dawn FM, The Weeknd) were analysed row by row. Both show a width-uniform luminance step of
about 44 px (about 15 dp) near the photo's foot: a flat band, not photo content (photo edges are never
uniform across the width). It matches the code exactly. The header is THREE layers that do not agree:

| layer | what it does | the defect |
|---|---|---|
| `ArtworkFootFade` | photo -> wash, ends at **alpha 0.88** | the photo's last row is still 12% photo, the row below is 0%: a hard edge on any bright photo |
| `MergeBand` | 96 dp veil, opaque core ~23 dp | tries to hide that edge by painting a flat stripe: this IS the dark band |
| `ArtworkWash` | static page colour, holds wash then ramps | correct, but the photo is a separate translated layer, so the two disagree by a sub-pixel while scrolling |

Also: the photo height is `width / 0.95` (fractional), moved by `Transform.translate` with a fractional
offset -> anti-aliased hairline at the edge.

### 1b. Jump back in
`planHomeShelves` keeps `localHistory = recents.where(!isStreamableTrack)` when the feed has a history
shelf (a deliberate rule from dd2001e: a local file cannot live in a YouTube shelf). That is the only way
local plays resurrect the shelf. A test pins it (`local-file plays ... stay in Jump back in`) and must be
inverted.

### 1c. Artist top-right
`artist_detail_screen.dart` still has the decorative `person_rounded` container from before: no handler.

### 1d. What the glass package gives us (read from source, liquid_glass_widgets 1.8.1)
The bottom bar is `GlassTabBar.minimizable`. Its feel is the package's physics, available per widget:
`GlassButton` = spring inflation on press, squash and stretch while dragging, a specular glow that follows
the finger, `persistPressOnDrag` (hold keeps it inflated), shapes `LiquidOval` / `LiquidRoundedSuperellipse`,
styles filled / prominent / transparent. `GlassPullDownButton` / `GlassMenu` = liquid morph menu with
continuous swipe-to-select. `GlassButtonGroup` has NO per-item physics (stateless), so it is not used.
Rules from the package: premium quality only on static, non-scrolling surfaces; standard inside scrollables.

## 2. Research: what the screens must contain

Sources: Apple (iOS 27 Music artist pages: photo blends down into the page, dominant colour tints the
whole page, controls directly under the name, prominent shuffle; iOS 26.4 albums/playlists the same
full-colour treatment), Spotify (monthly listeners under the name, Popular = 5 then "See more", discography
filters, Fans also like, About), YouTube Music / BitChord (already studied), Apple's Liquid Glass guidance
(glass is for controls that float over content, never for content; group nearby controls).

### Album page
| need | decision |
|---|---|
| Full-bleed cover that dissolves into the page colour | yes (P1) |
| Title, artist (tap), "Album . 2022 . 15 tracks . 52 min" | have; keep honest (no invented parts) |
| Shuffle . Play . Download (state aware) | glass pills (P2) |
| Top bar: back . [search . sort . more] | glass; search toggles in-album search, **sort** is new (album order / title / duration), more = menu (P3) |
| Track rows: number or equalizer, title, explicit, **duration**, overflow | duration is new (every competitor shows it) |
| Rows play in the order shown | when sorted, the queue is the sorted list |
| About with More | have |
| Footer: song count + runtime + (p) line | have |
| **More by the artist / You might also like / Other versions** | new: parsed from the album response with the artist-shelf parser (shape assumed, same renderer) |
| Pull-down stretch of the cover, parallax, title -> top bar | yes (P1) |
| Save to library | not faked: no albums library exists. "Save as playlist" via `createPlaylistWith` instead |

### Artist page
| need | decision |
|---|---|
| Full-bleed photo that dissolves into a colour page | yes (P1) |
| Name + "239M monthly listeners" under it | caption is new (Spotify pattern); stat chips stay at the end |
| Shuffle . big Play . Share | glass (P2) |
| Top bar: back . [share . more . account] | **new function** (P3): share sheet, menu (Play next, Add to queue, Download top songs, Share), account switcher |
| Latest release, Top songs (20), shelves with Show all, Fans might also like, About + stats | done last round |
| Subscribe / follow | not faked: no write path |

## 3. Design

### 3a. ONE surface (`immersive_header.dart`)
- The photo is a normal child of the scroll view's first sliver (scrolls natively with the content: nothing
  to desync). Overscroll pulls the photo larger from its bottom edge (stretch); a gentle parallax (0.3)
  while scrolling up, off under reduce-motion.
- The fade is a single eased gradient (smootherstep sampled at 14 stops) from the photo's own pixels to the
  **opaque wash colour, alpha exactly 1.0**, with a flat tail of 3% at 1.0. No peak below 1.0, no band
  layer. The wash behind is the same colour, held flat for hero + 160 dp (covers overscroll), then ramps.
- Photo height is snapped to the physical pixel grid.
- Legibility: a "text scrim bump" (black, 0 -> 0.22 -> 0 across the title zone) sits inside the fade so
  white text is safe on a bright cover without a band at the bottom.
- `MergeBand`, `ArtworkFootFade`, `BitchordSliverAppBar` stay in the tree untouched (tests pin them) but
  the two pages stop using them.
- **Proof, not hope:** `immersive_header_seam_test.dart` renders the header over a PURE WHITE photo (worst
  case), reads the pixels and asserts: the last rows of the header equal the page colour within 1 level,
  and no row-to-row step above 3 levels anywhere in the fade, including across the hero's bottom edge.

### 3b. Glass kit (`detail_glass.dart`)
- Settings copied from `LiquidGlassNavBar` (thickness 24, blur 24, chromatic .04, light .85, refractive
  1.18, glass colour tinted from the cover accent, glow = accent at .38): same material, same physics.
- `DetailGlassCircle` (back, shuffle, download): `GlassButton`, 44 (bar) / 56 (actions), haptic on tap.
- `DetailGlassPill` (Play): `GlassButton.custom` on a superellipse capsule, white-tinted prominent glass
  with a dark label, so it keeps BitChord's white Play but is real glass (rim, specular, jelly).
- `DetailGlassCapsule` (top right): ONE glass capsule whose body gets the jelly/hold physics; each icon
  is its own tap target and pops (scale 1.0 -> 1.18) under the finger. Inner detectors win the tap arena
  over the outer no-op, the glass physics listen with a raw Listener, so both work together.
- `DetailTopBar`: overlay ABOVE the scroll view (so premium glass is legal there), back circle left,
  capsule right, centre title fading in after the header leaves, gradient-only scrim under the status bar
  once content scrolls beneath. Action pills inside the scroll content use standard quality.
- Menus: `GlassMenu` (liquid morph). If it will not lay out in the overlay, fall back to a glass modal
  sheet; the actions are the same either way.

### 3c. Data
- `AlbumDetailData.shelves` (default empty), parsed with a shared `_parseCarouselShelves` extracted from
  the artist parser (no behaviour change there; covered by a synthetic-JSON test).

## 4. Phases (one commit each)

| # | Commit | Proof |
|---|---|---|
| P0 | Jump back in stays hidden with local songs | inverted plan + screen tests |
| P1 | ImmersiveHeader; album full bleed (framed sleeve removed); artist seam fixed | seam test on pixels, page tests |
| P2 | Glass kit + top bar + action rows with physics | widget tests: builds under the app theme, tap and long-press callbacks fire, capsule slots route taps |
| P3 | Functions: artist capsule + menu, album search/sort/more, durations, More-by shelf, sort order plays in order | tests per function |
| P4 | Full gates, CONTEXT.md, report that separates proven from unverified |

## 5. Risks, stated up front
- Glass physics and the liquid menu cannot be SEEN here. What is proven: builds, taps, hold, routing.
  What is not: how the jelly feels. The settings are the nav bar's, so the feel should match, but that is
  an inference until it runs on the phone.
- The album-page carousel shape is assumed to be the artist page's. If it is absent the shelves are empty
  and nothing renders (fails closed).
- Impeller "premium" glass over the scroll view is avoided by design (package rule); top bar is an overlay.
