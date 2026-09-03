# Explore Stream-List Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recompose the Explore page from the big-artwork deck into the Reference-B stream: a diagonal flow of circular album objects with one active liquid-glass pill (art + title/artist + Play capsule), faded neighbors, minimal chrome — dark MineMusic identity, same engine/playback underneath.

**Architecture:** `PageView` stays the interaction engine (snap + settle → existing `controller.settle`). Each page renders a 5-slot window (`i-2..i+2`) along fixed diagonal offsets: far/near neighbor rows (tappable → jump) + centered active glass pill + slim quiet rail. Pure `ExploreLayout` planner governs row sizes, offsets, and far-peek visibility. Zero changes to controller/session/engine/policy/palette/bootstrap.

**Tech Stack:** Flutter 3.47.1, existing `GlassSurface`/`GlassCircleButton`/`LiquidPlayButton`? (no — custom Play capsule instead), `showGlassSnackBar`/`ThemedOptionsSheet`/`ArtistPickerSheet.showIfNeeded`, `ExplorePaletteCache`, `provider`.

## Global Constraints

- NO logic changes (ranking, session, refill, races, palette, bootstrap ladders). NO `Random()`. NO new deps. NO new glass package. NO `Hero`.
- NO scroll view inside vertical PageView — planner guarantees fit.
- Stable keys: pages keep `ValueKey('explore_page_<id>')`; active pill gets `ValueKey('explore_pill_<id>')`.
- Palette hysteresis + pill-hiding + prefetch + EXPLORE_* logs preserved as-is.
- 235→244 baseline must stay green; `flutter analyze` 0 errors; format only touched files.

---

### Task 1: Stream planner + tokens (test-first)

**Files:**
- Rewrite: `lib/presentation/explore/explore_layout.dart`
- Modify: `lib/presentation/explore/explore_tokens.dart` (replace deck-chrome block; keep ambient/palette/type values)
- Test: rewrite `test/explore_layout_test.dart`

**Interfaces (exact):**
```dart
// explore_layout.dart
class ExploreStreamSpec {
  const ExploreStreamSpec({
    required this.activeArt,
    required this.nearArt,
    required this.farArt,
    required this.activeRowH,
    required this.nearRowH,
    required this.farRowH,
    required this.slotDx, // length 5, slots -2..+2
    required this.showFar,
    required this.contentMaxWidth,
  });
  final double activeArt; final double nearArt; final double farArt;
  final double activeRowH; final double nearRowH; final double farRowH;
  final List<double> slotDx;
  final bool showFar;
  final double contentMaxWidth;
}

class ExploreLayout {
  static ExploreStreamSpec plan(Size viewport);
  static bool shouldShowReason(double confidence); // keep, unchanged
}
```

**Planner math (exact):**
```dart
static ExploreStreamSpec plan(Size viewport) {
  final h = viewport.height;
  // Fixed chrome without far rows: active 104 + 2×near 76 + rail 48 +
  // not-interested 28 + 5 gaps ×12 + vertical padding 24 = 416.
  const base = 104.0 + 2 * 76.0 + 48.0 + 28.0 + 5 * 12.0 + 24.0; // 416
  const withFar = base + 2 * 56.0 + 2 * 12.0;                    // 552
  return ExploreStreamSpec(
    activeArt: 76, nearArt: 52, farArt: 40,
    activeRowH: 104, nearRowH: 76, farRowH: 56,
    slotDx: const [56, 28, 0, -28, -56],
    showFar: h >= withFar,
    contentMaxWidth: 560,
  );
}
```

**Tokens to set (exact):**
```dart
pagePadding = 20.0; headerHeight = 56.0;
activeArtSize = 76.0; neighborArtSize = 52.0; farArtSize = 40.0;
activeRowHeight = 104.0; neighborRowHeight = 76.0; farRowHeight = 56.0;
slotDxFar = 56.0; slotDxNear = 28.0;
railHeight = 48.0; controlSizeSmall = 36.0;
contentMaxWidth = 560.0;
titleSize = 20.0 (pill) / artistSize = 14.0 / neighborTitleSize = 15.0 /
  neighborArtistSize = 12.0 / farTitleSize = 13.0 / farArtistSize = 11.0;
playCapsuleHeight = 44.0;
nearOpacity = 0.75; farOpacity = 0.4;
reasonConfidenceFloor = 0.35 (kept for logs/future; no visible reason text);
```
Keep: artworkRadius 24, ambientTransition 500ms, blurSigma 40, backgroundStrength 0.55, scrims, artworkGlow, memCache widths, artworkFraction? (unused now — DELETE artworkFraction/artworkMaxWidth/artworkMinSize/gapAfterArtwork/prevPeekHeight/nextPeekHeight/prevPeekOpacity/nextPeekOpacity/progressHeight/metadataGap? metadataGap unused — delete dead tokens).

- [ ] Step 1: Write failing test `test/explore_layout_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/presentation/explore/explore_layout.dart';

void main() {
  group('ExploreLayout.plan stream', () {
    test('390 phone: far peeks visible, diagonal offsets', () {
      final spec = ExploreLayout.plan(const Size(390, 700));
      expect(spec.showFar, isTrue);
      expect(spec.slotDx, [56, 28, 0, -28, -56]);
      expect(spec.activeArt, 76);
      final total = spec.activeRowH + 2 * spec.nearRowH + 2 * spec.farRowH
          + 48.0 + 28.0 + 7 * 12.0 + 24.0;
      expect(total, lessThanOrEqualTo(700));
    });
    test('360x640 small: far peeks drop, fits', () {
      final spec = ExploreLayout.plan(const Size(360, 457));
      expect(spec.showFar, isFalse);
      final total = spec.activeRowH + 2 * spec.nearRowH
          + 48.0 + 28.0 + 5 * 12.0 + 24.0;
      expect(total, lessThanOrEqualTo(457));
    });
    test('tablet: column bounded', () {
      final spec = ExploreLayout.plan(const Size(820, 1000));
      expect(spec.contentMaxWidth, 560);
      expect(spec.showFar, isTrue);
    });
    test('deterministic', () {
      final a = ExploreLayout.plan(const Size(390, 700));
      final b = ExploreLayout.plan(const Size(390, 700));
      expect(a.slotDx, b.slotDx);
      expect(a.showFar, b.showFar);
    });
  });
  group('shouldShowReason', () {
    test('gates low confidence', () {
      expect(ExploreLayout.shouldShowReason(0.2), isFalse);
      expect(ExploreLayout.shouldShowReason(0.5), isTrue);
    });
  });
}
```
- [ ] Step 2: Run — FAIL (spec shape changed).
- [ ] Step 3: Implement layout + tokens exactly as above.
- [ ] Step 4: Run — green.
- [ ] Step 5: Commit `feat(explore): stream planner + tokens`.

### Task 2: Stream recomposition

**Files:**
- Rewrite composition in: `lib/presentation/explore/explore_screen.dart` (keep `open`, `bootstrapExploreController` + EXPLORE_LOAD, state fields, palette hysteresis, prefetch, `_jumpTo`, hide-pill, `_LoadingStub`, `_EmptyState`)
- Rewrite test: `test/explore_screen_widget_test.dart`

**Consumes:** `ExploreLayout.plan`, `ExploreStreamSpec`, controller/session APIs (unchanged), `ArtistPickerSheet.showIfNeeded`, `GlassSurface`, `GlassCircleButton`, `showGlassSnackBar`, `ThemedOptionsSheet.show`, `SharePlus.instance.share(ShareParams(...))`.

**Produces (private):** `_StreamPage`, `_NeighborRow`, `_ActivePill`, `_PlayCapsule`, `_QuietRail`, `_ExploreSkeleton` (ghost pills). DELETE: `_DeckPage`, `_PrevPeek`, `_NextPeek`, `_FloatingMetadata`, `_SlimRail`, `_TrackProgress`, `_ExploreHeader` counter/progress parts (rewrite header slim).

**Exact structure:**

1. **Header:** `SizedBox(headerHeight 56)` → Row: back 38 + `Explore` 19w700 + Spacer + autoplay toggle 38 (`play_circle` / `play_disabled`, semantic 'Toggle autoplay'). DELETE thin progress bar + counter + autoplay-off label.

2. **`_StreamPage(item, neighbors[-2..+2 with nulls], accent, controller, onJump, isActivePage)`:** LayoutBuilder → spec → Center → ConstrainedBox(maxWidth 560) → Padding(20, 12) → Column(center):
```
if (showFar && m2 != null) _NeighborRow(m2, far, dx+56, jump) + gap 12
if (m1 != null) _NeighborRow(m1, near, dx+28, jump) + gap 12
_ActivePill(item, isActivePage)        // entry animation when page becomes active
gap 12
_QuietRail + Not-interested link (28)
gap 12
if (p1 != null) _NeighborRow(p1, near, dx-28, jump) + gap 12
if (showFar && p2 != null) _NeighborRow(p2, far, dx-56, jump)
```
Slot dx via `Transform.translate(offset: dx)`? Offsets shift row right/left: wrap row in `Padding(left: dx>0?dx:0, right: dx<0?-dx:0)`. Deterministic, no transform layer.

3. **`_NeighborRow(item, artSize, titleSize, artistSize, opacity, dx, onTap)`:** Opacity → Semantics(label: 'Jump to ${title}', button) → InkWell(onTap) → Padding(dx) → SizedBox(height: rowH) → Row[ClipOval art + 10 + Expanded(title 1-line/artist 1-line)]. No glass (selective glass: pill only).

4. **`_ActivePill(item, active)`:** `AnimatedSwitcher(duration 250, child keyed 'pill_${item.id}')` → GlassSurface(floating, radius 40) → Padding(12) → Row[art 76 ClipOval + ring Border(accent .5, 1.5) + glow shadow, 12, Expanded(title 20w700 1-line? Reference shows 1-2 lines — maxLines 2 + artist 14 + GestureDetector artist → showIfNeeded), 8, `_PlayCapsule`]. Entry animation: wrap pill in `_PillEntry(itemId, isActivePage, child)` StatefulWidget — `didUpdateWidget`: if `isActivePage && (old.id != id || !old.active)` → `controller.forward(from: 0)`; build ScaleTransition(0.96→1.0, 300ms easeOut) + FadeTransition. Only animates on activation, never loops.

5. **`_PlayCapsule(track, isCurrent, playing, onTap)`:** Semantics('Play'/'Pause', button) → InkWell → GlassSurface(card, radius 24) → Padding(h16, v10) → Row[Icon(play/pause 18) + 6 + Text('Play'/'Pause' 13w600)]. onTap = same `_togglePlay` path as before (isCurrent ? pause/resume : playTrack with upcoming context).

6. **`_QuietRail`:** GlassSurface(card? floating too heavy — tier card, radius 24) → SizedBox(h48) → Row(spaceEvenly, 4× GlassCircleButton 36/18): Like (same), Queue (same+snackbar), Share (same), More (`ThemedOptionsSheet.show(...).then((_) => screenState?._hidePill())`). Then `TextButton('Not interested' 12 white38 → dislikeCurrent)` height 28.

7. **`_ExploreSkeleton`:** 3 ghost pills (rounded 40 bars: 104/76/76 heights, white6) with existing TweenAnimationBuilder pulse + music-note icon on first. No spinner.

8. **Keep:** `_ArtworkFallback` (reuse in thumbs), `_SwipeHint`, `_LoadingStub`, `_EmptyState`, ambient stack, scrim, `_jumpTo`, `_hidePill`, prefetch, settle wiring, page keys.

- [ ] Step 1: Rewrite widget tests FIRST (RED). Full new file:
```dart
// harness: same _t/_item/_controller/FakeExploreProvider (add playedTracks,
// pause/resume already there; DROP positionStream/duration overrides with _TrackProgress gone).
// wrap(controller, provider) same.
group('ExploreScreen stream', () {
  testWidgets('skeleton ghost pills before session', ... // music_note icons ≥2, no CircularProgressIndicator
  testWidgets('active pill: key, title, play capsule', ... // ValueKey('explore_pill_aaa11111111'), text Song, semantics 'Play'
  testWidgets('neighbor rows jump', ... // 'Jump to Song bbb11111111' tap → controller index 1
  testWidgets('play capsule plays track', ... // tap 'Play' → provider.playedTracks == [aaa]
  testWidgets('artwork tap toggles', ... // Semantics 'Toggle playback for Song aaa...' tap → played
  testWidgets('header slim: back/title/toggle, no progress', ... // Back, Explore, Toggle autoplay; LinearProgressIndicator findsNothing
  testWidgets('quiet rail actions present', ... // Like, Add to queue, Share, More options, Not interested
  testWidgets('not-interested advances', ... // index 0→1
  testWidgets('empty state', ... // unchanged
});
```
- [ ] Step 2: Run — FAIL.
- [ ] Step 3: Implement screen per §1–8.
- [ ] Step 4: Run file — green.
- [ ] Step 5: `flutter analyze` explore dirs — clean.
- [ ] Step 6: Commit `feat(explore): reference-B stream recomposition`.

### Task 3: Verify + docs

- [ ] `flutter analyze` repo → 0 errors.
- [ ] `flutter test` → all green (≈244 - ~4 removed + ~9 new ≈ 249).
- [ ] CONTEXT.md: layout row already there — update description to stream planner; NEXT STEPS stream-tuning line.
- [ ] Commit docs. Final report (UI / INTERACTION / DISCOVERY / QUEUE / PERFORMANCE / TESTS / RUNTIME / LIMITATIONS).

## Self-Review

- Coverage: animations (#51 easeOut entry + AnimatedSwitcher + palette fade; per-frame drag transforms deliberately skipped — rigid PageView slide carries motion, noted), transitions (#59/#60 switcher+slide), reason text removed per Reference (kept in logs + gate fn for future), progress line removed (Pause icon = state), counter removed, pill hidden (kept), artist tap kept, album via More (kept), autoplay toggle kept + persists? (check: current toggle calls controller.toggleAutoplay → onAutoplayChanged no-op wiring — autoplay NOT persisted across launches; spec #69 "persist if architecture supports" — SharedPreferences trivial? bootstrap passes onAutoplayChanged: (_) {}. Leave unpersisted = current behavior, note limitation.)
- Placeholders: none — all code/signatures/values exact.
- Types: `ExploreItem.confidence` double; `controller.upcomingTracks()` List<Track>; `ArtistPickerSheet.showIfNeeded(context, provider, name)`; `GlassSurface(tier/borderRadius/child/padding?)` — verify GlassSurface takes padding param? Current code uses `GlassSurface(tier:, borderRadius:, child: Padding(...))` — child owns padding. In §5 I wrote Padding inside — consistent. `_PlayCapsule` uses GlassSurface(card, 24) + inner Padding — consistent.

## Execution
Plan saved. Executing inline — same session, full context loaded.
