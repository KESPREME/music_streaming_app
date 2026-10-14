# Plan: Now Playing / Queue heat and battery

Status: PLAN ONLY. Nothing here is implemented. Every impact estimate comes from reading the code, not from a measurement. Phase 0 exists to check them.

Hard rules for every phase:
- The UI looks the same and every feature keeps working.
- Synced-lyric motion is untouched (frame rate, curves, wave).
- Gates: `flutter analyze --no-pub` reports 186 issues or fewer. All tests pass. `flutter build apk --debug` succeeds. The device scenarios from Phase 0 are re-run and show no regression.
- One phase is one small commit (`perf(player): …`), made only when approved.

## 1. Root cause

The app renders with Impeller, which is the Android default on Flutter 3.47 with a GLES fallback. Impeller has no raster cache, so every frame redraws the whole scene ([flutter#166184](https://github.com/flutter/flutter/issues/166184)). A BackdropFilter also costs a full offscreen pass on every frame, whether or not it repainted ([flutter#27677](https://github.com/flutter/flutter/issues/27677)). Several comments in the code assume that a `RepaintBoundary` "rasterises once". That holds on Skia only. On Impeller it saves Dart paint time and no GPU time.

Heat is therefore roughly frames per second multiplied by the GPU cost of one frame.

Frames per second: while Now Playing is open and a word-synced song is playing, the deck `LyricStrip` holds the vsync ticker for most of the song. That is 60 fps, or 120 fps on 120 Hz panels. Each of the following adds more frames:
- the scrubber `StreamBuilder` (about 5 Hz)
- the queue's `AnimatedEqualizerIcon` (`repeat()`, full refresh rate)
- the canvas video (about 30 fps)
- anything still animating underneath the player

Cost of one frame, everything that is redrawn every time:
- **Underneath the opaque player card, all still painted:**
  - The whole page under it: Home or Explore, with its images.
  - The glass tab bar.
  - The mini pill, a live `LiquidGlassLens` with blur 16, refraction, and a position `StreamBuilder`.
  - If the player was opened from Explore, that tab stays `TickerMode`-enabled. Its mesh drift, vinyl spin, equalizer and canvas video keep running under an opaque card. Gating comes from `main.dart:554-562` and `global_music_overlay.dart:349,362`.
- **The Now Playing backdrop:**
  - Full-screen `ImageFiltered(blur 60)` of a 1.6× scaled 800 px image (`now_playing_screen.dart:813-829`).
  - With canvas on, another full-screen `blur 55` over live video (`:833-879`).
  - Two full-screen radial gradients and two linear scrims (`:896-981`).
- **On the main page and in the queue:**
  - The hero `ShaderMask` saveLayer (`:1302-1345`). It is an identity mask whenever `t ≥ 0.05`.
  - The deck's glass pill lens (`liquid_glass_pill.dart:115-150`).
- **With the lyrics panel open:** one `saveLayer` plus a blur per visible inactive row (`lyric_line.dart:800-833`).

The audio side is not the main driver. Position ticks do not call `notifyListeners` (`music_provider.dart:1545`). There is no per-tick I/O, no wakelock and no display-mode forcing. There are still a few real costs, covered in Phase 7.

## 2. Phases, in order of expected value

### Phase 0: baseline and instrumentation (no behaviour change)
- Add `lib/utils/frame_probe.dart`. It is debug and profile only, behind `PerfTrace`, and uses `SchedulerBinding.addTimingsCallback`. Every 5 s it logs fps, p50 and p90 build ms, and p50 and p90 raster ms. It is a no-op in release.
- Device scenarios: 10 min each, fixed brightness, Wi-Fi, same song and position.
  - S1: main page, word-synced song.
  - S2: main page, line-synced song.
  - S3: queue page.
  - S4: lyrics panel open.
  - S5: player opened from the Explore tab.
  - S6: screen off.
  - S7: canvas on.
- Record for each scenario:
  - fps and raster ms from the probe
  - `adb shell top -H -p <pid>`: CPU for the `1.ui`, `1.raster`, ExoPlayer and `io` threads
  - `adb shell dumpsys thermalservice`: skin, CPU and GPU temperatures at the start and at 10 min
  - `adb shell dumpsys batterystats <pkg>`, after `--reset`, over wireless adb so USB charging does not skew the numbers
  - `adb shell dumpsys media.audio_flinger`: whether offload is active
- The results decide whether Phases 5, 6 and 8 run at all.

### Phase 1: stop rendering what the player covers (largest win, low risk)
- New `CoveredGate` widget (`lib/widgets/covered_gate.dart`):
  - It sets `TickerMode(enabled: !covered)`.
  - It wraps a `RenderProxyBox` that skips `paint` and `hitTest` while covered.
  - **Layout is untouched.** `liquid_glass_nav_bar.dart:63-73` documents why the bar must never re-layout during the flight. This gate never changes its constraints.
- `covered` becomes true only when the panel is at rest and fully open (`_panelController.value == 1 && !isAnimating`). It does not follow `isPlayerExpanded`, which flips mid-flight.
- `covered` drops on the first drag or close frame, in the same frame. The page's retained layer is reused, so un-covering costs no Dart repaint.
- Apply it in `global_music_overlay.dart` to `widget.child` (the page, which also hosts the tab bar and its pill accessory) and to `_buildMiniPlayer`.
- Explore: also fold `covered` into the `isActive` it receives, so its feed videos pause. First check what `isActive` gates in `explore_screen.dart:698`.
- Mini pill: `StreamBuilder(stream: covered ? null : positionStream)`.
- Tests:
  - Open the panel to rest: a ticker under the page reads muted, and a counting `CustomPaint` under the page stops painting.
  - Begin a drag: the page paints in that same frame.
  - A layout counter on the tab bar stays unchanged across open and close.
  - The existing overlay and back tests stay green.

### Phase 2: bake the blurred backdrop once per track
- New `lib/services/backdrop/blurred_backdrop_cache.dart`:
  - It draws the artwork with BoxFit.cover into a `PictureRecorder` at ¼ of the screen's physical size, through `saveLayer(Paint()..imageFilter = blur(60/4·dpr-adjusted))`.
  - It produces the result with `picture.toImage`.
  - LRU of 3, about 0.6 MB each.
- In `now_playing_screen.dart:813-829`:
  - Replace the live `ImageFiltered` with `RawImage(fit: fill, filterQuality: medium)` under the same `Transform.scale(1.6, topCenter)`.
  - Until the bake is ready, keep showing the previous baked image, or the current live blur on a cold start. There is never an empty frame.
  - Copy the existing image fade-in exactly. First read the fade durations in `_buildAlbumArtImage` (`:2386`).
- Apply the same change to the standalone queue backdrop (`queue_screen.dart:66-87`, blur 65, scale 1.25).
- Local files: decode with `cacheWidth` as well. Today they decode at full resolution in `:2393`. Move `File.existsSync` out of build and memoise it per track.
- Tests:
  - A pixel-parity test with the real-font and real-image probe setup used before. Render the live blur and the baked image at dpr 3 and require a mean absolute difference of 1/255 or less and a maximum of 4/255.
  - A track-change test: no frame without a backdrop.
  - A cache-eviction test.

### Phase 3: cheaper hero artwork
- Add `_GatedShaderMask`, a `RenderProxyBox` that pushes `ShaderMaskLayer` only while the mask is not the identity, meaning `t < 0.05`. The element tree stays the same, so the image never re-mounts. This removes one hero-size offscreen pass per frame whenever the lyrics or the queue header is showing.
- Optional, depending on Phase 0 S1: at `t == 0` the bottom fade is needed. The mask can be baked into the hero image once per track, using the Phase 2 bake path, and the live mask kept only during the morph.
- Tests: the gated and ungated versions paint identical pixels at `t` values of 0, 0.04, 0.05, 0.5 and 1.

### Phase 4: fewer frames, no visible change
- Scrubber (`now_playing_screen.dart:1552`): rebuild only when the slider's physical pixel or the displayed second changes, using a distinct-by `(px, sec)` stream. The output is identical, and long mixes save the most. Hoist the two `GoogleFonts` styles to `static final`.
- `LyricStrip`: attach the clock listener only when there are lyrics to resolve, not while loading or when none were found.
- `LyricClock` and `LyricClockFeed`: implement `WidgetsBindingObserver`. When the app is not `resumed`, stop the 100 ms coarse timer, because `Timer.periodic` is not muted by the scheduler. Re-anchor on resume through the existing restart path. Tests: no timer fires while paused, and the position is correct after resume.
- `AnimatedEqualizerIcon`:
  - Replace the three rebuilding `Container`s with one `CustomPainter` driven by `repaint: controller`, inside a `RepaintBoundary`. It keeps the same curve and 900 ms period.
  - It already stops on pause. Add a `TickerMode` gate for when the queue page is not on screen.
  - **Decision needed:** keep it at the full refresh rate, which is the default in this plan, or step it at 30 fps, which would halve the queue's idle frames but is a slight visual difference.
- `QueueScreen` (`:52`): replace the listening `Provider.of` with a `Selector` over the fields it reads: the queue lists, the current id, `isPlaying` and the palette. This avoids rebuilding every row on unrelated notifications.

### Phase 5: lyrics panel inactive rows (only if S4 raster is still high after Phases 1–4)
- In `RenderLyricLine`, when a row is stable (not active, not animating, and with constant sigma, alpha and text), cache its blurred `saveLayer` output once with `toImageSync` and draw the image on later frames. Invalidate the cache on any change to text, size, sigma, alpha, dpr or style. It never applies to the active row or while sigma is tweening.
- Tests:
  - Pixel parity between the cached and direct paths, with the same tolerance as Phase 2.
  - Invalidation on each input.
  - No cache use while animating.
  - All existing `lyric_*` tests pass.

### Phase 6: canvas video (opt-in feature, only if S7 is still hot)
- Check that the hero `InPlaceCanvasPlayer` and the backdrop `VideoPlayer` share one decoder in `CanvasVideoManager`.
- Pause the video when the app is not resumed and when the player is covered by a sheet.
- Give the video blur its own `RepaintBoundary`. This saves Dart paint time only.
- Any change to how the video blur looks needs a decision from you first.

### Phase 7: audio and network (small, independent changes)
- `audio_service.dart:192-201`: the `AndroidLoudnessEnhancer` in the pipeline is a fresh instance that nothing references, so it can never be enabled. Remove it from the pipeline so offload is not blocked by an attached effect, then confirm offload with `dumpsys media.audio_flinger` in S6. This changes nothing you can hear.
  - Separate finding, not changed here: `EqualizerService` toggles `_audioService.equalizer`, which is not in the pipeline unless `enableEqualizer: true`. This needs checking as a possible EQ no-op bug, as its own task.
- `_extendWindowFrom` (`music_provider.dart:3002`): resolve the first upcoming track immediately and the remaining three one at a time afterwards, instead of four parallel resolves on every track change. The final window and gapless behaviour stay the same, with fewer simultaneous radio and CPU bursts. Tests: window contents and order are identical, and a superseded track cancels the chain.
- `JustAudioBackground.init` (`main.dart:97`): add `artDownscaleWidth/Height: 512`, so the notification does not decode full-size artwork once per track.
- Explicit non-changes, with reasons:
  - `maxBufferDuration 15 min` stays. Downloading the song in one burst and then letting the radio sleep (race to idle) beats trickling.
  - `LockCachingAudioSource` stays for now, because offline replay and start latency depend on it. If S1 shows meaningful `1.ui` CPU during the download burst, moving the byte proxy off the UI isolate becomes its own plan.

### Phase 8: optional 60 Hz cap (needs your decision)
- On 120 Hz panels, ask for 60 Hz while the player is open at rest and restore the system default on close. This would use a `MethodChannel` on the existing `mine_music/audio_output` channel in `MainActivity` that sets `window.attributes.preferredDisplayModeId`.
- This roughly halves GPU work during word sweeps, and the sweep still looks smooth at 60 fps. Scrolling inside the queue would be at 60 Hz.
- It ships behind a setting. The default is your call.

## 3. Rejected
- Lowering blur sigma, removing glass, or simplifying gradients: these change the UI.
- Throttling the lyric sweep's frame rate: it would undo the motion work.
- Adding more `RepaintBoundary`s as the fix: there is no raster cache on Impeller, so they help Dart only.
- Shrinking the ExoPlayer buffer or `_windowUpcoming`: this means more radio wake-ups and risks gapless playback and lock-screen next.
- Disabling Impeller: Skia's raster cache would hide the static blur, but this trades one engine's problems for another's and is not a fix.

## 4. Order and risk
Phase 0, then 1, then 2, then 4, then 3, then 7. Phases 5, 6 and 8 run only if the measurements call for them.

Phases 1 and 2 should remove most of the per-frame cost. Phase 4 removes idle frame sources. The highest-risk code is Phase 5 (painter cache) and Phase 1 (paint gate around the overlay). Both are covered by parity and interaction tests before they reach the device.

## 5. Implementation log

Gates at the end of this pass: `flutter analyze --no-pub` 186 issues (the baseline), 1545 tests passing (63 new), `flutter build apk --debug` builds. Nothing here is measured on a device; Phase 0's probe exists so that you can.

### Done

| Phase | What shipped | Where |
| --- | --- | --- |
| 0 | `PERF_WINDOW` rolling line (fps, build and raster p50/p90) every 5 s, in the existing `PerfTrace`. Run with `flutter build apk --profile --dart-define=PERF_TRACE=true`. | `lib/core/perf_trace.dart` |
| 1 | `PanelCover` + `CoveredGate` + `CoveredScope`. The page and the floating mini are neither painted nor animated once the player has been fully open and still for 250 ms; they return in the first frame the panel moves. Layout is never touched. The mini pill unsubscribes from the position stream; Explore's canvas video and the album header video pause while covered. | `lib/widgets/covered_gate.dart`, `global_music_overlay.dart`, `mini_player.dart`, `explore_feed_card.dart`, `album_detail_screen.dart` |
| 2 | The Now Playing wash and the standalone queue wash are baked once per track and drawn as one image. Local artwork for queue rows is decoded at thumbnail size. | `lib/widgets/blurred_backdrop.dart`, `now_playing_screen.dart`, `queue_screen.dart` |
| 4 | Equalizer icon is a painter in its own layer. The scrubber has its own layer and a hoisted style. The seek-bar strip listens to the lyric clock only with timed lyrics. The lyric clock stops while the app is backgrounded. | `animated_equalizer_icon.dart`, `now_playing_screen.dart`, `lyric_strip.dart`, `lyric_clock_feed.dart` |
| 7 | The unused loudness enhancer left the audio pipeline. The player window fills one resolve at a time. | `audio_service.dart`, `lib/services/window_filler.dart`, `music_provider.dart` |

### Decisions on the two open questions
- **Equalizer icon rate:** full refresh rate. At 16 dp the saving from 30 fps is small, and stepped bars are a visible downgrade. The icon now costs a repaint of its own layer per frame instead of a build, a layout and a paint.
- **60 Hz cap (Phase 8):** not done. It trades the smoothness of every lyric sweep for GPU time, which is the opposite of the brief. Phases 1 and 2 remove far more per-frame work without touching the frame rate. It remains available if Phase 0 shows the device still running hot.

### Changed from the plan, and why
- **Phase 3 (gated hero mask) dropped.** The hero's mask is the identity from `t = 0.05`, but by then the hero is a 46 dp thumbnail (queue, lyrics): the pass it would save is tiny. At rest on the main page the mask is needed. A baked mask is a possible follow-up, only if S1 shows hero raster time.
- **Queue `Selector` dropped.** The queue reads about a dozen provider fields and several lists that are mutated in place, so a selector's equality would have to copy them. Provider notifications happen a handful of times per track, never per tick, so the rebuilds it would save are small, and a missed field would show a stale queue.
- **Scrubber "distinct pixel" stream dropped.** At about 5 position events a second, a normal song moves the slider more than a pixel per event, so a distinct stream removes nothing. The real cost was the layer it repainted into, which now has its own boundary.
- **Notification artwork downscale dropped.** `artDownscaleWidth/Height` sets an exact size, so non-square thumbnails would be distorted and small ones upscaled. The saving is one decode per track.
- **Phase 5 (cached lyric rows) and Phase 6 (canvas video blur) not started.** Both are only justified by a measurement the device has to supply (S4 and S7), and Phase 5 carries the highest regression risk in this plan.

### Not changed, found on the way
- `EqualizerService` toggles `audioService.equalizer`, which is not in the pipeline unless `enableEqualizer: true`. The equalizer settings are probably a no-op today. It was switched off deliberately because the native effect made playback throw on some OEM builds, so enabling it is a product decision, not a perf one.

### What to run on the phone
1. Build with the probe and run S1 to S7 from Phase 0. For each, watch `PERF_WINDOW`: **fps** is the number to compare with the previous build; raster p50 is second.
2. Behaviour to look at by eye (all should look exactly as before):
   - Open the player, wait a second, close it: the page and tab bar are back at once, with no flash or rebuild.
   - Open the player from the Explore tab with a canvas video playing: the video pauses behind it and resumes on close.
   - Change track: the background cross-fades to the new colours with no empty frame.
   - Queue page: the equalizer bars animate as before; drag-reorder and swipe-to-delete still work.
   - Lock the phone with lyrics open, unlock after a minute: the lyric lands on the right line at once.
   - Skip through several tracks quickly: the next track still starts, and the lock-screen next button still works.
