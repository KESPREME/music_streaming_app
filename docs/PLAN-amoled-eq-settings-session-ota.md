# Plan: pure-black glass, a real equalizer, a rebuilt Settings, a session that survives, and OTA updates

Written before any code. Each phase is one commit. Gates for every phase:
`flutter analyze --no-pub` <= 186 (last 180), targeted tests green, full suite green at the
end, `flutter build apk --debug --no-pub` builds. No device is attached, so anything that
needs a GPU, an audio route or the system installer is listed under "Unproven" at the end.

## 0. What the two screenshots show (read, not guessed)

Screenshot A (idle, Home scrolled so nothing is under the bar):
* Behind the Home pill and the Search pill there is **flat #000**. Nothing to refract, yet the
  pills show a hard vertical split, a magenta streak and nested "D" contours.
  => the defect is not "content under the glass sampled badly". It is the glass pipeline itself.

Screenshot B (scrolling, bar and mini player over a list):
* Horizontal smears, a black rectangle cut out of the right of the bar, white blobs, mirrored
  text on top of the mini player ("Tame Impala" upside down), garbled tab labels.
* The list text seen through both the bar (blur 24) and the mini player (blur 16) is **sharp**.
  A working blur would have erased it. So the blur layer is not doing its job on this device.
* Everything built with the standard / minimal tier in the same screenshots (profile disc,
  play disc, the For-you card, cards) is clean.

Code facts (context-gatherer, verified against lgw 1.8.1 and liquid_glass_easy 4.3.4):
* Bar and pills: `GlassTabBar` at `GlassQuality.premium` (package default, no `quality:` passed,
  no adaptive scope). Premium = geometry matte + mirror-tiled blur + `ImageFilter.shader`
  refraction whose taps are not clamped. The package itself says premium "may not render
  correctly in scrollable contexts"; this app already moved its detail chrome to `standard` for
  that reason (`detail_glass.dart`).
* Mini player: `LiquidGlassLens` (easy) with the Impeller shader path, clamp-to-edge UVs.
* Pure black changes only the pixels behind; no glass parameter reads `AmoledTheme`. It is an
  amplifier: black + white text + saturated accent makes every sampling error maximal, and the
  shader's content-adaptive maths raises saturation ~1.2x on a black backdrop.

Root cause (ranked): (1) premium multi-pass pipeline over a scrolling body on this GPU;
(2) lens shader window/clamp on the mini player; (3) driver specifics (unverifiable here).

Fix, and why it is the right shape rather than a patch:
* On pure black there is nothing for refraction to show except scrolling content. The correct
  material there is dark frosted glass with a crisp specular rim - what Apple Music, Spotify
  and every OLED-first UI use. So pure black gets the **frosted** tier (`standard`), which
  needs only a plain `BackdropFilter` + a lightweight shader that this device already renders
  correctly elsewhere.
* A pure function `ChromeGlassSpec.resolve(amoled:, rendering:)` decides tiers and settings, so
  the decision is unit-tested instead of buried in a widget.
* An escape hatch in Settings > Appearance: **Glass rendering: Auto / Refraction / Frosted**.
  Auto = Frosted on pure black, Refraction otherwise (today's look, untouched). Any future
  device-specific shader fault is one tap, not a release.
* Mini player: `LiquidGlassStyle.liteGlass` (per-lens opt-in; frost + tint + rim, no shader)
  when the spec says frosted.
* Not done: dithering (no evidence banding is involved; the artefacts are geometric).

## 1. Session persistence ("the app resets almost every time")

Findings: nothing about playback is persisted (queue, track, position, shuffle context);
UI state is all in-memory; the foreground service ends on every pause
(`androidStopForegroundOnPause` default, `START_NOT_STICKY`), so a paused app is cheap for
Android to kill; back from Home **finishes the activity**; `_initialize()` awaits three
network fetches before the cached Home feed is published, so even a warm cache looks like a
reset on a slow network.

Design:
* `SessionSnapshot` (pure model, versioned JSON) + `SessionStore` (shared_preferences, atomic
  write, size-capped, corrupt data discarded, never throws).
* Recorded by `MusicProvider` through one hook (`notifyListeners` signature diff, 1.5 s
  debounce) + a 5 s position tick while playing + immediate flush on pause / background /
  detach. No scattered call sites.
* Restored in `_initialize()` right after settings: current track, context list (+ shuffle
  order), user queue, position, shuffle/repeat. **Never auto-plays.** Mini player appears
  instantly. Pressing play loads the source and seeks to the saved position (the existing
  "stopped-but-loaded" branch of `resumeTrack` already re-enters `playTrack`; a pending seek
  is applied after it).
* UI session: selected tab, Library filter + sort. Deliberately NOT restored: pushed detail
  stacks, scroll offsets, search text (Spotify/Apple/YTM cold-start at tab roots too).
* Back on the Home root now **moves the task to the background** (`moveTaskToBack`) instead of
  finishing the activity, like Spotify/YTM: coming back is instant and exact.
* Home publishes its cached feed **before** awaiting the legacy network loads.
* Settings: "Remember what I was playing" (default on). Logout clears the snapshot.
* More `configChanges` on the activity (colorMode, navigation, touchscreen).

## 2. Equalizer (audiophile-grade, honest about the hardware)

Today: non-functional (pipeline empty; the public equalizer is a different instance than the
pipeline's; refuses to enable). `just_audio`'s `AndroidEqualizer` must be constructed with the
player and throws out of `play()` on OEMs without the effect, hence the existing guard.

Design:
* **Native engine** (`EqualizerChannel.java`, `mine_music/equalizer`) over
  `android.media.audiofx`: `Equalizer`, `BassBoost`, `Virtualizer`, `LoudnessEnhancer`, each
  created in its own try/catch per audio session id. Failure => capability false, playback
  untouched. Effects are attached **only while the EQ is on** (an attached effect defeats the
  low-power audio-offload path the player requests), and released on off.
* Sessions: both decks (crossfade). `AudioService` reports each deck's
  `androidAudioSessionId`; the engine keeps effects per session id and re-applies on change.
* **Honest bands**: the UI shows the device's real bands (count, centre frequencies, range) and
  draws a smooth log-frequency response curve through them. Presets are defined as
  frequency/gain control points and resampled onto whatever bands exist.
* Audiophile features: master on/off; hold-to-compare bypass (A/B); pre-amp; auto headroom
  (prevents digital clipping when boosting); loudness boost (LoudnessEnhancer); bass boost;
  virtualizer / spatial widening; ~20 curated presets + user presets (save, rename, delete);
  per-output profiles (speaker / wired / Bluetooth) applied automatically on route change;
  reset; capability card ("Android DSP - 5 bands - +-15 dB").
* UI: an interactive glass graph (draggable nodes on the live curve, haptic detent at 0 dB,
  value bubble, double-tap resets a node), preset carousel with mini curve thumbnails, effect
  cards, accent from the playing album. Entry points: Settings and the Now Playing sheet.
* Persistence: one JSON key `eq_state_v2`, migrating `eq_enabled` / `eq_preset` /
  `eq_custom_gains`. The legacy `EqualizerService` API (used by the Material You screen,
  which must stay untouched) and `equalizer_platform_guard_test` keep passing.

## 3. Settings, rebuilt

Contract kept (pinned by tests): `settingsSearchEntries` public const; first `TextField` is
the search field; "Pure black (AMOLED)" row (exact subtitles, switch in the nearest Row, whole
row toggles once, toggled semantics); lyric group gate ids; keyword rules for 'loudness'.

Design: a glass hub with a collapsing large title, pinned search, staggered entrance,
Jelly press on every row, tinted category chips with live one-line summaries.
Order: profile hero -> **Software update** banner (only when one exists) -> Sound card
(Equalizer with mini curve + Transitions) -> Appearance (theme, pure black, glass rendering,
accent, font, weight) -> Playback (auto queue, **remember session**, offline, low data) ->
Quality & data (segmented selectors instead of dialogs) -> Storage (cache size, downloads,
clear) -> Lyrics & artwork -> About (real version/build, Software update, source, made-by).
Every row is registered in the search index. Real version from the platform, not a literal.

## 4. OTA updates + CI/CD

Reference: BitChord polls `releases/latest`, picks the APK by name, streams it to cache,
installs through a FileProvider intent. It has no checksum, no images, and its CI never makes
a release. We add all three.

Client (`lib/services/update/`): `UpdateService` (ChangeNotifier) with states
idle / checking / upToDate / available / downloading / verifying / ready / installing / failed;
`UpdateRepository` (GitHub API, ETag, 6 h throttle, offline-tolerant, prefers the
`update.json` manifest asset, falls back to the release body); `ReleaseNotes` parser (sections,
banner + gallery images, no markdown dependency); semver + build comparison; resumable dio
download; SHA-256 verified before install; stale files swept on start; skip-this-version.
Native: `mine_music/app` channel (version, ABIs, can-install, open install settings, install
APK via FileProvider, move-to-back). UI: Apple-style "Software Update" screen (hero, release
notes, image gallery, morphing Download -> progress ring -> Install), a once-per-version
prompt sheet, a dot on the avatar, and a post-update "What's new" sheet.

CI/CD (`.github/workflows`): `ci.yml` (analyze + test on every push/PR);
`release.yml` (push to master/main or `v*` tag): version from pubspec, build number from the
run, sign with repo secrets (fails loudly without them rather than shipping a debug-signed APK
that cannot update), build, SHA-256, `update.json`, banner + screenshots, notes from
conventional commits (or a hand-written `release/notes/<version>.md`), GitHub Release.
`android/app/build.gradle.kts` reads `key.properties` or env vars and falls back to debug
locally. `tools/release/*` generate notes/manifest and are unit-tested here.
One-time caveat, documented: installs signed with the old debug key can only update if CI is
given that same key (`tools/release/setup-signing.ps1` exports it); otherwise one reinstall.

## 5. Phases

P1 glass spec + setting  - P2 session  - P3 equalizer engine+UI  - P4 update client+native+UI
P5 settings rebuild  - P6 CI/CD + tools + docs.

## 6. Unproven without a device (will be said again in the report)

Whether the frosted tier looks right on your GPU; the audio effects actually attaching on your
phone and on Bluetooth; the system installer hand-off; the GitHub workflow end to end (YAML is
parsed and the tools are run locally, but Actions has not run).

## 7. Outcome

Everything above shipped, one commit per phase, with the full suite at 2,930 tests green, the
analyzer at 179 issues (baseline 180) and a debug APK building. Additions beyond the plan, found
while building:

* **Home published its cache after three network awaits** (`_initialize`), which on a slow
  connection looked exactly like the app having forgotten everything. It now publishes first.
* **Two APKs per release** (universal ~105 MB measured, plus arm64-only), because a 105 MB OTA is a
  bad update. The app chooses by CPU; both share a versionCode (a `--split-per-abi` build would have
  offset it and broken the update comparison).
* **A CI-to-app contract test** that runs the real release tool and feeds its output to the real
  client. It already caught one real mismatch class (UTF-8 bodies) while being written.
* A local signed release build was proven end to end with a throwaway keystore and the same
  environment variables CI uses; the guard that refuses to build unsigned in CI was proven to fail.
* The Windows release build flakes with "Permission denied" on Gradle intermediates when a previous
  build was interrupted (`gradlew --stop`, delete `build/app/intermediates`, retry). Linux CI is clean.

Still unproven (needs a device or GitHub): how the frosted tier looks on your GPU; the audio effects
attaching and the Bluetooth/wired profile switch; the system installer hand-off; the workflow running
on Actions. Nothing here was run on hardware.
