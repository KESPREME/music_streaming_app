# MINE MUSIC — FULL-SCALE FLUTTER REFACTOR
## Premium Music Client / Liquid Glass / Gesture-Driven / Offline-First

You are working inside an existing Flutter music application named **MineMusic**.

This is an EXISTING PRODUCT REFACTOR.

Do NOT treat this as a greenfield UI exercise.

Your responsibility is to:

1. inspect the existing MineMusic codebase first
2. understand its current architecture and functionality
3. preserve working business logic wherever possible
4. refactor the architecture where necessary
5. reproduce the interaction language and visual behavior observed in the supplied reference recording
6. elevate the UI to a production-grade premium liquid-glass system
7. improve performance, maintainability, state isolation, error handling, responsiveness, animation quality, and long-term scalability
8. avoid generic AI-generated UI patterns
9. follow the Taste-Skill philosophy throughout the redesign

The result must be a REAL Flutter application, not a collection of screenshot-specific mockups.

---

# 0. NON-NEGOTIABLE RULE

Before modifying anything:

AUDIT THE EXISTING REPOSITORY.

Do not start by creating new screens.

First inspect:

- pubspec.yaml
- pubspec.lock
- analysis_options.yaml
- lib/
- models/
- providers/
- services/
- repositories if present
- widgets/
- screens/
- theme system
- navigation
- audio lifecycle
- persistence
- networking
- background playback
- download implementation
- lyrics implementation
- deep links
- share intents
- platform integration
- Android configuration
- iOS configuration
- desktop configuration if supported
- custom packages
- shaders
- image loading/caching
- existing animations
- any custom platform code

Produce an internal architecture map before refactoring.

Do not blindly replace code.

For every major refactor, determine:

- what exists
- what is correct
- what is fragile
- what is duplicated
- what is coupled
- what is obsolete
- what must remain backwards compatible
- what can be extracted
- what should become a reusable abstraction
- what should be deleted

---

# 1. REFERENCE IMPLEMENTATION TARGET

The attached video is the primary behavioral reference.

The visual references are secondary material references.

Do NOT redesign the product into an unrelated futuristic music application.

The goal is:

REFERENCE BEHAVIOR
+
REFERENCE INFORMATION ARCHITECTURE
+
REFERENCE INTERACTION LANGUAGE
+
IMPROVED IMPLEMENTATION
+
MORE BELIEVABLE LIQUID GLASS
+
BETTER SOFTWARE ARCHITECTURE

The app should feel like the same family of product, but implemented cleanly and robustly.

Do not copy branding or proprietary assets.

Use the MineMusic brand, MineMusic content model, and existing MineMusic assets.

---

# 2. EXPLICITLY OUT OF SCOPE FOR THIS PASS

Do NOT implement or discuss these features in this refactor unless MineMusic already requires them internally:

- login/authentication UX
- QR-code feature
- Listen Together feature

Do not spend architecture/design budget on those features.

They can remain extension points in the architecture, but they are not part of this implementation pass.

---

# 3. TASTE-SKILL MUST BE APPLIED

Use the Taste-Skill approach as a design quality layer.

The current Taste-Skill philosophy explicitly emphasizes:

- audit-first redesign
- intentional visual direction
- typography discipline
- controlled layout variance
- meaningful motion
- visual density tuning
- avoiding template-like output
- avoiding repetitive cards
- avoiding generic component libraries disguised as product design
- strong hierarchy
- deliberate spacing
- purposeful animation
- a strict design pre-flight

For this project, treat the following dials approximately as:

DESIGN_VARIANCE = 6
MOTION_INTENSITY = 7
VISUAL_DENSITY = 5

These are starting points, not hard values.

MineMusic should feel:

- premium
- calm
- tactile
- sophisticated
- editorial
- immersive
- spatial
- dark
- physically dimensional

Do NOT make it:

- cyberpunk
- neon
- holographic
- gaming-oriented
- futuristic HUD
- excessive glassmorphism
- purple/cyan gradient slop
- repetitive card grids

Never add visual effects simply because they are technically possible.

Every visual effect must support:

- hierarchy
- feedback
- spatial understanding
- interaction
- atmosphere
- or material realism

---

# 4. PRIMARY DESIGN PRINCIPLE

The product is NOT "a glass UI".

It is a music application that uses **liquid glass as an interaction material**.

This distinction is critical.

The visual hierarchy should be:

1. music/content
2. hierarchy
3. interaction
4. material
5. decoration

NOT:

1. glass
2. glow
3. gradients
4. decoration
5. content

---

# 5. CORE ARCHITECTURE

Refactor toward a modular architecture.

Preferred high-level structure:

lib/
  app/
    app.dart
    router/
    theme/
    responsive/
    lifecycle/

  core/
    constants/
    errors/
    logging/
    result/
    utils/
    extensions/

  design/
    tokens/
    colors/
    typography/
    spacing/
    radii/
    elevation/
    motion/
    glass/
    icons/

  domain/
    entities/
    repositories/
    use_cases/

  data/
    models/
    datasources/
    repositories/
    mappers/
    cache/

  features/
    home/
      presentation/
      providers/
    search/
      presentation/
      providers/
    discover/
      presentation/
      providers/
    library/
      presentation/
      providers/
    player/
      presentation/
      providers/
    lyrics/
      presentation/
      providers/
    queue/
      presentation/
      providers/
    artist/
      presentation/
      providers/
    album/
      presentation/
      providers/
    playlist/
      presentation/
      providers/
    downloads/
      presentation/
      providers/
    settings/
      presentation/
      providers/

  playback/
    audio_controller/
    queue/
    media_session/
    effects/
    state/

  networking/
    clients/
    interceptors/
    endpoints/
    retry/
    connectivity/

  persistence/
    database/
    preferences/
    migrations/
    cache/

  widgets/
    common/
    media/
    glass/
    navigation/
    overlays/
    feedback/

Do not force this structure mechanically if the existing project has better organization.

The important objective is SEPARATION OF RESPONSIBILITIES.

---

# 6. STATE MANAGEMENT

Use Riverpod as the primary application state architecture.

Current Muzo v3.9 already uses Riverpod, but avoid the common problem of mixing multiple state systems without clear ownership. :contentReference[oaicite:3]{index=3}

Prefer:

- Provider
- StateProvider only for genuinely simple state
- Notifier / AsyncNotifier for feature state
- StreamProvider for streams
- family providers for parameterized resources
- autoDispose where appropriate
- keepAlive only where justified

Do NOT introduce global mutable singletons everywhere.

Do NOT put business logic into widgets.

Do NOT make screens responsible for networking.

Do NOT make widgets directly coordinate persistence.

Every major state domain should have one owner.

---

# 7. PLAYBACK MUST BECOME A FIRST-CLASS SUBSYSTEM

Playback is not a UI concern.

Create a dedicated playback subsystem.

Conceptual model:

PlaybackController
    ↓
AudioEngine
    ↓
AudioService / platform session
    ↓
QueueController
    ↓
PlaybackState
    ↓
UI projections

The UI should NEVER directly manipulate low-level player state everywhere.

Expose a stable domain-level API:

- play(track)
- pause()
- resume()
- toggle()
- seek()
- skipNext()
- skipPrevious()
- playQueue()
- addToQueue()
- removeFromQueue()
- reorderQueue()
- clearQueue()
- setVolume()
- setSpeed()
- setLoopMode()
- setShuffle()
- retry()
- stop()
- dispose()

Expose immutable state:

PlaybackState(
  currentTrack
  isPlaying
  isBuffering
  duration
  position
  bufferedPosition
  queue
  currentIndex
  loopMode
  shuffleEnabled
  volume
  playbackRate
  error
)

Never make individual screens subscribe to dozens of independent low-level streams unnecessarily.

Aggregate where useful.

---

# 8. AUDIO ENGINE

Use the current stable compatible `just_audio` and `audio_service` stack.

As of the current environment:

- just_audio 0.10.6 is current
- audio_service 0.18.19 is current

but always verify package compatibility before locking versions. :contentReference[oaicite:4]{index=4}

Do not upgrade blindly.

Check:

- Android compatibility
- iOS compatibility
- background playback
- notification metadata
- audio focus
- interruptions
- Bluetooth controls
- headset controls
- lock screen controls
- seek
- queue synchronization
- stream failures
- reconnection
- lifecycle handling

Prefer the newer just_audio playlist APIs when migrating legacy APIs.

Do not preserve deprecated patterns merely for historical compatibility.

---

# 9. PLAYBACK STATE SYNCHRONIZATION

Guarantee consistency between:

- mini-player
- full player
- queue screen
- lyrics screen
- notification
- lock-screen playback
- widgets
- audio service
- media metadata
- current playlist
- current track
- progress bar

A seek performed in one UI must update every other projection.

A track changed from notification must update the app.

A queue reorder must update every UI.

A favorite toggle from the mini-player must immediately update:

- current player
- home
- library
- search result
- playlist

Avoid duplicated copies of the same playback state.

---

# 10. ARTWORK PIPELINE

Artwork is not decoration.

It drives:

- content hierarchy
- environmental atmosphere
- dynamic glass tinting
- player background
- visual transitions
- theme context

Create an artwork pipeline:

ArtworkURL
    ↓
ImageRepository
    ↓
memory cache
    ↓
disk cache
    ↓
decoded image
    ↓
palette extraction
    ↓
safe color transformation
    ↓
ambient backdrop

Use image caching strategically.

Avoid decoding huge source images when thumbnails are sufficient.

Prefetch images for visible and near-visible carousel items.

Never allow image decoding to cause avoidable UI jank.

---

# 11. DYNAMIC ARTWORK ATMOSPHERE

Artwork can influence the environment subtly.

Do NOT simply extract one dominant color and fill the whole background.

Instead derive:

- dominant tonal family
- dark ambient color
- subdued secondary tone
- luminance
- contrast
- warmth/coolness

Create a restrained ambient background.

The result should be approximately:

artwork
→ low-amplitude environmental atmosphere
→ dark stabilization layer
→ UI

Do not produce a giant color wash.

Do not produce neon backgrounds.

Do not make every track generate a dramatically different theme.

Changes should feel organic.

---

# 12. LIQUID GLASS SYSTEM

This is a major refactor.

Do not use a single generic `GlassContainer` for everything.

Create a proper glass material system.

Example:

GlassSurface
GlassButton
GlassIconButton
GlassNavBar
GlassMiniPlayer
GlassSheet
GlassSegment
GlassFilter
GlassControlCluster
GlassFloatingAction

Each should have a semantic material role.

---

# 13. LIQUID GLASS MATERIAL MODEL

The material must combine multiple layers.

Conceptual pipeline:

BACKGROUND
    ↓
optional artwork / ambient blur
    ↓
localized backdrop filter
    ↓
refraction/distortion layer
    ↓
transparent tint layer
    ↓
internal luminance modulation
    ↓
edge definition
    ↓
specular highlight
    ↓
content

Never implement it as:

BackdropFilter
+
white alpha
+
border
+
shadow

That is explicitly insufficient.

The existing v3.9 GlassContainer does almost exactly that, so it should be replaced or significantly generalized. :contentReference[oaicite:5]{index=5}

---

# 14. LIQUID GLASS TECHNOLOGY

Evaluate:

`liquid_glass_easy`

The current package provides shader-driven lens effects including:

- distortion
- magnification
- refraction
- blur
- custom shapes
- optical borders
- fluid interaction

The current pub.dev release is 4.2.0, but verify compatibility before locking it. :contentReference[oaicite:6]{index=6}

Use it where it provides reliable performance.

Do not assume every glass surface should use maximum shader complexity.

Prefer a tiered system.

---

# 15. GLASS PERFORMANCE TIERS

Define:

GlassTier.none
GlassTier.subtle
GlassTier.standard
GlassTier.rich

### none

No blur / no refraction.

Used for:

- grounded content
- dense lists
- static sections

### subtle

Used for:

- compact buttons
- icon buttons
- filters

### standard

Used for:

- navigation
- mini-player
- control clusters

### rich

Used for:

- expanded player controls
- major transient surfaces
- selected controls
- hero-level interaction surfaces

Do not allow all widgets to request rich glass simultaneously.

---

# 16. GLASS OPTICAL PARAMETERS

Create tokens for:

- opacity
- blur
- distortion
- magnification
- refraction strength
- edge intensity
- inner highlight
- specular intensity
- tint amount
- background contribution
- depth
- corner radius

Do not hardcode these throughout the application.

Example conceptual values:

GlassNav:
  low opacity
  medium blur
  low distortion
  subtle specular
  moderate edge separation

GlassMiniPlayer:
  medium opacity
  medium blur
  moderate distortion
  artwork-adaptive tint

GlassSheet:
  higher opacity
  stronger background separation
  lower distortion
  high readability

---

# 17. IMPORTANT GLASS RULE

Glass must distort WHAT IS BEHIND IT.

The user must be able to perceive:

- slight displacement
- soft optical enlargement
- local bending
- subtle chromatic separation
- background content changing through the lens

Do not simply put a transparent surface over a static blurred screenshot.

The effect needs to respond to the actual composited background whenever technically feasible.

---

# 18. REFRACTION MUST BE LOCALIZED

Do NOT distort the entire screen.

The recording's overall identity depends on visual stability.

The glass should interact with:

- artwork
- background texture
- nearby controls

but large areas of the screen should remain visually still.

Approximate intention:

background motion = low
glass optical motion = medium
interaction feedback = medium/high
decorative animation = almost none

---

# 19. GLASS EDGE BEHAVIOR

Edges should communicate thickness.

Use:

- subtle highlight on light-facing edge
- subtle darkening on opposite edge
- curved specular response
- no luminous border

Avoid:

- glowing outlines
- bright white borders
- neon edges

The edge should look like light catching glass.

---

# 20. GLASS REFLECTION

Reflection should be driven by the environment.

Useful sources:

- artwork
- surrounding UI
- bright text/control regions
- ambient background

Reflection intensity should stay restrained.

Do not draw generic diagonal white streaks on every glass object.

---

# 21. GLASS SELECTED STATE

The selected navigation item and selected controls should feel like matter.

Not:

"selected = pink pill"

Instead:

unselected
→ neutral smoked glass

selected
→ local volume shifts
→ inner surface becomes slightly denser
→ optical distortion increases subtly
→ local highlight changes
→ content underneath is gently refracted

Use animated shape/opacity/distortion if available.

Selected state should feel like a small liquid displacement.

---

# 22. GLASS TOUCH FEEDBACK

When the user presses a glass control:

down:
- slight compression
- slight scale reduction
- optical density increase
- specular movement
- tiny haptic if appropriate

release:
- spring back
- subtle overshoot
- settle quickly

Do NOT use generic Material ripple as the main effect.

A subtle physical response is preferred.

You may retain a very faint feedback overlay for accessibility.

---

# 23. MOTION SYSTEM

Create one global motion token system.

Do not invent random animation durations.

Define:

Motion.fast
Motion.normal
Motion.emphasized
Motion.sheet
Motion.page
Motion.spring

Example targets:

micro-feedback:
100–180 ms

state transition:
180–280 ms

surface expansion:
280–420 ms

page transition:
300–500 ms

large gesture completion:
350–600 ms

Use spring curves for physical surfaces.

Use easing for content movement.

---

# 24. MOTION SHOULD HAVE PURPOSE

Every animation must belong to one of these categories:

1. state change
2. navigation
3. spatial continuity
4. direct manipulation
5. playback feedback
6. loading
7. content arrival

If an animation belongs to none of them, remove it.

No:

- floating blobs
- particles
- decorative parallax
- constant background movement
- random pulsing
- gratuitous morphing

---

# 25. SCREEN TRANSITIONS

Avoid replacing screens with an abrupt hard cut.

Use continuity where meaningful.

Examples:

Mini Player
→ expands into Full Player

Artwork thumbnail
→ grows into player artwork

Album/track artwork
→ expands into detail view

Contextual action
→ sheet originates from source control

Search field
→ expands from navigation/search action

For transitions that don't have a natural shared element:

use subtle fade + slide + scale.

---

# 26. MAIN APP SHELL

Create a stable application shell.

Conceptually:

AppShell
 ├── BackgroundLayer
 ├── NavigationContent
 ├── OverlayLayer
 ├── MiniPlayerLayer
 ├── BottomNavigationLayer
 └── SystemFeedbackLayer

The shell should persist while primary content changes.

This is one of the strongest architectural ideas visible in the reference behavior.

---

# 27. MINI PLAYER

Mini-player is a globally persistent component.

It should:

- appear when a track is active
- disappear when nothing is playing
- remain synchronized
- open full player
- allow play/pause
- expose favorite where appropriate
- expose track context
- show artwork
- show progress
- visually react to buffering
- adapt to artwork
- coexist correctly with bottom navigation

The existing v3.9 mini-player already uses Riverpod + audio state and expands into the player, so preserve the idea while refactoring implementation. :contentReference[oaicite:7]{index=7}

---

# 28. MINI PLAYER MOTION

When it appears:

- slide from bottom
- fade in
- slight upward spring
- settle above navigation

When it disappears:

- compress
- lower slightly
- fade

When the current track changes:

- artwork crossfades
- metadata changes with continuity
- progress resets smoothly
- ambient color morphs gradually

Do not make the entire component pop.

---

# 29. MINI PLAYER EXPANSION

Treat the mini-player and full-player artwork as related spatial elements.

Ideal sequence:

tap mini-player
→ mini-player slightly enlarges
→ surrounding content softens
→ player background emerges
→ artwork scales
→ controls reveal
→ full player settles

Use shared-element-like continuity where practical.

Do not create two unrelated screens with a simple route transition.

---

# 30. BOTTOM NAVIGATION

The reference relies heavily on a floating bottom navigation layer.

Create:

FloatingGlassNavigation

Properties:

- persistent
- safe-area aware
- material-aware
- artwork-aware
- selection-aware
- keyboard aware
- player-aware

When full player opens:

navigation should fade/disable appropriately rather than being destroyed and recreated.

The current v3.9 shell already positions the nav as a floating layer and places the mini-player above it. Preserve this conceptual ordering. :contentReference[oaicite:8]{index=8}

---

# 31. NAVIGATION ARCHITECTURE

Use a proper declarative router.

A current compatible option is `go_router`; version 18.0.0 is current at the time of this prompt and requires a modern Flutter/Dart baseline. :contentReference[oaicite:9]{index=9}

But do NOT introduce it blindly.

First determine:

- current navigation mechanism
- deep-link requirements
- nested navigation
- shell routing
- player route
- modal routes
- detail routes
- back-stack rules
- state restoration

Preferred route families:

/
 /home
 /discover
 /search
 /library
 /player
 /lyrics
 /queue
 /artist/:id
 /album/:id
 /playlist/:id
 /settings
 /downloads

Use nested shell routing where useful.

---

# 32. HOME SCREEN

Home is:

PERSONALIZED
EDITORIAL
EXPANSIVE
CONTENT-FIRST

Do not make it look like a dashboard.

Possible sections:

- contextual greeting
- top picks
- recently played
- recommended albums
- mixes
- music videos
- artist discovery
- genre discovery
- playlist discovery

Do not make every section visually identical.

---

# 33. HOME COMPOSITION

Use layout variance.

Examples:

Hero recommendation:
large horizontal composition

Mixes:
compact vertical artwork cards

Recently played:
dense 2-column or asymmetric grid

Artists:
circular avatars

Tracks:
dense rows

Featured collection:
large editorial artwork

Do not:

card
card
card
card
card
card

repeated forever.

This is explicitly forbidden by the Taste-Skill principles.

---

# 34. HOME SCROLL BEHAVIOR

Use:

- smooth native scrolling
- intentional section spacing
- subtle section arrival
- artwork prefetching
- sticky contextual controls only when useful

Avoid triggering large expensive animations on every pixel of scroll.

Use scroll-driven animation only for high-value moments.

---

# 35. HOME HEADER

Keep the header clean.

Potential controls:

- title/context
- profile/settings entry if already supported by MineMusic
- search entry
- compact actions

Do not overload the top bar.

---

# 36. DISCOVER SCREEN

Discover should feel fundamentally different from Home.

Home:
browse many things

Discover:
focus on one thing

Design language:

immersive
focused
interactive

Use a large primary media presentation.

Possible flow:

featured media
→ evaluate
→ play/save/skip
→ next

Avoid a conventional infinite-feed design.

---

# 37. DISCOVER INTERACTION

The user should feel that the content is physically browsable.

Support:

- swipe left/right
- drag
- tap actions
- favorite
- play
- next
- previous
- contextual actions

Gestures need clear thresholds.

Avoid accidental skips.

Use velocity-aware completion.

---

# 38. GESTURE SYSTEM

Create a dedicated gesture interpreter.

It should distinguish:

horizontal swipe
vertical swipe
tap
double-tap
drag
long press

Do not implement gesture logic independently inside each widget.

Centralize gesture semantics where practical.

---

# 39. GESTURE PLAYER

The v3.9 reference explicitly describes:

- double-tap play/pause
- swipe left/right track switching
- swipe down dismiss
- right-side vertical volume gesture
- glass controls overlay

Preserve this interaction family for MineMusic where it matches the existing product requirements. :contentReference[oaicite:10]{index=10}

Use gesture zones carefully.

Never allow a lyric panel, artwork, seek gesture, or overlay to steal gestures unintentionally.

---

# 40. GESTURE FEEDBACK

Gesture states should have physical feedback.

Example:

drag left:

artwork follows finger
→ velocity influences displacement
→ neighboring artwork enters
→ release threshold determines completion
→ completed swipe springs into place

cancel:

artwork returns naturally

This is much better than:

onHorizontalDragEnd → change item instantly

---

# 41. FULL PLAYER

The full player should be one of the most polished surfaces in the app.

Layers:

background artwork
↓
dark stabilization
↓
ambient atmosphere
↓
artwork
↓
metadata
↓
progress
↓
controls
↓
contextual controls

Controls should never fight with the artwork.

---

# 42. PLAYER ARTWORK

Artwork should be visually rich.

Do not apply unnecessary blur to the artwork itself.

Use a separate environmental background.

The actual album art should remain sharp enough to read as content.

---

# 43. PLAYER BACKGROUND

Use artwork-derived ambient rendering.

Potential stack:

- scaled artwork
- blur
- dark overlay
- subtle vignette
- low-frequency color stabilization

Do NOT create an obvious blurred duplicate that looks like wallpaper.

---

# 44. PLAYER CONTROLS

Primary controls:

previous
play/pause
next

Secondary:

shuffle
repeat
favorite
queue
lyrics
speed
audio quality
more

Prioritize hierarchy.

Primary play/pause should dominate.

Do not make all icons identical in visual weight.

---

# 45. PLAY / PAUSE FEEDBACK

Use micro-animation:

play → pause morph
pause → play morph

Do not instantly swap static icons.

Buffering:

play button transforms into a restrained loading state.

Avoid full-screen spinners.

---

# 46. DOUBLE TAP FEEDBACK

Double-tap artwork:

show temporary play/pause or favorite response.

Use:

- tiny scale
- opacity
- icon morph
- optional haptic

Then naturally disappear.

Never use huge glowing overlays.

---

# 47. SCRUBBER

Scrubber must feel physical.

Track:

- progress
- buffered region
- thumb
- hit target

On drag:

- thumb enlarges slightly
- progress becomes easier to target
- time indicators may become more prominent

On release:

- thumb returns
- progress settles

Use the audio state as the source of truth.

Do not create an independent timer loop.

---

# 48. QUEUE

Queue is a denser surface.

Support:

- current track
- upcoming tracks
- drag reorder
- remove
- clear
- queue add
- play next
- play from here

The audio handler in the reference already contains queue reorder and clear behavior; preserve those semantics while moving them behind a clean queue controller. :contentReference[oaicite:11]{index=11}

---

# 49. SMART QUEUE / AUTO-QUEUE

Define queue rules explicitly.

Examples:

manual queue
auto-generated recommendations
active item
pending items

Clearing queue must not accidentally stop the active track unless explicitly requested.

Disabled states must reflect actual capability.

Do not allow UI to show an action that cannot currently execute.

---

# 50. LYRICS SYSTEM

Lyrics are a first-class feature.

Support:

- synced lyrics
- line synchronization
- word synchronization
- karaoke highlighting
- scrolling
- active line focus
- loading
- unavailable state
- language changes
- lyrics panel/player integration

The reference product describes word-level karaoke and active-line movement as key behavior. :contentReference[oaicite:12]{index=12}

---

# 51. KARAOKE RENDERING

Current line:

highest contrast

previous/next:

reduced opacity

Word highlighting:

progressively fill the word based on timing

Do not rebuild the entire lyrics widget on every timing tick.

Use a rendering strategy optimized for frequent updates.

Target:

60 FPS or better where feasible.

---

# 52. LYRICS PERFORMANCE

Do not call setState on the entire page for every word update.

Use fine-grained state.

Possible structure:

LyricsController
 ├── currentLineIndex
 ├── wordProgress
 ├── scrollTarget
 └── playbackPosition

The lyrics rendering layer should be highly isolated.

---

# 53. ACTIVE-LINE MOTION

Reference behavior:

inactive
↓
current line approaches
↓
line becomes visually dominant
↓
line settles
↓
previous line fades

Use smooth scrolling rather than abrupt jumps.

Do not center every line unnecessarily if it harms reading.

---

# 54. SEARCH

Search is a major product feature.

Search must support:

- real input
- debounce
- recent searches
- empty state
- loading
- results
- categories
- songs
- videos
- artists
- albums
- playlists
- offline fallback where appropriate

Do not simulate search with static data.

---

# 55. SEARCH UX

Search field should have:

- tactile focus state
- clear button
- keyboard-safe behavior
- loading state
- query preservation
- cancellation

Debounce remote calls.

Cancel stale requests.

Do not display stale results after a newer query completes.

Use request identity / cancellation / generation tokens.

---

# 56. SEARCH RESULTS

Use information-dense rows.

Different result types should have distinct presentation.

Song:
artwork + title + artist + duration

Artist:
avatar/artwork + name + metadata

Album:
artwork + title + artist + year

Playlist:
artwork + title + owner + count

Do not render everything as the same card.

---

# 57. LIBRARY

Library should feel calm and organized.

Support:

- favorites
- history
- playlists
- artists
- downloads
- cached music
- local music
- albums
- songs

Use clear category switching.

Keep collection content grounded.

Glass should be used mostly for:

- category navigation
- filter controls
- compact actions
- persistent player

---

# 58. LIBRARY DENSITY

Library is more information-dense than Home.

Use:

- list rows
- compact artwork
- dividers
- grouped sections
- sorting
- filtering

Avoid large empty decorative areas.

But do not make it look like an admin dashboard.

---

# 59. PLAYLISTS

Support:

- create
- rename
- delete
- add track
- remove track
- reorder
- play
- play next
- download
- share where already supported

Provide optimistic UI for local changes where safe.

Persist changes transactionally.

---

# 60. ARTIST SCREEN

Artist screen has its own composition.

Possible hierarchy:

artist image
artist identity
actions
latest release
top songs
albums
featured-on
biography
similar artists

Do not reuse Home's layout.

Artist pages should feel informational.

---

# 61. ALBUM SCREEN

Album page:

artwork
title
artist
metadata
actions
track list

Track list should be grounded and highly readable.

Primary play action should be easy to reach.

---

# 62. TRACK / SONG ACTIONS

Create one reusable contextual action system.

Actions may include the existing MineMusic functionality such as:

- add to playlist
- play next
- add to queue
- favorite
- download
- open artist
- open album
- share
- song information
- other existing actions

Do not hardcode menu markup repeatedly.

Use semantic action descriptors.

---

# 63. BOTTOM SHEET SYSTEM

Create a central sheet coordinator.

Requirements:

- source-aware opening
- appropriate animation
- safe-area handling
- accessibility
- scrolling
- drag-to-dismiss where appropriate
- correct z-order above player/nav
- dismiss on route change where appropriate

Sheets should feel attached to the interaction that opened them.

---

# 64. OVERLAY MANAGEMENT

Create a predictable layer order:

system
↓
page background
↓
page content
↓
ambient effects
↓
persistent mini-player
↓
bottom navigation
↓
context overlay
↓
sheet
↓
toast/snackbar
↓
system dialog

Do not let random widgets insert themselves into arbitrary Stack positions.

---

# 65. SNACKBARS / FEEDBACK

Feedback should be quiet.

Use:

- subtle glass snackbar
- short duration
- readable message
- action only when useful

Do not overuse toasts.

Prefer inline state where possible.

---

# 66. LOADING STATES

Do not fill every surface with skeleton cards.

Choose loading strategy by task.

Small item:
small loader

Screen:
section-level skeleton

Full-player:
artwork-preserving loading

Lyrics:
preserve player context + loading indicator

Search:
inline loading state

Avoid distracting animations.

---

# 67. ERROR STATES

Every async surface needs:

loading
success
empty
error
retry

Do not leave users with:

- blank black screens
- infinite spinners
- dead buttons
- unhandled exceptions

Errors should be contextual.

Example:

Playback failure:
"Couldn't start this track"

with:

Retry

not a generic exception dump.

---

# 68. OFFLINE MODE

The app should degrade gracefully.

Define network states:

online
limited
offline
recovering

Offline content should remain usable.

Cached metadata and downloaded tracks should still appear.

Do not make the entire app unusable because one network request fails.

---

# 69. SMART CACHE

The reference app's smart caching is important.

Cache:

- metadata
- artwork
- low-res artwork
- high-res artwork where useful
- stream metadata where legal/appropriate
- downloaded audio/video
- lyrics
- recommendations when useful

Do not cache everything indefinitely.

Implement:

- cache size
- expiration
- eviction
- priority
- active download cancellation
- storage accounting

---

# 70. CACHE PRIORITIES

Example priority:

P0:
currently playing artwork/metadata

P1:
next queue items

P2:
visible library items

P3:
recently played

P4:
background recommendations

Never allow background prefetching to starve active playback.

---

# 71. DOWNLOAD SYSTEM

Downloads must be stateful.

Model:

queued
starting
downloading
paused
completed
failed
cancelled
deleted

Expose:

- progress
- speed if available
- remaining data if available
- error

Do not rely on a boolean `isDownloading`.

---

# 72. DOWNLOAD CONCURRENCY

Limit parallel downloads.

Do not start hundreds of downloads simultaneously.

Use a queue.

Pause lower-priority downloads when:

- playback is under pressure
- device is constrained
- connectivity changes
- storage is low

---

# 73. NETWORKING ARCHITECTURE

Use Dio as the primary networking client if compatible with MineMusic's current architecture.

Current v3.9 already uses Dio and http. Reduce unnecessary duplication. :contentReference[oaicite:13]{index=13}

Prefer:

ApiClient
 ├── interceptors
 ├── retries
 ├── auth if ever needed
 ├── connectivity awareness
 └── structured errors

Do not use raw `http.get()` all over the UI layer.

---

# 74. NETWORK RETRY POLICY

Retries should be selective.

Retry:

- transient network failures
- timeouts
- temporary 5xx

Do not retry:

- invalid request
- unsupported content
- permanent 4xx

Use exponential backoff.

Add jitter.

Cap retry count.

---

# 75. STREAM EXTRACTION

Streaming is a fragile subsystem.

The v3.9 reference already has a dedicated `StreamExtractionService` with a primary extractor and fallback strategy. Preserve the abstraction. :contentReference[oaicite:14]{index=14}

Do not move extraction logic into player widgets.

Create:

StreamResolver
 ├── primary source
 ├── secondary source
 ├── fallback
 ├── retry
 └── validation

Validate:

- URL
- mime type
- expiration
- bitrate
- duration
- availability

---

# 76. STREAM FAILURE HANDLING

If a stream fails:

1. determine whether URL expired
2. invalidate resolver cache
3. refresh source
4. retry
5. fallback to alternate source
6. notify UI only after recovery strategies fail

Do not instantly show an error on transient failures.

---

# 77. DATABASE / LOCAL STORAGE

The legacy Muzo snapshot uses Hive. :contentReference[oaicite:15]{index=15}

For MineMusic, evaluate whether a relational local database is more appropriate.

For a growing music application, `drift` is a strong candidate because it provides:

- relational queries
- transactions
- migrations
- reactive queries
- type-safe generated APIs
- isolate support

Current drift is 2.34.3. :contentReference[oaicite:16]{index=16}

Do not migrate purely for fashion.

If the current Hive implementation is small and stable, retain it.

If the application contains many relationships:

tracks
artists
albums
playlists
playlist_tracks
downloads
history
favorites
cache entries

then strongly consider Drift.

---

# 78. DATABASE MODEL

Think relationally.

Tables/entities could include:

Track
Artist
Album
Playlist
PlaylistTrack
Favorite
HistoryEntry
Download
CachedArtwork
Lyrics
QueueSnapshot
AppPreference
SearchHistory

Use stable IDs.

Never identify records using title alone.

---

# 79. TRANSACTIONS

Operations such as:

create playlist
+
insert tracks
+
update metadata

must be transactional.

Favorite mutations must be atomic.

Download metadata and state changes must remain consistent.

---

# 80. MIGRATIONS

If changing storage technology:

1. preserve legacy data
2. add migration
3. verify migrated row counts
4. verify foreign keys
5. verify playback references
6. verify favorites
7. verify playlists
8. only then remove old implementation

Never silently wipe user music data.

---

# 81. MODELS

Use immutable models.

Consider Freezed where it improves clarity.

Current Freezed 4.0.1 supports modern Dart 3.13 features, but verify compatibility before upgrading. :contentReference[oaicite:17]{index=17}

Use models with:

- stable equality
- copyWith
- exhaustive states
- serializability where needed

Avoid mutable DTOs leaking into presentation.

---

# 82. DATA / DOMAIN SEPARATION

Networking response models must not be used directly as UI state.

Flow:

API response
→ DTO
→ mapper
→ domain entity
→ UI state

This prevents external API shape changes from contaminating the UI.

---

# 83. FEATURE-SCOPED PROVIDERS

Example:

homeFeedProvider
searchControllerProvider
libraryProvider
playerControllerProvider
lyricsControllerProvider
queueProvider
artistProvider
albumProvider
playlistProvider
downloadManagerProvider

Avoid one giant AppProvider.

---

# 84. DEPENDENCY INJECTION

Use Riverpod providers as the dependency injection mechanism.

Services should receive dependencies.

Avoid:

final api = SomeApi();

inside random widgets.

Centralize construction.

---

# 85. DEPENDENCY RECOMMENDATION

Candidate stack:

Flutter + Dart

State:
flutter_riverpod

Audio:
just_audio
audio_service
audio_session

Glass:
liquid_glass_easy

Networking:
dio

Images:
cached_network_image
flutter_cache_manager

Persistence:
drift
drift_flutter
OR keep Hive if migration cost is unjustified

Models:
freezed
json_serializable

Navigation:
go_router

Animation:
flutter_animate where appropriate
Flutter's built-in AnimationController / TweenAnimationBuilder / AnimatedBuilder for custom physical interactions

Lyrics:
flutter_lyric if compatible
custom renderer for MineMusic-specific karaoke behavior

Video:
video_player where canvas/video playback is required

Icons:
choose ONE coherent icon family

Utilities:
path_provider
connectivity_plus
permission_handler
url_launcher
receive_sharing_intent where existing MineMusic functionality needs it
flutter_local_notifications where notifications are required

Do not add libraries merely because they are popular.

---

# 86. CURRENT BASELINE

The legacy v3.9 package manifest includes:

- flutter_riverpod
- cached_network_image
- google_fonts
- just_audio
- just_audio_background
- audio_session
- http
- hive
- hive_flutter
- path_provider
- dio
- permission_handler
- palette_generator
- receive_sharing_intent
- flutter_local_notifications
- font_awesome_flutter
- flutter_svg
- connectivity_plus
- sliding_up_panel
- audio_video_progress_bar
- ionicons
- fluentui_system_icons
- widget_marquee
- flutter_cache_manager
- scrollable_positioned_list
- window_manager
- muzoapi
- get
- audio_service
- url_launcher
- flutter_lyric
- dynamic_color
- flutter_animate

and related generators. :contentReference[oaicite:18]{index=18}

Audit every dependency.

For each dependency answer:

KEEP
UPGRADE
REPLACE
REMOVE

with justification.

Do not keep multiple libraries providing the same function.

---

# 87. STATE MANAGEMENT DUPLICATION

The legacy project contains Riverpod and also `get`. :contentReference[oaicite:19]{index=19}

Do not casually build a new architecture around both.

Choose one primary app state system.

Preferred:

Riverpod.

Remove redundant GetX-style state management unless a specific dependency requires it.

---

# 88. ICON SYSTEM

Choose one coherent icon family.

Do not mix:

Material icons
Cupertino icons
Font Awesome
Fluent
Ionicons

randomly.

The legacy snapshot uses several icon packages. :contentReference[oaicite:20]{index=20}

Refactor toward one dominant icon language plus carefully justified exceptions.

Icons must have:

- consistent optical weight
- similar geometry
- consistent stroke/fill behavior
- consistent sizing

---

# 89. TYPOGRAPHY SYSTEM

Create design tokens.

Define:

Display
Title
Section
Body
Label
Metadata
Caption

Use font weights deliberately.

Avoid:

- arbitrary font sizes everywhere
- too many families
- all-bold interfaces
- excessive uppercase text
- tiny unreadable metadata

Typography should establish hierarchy.

---

# 90. SPACING SYSTEM

Create a spacing scale.

Example concept:

4
8
12
16
20
24
28
32
40
48
64

Use the tokens consistently.

Do not invent:

13
17
19
23
27

unless there is a specific optical reason.

---

# 91. CORNER SYSTEM

Define semantic radii.

Example:

small
medium
large
sheet
pill
circle

Do not give every object the same 20px radius.

Different surfaces need different geometry.

---

# 92. DENSITY SYSTEM

Define screen-level density.

Home:
medium

Discover:
focused

Library:
dense

Settings:
compact

Player:
immersive

Lyrics:
spacious

Do not force one spacing system onto every screen.

---

# 93. CONTENT HIERARCHY

Every screen must answer:

What is the primary thing?

What should I do next?

What is secondary?

What is background information?

Do not give every component equal visual weight.

---

# 94. COLOR SYSTEM

Foundation:

near black
charcoal
graphite
warm dark neutrals

Text:

warm off-white

Secondary:

muted warm gray

Accent:

very restrained MineMusic accent

Artwork:

primary source of color variation

Never use:

neon purple
neon cyan
rainbow
RGB
holographic gradients

---

# 95. DARK THEME

Dark mode should not be "everything #000".

Use nuanced layers:

background
elevated background
surface
floating surface
glass
selected state

The difference should be perceptible but subtle.

---

# 96. ACCESSIBILITY

Every interactive element:

- sufficient hit target
- semantic label
- accessible state
- focus handling
- contrast

Liquid glass must never destroy readability.

When contrast drops:

increase local scrim
increase text contrast
increase surface density

Do not sacrifice accessibility for transparency.

---

# 97. REDUCED MOTION

Respect platform reduced-motion settings.

When reduced motion is enabled:

- eliminate large transforms
- shorten transitions
- reduce deformation
- disable decorative movement
- preserve usability

The material should still look good without animation.

---

# 98. RESPONSIVENESS

The primary target is phone portrait.

But architecture should not assume one fixed resolution.

Support:

- small phone
- normal phone
- large phone
- tablet
- desktop where MineMusic supports it

The current Muzo project itself has evolved toward large-screen/tablet layouts, so do not hardwire phone-only assumptions into the domain or data layers. :contentReference[oaicite:21]{index=21}

---

# 99. SAFE AREAS

All persistent UI must correctly account for:

- top status area
- bottom gesture area
- keyboard
- landscape
- notches
- cutouts
- desktop windows

Do not use arbitrary `MediaQuery` constants everywhere.

Create safe-area aware layout primitives.

---

# 100. KEYBOARD HANDLING

Search and forms must:

- resize correctly
- maintain focus
- avoid content being hidden
- preserve mini-player behavior
- dismiss keyboard intentionally

Do not manually offset screens with hardcoded keyboard heights.

---

# 101. PERFORMANCE TARGET

Target:

smooth 60 FPS as baseline

and higher where device/GPU allows.

Monitor:

- frame build time
- raster time
- image decode
- shader compile
- memory
- allocations
- scrolling performance

Glass shaders are expensive.

Never assume a visually impressive shader is acceptable if it destroys scrolling performance.

---

# 102. JANK HOTSPOTS

Pay particular attention to:

- Home scrolling
- image-heavy carousels
- mini-player appearance
- player expansion
- lyrics karaoke
- queue reorder
- search typing
- library filtering
- artwork palette extraction
- glass shader surfaces
- simultaneous background loading

---

# 103. IMAGE PERFORMANCE

Avoid rebuilding image widgets unnecessarily.

Use keys where needed.

Avoid:

ClipRRect
+
BackdropFilter
+
Shader
+
AnimatedContainer

stacked hundreds of times in a scrolling list.

Use rich glass only for visible interaction surfaces.

---

# 104. SHADER PERFORMANCE

For each shader:

- define fallback
- define low-power mode
- define disabled mode
- avoid unnecessary full-screen passes
- avoid overlapping expensive blur layers
- reuse shared resources where possible

A "Turn Off Fancy Graphics" equivalent can be considered for MineMusic if useful.

---

# 105. GLASS FALLBACK

If liquid-glass shader is unavailable, degraded, or too expensive:

fallback to:

transparency
+
controlled blur
+
soft highlight

The app must still function and look intentional.

Do not crash.

---

# 106. NO FULL-SCREEN GLASS

Do not apply liquid glass to:

- entire Home
- entire Library
- all cards
- every list row
- every section

Ground content first.

Glass belongs to interaction.

---

# 107. COMPONENT VARIETY

Use different content compositions.

Examples:

horizontal media rail
vertical track list
2-column recent grid
circular artist rail
large editorial feature
compact playlist row
hero player
queue list

This is required both for usability and Taste-Skill anti-repetition.

---

# 108. HOME EDITORIAL SYSTEM

Home sections should be data-driven.

Create:

HomeSection
(
  type
  title
  subtitle
  items
  presentation
)

Renderer chooses layout by section type.

Do not hardcode enormous widget trees.

---

# 109. DISCOVERY ENGINE

Keep discovery logic separate from rendering.

Discover provider returns:

DiscoverCard
(
  content
  source
  index
  reason
  artwork
)

Presentation handles:

- gesture
- animation
- actions

not data retrieval.

---

# 110. RECENT HISTORY

Every successful play should update history intelligently.

Avoid duplicate spam entries when a user repeatedly pauses/resumes.

Store:

- track ID
- timestamp
- completion ratio if useful
- playback context

---

# 111. RECOMMENDATION CONTEXT

Recommendations should be able to use:

- history
- favorites
- playlists
- current artist
- current track
- genre
- recency

But this logic belongs outside UI.

---

# 112. PLAYBACK PERSISTENCE

Persist enough state to restore:

- current track
- position where appropriate
- queue snapshot
- repeat mode
- shuffle mode

But never restore stale/invalid stream URLs blindly.

Resolve fresh stream sources when required.

---

# 113. APP LAUNCH

The reference emphasizes fast startup.

Do not block the first frame waiting for:

- entire library
- entire cache scan
- recommendation data
- artwork palette
- remote metadata

Launch strategy:

critical initialization
→ render
→ background warmup

Use parallel async initialization.

---

# 114. INITIALIZATION PRIORITIES

P0:

theme
routing
playback state
local storage availability

P1:

current track
library shell
recent history

P2:

Home feed
artwork
recommendations

P3:

background cache warmup

Never make P3 block P0.

---

# 115. DEEP LINKING

If MineMusic already supports deep links, preserve and centralize them.

Routes may map to:

song
artist
album
playlist

Validate IDs.

Do not create navigation directly from raw URL parsing in individual screens.

---

# 116. SHARE-TO-PLAY

If already supported:

shared URL
→ identify source
→ normalize URL
→ resolve content
→ open player/detail

Handle malformed URLs gracefully.

Do not open external browsers unnecessarily.

---

# 117. LOCAL FILES

If MineMusic supports local music:

scan asynchronously.

Maintain:

- permission state
- scan progress
- metadata
- artwork
- playback
- library indexing

Do not block startup while scanning.

---

# 118. VIDEO / CANVAS

If MineMusic supports video or canvas-like playback:

separate video rendering from audio playback state.

Use `video_player` or the existing MineMusic-compatible solution.

Current `video_player` supports modern Flutter and native mobile video surfaces. :contentReference[oaicite:22]{index=22}

Do not make video playback determine the entire app architecture.

---

# 119. SETTINGS

Settings should be grouped semantically.

Examples:

Playback
Downloads
Appearance
Lyrics
Streaming
Storage
Notifications
Advanced

Use dense but elegant list rows.

Do not convert settings into giant glass cards.

---

# 120. THEME SYSTEM

Create semantic theme roles:

background
surface
surfaceElevated
glass
textPrimary
textSecondary
divider
accent
danger
success
warning

Glass should consume theme tokens rather than hardcoded colors.

---

# 121. DYNAMIC THEME STATE

Theme state should depend on:

base theme
+
artwork environment
+
contrast mode
+
accessibility

The artwork should influence only the presentation layer.

Do not mutate global business state because an album changed color.

---

# 122. STATUS BAR

Status bar behavior should be computed.

Do not manually choose white icons on every screen.

Use background luminance / current surface to select appropriate system UI style.

When player becomes immersive:

status area should transition naturally.

---

# 123. HAPTICS

Use haptic feedback sparingly.

Good candidates:

play/pause
selection
drag threshold completion
favorite
important destructive action

Do not vibrate for every scroll.

---

# 124. ANIMATION TESTING

Every major animation must be evaluated at:

0%
25%
50%
75%
100%

Check:

- no jumping
- no snapping
- no flicker
- no clipping
- no z-order glitches
- no text reflow surprises
- no gesture dead zones

---

# 125. SCREEN TRANSITION MATRIX

Document transitions explicitly.

Examples:

Home → Player
Player expansion

Home → Library
shell content replacement

Track → Artist
detail route

Track → Album
detail route

MiniPlayer → Player
shared spatial expansion

Context menu → action
sheet dismissal + action

Search → result
content continuity

Do not leave transition behavior implicit.

---

# 126. Z-ORDER RULES

Define explicit z-order.

Example:

0 background
10 content
20 local overlays
30 mini-player
40 navigation
50 transient controls
60 sheets
70 dialogs
80 global notifications

Avoid ad hoc `Positioned` stacking without a clear layer system.

---

# 127. ERROR BOUNDARIES

Each major feature should have error isolation.

An artwork failure should not crash the track list.

A lyrics parser failure should not stop audio.

A recommendation API failure should not blank Home.

A cache failure should not prevent playback.

---

# 128. OBSERVABILITY

Add structured logs.

Categories:

network
playback
cache
downloads
lyrics
navigation
glass
performance

Avoid noisy `print()` spam.

Do not log sensitive user data.

---

# 129. DEBUG PANEL

For development builds, provide optional diagnostics:

- current track
- player state
- queue length
- cache state
- network state
- active glass tier
- shader status
- frame/render diagnostics where available

Never expose this in production unless intentionally enabled.

---

# 130. TESTING STRATEGY

Tests required:

unit
widget
integration

Unit:

- playback state
- queue transitions
- repository logic
- cache
- mapping
- search debounce
- lyrics synchronization
- download state

Widget:

- mini-player
- glass controls
- navigation selection
- search
- track rows
- library filters

Integration:

- launch
- play track
- pause
- seek
- skip
- queue
- navigation
- search
- offline playback
- deep link where applicable

---

# 131. GOLDEN / VISUAL TESTING

Create representative golden states for:

Home
Library
Discover
Player
Queue
Lyrics
Search

Also test:

- no artwork
- low contrast artwork
- very bright artwork
- very dark artwork
- long track title
- long artist name
- empty library
- many queue items
- loading
- error
- offline

---

# 132. VISUAL QA CHECKLIST

For each screen inspect:

Hierarchy
Spacing
Alignment
Artwork crop
Typography
Icon geometry
Glass opacity
Refraction
Reflection
Surface separation
Contrast
Touch target
Safe-area behavior
Animation
Scrolling
Loading
Empty state
Error state

---

# 133. RESPONSIVE QA

Test at least:

small Android phone
normal Android phone
large Android phone
iPhone-sized viewport
tablet
desktop window if supported

Do not accept:

overflow
clipping
text collision
buttons becoming unreachable
glass extending beyond safe bounds

---

# 134. DATA RACE PREVENTION

Guard against:

search request A returning after B

old artwork palette replacing new artwork state

old playback event arriving after next track

download cancellation racing completion

queue reorder racing track change

lyrics timing continuing after track change

Use request IDs / generation counters / cancellation where necessary.

---

# 135. RESOURCE LIFECYCLE

Dispose:

- AnimationController
- ScrollController
- VideoPlayerController
- StreamSubscription
- TextEditingController
- FocusNode
- shader resources where required
- image/cache listeners

Do not leak controllers through navigation.

---

# 136. SCROLL ARCHITECTURE

Avoid nested unconstrained scroll views.

Prefer:

CustomScrollView
SliverList
SliverGrid
SliverToBoxAdapter

where screen architecture benefits from it.

Do not build giant lists eagerly.

---

# 137. HOME DATA LOADING

Load sections independently.

A failed "artists you may like" section must not prevent:

Top Picks
Recently Played
Library actions

from rendering.

---

# 138. SEARCH DATA LOADING

Search results should be stream/cancellable.

Do not wait for all result categories if the architecture can progressively show useful results.

But don't cause visual instability by endlessly reshuffling content.

---

# 139. LIBRARY DATA LOADING

Library should prioritize local data first.

Render immediately from local storage.

Then refresh remote-derived metadata if applicable.

This makes the app feel instant.

---

# 140. OPTIMISTIC INTERACTIONS

Good candidates:

favorite
playlist add/remove
queue insertion
download request

Update UI immediately when safe.

Rollback on failure.

Show subtle feedback.

---

# 141. CONTENT PLACEHOLDERS

Do not use generic gray skeleton rectangles everywhere.

Prefer content-aware placeholders.

Artwork:
dark tonal placeholder

Track:
subtle line placeholder

Large hero:
tonal image placeholder

Glass control:
quiet placeholder shape

---

# 142. NO AI-SLOP RULES

Absolutely reject:

- generic purple/blue gradient
- giant glowing CTA
- excessive cards
- identical rounded rectangles
- excessive pill controls
- glass applied indiscriminately
- huge text without hierarchy reason
- arbitrary decorative blobs
- floating fake 3D objects
- neon outlines
- glowing icons
- random motion
- repeated section templates
- excessive drop shadows
- visually noisy metadata
- meaningless badges

---

# 143. DESIGN REVIEW GATE

Before calling any screen complete, ask:

What is the primary visual focus?

Why is this element glass?

Why is this element not glass?

What is moving?

Why is it moving?

What does the user understand from that motion?

Could this animation be removed?

Could this visual layer be removed?

Would the design still work without the effect?

If yes, decide whether the effect is still justified.

---

# 144. MATERIAL REVIEW GATE

For every glass surface:

Can I see something behind it?

Is that background subtly different because of the glass?

Can I perceive thickness?

Does the edge catch environmental light?

Is the reflection localized?

Is distortion controlled?

Is the surface too opaque?

Is the surface too blurry?

Does it still look correct against dark artwork?

Does it still look correct against bright artwork?

---

# 145. LIQUID GLASS ANTI-SLOP CHECK

If the glass looks like:

blurred rectangle
+
white border
+
shadow

FAIL.

If it looks like:

physical surface
+
controlled transmission
+
localized optical displacement
+
subtle reflection
+
clear hierarchy

PASS.

---

# 146. MOTION ANTI-SLOP CHECK

If animation is:

fade in
fade out
slide in
slide out

for every component:

FAIL.

Use different motion according to object semantics.

Navigation:
settle

Glass selection:
fluid displacement

Player:
expansion

Sheet:
spring

Track:
content continuity

Lyrics:
progressive movement

Gesture:
direct manipulation

---

# 147. SCREEN-SPECIFIC COMPOSITION RULES

HOME:

editorial
personal
expansive
varied density

DISCOVER:

focused
immersive
gesture-centric

LIBRARY:

organized
calm
dense

PLAYER:

immersive
emotion-led

LYRICS:

typographic
rhythmic

SEARCH:

functional
fast
dense

QUEUE:

information-heavy

ARTIST:

editorial/informational

ALBUM:

content-first

---

# 148. REFERENCE-DRIVEN SPACING

Do not make all surfaces edge-to-edge.

Use breathing room around:

- hero artwork
- section starts
- controls
- player
- navigation

Use tighter spacing in:

- queue
- search results
- library rows
- settings

---

# 149. ARTWORK CROP RULES

Always choose intentional crop.

Hero:
preserve subject

square:
center-safe crop

artist:
face-aware crop

album:
full cover

background:
cover with controlled focal point

Do not blindly use `BoxFit.cover` everywhere.

---

# 150. TEXT TRUNCATION

Long titles must never break the layout.

Use:

- maxLines
- ellipsis
- marquee only where useful

Do not use marquee for every track title.

Marquee should communicate that text exceeds the available width, not become decorative motion.

---

# 151. PLAYER METADATA

Track title:
dominant

Artist:
secondary

album / source:
tertiary

Do not overload player with metadata.

---

# 152. SEARCH RESULT PRIORITY

Result categories should be obvious.

Do not make the user guess whether an item is:

artist
album
song
playlist

Use visual language rather than excessive textual labels.

---

# 153. EMPTY STATES

Empty states should be useful.

Examples:

No favorites:
invite discovery

No history:
explain what will appear here

No downloads:
offer relevant action

No playlists:
create playlist

No lyrics:
clearly explain unavailable state

Avoid giant illustrations unless MineMusic already uses them.

---

# 154. OFFLINE EMPTY STATES

Offline content should clearly communicate why something is unavailable.

Do not say:

"Something went wrong"

when the actual issue is:

"Not available offline"

---

# 155. DOWNLOAD UI

Download actions must make state visible:

not downloaded
queued
downloading
downloaded
error

Do not make the icon jump between arbitrary colors.

Use subtle material state changes.

---

# 156. FAVORITE UI

Favorite interaction:

unselected
→ pressed
→ selected

Use icon morph + subtle material feedback.

Do not add a giant heart animation unless intentionally justified.

---

# 157. QUEUE DRAG UI

While dragging:

- row lifts slightly
- background separation increases
- shadow/elevation changes minimally
- surrounding rows shift
- drop location becomes apparent

Do not make the entire row transform excessively.

---

# 158. SHEET PHYSICS

Sheets should:

- originate naturally
- have drag resistance
- snap to meaningful positions
- dismiss with velocity
- respect safe areas

Avoid rigid modal behavior everywhere.

---

# 159. MODAL PRIORITY

Use the least disruptive overlay that solves the task.

Inline:
simple feedback

popover:
small action

bottom sheet:
contextual action set

dialog:
confirmation / critical interaction

full screen:
major dedicated task

Do not open a full modal for a small action.

---

# 160. APP LIFECYCLE

Handle:

resume
pause
background
termination
audio interruption
network reconnection
headphone disconnect
Bluetooth route changes

Playback should not unexpectedly stop or duplicate.

---

# 161. AUDIO INTERRUPTIONS

Support:

phone calls
other audio apps
audio focus loss
temporary ducking
resume behavior

Do not hardcode platform behavior into widgets.

---

# 162. NOTIFICATION / MEDIA SESSION

Playback metadata should remain accurate:

title
artist
album
artwork
duration

Buttons:

play
pause
previous
next

where supported.

---

# 163. BATTERY

Avoid:

constant timers
high-frequency rebuilds
unnecessary shader animation
continuous artwork analysis

Especially avoid permanent animations when music is paused and the UI is idle.

---

# 164. MEMORY

Monitor:

large artwork
video textures
lyrics caches
queue size
image cache
database queries

Avoid retaining full-size artwork for every track simultaneously.

---

# 165. NETWORK BANDWIDTH

Do not repeatedly request:

same artwork
same metadata
same lyrics

Deduplicate requests.

Prefetch intentionally.

---

# 166. REQUEST DEDUPLICATION

Repository layer should collapse identical simultaneous requests.

Example:

5 widgets request same album
→ one network request
→ shared result

Not:

5 duplicate HTTP calls.

---

# 167. CACHE INVALIDATION

Define invalidation rules.

Example:

track metadata:
long-lived

stream URL:
short-lived

artwork:
long-lived

lyrics:
long-lived

recommendation:
short-lived

Never treat everything as permanent cache.

---

# 168. SECURITY

Do not hardcode API secrets.

Do not log private paths unnecessarily.

Do not expose debug endpoints in production.

Validate externally supplied URLs.

---

# 169. PLATFORM FILE HANDLING

Downloads must use platform-safe directories.

Use path_provider where appropriate.

Handle:

storage unavailable
permission denied
file removed externally
partial download

---

# 170. BUILD CONFIGURATION

Separate:

debug
profile
release

Environment configuration should be clean.

Do not embed secrets in source.

---

# 171. CODE QUALITY

Require:

flutter analyze
dart format

No analyzer warnings casually ignored.

No TODO placeholders pretending implementation is complete.

No giant methods.

No duplicated UI trees.

No magic numbers scattered through screens.

---

# 172. FILE SIZE DISCIPLINE

If a Dart file becomes enormous:

split it.

Widgets should generally have one clear responsibility.

Avoid 700–1000 line screens unless there is a very good reason.

The historical v3.9 source already demonstrates oversized screens/widgets such as a large Home screen and main layout, which makes this a useful refactor target. :contentReference[oaicite:23]{index=23}

---

# 173. WIDGET RESPONSIBILITY

A widget should generally:

receive state
render state
emit user intent

It should not:

query APIs
write database rows
resolve streams
manage global audio
parse lyrics
change navigation architecture

---

# 174. REPOSITORY RESPONSIBILITY

Repository:

fetch
cache
map
persist

Provider/controller:

coordinate state

Widget:

render

This separation is mandatory.

---

# 175. DOMAIN USE CASES

Where complexity is justified, use cases such as:

PlayTrack
ToggleFavorite
AddToPlaylist
DownloadTrack
SearchMusic
LoadLyrics
ResolveStream
BuildQueue
UpdateHistory

Do not create meaningless abstraction layers for trivial code.

---

# 176. ERROR TYPES

Use typed errors:

NetworkError
PlaybackError
StreamResolutionError
CacheError
DatabaseError
LyricsError
DownloadError

UI maps them to friendly messages.

---

# 177. ASYNC STATE

Prefer explicit state.

Example:

AsyncValue
or

sealed state:

Idle
Loading
Success
Error

Avoid nullable soup:

data == null
loading == true
error == null
etc.

---

# 178. DESIGN TOKEN LOCATION

Create one source of truth:

design/tokens/

Do not define:

padding
radius
text style
glass opacity

inside random screens.

---

# 179. GLASS DESIGN TOKEN EXAMPLE

Create semantic materials:

glassNavigation
glassMiniPlayer
glassControl
glassSheet
glassFloatingButton
glassSelected
glassDisabled

Each material may have:

fill
blur
distortion
refraction
border
specular
shadow
tint

---

# 180. OPTICAL CONTRAST

Glass must adapt to underlying content.

If underlying artwork is bright:

reduce glass transparency
increase text contrast

If underlying artwork is dark:

allow more transmission

If highly saturated:

reduce tint

This creates more consistent readability.

---

# 181. CONTRAST-AWARE ICONS

Icons should adapt to local luminance.

Do not globally make all icons white regardless of background.

But do not constantly flicker between black/white.

Use smoothed transitions.

---

# 182. MATERIAL TRANSITIONS

When track artwork changes:

Do not immediately snap glass colors.

Interpolate environment.

Example:

previous palette
→ blend
→ new palette

over a restrained duration.

---

# 183. GLASS INTERACTION WITH ARTWORK

When glass overlaps artwork:

artwork should remain recognizable

but:

- slightly distorted
- slightly softened
- optically shifted

Do not make artwork unreadable.

---

# 184. BACKDROP DISTORTION

Distortion should be strongest near:

curved edges
pressed regions
selected regions
highly curved controls

and weakest in the center.

This creates a more convincing lens.

---

# 185. CHROMATIC DISPERSION

Only tiny amounts.

Use only where appropriate.

It must read as optical behavior.

Never as:

RGB
rainbow
neon fringe

---

# 186. LIGHT DIRECTION

Choose an ambient lighting direction.

Keep it consistent across surfaces.

Highlights should not randomly appear from opposite directions on neighboring components.

---

# 187. SURFACE THICKNESS

Different materials should have different visual thickness.

Navigation:
thin

mini-player:
medium

sheet:
medium/thick

primary interactive lens:
thicker

This gives spatial hierarchy.

---

# 188. ELEVATION MODEL

Do not rely on drop shadows alone.

Depth should come primarily from:

transparency
blur
optical distortion
sharpness contrast
edge definition
reflection
layer separation

Shadow should be supplementary.

---

# 189. CONTENT DEPTH

Foreground controls should be clearer than background content.

Example:

background:
soft

artwork:
sharp

glass:
semi-transparent
optically active

controls:
sharp

This creates believable spatial hierarchy.

---

# 190. NO UNIFORM GLASS

Every glass surface should not look identical.

Variation should be intentional.

Different semantic surfaces:
different optical response.

---

# 191. DISCOVERY CARD MATERIAL

If the discovery screen uses a large primary interaction card:

make it physically substantial.

It can have:

- stronger optical thickness
- stronger localized refraction
- more internal reflection

But do not make it a generic frosted rectangle.

---

# 192. PLAYER CONTROL MATERIAL

Circular play/pause control:

- slightly denser glass
- stronger specular
- physical press
- spring release

Secondary controls:

lighter material.

This creates hierarchy.

---

# 193. NAVIGATION MATERIAL

Bottom nav:

- broad translucent surface
- subtle internal lighting
- low distortion
- localized selected-state deformation

Do not over-distort the entire bar.

---

# 194. GLASS SEARCH

Search control can use glass.

But once keyboard is active:

prioritize readability and input responsiveness over visual theatrics.

---

# 195. LIBRARY FILTERS

Filter/category control can be glass.

Selected state:
local material response

Unselected:
clear but subdued

Avoid multiple glowing pills.

---

# 196. HOME CAROUSELS

Use deliberate peek behavior.

Show enough of the next card to communicate horizontal scrollability.

Do not center every item so perfectly that the user sees no continuation.

---

# 197. CAROUSEL PHYSICS

Use native scroll physics.

Avoid custom physics unless needed.

Card snapping can be subtle.

Do not over-animate each card.

---

# 198. LARGE HERO TRANSITIONS

Hero artwork to full player should preserve identity.

Use shared artwork identity.

Avoid a completely different background appearing abruptly.

---

# 199. PLAYER / LYRICS TRANSITION

Lyrics should feel like a state of the player.

Not a disconnected page.

Possible transition:

artwork lowers
lyrics rise
controls reposition
background remains related

---

# 200. SEARCH / NAVIGATION TRANSITION

Search should open quickly.

Do not use a long cinematic animation for basic utility.

---

# 201. LIBRARY / DETAIL TRANSITIONS

When opening album/playlist:

title/content should move naturally.

Use hero image continuity where worth the complexity.

---

# 202. MOBILE INPUT TARGETS

Target at least comfortable mobile interaction sizes.

Do not make small translucent icons impossible to hit.

Visual size can be small while hit area remains larger.

---

# 203. SCROLLBAR / OVERSCROLL

Use platform-appropriate behavior.

Do not customize unnecessarily.

---

# 204. DESKTOP / TABLET ADAPTATION

Where supported:

phone:
bottom navigation

tablet/desktop:
consider side/top navigation or more spacious shell

Do not scale the phone UI linearly to a 13-inch screen.

---

# 205. RESPONSIVE GLASS

Glass distortion amount may need to adapt to screen size.

Small screen:
lower effect complexity

Large screen:
can use richer material

Performance remains the priority.

---

# 206. ANIMATION INTERRUPTION

Animations must be interruptible.

Example:

user starts opening player
→ immediately swipes back

The system should reverse cleanly.

Avoid animation state traps.

---

# 207. GESTURE / ROUTE CONFLICTS

Explicitly resolve:

horizontal player swipe vs page horizontal scroll

vertical volume gesture vs lyrics scrolling

bottom navigation tap vs swipe-to-dismiss

sheet drag vs internal scroll

Use gesture arenas carefully.

---

# 208. ACCESSIBLE MOTION

When reduced motion:

preserve state change
remove decorative physics

When high contrast:

increase surface separation

When text scale increases:

prevent clipping.

---

# 209. INTERNATIONALIZATION

The historical project supports many languages. :contentReference[oaicite:24]{index=24}

MineMusic should keep text externalized.

Do not hardcode strings in widgets.

Test:

long translations
RTL
mixed scripts

---

# 210. DATE / DURATION FORMATTING

Centralize:

song duration
time remaining
history timestamps
download sizes

Do not duplicate formatting logic.

---

# 211. TRACK TITLE EDGE CASES

Test:

very long title
emoji
CJK
RTL
explicit markers
missing artist
missing album
empty metadata

UI must degrade gracefully.

---

# 212. ARTIST EDGE CASES

Missing image:
use deliberate fallback

Long artist name:
truncate gracefully

Multiple artists:
render readable joining

---

# 213. QUEUE EDGE CASES

Test:

one item
two items
empty queue
current item removed
reorder current item
skip while loading
skip rapidly multiple times
duplicate tracks

---

# 214. PLAYBACK EDGE CASES

Test:

play immediately after app launch

pause during loading

skip during buffering

seek before duration known

track ends while screen is backgrounded

network disconnect mid-track

network returns

stream source expires

---

# 215. DOWNLOAD EDGE CASES

Test:

download while playing
download offline
storage full
permission denied
cancel during network failure
file partially exists
duplicate download

---

# 216. LYRICS EDGE CASES

Test:

no lyrics
unsynced lyrics
partially synced
word timings missing
language mismatch
very long lyrics
rapid track switching

---

# 217. SEARCH EDGE CASES

Test:

empty query
single character
rapid typing
same query twice
offline
server failure
slow response
keyboard open
switching categories rapidly

---

# 218. CACHE EDGE CASES

Test:

corrupt image
deleted file
expired stream
cache exceeds limit
low storage
app restart during download

---

# 219. SOFTWARE VERSION STRATEGY

Do not blindly retain the old Flutter/Dart baseline from the historical snapshot.

The current stable Flutter line in 2026 has moved forward substantially; Flutter 3.47 was released in August 2026, while Dart 3.13 is the current documented stable line. :contentReference[oaicite:25]{index=25}

Start by evaluating:

Flutter stable
+
Dart stable
+
all package constraints

Then choose the latest stable combination that does not create unnecessary migration risk.

Do not upgrade 30 dependencies simultaneously without validation.

Prefer staged upgrades.

---

# 220. DEPENDENCY MIGRATION ORDER

Recommended:

1. Flutter/Dart baseline
2. Riverpod
3. audio stack
4. networking
5. persistence
6. models/codegen
7. navigation
8. glass rendering
9. auxiliary UI dependencies

Run:

flutter analyze
flutter test

after each major group.

---

# 221. DEPENDENCY CLEANUP

After the audit:

remove unused packages

remove duplicate responsibilities

remove dead transitive workarounds

remove obsolete UI packages

Do not add:

three animation libraries
three icon libraries
two state-management systems
two HTTP clients
two routing systems

unless there is a documented reason.

---

# 222. CURRENT PACKAGE EXAMPLES

Potential current versions worth evaluating:

liquid_glass_easy 4.2.0
just_audio 0.10.6
audio_service 0.18.19
flutter_riverpod 3.4.2
go_router 18.0.0
freezed 4.0.1
drift 2.34.3

These are examples from the current 2026 ecosystem, not blind mandates. Verify compatibility with MineMusic's actual Flutter/Dart target before committing. :contentReference[oaicite:26]{index=26}

---

# 223. ANIMATION LIBRARY POLICY

Flutter's own animation system should remain the foundation.

Use flutter_animate for concise compositions where useful.

Do not route every simple animation through a third-party abstraction.

Complex physical interaction should use direct animation primitives where that provides greater control.

---

# 224. VIDEO POLICY

Do not rebuild video controllers during ordinary rebuilds.

Keep lifecycle in a dedicated controller/provider.

---

# 225. IMAGE POLICY

Do not rebuild expensive image providers unnecessarily.

Use stable keys and caching.

---

# 226. PALETTE POLICY

Palette extraction should happen asynchronously.

Never block frame rendering.

Cache derived colors.

Do not recompute on every rebuild.

---

# 227. GLOBAL BACKGROUND REFACTOR

The v3.9 GlobalBackground is extremely simple: it primarily wraps content with an animated scaffold-colored background. :contentReference[oaicite:27]{index=27}

MineMusic should make this a real environment layer.

Potential:

AppBackdrop
 ├── base color
 ├── artwork ambient color
 ├── gradient stabilization
 ├── blur
 └── optional low-frequency movement

But keep the background mostly stable.

---

# 228. BACKGROUND MOTION

Use near-static atmosphere.

If any movement exists:

very slow
low amplitude
non-distracting

Do not turn the Home screen into animated wallpaper.

---

# 229. GLOBAL EFFECT BUDGET

Set a strict maximum effect budget.

For example:

Home:
1 rich glass region
2–4 subtle glass regions

Library:
mostly subtle

Discover:
1 primary rich surface
few controls

Player:
richer glass allowed

Lyrics:
minimal

This avoids GPU overload and visual clutter.

---

# 230. VISUAL DENSITY BUDGET

Home:
5/10

Discover:
4/10

Library:
7/10

Player:
3/10

Lyrics:
3/10

Search:
7/10

Queue:
8/10

Settings:
6/10

Tune per screen.

---

# 231. MOTION BUDGET

Home:
5/10

Discover:
8/10

Library:
4/10

Player:
7/10

Lyrics:
8/10

Search:
3/10

Settings:
2/10

Motion intensity follows interaction importance.

---

# 232. DESIGN VARIANCE

Home:
7/10

Discover:
8/10

Library:
4/10

Search:
3/10

Player:
5/10

Do not force asymmetric layouts where they harm usability.

---

# 233. REFACTOR STRATEGY

Do not rewrite everything in one commit.

Use vertical slices.

Suggested order:

Phase 1:
architecture audit

Phase 2:
design tokens

Phase 3:
application shell

Phase 4:
glass system

Phase 5:
player subsystem

Phase 6:
Home

Phase 7:
Discover

Phase 8:
Library

Phase 9:
Search

Phase 10:
Lyrics

Phase 11:
Queue

Phase 12:
Artist/Album/Playlist

Phase 13:
downloads/cache

Phase 14:
performance

Phase 15:
visual QA

---

# 234. PHASE 1 — AUDIT

Produce:

architecture map
dependency map
state map
navigation map
playback map
persistence map
performance hotspots
UI duplication map
risk register

Do not code yet.

---

# 235. PHASE 2 — DESIGN SYSTEM

Implement:

tokens
theme
type
spacing
radii
motion
icons
glass materials

Do not redesign business flows yet.

---

# 236. PHASE 3 — APP SHELL

Implement:

router
persistent player
navigation
overlay layer
safe areas
global background

Validate before proceeding.

---

# 237. PHASE 4 — PLAYER

Make player behavior solid before polishing every other screen.

Playback correctness comes first.

---

# 238. PHASE 5 — GLASS

Implement and benchmark:

navigation
mini-player
control buttons
sheets

Then decide whether rich glass can safely be used elsewhere.

---

# 239. PHASE 6 — HOME

Refactor into reusable section renderers.

Validate scrolling and image performance.

---

# 240. PHASE 7 — DISCOVER

Implement gesture-driven discovery.

Validate gesture conflicts.

---

# 241. PHASE 8 — LIBRARY

Refactor around local data and efficient queries.

---

# 242. PHASE 9 — SEARCH

Implement real async search with request cancellation.

---

# 243. PHASE 10 — LYRICS

Implement high-frequency updates separately from page state.

---

# 244. PHASE 11 — DETAILS

Artist
Album
Playlist
History

Reuse domain models, not UI markup.

---

# 245. PHASE 12 — CACHE / DOWNLOADS

Optimize background tasks.

---

# 246. PHASE 13 — PERFORMANCE

Profile:

scroll
player
lyrics
glass
artwork
search

---

# 247. PHASE 14 — FINAL VISUAL PASS

Use Taste-Skill pre-flight.

Remove:

repetition
slop
unnecessary decoration
unnecessary text
redundant cards
random animations
weak hierarchy

---

# 248. DO NOT OVERFIT TO SCREENSHOTS

The recording is a behavioral reference.

Implement responsive logic.

Do not:

hardcode screenshot coordinates
hardcode exact viewport dimensions
use hundreds of pixel-position hacks
build static scenes

Use:

constraints
flex
slivers
responsive breakpoints
intrinsic sizing
semantic tokens

---

# 249. DO NOT SACRIFICE REAL DATA FOR VISUALS

All UI should work against real MineMusic data.

No fake:

tracks
artists
albums
queue
search results

except isolated development fixtures/tests.

---

# 250. NO PLACEHOLDER CODE

Do not write:

TODO implement
coming soon
dummy callback
fake repository
empty method
placeholder animation

unless explicitly marked as a non-production scaffold and documented.

The final implementation must be complete.

---

# 251. PRE-FLIGHT BEFORE DECLARING SUCCESS

Run:

flutter pub get
dart format .
flutter analyze
flutter test

Then run the application in profile/release-like mode.

Test:

- launch
- Home
- Discover
- Library
- Search
- Player
- Lyrics
- Queue
- Artist
- Album
- Playlist
- Downloads
- offline states
- playback background
- navigation
- rotation where supported
- keyboard
- accessibility

---

# 252. VISUAL ACCEPTANCE CRITERIA

The application should feel:

quiet
premium
physical
tactile
dark
editorial
responsive
high-end

Glass must feel:

transparent
thick
optical
slightly fluid
reflective
refractive
context-sensitive

It must NOT feel:

neon
sci-fi
holographic
plastic
gel
smoke
liquid metal
generic frosted glass

---

# 253. FINAL MATERIAL TEST

Place each major glass surface over:

1. black background
2. bright artwork
3. dark artwork
4. detailed artwork
5. flat artwork

Confirm that:

- translucency remains visible
- refraction remains controlled
- text remains readable
- highlight remains neutral
- surface remains believable

---

# 254. FINAL INTERACTION TEST

Confirm:

tap
double-tap
long press
horizontal swipe
vertical swipe
drag
scroll
sheet drag
queue reorder
seek
volume gesture
player expansion
navigation selection

all coexist without gesture conflicts.

---

# 255. FINAL QUALITY TEST

Ask:

Does this still look premium without the glass?

Does the glass improve the interaction?

Does the animation communicate state?

Can I identify the primary action immediately?

Does the screen have a focal point?

Is there enough negative space?

Is any component repeated unnecessarily?

Is any card merely decorative?

Is any gradient meaningless?

Is any glow unnecessary?

If yes:
remove it.

---

# 256. FINAL DELIVERABLE

Do not merely return code.

At completion provide:

1. architecture changes
2. dependency changes
3. files created
4. files refactored
5. files removed
6. major design-system additions
7. glass-material architecture
8. animation architecture
9. playback architecture
10. cache architecture
11. persistence changes
12. navigation changes
13. performance improvements
14. known limitations
15. remaining technical debt
16. test coverage added
17. visual QA findings
18. commands used for validation

---

# 257. MOST IMPORTANT PHILOSOPHY

The final result should NOT look like:

"AI made a futuristic music app."

It should look like:

"a real premium music product that happens to have exceptionally good material design."

The interface should communicate quality through:

composition
spacing
typography
content hierarchy
motion
optical depth
touch feedback
material realism

not through:

glow
neon
gradients
ornament
random animation

---

# 258. FINAL IMPLEMENTATION PRIORITY

When tradeoffs occur, prioritize in this order:

1. correctness
2. playback reliability
3. usability
4. hierarchy
5. interaction quality
6. performance
7. material realism
8. responsiveness
9. typography
10. visual polish
11. decorative detail

Never reverse this order.

---

# 259. ABSOLUTE DO-NOT-BREAK RULES

Never break:

- playback
- queue integrity
- downloaded data
- local library
- favorites
- history
- playlists
- lyrics synchronization
- deep-link behavior already supported
- offline functionality
- background playback
- accessibility

while refactoring visuals.

---

# 260. FINAL OUTPUT STANDARD

The finished MineMusic application must feel like:

A mature, production-ready Flutter music client with a sophisticated dark visual system, a carefully engineered liquid-glass interaction layer, responsive gesture-driven playback, fast local-first content, robust background audio, high-quality lyrics, intelligent caching, and a cohesive visual language.

Do not ship a concept.

Ship the product.

USE ANY SKILLS YOU LIKE ALONG WITH CLAUDE-SUPERPOWERS,PONYTAIL,TASTE-SKILL AND IMPECCABLE
