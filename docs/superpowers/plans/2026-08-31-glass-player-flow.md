# Glass Player Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate Glass-theme mini-player, Now Playing, queue, lyrics playback, and player sheets to one restrained package-backed liquid-glass system without changing playback behavior or the Material You branch.

**Architecture:** Keep `GlobalMusicOverlay` as the single owner of expanded/minimized player presentation and nested player navigation. Keep Glass and Material You interiors selected by existing themed wrappers. Add one reusable Glass player-control atom, route Glass surfaces through `GlassSurface`/`GlassTokens`, and call existing `MusicProvider` methods directly.

**Tech Stack:** Flutter 3.47.1, Dart 3.13.1, Provider, `liquid_glass_widgets: ^1.2.1`, `just_audio`, `google_fonts`, Flutter widget tests.

## Global Constraints

- Use `liquid_glass_widgets: ^1.2.1` through `GlassSurface`.
- Preserve existing `MusicProvider` playback, queue, download, cast, lyrics, persistence, and error contracts.
- Leave `material_you_*` widgets/screens unchanged except for compilation fixes forced by touched shared interfaces.
- Use current app screenshots as functional/information-architecture truth.
- Use Muzo screenshots only for material depth, hierarchy, and motion references; copy no Muzo layout, branding, copy, colors, icons, or typography.
- No new backend, network, mock-data, stream-resolution, InnerTube, Saavn, PO-token, authentication, or recommendation work.
- Allow one narrow internal `MusicProvider.playTrack` error-policy guard only for queue-row calls with `setContext: false, clearQueue: false`; preserve its public signature, queue contents, and normal auto-failover behavior for all other callers.
- No global glass treatment, neon/RGB/holographic styling, colored shadow halos, or nested full-screen blur.
- Grounded content remains solid near-black/charcoal; accent is limited to selected controls, progress, icons, and localized ink.
- Maintain safe-area support, 48dp effective targets, semantic labels/tooltips, cached artwork, and reduced-motion behavior.
- Do not push changes.

---

## File Map

### Shared material/control files

- Create `lib/widgets/glass_player_control.dart`: reusable Glass player/header control with selected and primary states.
- Modify `lib/theme/glass_tokens.dart`: player-specific sizes, scrim, control fill, and zero-halo values.
- Modify `lib/widgets/glass_surface.dart`: consume centralized glow/saturation values and remove its unused `borderColor` API; no callers exist.
- Create `test/glass_player_control_test.dart`: deterministic semantic/render tests for the new control.
- Modify `test/glass_surface_test.dart`: render `floating` and `sheet` tiers.

### Glass player flow

- Modify `lib/widgets/global_music_overlay.dart`: transform-based expanded panel and existing back/gesture state flow.
- Modify `lib/widgets/mini_player.dart`: floating tier, shared controls, tokenized dimensions, semantic actions.
- Modify `lib/now_playing_screen.dart`: flat scrimmed artwork atmosphere, shared controls, tokenized Glass surfaces.
- Modify `lib/screens/queue_screen.dart`: grounded queue, real row playback, tokenized destructive confirmation.
- Modify `lib/providers/music_provider.dart`: queue-row playback failures rethrow without auto-skipping or consuming queue entries; all other playback error behavior stays unchanged.
- Modify `lib/widgets/glass_playback_bar.dart`: shared control atom and package-backed surface.
- Modify `lib/screens/lyrics_screen.dart`: tokenized header/bar without duplicate gradient blur.
- Modify `lib/widgets/wavy_progress_bar.dart`: no halo default and no continuous animation while paused/reduced-motion.
- Modify `lib/widgets/glass_options_sheet.dart`: package-backed Glass sheet while preserving all option callbacks.
- Modify `lib/widgets/glass_download_selection_sheet.dart`: package-backed Glass sheet while preserving selection/download behavior.
- Modify `lib/widgets/playlist_selection_dialog.dart`: tokenized Glass dialog/sheet surface.
- Modify `lib/widgets/artist_picker_sheet.dart`: tokenized Glass picker surface.
- Modify `lib/widgets/glass_snackbar.dart`: compact transient Glass surface with black depth.

### Explicitly untouched

- `lib/screens/material_you_now_playing_screen.dart`
- `lib/screens/material_you_queue_screen.dart`
- `lib/widgets/material_you_playback_bar.dart`
- `lib/widgets/material_you_options_sheet.dart`
- `lib/screens/material_you_lyrics_screen.dart`
- `lib/services/audio_service.dart`
- stream-resolution and source services.

`lib/providers/music_provider.dart` remains untouched except for the narrow
queue-row playback error-policy guard defined in Task 4.

## Execution Tasks

### Task 1: Establish Glass Player Control Atom

**Files:**
- Create: `lib/widgets/glass_player_control.dart`
- Modify: `lib/theme/glass_tokens.dart`
- Modify: `lib/widgets/glass_surface.dart`
- Test: `test/glass_player_control_test.dart`
- Test: `test/glass_surface_test.dart`

**Interfaces:**
- Produces `GlassPlayerControl({Key? key, required IconData icon, required VoidCallback? onPressed, required String semanticLabel, String? tooltip, bool selected = false, bool primary = false})`.
- `selected` changes icon/ink emphasis only; it must not create a colored halo.
- `primary` chooses the larger `GlassTier.floating` control; normal controls use `GlassTier.chrome`.

- [ ] **Step 1: Write failing control tests.**

```dart
testWidgets('exposes icon and semantic label', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: GlassTheme.build(AccentColors.peach),
      home: Scaffold(
        body: GlassPlayerControl(
          icon: Icons.play_arrow_rounded,
          semanticLabel: 'Play',
          onPressed: () {},
        ),
      ),
    ),
  );

  expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  expect(find.bySemanticsLabel('Play'), findsOneWidget);
});

testWidgets('exposes disabled semantics', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: GlassTheme.build(AccentColors.peach),
      home: Scaffold(
        body: GlassPlayerControl(
          icon: Icons.skip_next_rounded,
          semanticLabel: 'Next track',
          onPressed: null,
        ),
      ),
    ),
  );

  final semantics = tester.getSemantics(find.bySemanticsLabel('Next track'));
  expect(semantics.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
  expect(semantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
});
```

- [ ] **Step 2: Run targeted tests and verify failure.**

Run: `flutter test test/glass_player_control_test.dart test/glass_surface_test.dart`

Expected: fail because `GlassPlayerControl` does not yet exist.

- [ ] **Step 3: Add centralized player tokens.**

Add these values to `GlassTokens` and use them instead of literals in later tasks:

```dart
static const double playerBackdropBlur = 24.0;
static const double playerScrimOpacity = 0.68;
static const double playerPillHeight = 64.0;
static const double playerControlSize = 48.0;
static const double playerPrimaryControlSize = 64.0;
static const double playerControlFillOpacity = 0.14;
static const double playerProgressGlowAlpha = 0.0;
static const double glassGlowIntensity = 0.0;
static const double glassSaturation = 1.12;
```

- [ ] **Step 4: Implement `GlassPlayerControl`.**

Use `Semantics`, optional `Tooltip`, `GlassSurface`, `Material`, and `InkWell`. Use `GlassTokens.playerControlSize` or `playerPrimaryControlSize`; use `accent` for selected/primary icon or a low-opacity fill only. Do not add a `BoxShadow` using the accent.

```dart
class GlassPlayerControl extends StatelessWidget {
  const GlassPlayerControl({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.tooltip,
    this.selected = false,
    this.primary = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final String? tooltip;
  final bool selected;
  final bool primary;
}
```

Use `GlassSurface(tier: primary ? GlassTier.floating : GlassTier.chrome, borderRadius: size / 2, child: controlContent)` and keep `controlContent` constrained to a square size.

- [ ] **Step 5: Remove GlassSurface halo hardcoding.**

Replace `glowIntensity: 0.55` with `GlassTokens.glassGlowIntensity` and `saturation: 1.35` with `GlassTokens.glassSaturation`. No `borderColor:` callers exist, so remove that unused field from `GlassSurface`.

- [ ] **Step 6: Run targeted tests and verify success.**

Run: `dart format lib/theme/glass_tokens.dart lib/widgets/glass_surface.dart lib/widgets/glass_player_control.dart test/glass_player_control_test.dart test/glass_surface_test.dart`

Run: `flutter test test/glass_player_control_test.dart test/glass_surface_test.dart`

Expected: all targeted tests pass.

- [ ] **Step 7: Commit foundation.**

```bash
git add lib/theme/glass_tokens.dart lib/widgets/glass_surface.dart lib/widgets/glass_player_control.dart test/glass_player_control_test.dart test/glass_surface_test.dart
git commit -m "feat: add glass player control atom"
```

### Task 2: Refactor Overlay and Mini-player

**Files:**
- Modify: `lib/widgets/global_music_overlay.dart`
- Modify: `lib/widgets/mini_player.dart`
- Test: `test/player_flow_widget_test.dart`

**Interfaces:**
- Consumes `GlassPlayerControl` from Task 1.
- Preserves `MusicProvider.setPlayerExpanded`, `setHideMiniPlayer`, `pauseTrack`, `resumeTrack`, `skipToPrevious`, `skipToNext`, `currentTrack`, `isPlaying`, `positionStream`, and `duration`.
- Produces the same `MiniPlayer` constructor and `GlobalMusicOverlay` constructor signatures.

- [ ] **Step 1: Add deterministic test provider and mini-player regression tests.**

Create `test/player_flow_widget_test.dart` with a `FakeMusicProvider extends MusicProvider` that overrides only playback getters/actions used by the tested widgets:

```dart
class FakeMusicProvider extends MusicProvider {
  FakeMusicProvider({this.track, bool playing = false}) : _playing = playing;

  Track? track;
  bool _playing;
  int resumeCalls = 0;
  int pauseCalls = 0;

  @override
  Track? get currentTrack => track;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isMiniPlayerVisible => true;

  @override
  Duration get duration => const Duration(minutes: 3);

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Future<void> resumeTrack() async {
    resumeCalls++;
    _playing = true;
  }

  @override
  Future<void> pauseTrack() async {
    pauseCalls++;
    _playing = false;
  }

  @override
  Future<void> skipToPrevious() async {}

  @override
  Future<void> skipToNext() async {}
}
```

Add tests asserting no track renders no player content, a track renders its title/artist, and the play control calls `resumeTrack`.

- [ ] **Step 2: Run the new tests and verify failure.**

Run: `flutter test test/player_flow_widget_test.dart`

Expected: the semantic control lookup fails because the current mini-player still uses an unlabeled `IconButton`.

- [ ] **Step 3: Simplify mini-player material.**

In `_PillBody`, keep `_PressSquish`, horizontal swipe callbacks, Hero artwork, progress stream, and tap-to-expand. Replace `GlassTier.chrome` with `GlassTier.floating`, wrap the child in a fixed-height `SizedBox(height: GlassTokens.playerPillHeight)`, replace the play `IconButton` with `GlassPlayerControl` using `semanticLabel: musicProvider.isPlaying ? 'Pause' : 'Play'`, and replace hardcoded text colors/sizes with the existing theme text styles plus tokenized opacity.

- [ ] **Step 4: Make overlay panel movement transform-based.**

Keep `_panelController`, provider synchronization, nested `Navigator`, and `PlayerAwarePopScope`. Replace the expanded panel's `Positioned(top: topOffset, height: screenHeight)` movement with a full-screen positioned child translated by `Offset(0, screenHeight * (1 - value))`. Keep opacity and `IgnorePointer` thresholds so hidden player content cannot intercept app gestures.

```dart
final panelOffset = screenHeight * (1.0 - value);

Positioned.fill(
  child: IgnorePointer(
    ignoring: value < 0.02,
    child: Opacity(
      opacity: value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, panelOffset),
        child: Navigator(
          key: musicProvider.playerNavigatorKey,
          observers: [_heroController],
          onGenerateRoute: _buildPlayerRoute,
        ),
      ),
    ),
  ),
);
```

Keep the mini-player above navigation using `GlassTokens.playerBottomInset`; do not add another blur layer.

- [ ] **Step 5: Run focused tests and analyzer.**

Run: `dart format lib/widgets/global_music_overlay.dart lib/widgets/mini_player.dart test/player_flow_widget_test.dart`

Run: `flutter test test/player_flow_widget_test.dart test/glass_player_control_test.dart`

Run: `dart analyze lib/widgets/global_music_overlay.dart lib/widgets/mini_player.dart lib/widgets/glass_player_control.dart`

Expected: tests pass and touched files have no analyzer errors.

- [ ] **Step 6: Commit overlay slice.**

```bash
git add lib/widgets/global_music_overlay.dart lib/widgets/mini_player.dart test/player_flow_widget_test.dart
git commit -m "feat: refine glass mini player flow"
```

### Task 3: Refactor Glass Now Playing

**Files:**
- Modify: `lib/now_playing_screen.dart`
- Test: `test/player_flow_widget_test.dart`

**Interfaces:**
- Preserve `NowPlayingScreen({required Track track, VoidCallback? onMinimize, Key? key})`.
- Preserve every existing provider call: `pauseTrack`, `resumeTrack`, `skipToPrevious`, `skipToNext`, `toggleShuffle`, `cycleRepeatMode`, `seekTo`, `toggleLike`, `downloadTrack`, cast discovery, queue navigation, lyrics navigation, artist/album navigation, options, and sleep timer.
- Preserve `ThemedNowPlayingScreen` as the branch selector.

- [ ] **Step 1: Add a render regression test for player content.**

Use the Task 2 fake provider and a `Track` with a title, artist, and empty artwork. Pump `NowPlayingScreen` inside `ChangeNotifierProvider.value`; assert title, artist, `NOW PLAYING`, and semantic labels `Play`, `Previous track`, `Next track`, `Shuffle`, and `Repeat` are present.

- [ ] **Step 2: Run the test and record current failure.**

Run: `flutter test test/player_flow_widget_test.dart`

Expected: semantic labels for existing inline controls are absent before migration.

- [ ] **Step 3: Replace Glass background atmosphere.**

Remove `_buildAmbientGlows`, `_LiquidGlob`, the `flutter_animate` use that exists only for those globs, and the accent gradient background. Add one isolated artwork backdrop behind the content:

```dart
RepaintBoundary(
  child: ImageFiltered(
    imageFilter: ImageFilter.blur(
      sigmaX: GlassTokens.playerBackdropBlur,
      sigmaY: GlassTokens.playerBackdropBlur,
    ),
    child: _buildAlbumArtImage(currentTrack),
  ),
),
Positioned.fill(
  child: ColoredBox(
    color: Colors.black.withValues(alpha: GlassTokens.playerScrimOpacity),
  ),
),
```

Keep a solid near-black fallback when artwork is empty. Do not use a full-screen `BackdropFilter` over the complete stack.

- [ ] **Step 4: Replace inline Glass controls.**

Use `GlassPlayerControl` for the header down/lyrics/options buttons, like/download controls, shuffle/previous/play/next/repeat controls, and circular footer cast/queue actions. Give each icon-only control a stable semantic label and tooltip. Keep accent on selected shuffle/repeat/like/download states and on the play icon/fill without an accent shadow.

- [ ] **Step 5: Preserve artwork, metadata, and action behavior.**

Keep the existing Hero tag `albumArt_<track.id>`, local-file fallback, artist picker, download `FutureBuilder`, `WavyProgressBar`, `ThemedLyricsScreen`, `ThemedQueueScreen`, cast device sheet, and options/sleep-timer routes. Do not change any provider/service code.

- [ ] **Step 6: Run focused tests and analyzer.**

Run: `dart format lib/now_playing_screen.dart test/player_flow_widget_test.dart`

Run: `flutter test test/player_flow_widget_test.dart test/glass_player_control_test.dart`

Run: `dart analyze lib/now_playing_screen.dart`

Expected: player content and semantic tests pass; no analyzer errors in `now_playing_screen.dart`.

- [ ] **Step 7: Commit Now Playing slice.**

```bash
git add lib/now_playing_screen.dart test/player_flow_widget_test.dart
git commit -m "feat: refine glass now playing surface"
```

### Task 4: Ground Glass Queue and Wire Row Playback

**Files:**
- Modify: `lib/screens/queue_screen.dart`
- Modify: `lib/providers/music_provider.dart`
- Test: `test/player_flow_widget_test.dart`

**Interfaces:**
- Preserve `QueueScreen` constructor.
- Use `MusicProvider.playTrack(track, setContext: false, clearQueue: false)` for a queue-row tap so existing queue contents remain intact.
- Preserve `removeFromQueue`, `reorderQueueItem`, and `clearQueue` calls.
- Preserve the `MusicProvider.playTrack` public signature. For queue-row flags only, validation/playback failures set the existing error, notify listeners, rethrow to the screen, and do not invoke automatic skip; all other callers retain current error handling.

- [ ] **Step 1: Extend fake provider with queue contract.**

Add these overrides to the test provider. Add a `failQueuePlay` switch needed
to exercise the queue screen's mounted-safe failure path without network/audio
work:

```dart
@override
List<Track> get queue => List.unmodifiable(queueTracks);

final List<Track> queueTracks = [];
Track? lastPlayed;
bool? lastClearQueue;
bool failQueuePlay = false;

@override
Future<void> playTrack(
  Track track, {
  String? playlistId,
  List<Track>? playlistTracks,
  bool setContext = true,
  bool clearQueue = true,
}) async {
  if (failQueuePlay) throw StateError('Queue playback failed');
  lastPlayed = track;
  lastClearQueue = clearQueue;
}

@override
void removeFromQueue(dynamic item) => queueTracks.remove(item);

@override
void reorderQueueItem(int oldIndex, int newIndex) {}

@override
void clearQueue() => queueTracks.clear();
```

Add a widget test that pumps one queue track, taps its title, and asserts `lastPlayed` is that track and `lastClearQueue` is `false`. Add a second test with `failQueuePlay` enabled that asserts the queue remains unchanged and the failure snackbar text is rendered. Add a focused provider test using a non-playable ID such as `PL_test`: call `MusicProvider.playTrack` with the queue-row flags, assert it throws `StateError`, assert the provider error is set, and assert a previously added queue item remains present; dispose the provider in `finally`.

- [ ] **Step 2: Run queue test and verify failure.**

Run: `flutter test test/player_flow_widget_test.dart`

Expected: current queue row tap does not call the provider because `QueueScreen` passes an empty callback.

- [ ] **Step 3: Remove dynamic Glass queue background.**

Remove `ColorUtils`, `bgColors`, `ImageFilter`, and the full-screen gradient. Use `Theme.of(context).scaffoldBackgroundColor`/`colorScheme.surface` for the solid canvas. Keep `SafeArea`, `ReorderableListView`, dismiss gesture, reorder callback, and empty state.

- [ ] **Step 4: Ground queue rows and tokenized destructive UI.**

Use solid near-black/charcoal row containers with a thin white or selected-accent outline. Keep the selected track visually distinct without accent glow. Replace hardcoded destructive red with `colorScheme.error`; use theme typography instead of direct `GoogleFonts` calls where existing theme styles provide the same hierarchy. Keep the AppBar clear action and confirmation dialog.

- [ ] **Step 5: Wire row playback without clearing queue.**

In `MusicProvider.playTrack`, define queue-row mode from the two existing flags. In `_playTrackInternal`, pass `clearQueue: setContext ? clearQueue : true` when it delegates to `playTrack` and `playOfflineTrack`; `clearQueue` has no effect when `setContext` is false, and this keeps internal auto-advance distinct from the direct queue-row `false/false` call. In the early non-playable-ID validation branch, keep setting `_errorMessage` and notifying listeners, but throw a `StateError` with that message when queue-row mode is active; retain the current return for all other callers. In the existing playback `catch`, keep current logging and message truncation, set `_errorMessage` and notify listeners, then rethrow when queue-row mode is active instead of calling `_handlePlaybackError`; retain `_handlePlaybackError` for all other callers. This prevents queue auto-skip only for direct queue-row playback and leaves normal failover unchanged.

Replace the empty `onTap` callback passed to `TrackTile` with:

```dart
onTap: () async {
  try {
    await musicProvider.playTrack(
      track,
      setContext: false,
      clearQueue: false,
    );
  } catch (error) {
    if (context.mounted) {
      showGlassSnackBar(context, 'Could not play ${track.trackName}');
    }
  }
},
```

Add the `showGlassSnackBar` import to `queue_screen.dart`; do not change `TrackTile`'s default behavior for other screens.

- [ ] **Step 6: Run queue tests and analyzer.**

Run: `dart format lib/screens/queue_screen.dart test/player_flow_widget_test.dart`

Run: `flutter test test/player_flow_widget_test.dart`

Run: `dart analyze lib/screens/queue_screen.dart lib/providers/music_provider.dart`

Expected: queue playback test passes and no analyzer errors remain in the touched queue file.

- [ ] **Step 7: Commit queue slice.**

```bash
git add lib/screens/queue_screen.dart lib/providers/music_provider.dart test/player_flow_widget_test.dart
git commit -m "feat: refine glass playback queue"
```

### Task 5: Unify Glass Progress, Lyrics, and Playback Bar

**Files:**
- Modify: `lib/widgets/wavy_progress_bar.dart`
- Modify: `lib/widgets/glass_playback_bar.dart`
- Modify: `lib/screens/lyrics_screen.dart`
- Test: `test/player_flow_widget_test.dart`

**Interfaces:**
- Preserve `WavyProgressBar({required MusicProvider provider, required Color accentColor, WavyBarStyle style = const WavyBarStyle(), Key? key})`.
- Preserve seek-on-tap and seek-on-drag behavior.
- Preserve lyrics fetching, timed highlighting, auto-scroll, tap-to-seek, retry, and playback bar actions.

- [ ] **Step 1: Add a reduced-motion progress test.**

Pump `WavyProgressBar` with reduced motion enabled and assert the widget renders the current/total duration labels. Use the `FakeMusicProvider` from Task 2 so the test is deterministic:

```dart
testWidgets('renders progress labels with reduced motion', (tester) async {
  final provider = FakeMusicProvider();
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: Scaffold(
          body: WavyProgressBar(
            provider: provider,
            accentColor: Colors.white,
          ),
        ),
      ),
    ),
  );

  expect(find.text('0:00'), findsOneWidget);
  expect(find.text('3:00'), findsOneWidget);
});
```

Also assert the default style has no halo:

```dart
test('default progress style has no halo', () {
  expect(const WavyBarStyle().glowAlpha, 0.0);
});
```

- [ ] **Step 2: Run the progress test and verify its initial failure or missing coverage.**

Run: `flutter test test/player_flow_widget_test.dart`

Expected: fail because the current `WavyBarStyle` default has `glowAlpha: 0.4`.

- [ ] **Step 3: Remove progress halo and idle ticker work.**

Import `glass_tokens.dart`, set `WavyBarStyle.glowAlpha` default to `GlassTokens.playerProgressGlowAlpha`, and wrap the animated painter in `TickerMode` with `enabled: !MediaQuery.of(context).disableAnimations && provider.isPlaying`; pass phase `0` when disabled or paused. Keep the active line, thumb, labels, drag math, and seek calls unchanged.

- [ ] **Step 4: Refactor `GlassPlaybackBar`.**

Remove its direct `BackdropFilter`, dynamic accent gradient, and accent `BoxShadow`. Wrap the existing content in `GlassSurface(tier: GlassTier.floating, borderRadius: GlassTokens.radiusCard)` with tokenized padding; use `GlassPlayerControl` for previous/play/next and add semantic labels to share/options. Keep `SharePlus`, `WavyProgressBar`, provider calls, and `GlassOptionsSheet.show` unchanged.

- [ ] **Step 5: Refactor Glass lyrics chrome only.**

Keep the lyrics list/state methods intact. Replace the full-screen accent gradient with a solid near-black background, replace the header `BackdropFilter` with a `GlassSurface` chrome header, and keep the positioned `GlassPlaybackBar`. Preserve back, auto-scroll toggle, retry, timed line updates, and provider calls.

- [ ] **Step 6: Run focused tests and analyzer.**

Run: `dart format lib/widgets/wavy_progress_bar.dart lib/widgets/glass_playback_bar.dart lib/screens/lyrics_screen.dart test/player_flow_widget_test.dart`

Run: `flutter test test/player_flow_widget_test.dart`

Run: `dart analyze lib/widgets/wavy_progress_bar.dart lib/widgets/glass_playback_bar.dart lib/screens/lyrics_screen.dart`

Expected: reduced-motion/progress tests pass and no analyzer errors exist in touched files.

- [ ] **Step 7: Commit playback-bar slice.**

```bash
git add lib/widgets/wavy_progress_bar.dart lib/widgets/glass_playback_bar.dart lib/screens/lyrics_screen.dart test/player_flow_widget_test.dart
git commit -m "feat: unify glass progress and lyrics chrome"
```

### Task 6: Migrate Glass Sheets, Dialogs, and Snackbar

**Files:**
- Modify: `lib/widgets/glass_options_sheet.dart`
- Modify: `lib/widgets/glass_download_selection_sheet.dart`
- Modify: `lib/widgets/playlist_selection_dialog.dart`
- Modify: `lib/widgets/artist_picker_sheet.dart`
- Modify: `lib/widgets/glass_snackbar.dart`
- Test: `test/player_flow_widget_test.dart`

**Interfaces:**
- Preserve all existing static `show` methods and constructor parameters.
- Preserve `setHideMiniPlayer(true)` before modal presentation and restoration in `finally`.
- Preserve every option callback and provider/service method.

- [ ] **Step 1: Add a modal restoration regression test.**

Use a provider with mutable `hideMiniPlayer` state and pump `GlassOptionsSheet(track: track)` directly. Assert the rendered sheet contains one `GlassSurface`. Then open it through `GlassOptionsSheet.show`, dismiss the route with `tester.pageBack()`, and assert the provider's `hideMiniPlayer` value is `false` after the returned future completes.

- [ ] **Step 2: Run the sheet test and verify current surface mismatch.**

Run: `flutter test test/player_flow_widget_test.dart`

Expected: the direct-surface assertion fails because the current options sheet uses an ad-hoc `BackdropFilter` container rather than `GlassSurface`.

- [ ] **Step 3: Replace options-sheet outer decoration.**

In `GlassOptionsSheet` and `GlassPlaylistOptionsSheet`, remove direct `BackdropFilter`/gradient/opaque container decoration. Keep `Consumer<MusicProvider>`, header art/title/artist, list order, and all callbacks. Replace the outer `Container`/`ClipRRect`/`BackdropFilter` stack with `GlassSurface(tier: GlassTier.sheet, borderRadius: GlassTokens.radiusSheet)` and pass the existing `SafeArea`/header/divider/options Column subtree as its child. Keep that existing Column unchanged and do not extract a second options-list abstraction.

Use `Theme.of(context).colorScheme` for text and destructive colors. Keep the handle as a small neutral affordance.

- [ ] **Step 4: Replace download/playlist/artist sheet surfaces.**

Apply the same `GlassTier.sheet` wrapper to `GlassDownloadSelectionSheet`, `playlist_selection_dialog.dart`, and `artist_picker_sheet.dart`. Keep selection state, list contents, download calls, navigation, and dismissal behavior unchanged. Remove only duplicated blur/gradient/shadow recipes.

- [ ] **Step 5: Refactor snackbar surface.**

Replace `GlassSnackBar`'s direct `BackdropFilter` with `GlassSurface(tier: GlassTier.floating, borderRadius: GlassTokens.radiusButton)` and tokenized padding. Keep `showGlassSnackBar` signature, duration, message, and ScaffoldMessenger integration. Use black shadow only and no accent fill.

- [ ] **Step 6: Run legacy-recipe scan on the scoped Glass files.**

Run:

```bash
rg -n "BackdropFilter|ImageFilter\.blur|gradient:|glow|accentColor\.withValues\(alpha: 0\.[2345]" lib/now_playing_screen.dart lib/widgets/global_music_overlay.dart lib/widgets/mini_player.dart lib/screens/queue_screen.dart lib/widgets/glass_playback_bar.dart lib/screens/lyrics_screen.dart lib/widgets/glass_options_sheet.dart lib/widgets/glass_download_selection_sheet.dart lib/widgets/playlist_selection_dialog.dart lib/widgets/artist_picker_sheet.dart lib/widgets/glass_snackbar.dart lib/widgets/wavy_progress_bar.dart
```

Expected: no duplicated Glass surface blur/gradient recipes remain; the single isolated Now Playing artwork `ImageFiltered` backdrop and package implementation internals are the only intentional optical filters.

- [ ] **Step 7: Run tests and analyzer.**

Run: `dart format lib/now_playing_screen.dart lib/widgets/global_music_overlay.dart lib/widgets/mini_player.dart lib/screens/queue_screen.dart lib/widgets/glass_playback_bar.dart lib/screens/lyrics_screen.dart lib/widgets/glass_options_sheet.dart lib/widgets/glass_download_selection_sheet.dart lib/widgets/playlist_selection_dialog.dart lib/widgets/artist_picker_sheet.dart lib/widgets/glass_snackbar.dart lib/widgets/wavy_progress_bar.dart test/player_flow_widget_test.dart`

Run: `flutter test`

Run: `dart analyze`

Expected: all tests pass; touched Glass files have no analyzer errors. Existing unrelated warnings may remain and must be listed in the handoff.

- [ ] **Step 8: Commit sheet slice.**

```bash
git add lib/widgets/glass_options_sheet.dart lib/widgets/glass_download_selection_sheet.dart lib/widgets/playlist_selection_dialog.dart lib/widgets/artist_picker_sheet.dart lib/widgets/glass_snackbar.dart
git commit -m "feat: unify glass player sheets"
```

### Task 7: Full Verification and Device Smoke Gate

**Files:**
- Modify only files required by failing verification from Tasks 1-6.
- Do not modify provider/service code to silence UI test failures.

- [ ] **Step 1: Inspect the complete diff.**

Run:

```bash
git status --short --branch
git diff --name-only HEAD~6..HEAD
git diff --stat HEAD~6..HEAD
git diff --check
git log --oneline -12
```

Confirm only the approved Glass player-flow files and test/spec/plan files changed.

- [ ] **Step 2: Run analyzer and tests from clean Dart state.**

Run: `flutter clean`

Run: `flutter pub get`

Run: `dart analyze`

Run: `flutter test`

Expected: no analyzer errors, all tests pass. Record any remaining warning/info count without hiding it.

- [ ] **Step 3: Build the debug APK.**

Run: `flutter build apk --debug`

Expected: success at `build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 4: Run manual device smoke when the Android device reconnects.**

Install the generated APK, then verify both theme branches:

- expand mini-player by tap and upward drag
- minimize by down gesture and system back
- play/pause, previous/next, seek, shuffle, repeat
- like/download and artist navigation
- open lyrics, tap a lyric line, toggle auto-scroll, retry
- open options, add queue, play next, playlist, download, share, artist/album, equalizer, sleep timer
- open queue, tap a row, reorder, swipe-delete, clear
- verify mini-player restoration after every modal sheet
- verify no player surface intercepts Home/Discover/Library navigation

- [ ] **Step 5: Perform one bounded visual pass.**

Check against the approved design and Muzo references: solid AMOLED base, visible artwork atmosphere only in Now Playing, restrained package refraction, thin edges, black depth shadows, localized accent ink, no colored halos, no nested blur, readable text, and safe-area clearance.

- [ ] **Step 6: Commit only fixes found by verification.**

Stage only these approved paths after confirming each appears in `git diff --name-only`:

```bash
git add lib/theme/glass_tokens.dart lib/widgets/glass_surface.dart lib/widgets/glass_player_control.dart lib/widgets/global_music_overlay.dart lib/widgets/mini_player.dart lib/now_playing_screen.dart lib/screens/queue_screen.dart lib/providers/music_provider.dart lib/widgets/wavy_progress_bar.dart lib/widgets/glass_playback_bar.dart lib/screens/lyrics_screen.dart lib/widgets/glass_options_sheet.dart lib/widgets/glass_download_selection_sheet.dart lib/widgets/playlist_selection_dialog.dart lib/widgets/artist_picker_sheet.dart lib/widgets/glass_snackbar.dart test/glass_player_control_test.dart test/glass_surface_test.dart test/player_flow_widget_test.dart
git commit -m "fix: close glass player verification gaps"
```
