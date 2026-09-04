# Explore Rotary Wheel Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Explore PageView deck with a tactile rotary wheel: album rows flow along a parametric arc with snap-to-center physics, haptic snap, debounced preview-autoplay, spinning active vinyl, micro-equalizer, liquid-mesh palette background — reusing engine/session/playback/palette-cache untouched.

**Architecture:** `ListView.builder` (uniform `itemExtent`) + custom `_SnapScrollPhysics` + per-frame arc transforms (`AnimatedBuilder` on the scroll controller, transform/opacity only) + `ScrollEndNotification` → haptic → 180ms debounce → existing `controller.settle(index)`. Palette extended with vibrant/deep tones (same 100px decode, zero new cost) feeding a tweened 3-blob mesh + ambient glow + luminance scrim.

**Tech Stack:** Flutter 3.47.1, existing `GlassSurface`/`GlassCircleButton`/`showGlassSnackBar`/`ThemedOptionsSheet`/`ArtistPickerSheet`, `ExploreController`/`ExploreSession`/`ExploreEngine`/`ExplorePaletteCache` (logic untouched), `HapticFeedback` (services, try/catch-guarded), `provider`.

## Global Constraints

- NO logic changes to engine/session/controller/ranker/policy (settle/upcomingTracks/dislikeCurrent consumed as-is).
- NO new dependencies. NO `Random()`. NO `Hero` (cross-navigator flights impossible: panel is overlay-driven, not a route).
- Animate ONLY transform/opacity (+2dp color lerps in background layer); never layout props.
- Stable keys: `ValueKey('explore_row_<id>')`, pill `ValueKey('explore_pill_<id>')`.
- Palette hysteresis (resolve on settle) + pill-hiding + prefetch preserved.
- Baseline 244 tests stay green; `flutter analyze` 0 errors; format only touched files.
- Reduced motion: `MediaQuery.disableAnimations` (test env) must not crash spin/eq (controllers simply run; loop cost is one active row only).

---

### Task 1: Palette vibrant/deep extension (test-first)

**Files:**
- Modify: `lib/services/explore/explore_palette.dart`
- Test: modify `test/explore_palette_test.dart` (extend)

**Exact changes:**
```dart
class ExplorePalette {
  const ExplorePalette({
    required this.background,
    required this.accent,
    required this.vibrant,  // NEW: vivid tone → mesh blob 1
    required this.deep,     // NEW: dark tone → mesh blob 2 / base depth
    required this.isBright,
  });
  final Color background; final Color accent;
  final Color vibrant; final Color deep;
  final bool isBright;
  static const ExplorePalette neutral = ExplorePalette(
    background: Color(0xFF101018),
    accent: Color(0xFF9E9EB8),
    vibrant: Color(0xFF6E6E96),
    deep: Color(0xFF08080F),
    isBright: false,
  );
}
// _toneMap additions (same decode, zero new cost):
final vibrant = palette.vibrantColor?.color ??
    palette.lightVibrantColor?.color ?? palette.dominantColor?.color ?? accent-fallback;
// deep: darkest usable tone, darkened to band 0.03–0.08 lightness:
final deepBase = palette.darkMutedColor?.color ??
    palette.darkVibrantColor?.color ?? dominant;
final deep = HSLColor.fromColor(deepBase)
    .withLightness(deepBase-lightness.clamp(0.03, 0.08)).toColor();
```

- [ ] Step 1: Extend palette tests (RED):
```dart
test('tone map exposes vibrant + deep bands', () async {
  // neutral carries the new fields:
  expect(ExplorePalette.neutral.vibrant, isNotNull);
  expect(ExplorePalette.neutral.deep, isNotNull);
  final hsl = HSLColor.fromColor(ExplorePalette.neutral.deep);
  expect(hsl.lightness, inExclusiveRange(0.0, 0.12));
});
test('resolve stores vibrant/deep (empty url → neutral path)', () async {
  final p = await ExplorePaletteCache.resolve('vx', '');
  expect(p.vibrant, ExplorePalette.neutral.vibrant);
  expect(p.deep, ExplorePalette.neutral.deep);
});
```
- [ ] Step 2: Run — FAIL (fields missing).
- [ ] Step 3: Implement exactly as above.
- [ ] Step 4: Run — green.
- [ ] Step 5: Commit `feat(explore): palette vibrant/deep tones`.

### Task 2: Wheel math + snap physics (test-first)

**Files:**
- Rewrite: `lib/presentation/explore/explore_layout.dart`
- Create: `lib/presentation/explore/explore_wheel_physics.dart`
- Modify: `lib/presentation/explore/explore_tokens.dart` (append rotary block; delete dead deck/stream tokens no longer referenced: artworkFraction? verify each deletion compiles — artworkRadius/artworkMemCacheWidth/artworkGlow stay if vinyl uses glow; delete prevPeek/nextPeek/peek opacities/progressHeight/gapAfterArtwork/slotDx*/reasonSize? reason text gone — delete reasonSize + metaSize if unused; keep reasonConfidenceFloor (gate fn kept for traces))
- Test: rewrite `test/explore_layout_test.dart`; create `test/explore_wheel_physics_test.dart`

**Exact code:**
```dart
// explore_layout.dart
class ExploreWheelSpec {
  const ExploreWheelSpec({required this.itemExtent, required this.arcK,
    required this.maxTheta, required this.contentMaxWidth});
  final double itemExtent; final double arcK; final double maxTheta;
  final double contentMaxWidth;
}

class ExploreWheelMath {
  /// Uniform row height: ~5 rows visible, clamped for small/tablet.
  static double itemExtentFor(double viewportH) =>
      viewportH / 5 < 96 ? 96 : (viewportH / 5 > 128 ? 128 : viewportH / 5);

  static ExploreWheelSpec plan(Size viewport) => ExploreWheelSpec(
        itemExtent: itemExtentFor(viewport.height),
        arcK: 72.0,
        maxTheta: 1.2,
        contentMaxWidth: 560.0,
      );

  /// Signed centrality t in [-1,1] from row-center distance to viewport center.
  static double tForIndex(int index, double offset, double extent, double viewportH) {
    final rowCenter = index * extent + extent / 2 - offset;
    return ((rowCenter - viewportH / 2) / (viewportH / 2)).clamp(-1.0, 1.0);
  }

  static double centrality(double t) => (1.0 - t.abs()).clamp(0.0, 1.0);

  /// Arc: Δx = k·(1−cos(|t|·θmax)), always +x (wheel curves right).
  static double arcDx(double t, double k, double maxTheta) =>
      k * (1 - cos(t.abs() * maxTheta));

  static double scaleFor(double c) => 0.65 + 0.35 * c;
  static double opacityFor(double c) => 0.2 + 0.8 * c;
  /// Text gone at edges (vinyl-only peripherals).
  static double textOpacityFor(double c) => ((c - 0.35) / 0.65).clamp(0.0, 1.0);
  /// Pill chrome only near center.
  static double glassFor(double c) => ((c - 0.5) / 0.5).clamp(0.0, 1.0);

  static bool shouldShowReason(double confidence) =>
      confidence >= ExploreTokens.reasonConfidenceFloor; // unchanged
}
```
```dart
// explore_wheel_physics.dart
import 'package:flutter/widgets.dart';

/// Magnetic snap-to-row physics over a uniform itemExtent.
class SnapScrollPhysics extends ScrollPhysics {
  const SnapScrollPhysics({super.parent, required this.itemExtent});
  final double itemExtent;

  @override
  SnapScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      SnapScrollPhysics(parent: buildParent(ancestor), itemExtent: itemExtent);

  @visibleForTesting
  static double snapTarget(double pixels, double extent) =>
      (pixels / extent).round() * extent;

  @visibleForTesting
  static int indexFor(double pixels, double extent) =>
      (pixels / extent).round();

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final target = snapTarget(position.pixels, itemExtent);
    if ((velocity.abs() < tolerance.velocity) &&
        ((target - position.pixels).abs() < tolerance.distance)) {
      return null;
    }
    return ScrollSpringSimulation(
        spring, position.pixels, target, velocity,
        tolerance: tolerance);
  }
}
```

- [ ] Step 1: Write failing tests:
```dart
// explore_layout_test.dart (rewrite)
group('ExploreWheelMath', () {
  test('extent clamps: 5 rows visible', () {
    expect(ExploreWheelMath.itemExtentFor(660), closeTo(128, 0.01)); // 132→128
    expect(ExploreWheelMath.itemExtentFor(457), closeTo(96, 0.01));  // 91→96
    expect(ExploreWheelMath.itemExtentFor(560), closeTo(112, 0.01));
  });
  test('arc: center 0, edges ≈46px', () {
    expect(ExploreWheelMath.arcDx(0, 72, 1.2), 0);
    expect(ExploreWheelMath.arcDx(1, 72, 1.2), closeTo(45.9, 0.2));
    expect(ExploreWheelMath.arcDx(-1, 72, 1.2), closeTo(45.9, 0.2));
  });
  test('curves: center full, edge minimums', () {
    expect(ExploreWheelMath.scaleFor(1), 1.0);
    expect(ExploreWheelMath.scaleFor(0), 0.65);
    expect(ExploreWheelMath.opacityFor(0), 0.2);
    expect(ExploreWheelMath.textOpacityFor(0), 0.0);
    expect(ExploreWheelMath.textOpacityFor(1), 1.0);
    expect(ExploreWheelMath.glassFor(0.4), 0.0);
    expect(ExploreWheelMath.glassFor(1), 1.0);
  });
  test('tForIndex: centered row → 0', () {
    // extent 120, viewport 600: row 2 centered at offset 240.
    expect(ExploreWheelMath.tForIndex(2, 240, 120, 600), closeTo(0, 1e-9));
    expect(ExploreWheelMath.tForIndex(0, 240, 120, 600), closeTo(-1, 1e-9));
  });
  test('deterministic', () {
    final a = ExploreWheelMath.plan(const Size(390, 700));
    final b = ExploreWheelMath.plan(const Size(390, 700));
    expect(a.itemExtent, b.itemExtent);
  });
});
// explore_wheel_physics_test.dart
group('SnapScrollPhysics', () {
  test('snapTarget rounds to nearest row', () {
    expect(SnapScrollPhysics.snapTarget(250, 120), 240);
    expect(SnapScrollPhysics.snapTarget(310, 120), 360);
  });
  test('indexFor', () {
    expect(SnapScrollPhysics.indexFor(250, 120), 2);
    expect(SnapScrollPhysics.indexFor(0, 120), 0);
  });
});
```
- [ ] Step 2: Run both — FAIL.
- [ ] Step 3: Implement exactly as above (+ token appends below).
- [ ] Step 4: Run — green.
- [ ] Step 5: Commit `feat(explore): rotary math + snap physics`.

**Token appends (exact):**
```dart
static const double wheelMinExtent = 96.0;
static const double wheelMaxExtent = 128.0;
static const double wheelVisibleRows = 5.0;
static const double arcK = 72.0;
static const double arcThetaMax = 1.2;
static const double scaleMin = 0.65;
static const double opacityMin = 0.2;
static const double textFadeStart = 0.35;
static const double glassFadeStart = 0.5;
static const double vinylSize = 56.0;
static const double vinylActiveSize = 72.0;
static const double vinylHoleSize = 16.0;
static const double spinSeconds = 9.0;
static const int snapDebounceMs = 180;
static const double meshTransitionMs = 600.0; // Duration(milliseconds: 600)
static const double eqBars = 4.0; // int eqBarCount = 4
static const double eqLoopMs = 700.0;
```
(Write as proper typed consts; durations as `static const Duration`.)

### Task 3: Wheel widgets + screen rewire (test-first)

**Files:**
- Create: `lib/presentation/explore/explore_vinyl.dart` (`VinylDisc`, `MicroEqualizer`)
- Create: `lib/presentation/explore/explore_mesh.dart` (`LiquidMeshBackground`)
- Create: `lib/presentation/explore/explore_wheel.dart` (`ExploreWheel`, `WheelRow`, `WheelActions`)
- Modify: `lib/presentation/explore/explore_screen.dart` (state: ScrollController + debounce + snap + haptics; build: mesh + header + wheel + cluster; delete PageView path, `_StreamPage`, `_NeighborRow`, `_ActivePill`, `_PlayCapsule`, `_PillEntry`, `_QuietRail`, `_TrackProgress`? (already deleted), `_SwipeHint`, old skeleton content)
- Test: rewrite `test/explore_screen_widget_test.dart`

**Consumes:** `ExploreWheelMath`, `SnapScrollPhysics`, `ExplorePalette{..., vibrant, deep}`, controller APIs, `GlassSurface(tier, borderRadius, child)`, `GlassCircleButton(icon, onTap, size, iconSize, semanticLabel)`, `showGlassSnackBar`, `ThemedOptionsSheet.show`, `ArtistPickerSheet.showIfNeeded`, `SharePlus.instance.share(ShareParams(text:))`, `provider.setPlayerExpanded(true)`, `HapticFeedback.lightImpact` (guarded).

**Produces:**
```dart
// explore_vinyl.dart
class VinylDisc extends StatefulWidget {
  const VinylDisc({super.key, required this.imageUrl, required this.size,
    required this.spinning, this.accent});
  final String imageUrl; final double size; final bool spinning; final Color? accent;
  // spinning=false → static disc (no RotationTransition); true → 9s linear repeat.
}
class MicroEqualizer extends StatefulWidget {
  const MicroEqualizer({super.key, required this.color, this.barCount = 4});
  // 700ms repeat controller; bars height = 6 + 10*|sin(pi*(t + i/barCount))|.
  // Bars keyed ValueKey('eq_bar_$i') for tests.
}
```
```dart
// explore_mesh.dart
class LiquidMeshBackground extends StatefulWidget {
  const LiquidMeshBackground({super.key, required this.palette, required this.seed});
  final ExplorePalette palette; final String seed; // seed=item id → drift layout
  // State: prev/next palettes + 600ms controller; AnimatedBuilder lerps
  // background→, vibrant→, deep→, accent→; 3 radial blobs (alignments tweened
  // from seed hash among 3 fixed layouts) + center ambient glow (accent .35)
  // + base near-black + luminance scrim (0.55 + 0.3*lum(vibrant)).
  // RepaintBoundary inside. Blob helper: Container(decoration: RadialGradient(
  //   center, radius: 1.1, colors: [c.withValues(alpha:.5), transparent])).
}
```
```dart
// explore_wheel.dart
class ExploreWheel extends StatelessWidget {
  const ExploreWheel({
    super.key,
    required this.items,
    required this.scrollController,
    required this.physics,       // SnapScrollPhysics built with current extent
    required this.viewportH,
    required this.extent,
    required this.spec,          // ExploreWheelSpec (arcK/maxTheta)
    required this.settledIndex,
    required this.currentTrackId, // String?
    required this.isPlaying,
    required this.accent,
    required this.onTapRow,      // (int index) → jump
    required this.onTogglePlay,  // (ExploreItem item, bool isCurrent)
    required this.onOpenPlayer,  // () → setPlayerExpanded(true)
    required this.onOpenArtist,  // (Track) → ArtistPickerSheet
    required this.onToggleLike, required this.onQueue, required this.onShare,
    required this.onMore,        // (Track) → sheet (screen handles re-hide)
  });
  // ListView.builder(controller, physics, itemExtent: extent,
  //   padding: EdgeInsets.symmetric(vertical: (viewportH - extent) / 2),
  //   itemCount: items.length,
  //   itemBuilder: AnimatedBuilder(animation: scrollController, builder: (_, __) {
  //     final t = ExploreWheelMath.tForIndex(index, scrollController.offset, extent, viewportH);
  //     final c = centrality(t); dx/scale/opacity/text/glass...
  //     return Transform.translate(Offset(dx,0), child: Transform.scale(scale,
  //       child: Opacity(opacity, child: RepaintBoundary(child: WheelRow(...)))));
  //   }));
  // NOTE: reading scrollController.offset before attach throws — guard
  // `scrollController.hasClients ? offset : index*extent` (initial 0 → t from 0-offset;
  // screen jumpTo-restores before first paint anyway).
}
```
`WheelRow` (private `_WheelRow` in same file): Stack[ Opacity(glass)>GlassSurface(card,24, SizedBox.expand-ish fill), Padding(12)>Row[ _VinylDisc(size 56 or 72 by c>0.6? — keep fixed 60, scale transform handles size; spinning = isSettled&&isCurrent&&playing; tap vinyl → onTogglePlay), 12, Expanded(Opacity(textOpacity)>Column[title 20w700 1-line? Reference pill: 2 lines — maxLines 2; artist 14 accent-tappable → onOpenArtist])), 8, trailing: c>0.6 ? (playing&&isCurrent ? MicroEqualizer(tap→toggle) : play glass button 40 → toggle) : nothing ] ]. Title tap → onOpenPlayer. Row key `ValueKey('explore_row_<id>')`; vinyl Semantics 'Toggle playback for <title>'; eq Semantics 'Now playing equalizer'; play button GlassCircleButton semantic 'Play'/'Pause'.

`WheelActions` (private `_WheelActions`): GlassSurface(card,24) row spaceEvenly 5×GlassCircleButton(36/18): Like(liked?favorite:favorite_border,'Like'/'Unlike'), Queue(playlist_add,'Add to queue'), Expand(open_in_full,'Open player'), Share(ios_share,'Share'), More(more_horiz,'More options') + below tiny TextButton 'Not interested' 12 white38 → dislikeCurrent. Operates on `Track? activeTrack` (null → SizedBox.shrink).

**Screen state rewire (exact):**
```dart
final ScrollController _scrollController = ScrollController();
Timer? _snapTimer;
int _snappedIndex = -1;
bool _restored = false;

// in build, items known:
_ensureRestored(controller, items); // post-frame once: if session.currentIndex>0 → jumpTo silent snap

NotificationListener<ScrollNotification>(
  onNotification: (n) {
    if (n is ScrollStartNotification) { _snapTimer?.cancel(); }
    else if (n is ScrollEndNotification) { _snapToCurrent(); }
    return false;
  },
  child: ExploreWheel(...),
)

void _snapToCurrent({bool silent = false}) {
  final session = context.read<ExploreController>().session;
  if (session == null || !_scrollController.hasClients) return;
  final extent = ExploreWheelMath.itemExtentFor(_viewportH); // stored from LayoutBuilder
  final idx = SnapScrollPhysics.indexFor(_scrollController.offset, extent)
      .clamp(0, session.items.length - 1);
  if (idx == _snappedIndex && _snapTimer?.isActive == true) return;
  _snappedIndex = idx;
  if (!silent) _snapHaptic();
  _snapTimer?.cancel();
  _snapTimer = Timer(Duration(milliseconds: ExploreTokens.snapDebounceMs), () {
    if (!mounted) return;
    final c = context.read<ExploreController>();
    if (c.session == null) return;
    c.settle(idx);
    _resolvePalette(c);
    _preloadNext(c, c.session!.items, idx);
    _hidePill();
  });
}

Future<void> _snapHaptic() async {
  try { await HapticFeedback.lightImpact(); } catch (_) {}
}
```
- `_viewportH` field set inside LayoutBuilder wrapping the wheel (rebuild-safe: plain double assign during build is fine).
- physics rebuilt per build: `SnapScrollPhysics(parent: const ClampingScrollPhysics(), itemExtent: extent)`.
- `_jumpTo(index)`: `_scrollController.animateTo(index*extent, 350ms, easeOut)` (End notification → snap path, debounced — no direct settle).
- Keep: initState (hide pill post-frame + resolve), dispose (+timer cancel + show pill), palette hysteresis block, `_preloadNext`, `_ExploreHeader` (unchanged), `_EmptyState`, `_LoadingStub` (restyle? keep), skeleton rewrite (ghost rows).
- Delete: PageController, `_pageController`, `_jumpTo` old (replace), `_buildPageView`, `_showHint` + `_SwipeHint` class, `_StreamPage`, `_NeighborRow`, `_ActivePill`, `_PlayCapsule`, `_PillEntry`, `_QuietRail`, `_ArtworkPanel`? (check remaining refs — vinyl replaces; delete if unused), old `_ExploreSkeleton` body.
- Mesh replaces AnimatedContainer+blurred-layer block: `LiquidMeshBackground(palette: _palette, seed: active?.id ?? 'none')`. Keep scrim? Mesh includes scrim — delete old scrim block.

**Widget tests (rewrite file, RED first):**
```dart
// harness: existing _t/_item/_controller/FakeExploreProvider + playedTracks;
// FakeExploreProvider += bool expandCalls=false → override setPlayerExpanded(bool v){expandCalls=v;} — check base signature: void setPlayerExpanded(bool expanded) non-async? line 448: void setPlayerExpanded(bool expanded) — sync override records.
// wrap() same MultiProvider.
group('ExploreWheel rotary', () {
  testWidgets('rows render along wheel with stable keys', ... // explore_row_aaa found; vinyl disc present
  testWidgets('drag settles + debounced autoplay plays snapped track', ...
    // start(autoplay:false→true? use autoplay:true default) — drag ListView up 300px, pumpAndSettle → played last == bbb (or ccc by distance); assert played.isNotEmpty && controller.session.currentIndex>0
  );
  testWidgets('neighbor tap jumps', ... // tap row bbb key → pumpAndSettle → index 1
  testWidgets('playing shows equalizer, paused shows play', ... // provider fakeCurrent=aaa + fakePlaying=true → eq_bar_0 found; paused → Play semantics found
  testWidgets('spin only on active+current+playing', ... // RotationTransition found once when playing; pump with fakePlaying=false → findsNothing
  );
  testWidgets('expand opens fullscreen panel', ... // tap Open player → provider.expandCalls true
  testWidgets('actions operate on active track', ... // Like/Add to queue/Share/More options/Not interested found; Not interested → index advances
  testWidgets('skeleton + empty states', ...);
});
```
Drag test determinism: extent in test env = viewportH/5 — test window default 800×600 → wheel viewportH = 600 - header(56) - cluster(~100) - safearea? LayoutBuilder gives real constraints; extent = h/5 clamped. Drag 300px ≈ 300/extent rows. Compute expected in-test from controller? Assert: played.isNotEmpty && currentIndex == played-track index && settle called once-ish. Keep loose-but-meaningful: `expect(h.playedTracks, isNotEmpty)` + `expect(c.session!.currentIndex, greaterThan(0))`. Hmm — controller.play fake in harness records? Existing harness `play: (track, upcoming) async {}` — extend harness to record played list. I'll add `played` list to harness (like controller tests).

Also debounce: pumpAndSettle flushes 180ms timer ✓. Snap physics in test: ScrollSpringSimulation runs with fake async ✓. ScrollEndNotification fires ✓.

- [ ] Step 1: Write widget tests — FAIL (no wheel).
- [ ] Step 2: Implement vinyl + mesh + wheel + screen rewire.
- [ ] Step 3: Run — green. `flutter analyze` clean.
- [ ] Step 4: Commit `feat(explore): rotary wheel recomposition`.

### Task 4: Verify + docs

- [ ] `flutter analyze` → 0 errors.
- [ ] `flutter test` → green (≈244 − ~14 removed + ~20 new ≈ 250).
- [ ] CONTEXT.md: wheel file rows + rotary invariants (snap/debounce/haptic values).
- [ ] Commit docs. Final report (UI / INTERACTION / DISCOVERY / QUEUE / PERFORMANCE / TESTS / RUNTIME / LIMITATIONS + explicit non-goals: crossfade, snippet pre-cache, tab bar, Hero shared-element, shader mesh).

## Self-Review

- Coverage: mesh bg ✓, glass spec ✓ (our tiers — specular/border already in GlassTokens/GlassSurface; no restyle needed per "liquid glass of ours"), arc ✓, snap+haptics ✓, debounce ✓, spin ✓, eq ✓, manual override ✓ (pause halts spin via spinning flag; title tap expands via panel), header ✓ (back/title/autoplay kept; ··· dropped — global sheet owns options), bottom nav ✓ (route covers tabs; action cluster preserves functions), blur perf ✓ (single mesh RepaintBoundary + existing 100px palette), pre-cache ✓ (existing artwork/palette prefetch; snippet pre-cache declined), contrast ✓ (luminance scrim), hierarchy ✓ (mesh/wheel/header files + screen).
- Types: `ExplorePalette(vibrant, deep)` new required named — update neutral + _toneMap + tests; `SnapScrollPhysics(parent:, itemExtent:)`; `ExploreWheelMath` all static; `VinylDisc(imageUrl,size,spinning,accent?)`; `MicroEqualizer(color,barCount)`; `LiquidMeshBackground(palette,seed)`; `ExploreWheel(items,scrollController,physics,viewportH,extent,spec,settledIndex,currentTrackId,isPlaying,accent,onTapRow,onTogglePlay,onOpenPlayer,onOpenArtist,onToggleLike,onQueue,onShare,onMore)`.
- No placeholders: all code above is exact.

## Execution
Plan saved. Executing inline — same session, full context loaded.
