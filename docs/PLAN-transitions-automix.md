# Plan: Song Transitions — Crossfade and AutoMix

Status: PLAN ONLY. Nothing is implemented.

Every claim below is tagged:
- **[code]**: read in this repo or in a dependency's source in the pub cache.
- **[doc]**: from an official or press source, linked.
- **[assume]**: unverified. Each assumption has a Phase 0 spike that settles it before anything is built on it.

---

## 0. Summary

- **Two decoders are required.** A real crossfade has both songs audible at once, and one ExoPlayer or AVQueuePlayer renders one item at a time. Fading one player out and back in only leaves a dip of silence. **[code]** just_audio's maintainer has stated that crossfade won't be a just_audio feature until the platform supports it ([just_audio#815](https://github.com/ryanheise/just_audio/issues/815)). Media3 also has none ([androidx/media#2](https://github.com/androidx/media/issues/2)). So the app has to own two players. **[doc]**
- **The current stack cannot host two players.** `just_audio_background` supports only one `AudioPlayer` and throws when a second one initialises (`just_audio_background.dart:130-131`, README line 3). **[code]** The first piece of work is therefore moving to `audio_service` (already in the lock file, 0.18.18, transitive) with our own `AudioHandler`. That handler owns two just_audio decks.
- **Architecture:** we keep just_audio, ExoPlayer, the cache, the window model and MusicProvider's queue decisions. On top of them we add a Dart `TransitionEngine` that drives a `DeckPair`. AutoMix analysis comes from a small native analyser plugin (Kotlin first, Swift later). DJ effects (filters, bass swap, echo) need DSP inside each player's audio path. just_audio has no hook for that (its Android `RenderersFactory` at `AudioPlayer.java:779` is private), so effects come last, behind a small, pinned fork of just_audio's Android module.
- **Reference implementation:** BitChord (`BitChord-main/`, GPLv3) already ships this design on Media3: two peer ExoPlayers, the standby loaded with the incoming track, and a handoff at the blend midpoint. It is a proven behavioural reference. **We cannot copy its code into this project unless this project is also GPLv3** (and `BeatTracker.kt` is AGPLv3-derived). We use its behaviour, numbers and lessons. The code is written clean-room.
- **Beating Apple:**
  - Smart crossfade: trims silence and fade-out tails, picks its own length, and matches loudness.
  - AutoMix works on local files and downloads. Apple's is catalogue-only ([Apple](https://support.apple.com/en-ca/guide/music/muse5e9ec085/mac)).
  - A "beat-matching may change tempo" opt-out.
  - The whole player UI moves in lockstep with the audio fade.
  - The next song's lyrics, palette and backdrop are ready before the handoff, so nothing flashes or loads.

## 1. What we are matching (facts)

| Apple Music | Source |
|---|---|
| Settings › Music › **Song Transitions**: off, or Transition Style **AutoMix** or **Crossfade** | [Apple Support 105067](https://support.apple.com/en-us/105067) **[doc]** |
| Crossfade length is a slider from **1 to 12 s** | [Macworld](https://www.macworld.com/article/1993764/how-to-ios17-set-adjust-crossfade-apple-music.html), [AppleInsider](https://appleinsider.com/inside/apple-music/tips/how-to-crossfade-apple-music-tracks-in-ios-17) **[doc]** |
| AutoMix uses audio analysis, beat matching and time stretching, removes silence, and falls back to a plain crossfade | Apple newsroom, summarised by [rottenwifi](https://rottenwifi.com/automix-in-ios-26-adds-dj-like-song-transitions-to-apple-music/) and [peepstune](https://www.peepstune.com/what-is-apple-music-automix-in-ios-26-and-how-does-it-work/) (press, not Apple) |
| AutoMix toggle in the queue ("two overlapping turntables" icon) | [iDownloadBlog](https://www.idownloadblog.com/2025/08/29/how-to-use-automix-apple-music/) (press) |
| AutoMix works on catalogue streams only. Neither AutoMix nor Crossfade is available with hi-res lossless | [Apple Support](https://support.apple.com/nl-nl/105067) **[doc]** |
| Dragging into the last seconds of a song triggers the mix | [iDownloadBlog](https://www.idownloadblog.com/2025/08/29/how-to-use-automix-apple-music/) (press) |

Apple's exact fade curve, mix lengths and UI animation are not documented. Anything below that sounds like "what Apple does" beyond this table is our own design, not a claim about Apple.

## 2. Where the app is today (facts) and the gaps

**[code]**, from `lib/services/audio_service.dart`, `lib/providers/music_provider.dart` and `lib/main.dart`.

**Playback today:**
- One `AudioPlayer` (`audio_service.dart:209`). `JustAudioBackground.init` is in `main.dart:97`. The media session reads each `MediaItem` tag from the player's sequence.
- The window holds the current track plus up to 4 upcoming (`_windowUpcoming`). It is filled by `WindowFiller`, and ExoPlayer advances inside it gaplessly. The track-change signal is `windowIndexStream`, which drives `_onPlayerAdvancedTo`.
- Sources are a `LockCachingAudioSource` writing to `temp/audio_cache/audio_<id>.m4a` (whatever the real container is). A complete file over 100 KB is reused as `AudioSource.file`.
- Offload is on, `isSpeedChangeSupportRequired: false`, so any speed other than 1 leaves offload. Lofi uses speed 0.9 and pitch 0.9439.

**Volume and effects:**
- The Now Playing volume slider sets **system** volume (`DeviceVolumeSlider` → `AudioOutputService`). **Player volume is free** for fade gains.
- There are no audio effects in the pipeline. `EqualizerService` is initialised without an AudioService, so the EQ is a no-op.

**iOS:** just_audio uses `AVQueuePlayer` (`AudioPlayer.m:25`), and time-stretch uses `AVAudioTimePitchAlgorithmTimeDomain` (`UriAudioSource.m:77`). TimeDomain is the low-quality algorithm for music. Beat-matching on iOS needs it patched to `Spectral` (P6).

**Position:** just_audio's `position` is extrapolated in Dart from the last event (`just_audio.dart:671-676`), so a fade can be driven off it without platform calls.

**Existing bugs a transition engine must not inherit (fix in P1/P2):**
1. `onSkipToNext` / `onSkipToPrevious` controllers in `AudioService` are never fed, so their listeners in MusicProvider (`:1659-1670`) are dead.
2. The sleep timer "end of track" (`_stopAfterCurrentTrack`) is only checked in `_onTrackComplete` and the dead skip path. An in-window advance ignores it.
3. The timed sleep timer stops dead, with no fade.
4. AudioService's interruption and becoming-noisy handlers pause the single player directly. With two decks they must pause both.

**Missing data:** the stream resolver keeps nothing about loudness. YouTube player responses carry `playerConfig.audioConfig.loudnessDb`, and BitChord reads it (`PlaybackService.kt` `loudnessGainMb`). We need to capture it in `InnerTubeService` (`:941` area). **[code / assume: verify field present for our clients in P0]**

## 3. Architecture decision

| Option | Verdict |
|---|---|
| A. One player, fade out then fade in | Rejected. It produces silence at the join, not a crossfade. |
| B. Replace just_audio with a native Media3 engine (port BitChord's design) | Rejected for now. It rewrites caching, windowing, retry, the media session and iOS in one go, and its licence blocks copying. |
| **C. Keep just_audio, move to `audio_service`, add a `DeckPair` and a Dart `TransitionEngine`, plus a native analyser plugin; DJ effects later via a minimal fork of just_audio Android** | **Chosen.** Each step ships alone, and only the fork in P5 touches native playback. |

```
MusicProvider (queue decisions, unchanged API)
   │ playSources / appendWindow / seekToNext / streams
   ▼
PlaybackEngine  (replaces AudioService's single player; same public surface)
   ├─ DeckPair: deckA, deckB  (just_audio AudioPlayer each; one is ACTIVE)
   ├─ TransitionEngine (state machine, 30 ms ticks only while arming/fading)
   ├─ GainStage per deck = userVolume × fade × loudness × headroom
   └─ streams re-pointed to the ACTIVE deck (position, playing, index, duration)
MineAudioHandler (audio_service BaseAudioHandler)
   └─ mediaItem / queue / playbackState mirror the ACTIVE deck; one swap at handoff
TrackAnalyzer (native plugin, background thread) ──► AnalysisStore (sqflite)
TransitionPlanner (pure Dart; tiered; unit-tested)
```

**Core rule, learned from BitChord:**
- The standby deck only ever carries the **incoming** track, started at its cue point. The two decks never render the same audio, so there is nothing to align and no doubled audio.
- The handoff is a role swap at the blend midpoint. There is no seek and no re-buffer.
- When arming, the active deck's items after the current one are removed. This is the just_audio equivalent of Media3's `pauseAtEndOfMediaItems`, and it stops the active deck from advancing into the incoming song itself. It is done at least `fade + 4 s` before the end, so the renderer has not yet read into the next item. **[assume: S3]**

## 4. TransitionEngine (Crossfade, P2)

**States:** `idle → arming → fading → (handoff inside fading) → idle`, plus `bailing` and `sleepFade`.

| Item | Decision |
|---|---|
| Tick | Timer every 250 ms while idle and playing, only during the last 30 s of a track; otherwise no timer. 40 ms while arming, 30 ms while fading, 15 ms while bailing. Dart timers keep running in the background under the audio_service foreground service. **[assume: S6]** |
| Arm point | `remaining ≤ fade + 4 s`. The incoming source is rebuilt fresh, so it picks up the complete cache file. The deck is set to volume 0 with `setAudioSources([incoming, …rest], initialPosition: cue)`, then paused and prepared. |
| Arm timeout | 12 s. If the incoming deck is not ready, bail: re-extend the active deck's window and let it advance gaplessly as today. A missed crossfade is acceptable; a broken one is not. |
| Start | The incoming deck starts `fade` ms before the outgoing track's content end. In Crossfade mode that is its duration; in Smart mode it comes from analysis. |
| Progress | Driven by the incoming deck's position since the cue, not a wall clock, so a pause freezes the fade by itself. It is clamped so the outgoing deck reaches 0 by the time its file ends. |
| Curve | Equal-power: `in = sin(πp/2)`, `out = cos(πp/2)`. Power sums to exactly 1, so there is no mid-blend dip. This is correct for two different songs (uncorrelated signals). |
| Headroom | While `in+out > 1`, both decks get × `1/√(in+out)` (at most −1.5 dB) to avoid mixer clipping. This is BitChord's measured approach. |
| Fade length | User value from 1 to 12 s (Apple's range), default 6 s, capped at a third of the shorter track. |
| Handoff | At p = 0.5. Swap the active and standby roles, re-point the handler's mediaItem, queue and playbackState, and emit `windowIndexStream` with the incoming id. The existing `_onPlayerAdvancedTo` then does lyrics, palette, history and the window refill. Re-extend the new active deck's window through `WindowFiller`. |
| End | The outgoing deck stops, clears its sources and returns to volume 1. The incoming deck returns to speed 1 with a clickless notch (2×2 ms gain dip) if it was stretched. |
| Gain composition | `deck.setVolume(userVolume × fade × loudness × headroom)`. One writer per deck, so nothing fights over `setVolume`. |

**Edge-case matrix (all in unit tests with fake decks):**

| Case | Behaviour |
|---|---|
| Manual next/prev or a queue tap | No crossfade. A 100 ms declick runs on the leaving deck, then the move happens. A transition in flight bails (BitChord's rule: pressing next means "stop hearing this"). |
| Seek during a fade | Bail. Before the handoff, the incoming deck ramps out over 120 ms. After it, the outgoing deck does. |
| Seek into the last `fade` seconds while idle | Arm immediately with `fade = min(fade, remaining − 0.5 s)`. This matches Apple's drag-to-end behaviour. |
| Pause or resume during a fade | Both decks pause and resume. Mirrored every tick, so audio-focus loss and becoming-noisy pause both decks. |
| Repeat-one | Never armed. |
| Last item, autoplay off | Never armed. Plays out normally. |
| Album played in order (`playlistId` is an album and the next item is the following track) | **Gapless by default** (setting: "Crossfade albums", off). Live and concept albums depend on this. |
| Tracks under 45 s, or podcast/episode/audiobook | Never armed. |
| Casting | Disabled. The receiver plays one stream. |
| Offline or local files | Supported (better than Apple). |
| Network error on the incoming deck while arming | Bail. The outgoing deck plays out, and the existing retry and dry-window repair takes over. |
| Lofi or user speed ≠ 1 | Fade timing uses media time. The incoming deck inherits the user's speed. |
| Timed sleep timer | Fades out over 8 s, then stops (fixes bug 3). |
| Sleep "end of track" | The engine knows the boundary: fade-out instead of a transition, then stop (fixes bug 2). |
| App killed mid-fade | On restore the active deck wins. No fade state is persisted. |

**Loudness (P2, attenuation only):**
- Gain `= min(1, 10^(−loudnessDb/20))` from the YouTube figure. Attenuation only means it can never clip and needs no audio effect, so offload is not blocked.
- Local files use the analyser's measured LUFS (P3).
- Setting "Normalize volume" defaults to on. Matched levels are what make a fade sound even.

## 5. AutoMix (P3 → P5)

### 5.1 Analyser (native plugin `mine_audio_analysis`)

**Pipeline:**
- **Input:** a complete cache or download file. The next track is pre-fetched into the same cache path when it becomes "up next". It will be played anyway, at about 3–5 MB per song. Analysis never reads the network itself.
- **Decode:**
  - Android: `MediaExtractor` + `MediaCodec`, which support AAC/m4a and Opus/WebM. Output is mono at 11 025 Hz.
  - iOS (P6): `AVAssetReader`, AAC only. The iOS stream selection must stay m4a. **[assume: S4]**
- **Threading:** one background thread at low priority. One track at a time, current then next. It pauses when the device is hot or the battery is low.

**Features, all classic DSP:**

| Feature | Method | Phase |
|---|---|---|
| RMS envelope, 50 ms hop | — | P3 |
| Leading silence (audible start) | −50 dBFS relative to the track's loud reference | P3 |
| Trailing silence and fade-out tail (content end, outro start) | energy-slope detection | P3 |
| Integrated loudness | ITU-R BS.1770 (K-weighting, gating) | P3 |
| Onset strength | spectral flux | P4 |
| Tempo | autocorrelation plus a comb filterbank, with an octave check | P4 |
| Beat phase | dynamic programming beat tracker (Ellis 2007) | P4 |
| Downbeats and phrase boundaries | low-band accent every 4 beats, plus energy/novelty peaks at 8/16-beat multiples | P4 |
| Key, optional | chroma plus Krumhansl profiles | P4 |
| Vocal activity, optional | spectral heuristic first | P4 |

**Optional accuracy upgrade (P4b):** the *Beat This!* model (MIT code **and** weights, [CPJKU/beat_this](https://github.com/CPJKU/beat_this), [HF](https://huggingface.co/cstr/beat-this-GGUF)), int8 ONNX at about 4.3 MB, via onnxruntime-android.
- A neural vocal model (Open-Unmix "umxhq") is **not** shipped until its weight licence is cleared. It was trained on MUSDB18, which carries research-use terms. **[assume: legal check]**

**Output:** a compact `TrackAnalysis` JSON with bpm, beatConfidence, beats, downbeats, phrases, audibleStart, contentEnd, outroStart, LUFS, an energy curve at 2 Hz and optionally key and vocal mask.

**Storage:** `AnalysisStore` in sqflite, keyed by `(trackId, durationMs±1s)`, with a schema version and an LRU of 2 000 rows.

### 5.2 Planner (pure Dart, deterministic, table-tested)

**Tiers, from most to least ambitious:**

| Tier | When | Result |
|---|---|---|
| T0 Gapless | Album in order, or "continuous" pair (outgoing ends loud with no tail, incoming starts loud) | No overlap, 0 gap |
| T1 Smart crossfade (P3, the default before beat data exists) | Analysis present, beats weak | Equal-power. Ends at `contentEnd` (silence and fade tail skipped, at most 12 s of music discarded). Incoming cued at `audibleStart`. Length 3–10 s from the outgoing outro's energy slope. |
| T2 Beat-matched blend (P4) | Both beat confidences ≥ 0.55; octave-folded tempo ratio within ±4 % (beyond that, stretch is audible) | Incoming speed `= outBpm/inBpm`, set before it plays. Start snapped to a downbeat. Overlap 8 or 16 beats, clamped to 4–12 s. Shortened in steps of 4 beats while vocals clash. After the mix the incoming deck eases back to 1.0 at ≤ 0.75 % per beat. |
| T3 Filtered blend (P5) | Tempos far apart or keys clash | Outgoing low-pass sweep plus incoming high-pass. Needs the fork. |

**Thresholds:** the starting values (0.55, ±4 %, 12 s, 45 s guard) are the ones BitChord arrived at by measurement. They are numbers, not code, and they will be re-tuned on our own listening set.

**Beat-matching opt-out:** setting "Allow tempo changes" defaults to on. When off, T2 becomes downbeat-aligned without stretch. This is something Apple does not offer.

**Phase lock:**
- The two decks are not sample-synchronised. After the incoming deck starts, the engine measures beat phase error from both decks' positions (median of 5 readings, 300 ms after start). If the error exceeds 8 ms it nudges the incoming deck's speed by ±3 % for at most 1.5 s.
- Achievable error is unknown until measured. **[assume: S5]** The target is under 20 ms, roughly where flamming becomes audible. If S5 shows more than 30 ms of jitter, T2 ships without phase lock, with a shorter overlap and a stronger dip on the outgoing low end.

### 5.3 DJ effects (P5, exceeds Apple)

- **Android:** fork `just_audio`'s Android module, pinned to 0.10.5 and kept small, and add a per-player `AudioProcessor` chain:
  - TPT state-variable filter, LP/HP at 24 dB/oct
  - 200 Hz bass-swap shelf
  - feedback echo
  - per-deck loudness boost with a peak limiter (this replaces attenuation-only normalisation)

  The processor is exposed as `AndroidTransitionFx` on the player. Filter targets are aimed ahead by the sink's latency, because the audio thread runs ahead of the speaker (BitChord measured about 4 s on float routes).
- **iOS:** an `MTAudioProcessingTap` on `AVPlayerItem.audioMix` for the same filters. This is later, and only if P6 parity is wanted.
- **Styles:** bass swap on beat-matched blends, filter sweep on mismatched tempos, and echo-out when the outgoing song ends on a hard stop. All share the same equal-power gain curve.

## 6. UI, UX and motion

**Principles:**
- The interface moves on the **same timeline as the sound**.
- Nothing appears that the listener didn't cause, except one quiet indicator that a mix is happening.
- Everything the next song needs is prepared before the handoff, so the swap is one frame.

**Settings › Player & Playback › Song Transitions** (glass group; `_GlassRow` and `LiquidSwitch`, matching settings_screen.dart):
1. **Song Transitions** switch, default off (as Apple).
2. **Style** segmented control: *Crossfade · AutoMix*. AutoMix shows a one-line explanation.
3. **Crossfade length:** `ThinSlider` from 1 to 12 s with a live "6 s" label and a selection haptic on each whole second. Hidden in AutoMix mode, where the slider sets only the fallback length.
4. AutoMix options:
   - "Allow tempo changes" (default on)
   - "Crossfade albums" (default off)
   - "Analyze on mobile data" (default off; analysis only reads files that are already cached, but the next-track pre-fetch uses data)
5. **Normalize volume** (default on).

Each row gets a settings-search entry.

**Queue screen:** add an AutoMix segment to the existing mode pill, next to shuffle, repeat and autoplay. It uses an "overlapping circles" glyph, matching Apple's queue toggle, and has an accessibility label. Between the Now Playing row and the next row, a hairline connector with the same glyph shows "AutoMix" or "Crossfade 6 s" when a transition will happen.

**Now Playing, before a mix:** an optional transition marker on the scrubber, a tinted segment over the planned window. It is shown only when both tracks are analysed, so it never slides around. It fades in over 300 ms.

**Now Playing, during a mix** (driven by `TransitionEngine.progress`, a `ValueListenable<double>` that ticks only while fading):
- **Audio-locked artwork:**
  - The outgoing hero art scales from 1.00 to 0.97 while its opacity follows `cos²(πp/2)`.
  - The incoming art, decoded and positioned at arm time, scales from 1.03 to 1.00 with opacity `sin²(πp/2)`.
  - Perceived brightness stays constant, the same law as the audio.
- **Backdrop wash:** the incoming wash is baked at arm time (the existing `BlurredBackdrop` path) and cross-dissolves on `p`. The palette and accent tween on `p`.
- **Title and artist:** swap at the handoff (p = 0.5), since text cannot be half one song. 280 ms: up 6 dp with a fade, using the current easing.
- **Scrubber:**
  - The outgoing time keeps counting.
  - At the handoff, the fill springs (critically damped, about 350 ms) to the incoming position, which is the cue plus half the fade.
  - Time labels cross-dissolve.
  - During a beat-matched mix, a soft sheen travels the bar once per bar (4 beats), not per beat. It is subtle, not a metronome.
- **Mixing indicator:**
  - The caption slot under the lyric strip (`LyricCaption`) shows "AutoMix · ⟨next title⟩" with the overlapping-circles glyph breathing on `p`.
  - It fades in at p = 0 and out 600 ms after the end. Crossfade mode shows nothing, since a plain fade needs no announcement.
- **Lyrics:**
  - The outgoing lyrics keep sweeping until the handoff.
  - The incoming lyrics are pre-fetched at arm time and fade in, already scrolled to the line at the cue time. For AutoMix the cue may be past the intro.
  - The lyric clock receives a `jump(cue + elapsed)` at the handoff, so it never shows line 1 of a song that is already 20 s in.

**Mini player, notification, lock screen:**
- The mini player's artwork cross-dissolves on `p`, and its progress hairline tweens.
- The notification and lock screen update **once**, at the handoff. The media session is not touched mid-fade.

**Reduced motion** (`MediaQuery.disableAnimations`): no scale or sheen. A single 250 ms dissolve at the handoff.

**Accessibility:** a `SemanticsService` announcement "Now playing ⟨title⟩" at the handoff. All controls get labels. The slider supports keyboard and switch increments of 1 s.

**Performance budget:**
- The progress ticker runs only while fading and only when Now Playing is visible. `CoveredGate` and `TickerMode` already gate it.
- Arm-time preparation (art decode, backdrop bake, lyrics fetch, palette) runs on the arm tick, 4–16 s ahead, never on a mix frame.

## 7. Phases

| Phase | Deliverable | Ships alone? | Main risk |
|---|---|---|---|
| **P0 Spikes (go/no-go)** | S1 two just_audio players playing at once under an `audio_service` handler (Android device, background, screen off). S2 `setVolume` stepped at 30 ms has no zipper noise. S3 removing the active deck's upcoming items 10–16 s before the end causes no glitch. S4 `MediaExtractor` decodes our cache files (webm/opus and m4a), complete and partial. S5 phase jitter between two decks' positions. S6 Dart timers at 30 ms keep running with the screen off. S7 `loudnessDb` is present in our InnerTube clients' responses. S8 iOS: two AVQueuePlayers in the background. | n/a | Any failed spike changes the design before code is written |
| **P1 Engine foundation** | Replace `just_audio_background` with `MineAudioHandler` (`audio_service`) and `PlaybackEngine` with a `DeckPair`. Same behaviour, one active deck. Wire skip next/prev from the notification, which fixes bug 1. Pause both decks on interruptions, which fixes bug 4. | **Yes, alone first.** It touches the media session. | Notification, lock screen, Android Auto and headset regressions |
| **P2 Crossfade (Apple parity)** | `TransitionEngine`, equal-power fade, every row of the edge-case matrix, loudness attenuation, sleep fade (bugs 2 and 3), settings UI, motion v1 (artwork, backdrop, title, scrubber) | Yes | Handoff bookkeeping (history, queue consumption) |
| **P3 Smart crossfade** | Native analyser v1 (decode, envelope, silence and outro, LUFS), `AnalysisStore`, next-track pre-fetch, planner T0/T1 | Yes | Battery and thermal cost of decoding; gated by charging and thermal state |
| **P4 AutoMix** | Tempo, beats, downbeats, phrases; planner T2; tempo stretch and ease-back; phase lock (if S5 allows); queue AutoMix toggle; mixing indicator; transition marker; lyrics pre-fetch at arm; optional Beat This! (P4b) | Yes | Beat accuracy on non-dance genres; T2 gated by confidence |
| **P5 DJ effects** | just_audio Android fork with an FX chain; T3 filtered blends; bass swap; echo-out; loudness boost with limiter | Yes | Maintaining the fork |
| **P6 iOS parity** | Two-deck engine on iOS, patch time-pitch to `Spectral`, `AVAssetReader` analyser, then `MTAudioProcessingTap` effects | Yes | No macOS build machine here to verify |

**Gates for every phase:** analyzer at or below the current count, all tests green, `flutter build apk --debug` passes, and the phase's device checklist passes.

## 8. Testing

**Pure Dart (no device):**
- Curves:
  - `in² + out² = 1` within 1e-9.
  - Headroom never exceeds 1.19.
  - Progress is monotonic under pause.
- `TransitionEngine` against `FakeDeck`s with a controllable clock. Every row of §4's matrix becomes a test, as do the arm timeout, bail before and after the handoff, the handoff emitting exactly one `windowIndexStream` event, and history recording the outgoing track exactly once.
- Planner: table tests per tier, the 12 s discard budget, the 45 s guard, album-gapless, and the opt-out of tempo changes.

**Native analyser:** synthetic fixtures generated in tests.
- Click tracks at 90/120/128/174 BPM must read within ±0.5 BPM, with beat phase within ±15 ms.
- Leading and trailing silence must be trimmed to within ±50 ms.
- A −20 LUFS sine must measure −20 ±0.5 LUFS.
- Plus 20 real songs labelled by hand (our listening set) as a regression corpus.

**Widgets:** the motion mapping (opacity, scale and label swap against `p`), reduced-motion behaviour, settings persistence, and queue connector visibility.

**Device:**
- **Audio:** record the output via loopback (USB-C capture, or `AudioPlaybackCapture` in a debug build). Measure the gap at the join (expect none), the level dip at the midpoint (expect within ±1 dB), and the beat offset on T2 mixes (expect under 20 ms median).
- **Thermal and battery:** `PERF_WINDOW` and `dumpsys thermalservice` during 10 transitions, compared with the transitions-off baseline.

## 9. Risks and legal

- **Licence.** BitChord is GPLv3, and `BeatTracker.kt` is AGPLv3-derived. Copying its code would force this project's licence, so only its behaviour and numbers are reused. Beat This! (MIT code and weights) is safe with attribution. Open-Unmix weights are blocked until cleared.
- **YouTube streams:** the next track's pre-fetch uses the same signed URL and user agent as playback. Streams expire after about 6 h, and pre-fetching happens minutes before use, never earlier.
- **Battery:**
  - Two decoders only during a mix.
  - Analysis about 1–3 s of CPU per track **[assume: measure in P3]**, cached forever.
  - Speed ≠ 1 leaves offload only for the incoming deck during a T2 mix.
- **OEM audio effects:** P5 avoids platform `AudioEffect`s, the class of bug this app already hit, by doing DSP inside ExoPlayer's processor chain.

## 10. Decisions needed from you

1. **Licence posture.** Is this app closed-source? If it is, or may become, GPLv3, porting BitChord's engine directly would save P3 to P5 effort. The default plan assumes clean-room.
2. **P5 fork.** Acceptable to maintain a small just_audio Android fork for DJ effects? Without it AutoMix stops at T2 (beat-matched volume blends), which is still on par with Apple.
3. **iOS priority.** Android first, with iOS in P6, assumed because Android is the primary platform.
4. **Defaults.** Transitions off (Apple's default) or Crossfade 6 s on? Recommended: off, with a one-time tip in the queue the first time the user plays a playlist.

## 11. Implementation log (what shipped, what did not)

Built clean-room in Dart over `just_audio` + `audio_service`. Nothing audio-side has been run on a device yet: every number below is from unit tests, synthetic signals and sixteen real songs decoded on the desktop, not from a phone.

**Shipped**

| Piece | Where | Verified by |
|---|---|---|
| Media session over two decks (`MineAudioHandler`, `DeckPair`, `DeckRelay`) | `services/playback/` | engine tests with fake decks; APK builds. **Not on a device.** |
| Settings model (off by default, 1-12 s, AutoMix, match tempo BETA, albums gapless, sleep fade, skip silence, analyse on mobile data) | `transition_settings.dart` | `transition_support_test` |
| Equal-power curves, planner (tiers, guards, album gapless, tempo window +-4 %) | `fade_curves.dart`, `transition_planner.dart` | 18 planner tests |
| `TransitionEngine` (arm, mix, handoff at progress 0.5, bail, pause/skip/seek during a mix, sleep fade, stop-after-track) | `transition_engine.dart` | 28 engine tests |
| On-device analyser: level envelope, outro, onsets, tempo, beats, bar lines, confidence | `audio_analyzer.dart` | 19 tests on built signals + calibration below |
| Native decoder (`MediaExtractor` + `MediaCodec` to mono 11 025 Hz PCM) | `AudioDecoder.java`, `MainActivity.java` | compiles in `flutter build apk --debug`. **Not run on a file.** |
| `AnalysisService` (one at a time, SQLite store, Wi-Fi only unless allowed, offline/low-data aware, ten-minute failure cooldown) | `analysis_service.dart` | 20 tests with the platform replaced |
| Settings screen, queue chip (Off, Crossfade, AutoMix), Now Playing mix motion (art + backdrop dissolve, "Mixing" badge, scrubber smoothing) | `song_transitions_screen.dart`, `transition_chip.dart`, `mix_overlays.dart` | 23 widget tests |

**Analyser calibration (16 real songs, `%TEMP%`, never copied into the repo)**

- Tempo within 0.1 BPM of the published tempo on every song whose tempo is known to me (Dynamite 114, Memories 91, Circles 120, Astronomia 126).
- Analysis takes about 200 ms per song on a desktop CPU. **Phone timing is unmeasured.**
- Findings that changed the code, in order:
  1. Confidence from pulse contrast alone did not separate right from wrong tempos. Agreement of the tempo across 25 s stretches does.
  2. Autocorrelation alone reads a busy hi-hat pulse at 3:2 of its tempo (a 140 BPM pattern as 93, one real song at 102 as 151). Harmonic voting did not fix it; weighting the kick band did (`kickWeight = 2`). That real song now reads 100.6 at confidence 0.21, which the planner ignores (it read 151 at 0.63 before).
  3. A held tone has no onsets but looked like a perfect pulse after normalisation. An absolute activity gate (`minOnsetActivity = 15`; tone 1.7, noise 90, songs 83-116) rejects it.
- Known limit: tempo can come out at half or double speed (a 174 BPM pattern reads 87). The planner folds octaves (`alignTempoOctave`), so this is harmless to a mix. Sixteen songs is a small corpus; treat the thresholds as measured, not proven.

**Not done**

- Loudness normalisation (needs `loudnessDb` captured from InnerTube).
- Transition marker on the scrubber; title/artist swap animation; Material You settings entry; queue connector.
- DJ filters and echo (P5): needs a `just_audio` Android fork and a device to tune. iOS (P6): no decoder or second deck there yet; the analysis service is Android-only (`AnalysisPlatform.supported`).
- Re-using the player's cache file for analysis: the current song is fetched a second time when AutoMix is first turned on.
- Without a result from the analysis service (not yet analysed, or analysis not possible) AutoMix plans a plain crossfade of the chosen length.

**Device checklist (what still has to be heard)**

1. Lock-screen and notification: next, previous, seek, play/pause (they now go through `MineAudioHandler`).
2. Pause and resume during a mix; skip during a mix; seek during a mix.
3. Album tracks stay gapless with "Transition between album tracks" off.
4. Crossfade at 1, 6 and 12 s: no dip or bump at the midpoint, no click at the handoff.
5. Sleep timer fades out instead of cutting.
6. AutoMix on Wi-Fi: the second song of a session is analysed in the background; a mix between two analysed songs starts earlier than the end when the first has a fade-out.
7. AutoMix with mobile data: nothing is downloaded until "Analyse on mobile data" is on.
8. Queue chip cycles Off, Crossfade, AutoMix; long-press opens the settings screen.
9. `PERF_WINDOW` and battery over ten transitions against transitions-off.
## 12. Quality pass (measured, not guessed)

Prompted by: AutoMix works but does not sound as smooth as Apple Music. No device was attached (`adb devices` listed none), so nothing below was heard. What was done instead is measure the transitions this app would make between real songs, offline, and fix what the numbers showed.

### The instrument

`test/lab/mix_lab_test.dart` (skipped unless `MIX_LAB_SONGS` names a folder; needs ffmpeg). It runs the real analyser, planner, level planner and gain law over the full-bandwidth 44.1 kHz decode of both songs, with gains stepped every 30 ms like the engine, and measures the result. The analysis it feeds the planner comes from the same box-filter resampler `AudioDecoder.java` uses, so the plan is the one a phone would make. The loudness meter was validated against `ffmpeg -af ebur128` first.

### What it found

| Finding | Number | Consequence |
|---|---|---|
| The songs in one library differ a lot in loudness | -5.6 to -14.6 LUFS integrated across 16 songs (9 dB) | A crossfade between mismatched songs is not a blend: at the crossover one song has 8x the power of the other. |
| Level mismatch at the middle of the fade | Crossfade: median 6.7 dB, p90 29.8 dB. AutoMix: median 7.0, p90 18.3 | **The main reason a mix sounds like a cut.** |
| After balancing (this change) | Crossfade: median 2.0, p90 20.6. AutoMix: median 1.7, p90 6.7 | The remaining p90 is songs whose overlap is nearly silent (a fade-out to nothing), which no gain law should "fix". |
| Level plan acts | 82 % (Crossfade) to 89 % (AutoMix) of random pairs: more than 1.5 LU apart in the overlap | It is not an edge case. |
| Clipping from summing the two decks | Over full scale in 0.00 % of overlap samples on average; worst pair 0.03 %; peak 1.17 | The existing headroom trim is adequate. No limiter added. |
| Mono downmix loudness | Read 0.0-3.1 dB low vs ffmpeg, by stereo width | The decoder now returns stereo (`channels: 2`); the meter takes mid + side. Error vs ffmpeg through the Android resampler: mean -0.23 LU, worst -0.58, std 0.18. |
| Pair level basis | Two earlier bases were wrong on real songs: whole-song average, and the 10 s before the fade. A song that ends in a fade-out is -5 LUFS on average and -27 over the fade; an opening can be 20 LU under its body. Both "corrected" blends that were already balanced. | Level is compared over the **middle half of the overlap** of each song (what is heard at the crossover). Pinned by a test built from exactly that case. |

### What changed

- `loudness.dart`: BS.1770-4 / R128 meter (K-weighting derived for the sampling rate, 400 ms blocks, absolute and relative gates), plus a 1-second profile stored with each analysis (`TrackAnalysis` version 2: old results are re-measured).
- `level_plan.dart`: the pair plan and `mixGains`, shared by the engine and the lab. Attenuation only (a player cannot boost): a louder incoming song starts held down and climbs back over 8 s once alone; a quieter incoming song brings the *outgoing* one down early in the fade. Dead-band 1.5 LU, cap 12 dB. Setting: *Balance loudness*, on.
- `phase_lock.dart`: beat-matched mixes start the incoming deck on a timer tick and a platform call, so it begins tens of ms late, a different amount every mix. The lock reads both decks' positions and trims the incoming deck's speed (at most 3 %, median of 3 readings, bounded, lets go on an implausible error) until it is on the beat. Simulated: starts up to 120 ms late settle within 12 ms in six seconds; 220 ms is worked off as fast as the bound allows.
- **A bug found while writing the above:** `settleActive` snapped a stretched incoming song back to normal speed, and the tempo ease-back then started again from the stretched rate: two audible tempo jumps at the end of every tempo-matched mix. `settleActive(resetSpeed:)` and a steppable ease-back fix it; tested.
- `AudioService._applyGains` is single-flight, latest-wins, and sets both decks together. Before, every 30 ms tick queued two awaited platform calls behind any slow one, so a hiccup delayed the fade instead of being skipped.
- AutoMix's *Match tempo* default is on (what AutoMix is in Apple Music; capped at 4 %). Still labelled BETA.
- Analysis reads the player's cache file when the song is already on disk, and otherwise downloads **into** the player's cache (promoted only if the body length matches the server's) so the song is fetched once, not once for analysis and once for playback. Needs a device to confirm against the real stream servers.
- Crossfade now analyses too (for loudness), so *Analyse on mobile data* applies to both styles.
- Engine: `upcoming` (what will happen at the end of this song) and `lastMix` (`MixTrace`: plan, level plan, start lateness, longest gap between gain steps, beat error before and after, trim).
- UI: a bracket under the scrubber where the next song comes in (brightens while it runs); the title and artist exchange at the handoff (leaving 150 ms, arriving 360 ms, no overshoot, off with reduced motion); a connector line in the queue between the playing song and the next that says what the planner decided ("Gapless" for an album); a *Last transition* card (tap to copy the raw trace); the Material You settings now opens Song Transitions.

### Verdicts on what was not built

- **DJ filters / bass swap / echo (P5): not built, and not because of time.** The only ways to filter one deck are (1) a platform `AudioEffect` on the ExoPlayer session, or (2) an ExoPlayer `AudioProcessor`. (1): this repo already records two reasons against it: `just_audio`'s equalizer integration threw out of `play()`/`pause()` on hardware that cannot create the effect and skipped every track (commit 1a53ce1, `_buildAndroidAudioEffects`), and an attached effect is what stops Android from offloading decode, which the perf plan turned on. Attaching natively with a try/catch would avoid the first but not the second, and would do it *in the middle of a mix*, on the song that is playing. The 5-band platform EQ is also a set of wide peaking filters whose shape differs per OEM, so a bass swap built on it would sound different on every phone. (2) is the right design and needs a `just_audio` fork plus tuning by ear on a device.
- **Global "Sound Check" normalisation: not built.** A streamed song's loudness is unknown until it has been read, so normalising would change the volume part-way through the first play of every song, or normalise only the songs heard before, which is inconsistent. Balancing the *pair* needs only what is known before the join.
- **iOS (P6):** no decoder, no second-deck verification, and no macOS here. `AnalysisPlatform.supported` is false off Android, so iOS gets a plain crossfade.

### Still to be heard (device)

Everything in section 11's checklist, plus: do tempo-matched mixes sound on the beat (the *Last transition* card shows the beat error the lock measured; if it reports a few ms and it still sounds off, the decks' reported positions and the speaker disagree and the lock needs a constant offset); is the *Balance loudness* swell after a held-down song natural at 8 s; does the stereo decoder produce the right loudness on a real cache file (compare the card's Levels line with how it sounded).
## 13. The transition inside the seek bar

The bracket under the scrubber (section 12) is replaced by marking the bar itself. `widgets/seek_zone.dart`; the player's scrubber (`ThinSlider`) and the mini player's progress line both use it, so they cannot disagree.

| State | What the bar does |
|---|---|
| Planned | The last stretch of the bar (the engine's `startAt`..`endAt`, widened to at least 10 px) sweeps in left to right over 520 ms with a deceleration, tinted: the accent with fine diagonal hatching for AutoMix, a quiet white veil for a plain crossfade, so a crossfade does not shout. It dissolves in 240 ms when the plan is withdrawn (leaving is quicker than arriving). |
| Entered | The played fill is one continuous shape whose colour is dyed across the zone by one gradient: toward the accent for AutoMix (the next song arriving), thinning out for a crossfade (this song leaving). |
| Live | While the mix runs the tint brightens and the hatching flows toward the end of the song (1.8 s per cycle). |
| Reduced motion | The zone is simply there. No sweep, no flow. |

Painted from animations handed to the painter's `repaint`, so a zone coming and going repaints a 7 px bar and rebuilds nothing; a running mix's 30 ms progress ticks do not rebuild the bar (tested). It was checked by rendering the bar in every state and looking at it, and the colour claims (zone is the accent and the rest of the bar is not; the fill is dyed more the deeper it goes; a crossfade never gets colour) are pixel tests in `test/seek_zone_test.dart`. Screen readers are told where the transition begins ("AutoMix begins at 3:52").

Also in this pass: the mini player's title exchanges at the handoff like the player's; a one-time "Blend your songs" offer in the queue for someone who has never met transitions (off by default, so otherwise nobody who never opens Settings would learn they exist); search finds Song Transitions by "loudness", "beat", "tempo", "level"; analysis refuses tracks over 12 minutes (the decode alone holds ~90 MB, and there is no transition to plan into a DJ set).

**Not touched, on purpose:** the Material You player, queue and wavy progress bar. They are to be rebuilt in Material 3 Expressive, so transition affordances belong in that rebuild, not on screens about to be replaced. Only the Material You *settings* entry exists.