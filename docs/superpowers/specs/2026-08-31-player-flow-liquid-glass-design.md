# Player Flow Liquid Glass Design

Date: 2026-08-31  
Status: Approved direction; implementation pending written-spec review

## Context

The app already has a package-backed liquid-glass foundation in `GlassSurface`,
centralized values in `GlassTokens`, a Glass/Material You theme split, and a
working playback provider. The next pass targets the player flow because it is
the most frequently used interaction surface and still contains several legacy
blur, gradient, glow, and duplicated control recipes.

The current app screenshots remain the behavioral and information-architecture
baseline. The six Muzo screenshots are references for restraint, hierarchy,
material depth, and interaction choreography only. No Muzo layout, branding,
copy, colors, icons, or typography is copied.

## Goals

- Make Glass-theme playback surfaces feel like one coherent physical material.
- Preserve every existing playback action and provider contract.
- Keep Material You visuals and behavior unchanged.
- Remove the Glass branch's colored ambient globs, excessive glow, and ad-hoc
  `BackdropFilter` implementations.
- Keep the player usable on portrait phones, with safe-area handling, clear
  targets, explicit state feedback, and reduced-motion support.

## Non-goals

- No changes to stream resolution, InnerTube, Saavn, PO-token, authentication,
  downloads, persistence, recommendation logic, or queue algorithms.
- No new backend, network, or mock-data work.
- No replacement of the Material You branch.
- No global glass treatment for grounded content.
- No new Muzo-inspired features such as QR actions unless an existing app
  feature already provides them.
- Existing `MusicProvider` public APIs remain unchanged. A narrow internal
  error-policy guard is allowed for direct queue-row playback so queue contents
  remain intact and the existing snackbar path can surface failures; normal
  playback retains its current auto-failover behavior.

## Chosen Approach

Use a shared playback shell with separate theme interiors. `GlobalMusicOverlay`
continues to own the expanded/minimized player state and nested player
navigation. `ThemedNowPlayingScreen`, `ThemedQueueScreen`, and existing themed
sheet selectors continue choosing the active visual branch. Only Glass-theme
surfaces are migrated in this pass; Material You files remain regression
baselines.

The Glass branch uses `GlassSurface` and `GlassTokens` as its only reusable
material primitives. Existing provider methods remain the action boundary.

## Surface Design

### Global Overlay

- Keep one overlay above app content and keep the existing nested player
  navigator so lyrics, queue, and detail routes retain back behavior.
- Keep tap-to-expand, upward drag-to-expand, downward drag-to-minimize, and
  system-back priority handling.
- Animate the panel with interruptible transform/opacity motion where possible;
  do not rebuild the whole app for position ticks.
- Keep the mini-player hidden while a modal sheet is open and restore it in a
  `finally` path.

### Mini-player

- Use one `GlassSurface` floating pill above bottom navigation.
- Preserve album art, title, artist, progress, play/pause, tap-to-expand,
  horizontal swipe previous/next, and error visibility.
- Use dark optical depth and a thin edge highlight. Accent is limited to the
  progress indicator and selected state; no colored shadow halo.
- Keep artwork loading cached and isolate the progress repaint.

### Glass Now Playing

- Replace animated colored globs and the full-screen accent gradient with the
  current artwork as a subdued, blurred backdrop under a flat charcoal/black
  scrim. Artwork is atmosphere, not a colored UI surface.
- Keep the compact header: minimize, `NOW PLAYING`, lyrics, and options.
- Keep the album-art Hero, title/artist, artist navigation, like, download,
  seekable progress, shuffle, previous, play/pause, next, repeat, cast, queue,
  and sleep-timer actions.
- Use `chrome`/`floating` glass for header and control affordances, with the
  primary play control visually elevated but not glowing.
- Keep album art rounded and elevated with a black optical shadow only.
- Keep title and artist readable over the scrim; artist remains tappable.

### Queue

- Keep the Glass queue as a grounded dark list with restrained selected-row
  ink/border treatment, not a stack of translucent cards.
- Preserve reorder, swipe-to-remove, clear confirmation, empty state, and
  options-sheet access.
- Make tapping a queue row play that track through the existing
  `MusicProvider.playTrack` boundary without clearing the queue.
- Keep the Material You queue untouched.

### Lyrics and Sheets

- Keep lyric fetching, timed highlighting, auto-scroll, tap-to-seek, retry, and
  manual-scroll behavior unchanged.
- Refactor the Glass lyrics header and `GlassPlaybackBar` to use the same
  material tokens as the player, with no second blur recipe.
- Use `GlassSurface` `sheet` for Glass options, download selection, playlist
  selection, artist picker, and sleep-timer surfaces.
- Preserve all existing options: like, queue, play next, playlist, download,
  artist/album navigation, share, context removal, equalizer, and sleep timer.
- Keep snackbars transient and compact, with black depth and restrained white
  content rather than accent-filled backgrounds.

## Material System

Use `liquid_glass_widgets: ^1.2.1` through `GlassSurface`:

- `card`: minimal, cheap glass only where a surface is genuinely elevated.
- `chrome`: interactive controls and compact player chrome.
- `floating`: mini-player and prominent floating controls.
- `sheet`: modal/transient surfaces.

Use existing token groups for blur, thickness, refraction, Fresnel, edge
absorption, chromatic aberration, radii, opacity, and shadows. Add no isolated
numeric recipes in migrated Glass files. Accent remains localized to icons,
progress, selected controls, and small ink diffusion.

The Glass player must not introduce gradients, neon/RGB treatment, large
colored halos, or nested full-screen blur. Grounded content stays solid and
near-black/charcoal.

## Data and Error Handling

- Read playback state from existing `MusicProvider` properties and streams.
- Invoke existing methods for playback, seek, queue, like, download, cast,
  lyrics, and settings actions.
- Surface provider playback errors through existing inline/snackbar mechanisms;
  never silently hide a failed track.
- When `playTrack` is called for a queue row with
  `setContext: false, clearQueue: false`, preserve the queue on validation or
  playback failure, set the existing provider error, and rethrow so the caller
  can show its mounted-safe snackbar. Other `playTrack` calls keep existing
  error handling and auto-failover behavior. Internal auto-advance delegates
  retain their existing behavior and are not treated as queue-row calls.
- Keep modal visibility changes exception-safe so `hideMiniPlayer` cannot remain
  stuck after a dismissed or failed sheet.

## Accessibility and Performance

- Maintain at least 48dp effective touch targets and add semantic labels/tooltips
  to icon-only controls.
- Respect `MediaQuery.disableAnimations`/reduced-motion conditions by removing
  panel travel, squish, and waveform phase motion while retaining state changes.
- Avoid continuous repaint when playback is paused; isolate artwork, progress,
  and shader-heavy surfaces with repaint boundaries where useful.
- Keep content readable against artwork and preserve system-bar/safe-area
  insets.

## Verification

- Existing Flutter tests remain green; add focused widget coverage for player
  expansion/minimization, queue actions, and key Glass control states where the
  current test harness supports it.
- Run `dart analyze` and resolve analyzer errors in touched Glass files.
- Run `flutter test`.
- Run `flutter build apk --debug`.
- When the Android device reconnects, manually verify mini-player expand,
  minimize, seek, play/pause, previous/next, shuffle/repeat, queue reorder and
  play, lyrics, options, download selection, sleep timer, and system back in
  both theme branches.

## Initial File Scope

- `lib/widgets/global_music_overlay.dart`
- `lib/widgets/mini_player.dart`
- `lib/now_playing_screen.dart`
- `lib/screens/queue_screen.dart`
- `lib/widgets/glass_playback_bar.dart`
- `lib/screens/lyrics_screen.dart`
- `lib/widgets/glass_options_sheet.dart`
- `lib/widgets/glass_download_selection_sheet.dart`
- `lib/widgets/playlist_selection_dialog.dart`
- `lib/widgets/artist_picker_sheet.dart`
- `lib/widgets/glass_snackbar.dart`
- `lib/widgets/wavy_progress_bar.dart`
- `lib/widgets/glass_surface.dart` and `lib/theme/glass_tokens.dart` only when
  required to support the above surfaces without changing their public intent.
