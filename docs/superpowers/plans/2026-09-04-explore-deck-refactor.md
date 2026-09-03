# Explore Immersive Deck Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Explore page's presentation composition from a player-style card stack into a dark, spatial discovery deck (Reference B language + MineMusic identity) without touching recommendation/playback logic.

**Architecture:** Keep `ExploreController`/`ExploreSession`/`ExploreEngine`/`ExplorePolicy`/`ExplorePaletteCache`/`bootstrapExploreController` byte-identical in behavior (2 debug-log line swaps only). Add a pure `ExploreLayout` planner (viewport → deterministic spec, fully unit-tested). Rewrite page composition in `explore_screen.dart`: slim header + thin progress, prev-peek / artwork / floating metadata / slim rail / next-peek column sized by the planner. Hide the global pill via the existing `setHideMiniPlayer` sheet pattern while Explore is foreground.

**Tech Stack:** Flutter 3.47.1, existing `GlassSurface`/`GlassCircleButton`/`LiquidPlayButton`/`showGlassSnackBar`/`ThemedOptionsSheet`/`ArtistPickerSheet.showArtistOptions`, `palette_generator` via `ExplorePaletteCache`, `provider`.

## Global Constraints

- NO changes to ranking, session, refill, generation-race, palette-cache, or bootstrap source-ladder behavior (debug prints only).
- NO `Random()` / shuffle anywhere. NO new dependencies. NO new glass package.
- NO `Hero` widgets anywhere near the overlay (cff11bd poisoning lesson).
- NO `SingleChildScrollView` inside the vertical `PageView` (gesture conflict) — the planner must guarantee fit.
- Stable page keys `ValueKey('explore_page_<id>')` preserved.
- Palette hysteresis preserved (resolve on settle only).
- Existing tests stay green (235 baseline); `flutter analyze` 0 errors.
- Only `dart format` touched files.
- Test IDs 11-char lowercase-alnum.

---

### Task 1: ExploreLayout planner + token extension (test-first)

**Files:**
- Create: `lib/presentation/explore/explore_layout.dart`
- Modify: `lib/presentation/explore/explore_tokens.dart` (append; keep existing values)
- Test: `test/explore_layout_test.dart`

**Interfaces:**
```dart
// explore_layout.dart
class ExploreLayoutSpec {
  const ExploreLayoutSpec({
    required this.artworkSize,
    required this.showPrevPeek,
    required this.showReason,
    required this.prevPeekHeight,
    required this.nextPeekHeight,
    required this.gapAfterArtwork,
    required this.contentMaxWidth,
  });
  final double artworkSize;
  final bool showPrevPeek;   // false on short viewports
  final bool showReason;     // planner-level default; item confidence gates at render
  final double prevPeekHeight;
  final double nextPeekHeight;
  final double gapAfterArtwork;
  final double contentMaxWidth;
}

class ExploreLayout {
  /// Pure planner: viewport (PageView constraints) → deterministic spec.
  /// Priority under pressure: drop prev peek → shrink artwork (floor 150)
  /// → hide reason. Never overflows by construction.
  static ExploreLayoutSpec plan(Size viewport);

  /// Render-time reason gate (spec: subtle context only when confident).
  static bool shouldShowReason(double confidence);
}
```

**Tokens to append (exact values):**
```dart
static const double pagePadding = 20.0;
static const double headerHeight = 58.0;
static const double artworkFraction = 0.76;   // of content width (0.72–0.82 band)
static const double artworkMaxWidth = 430.0;
static const double artworkMinSize = 150.0;
static const double artworkRadius = 24.0;
static const double prevPeekHeight = 46.0;
static const double nextPeekHeight = 64.0;
static const double gapAfterArtwork = 18.0;
static const double railHeight = 56.0;
static const double titleSize = 28.0;         // keep existing
static const double reasonSize = 13.0;
static const double reasonConfidenceFloor = 0.35;
static const double contentMaxWidth = 560.0;  // tablet bound (#103)
static const double activeOpacity = 1.0;
static const double nextPeekOpacity = 0.8;
static const double prevPeekOpacity = 0.45;
static const double progressHeight = 2.0;
static const double controlSizeSmall = 42.0;
```

**Planner math (exact):**
```dart
static ExploreLayoutSpec plan(Size viewport) {
  final w = viewport.width, h = viewport.height;
  final contentW = (w - pagePadding * 2).clamp(0.0, contentMaxWidth);
  var art = (contentW * artworkFraction).clamp(artworkMinSize, artworkMaxWidth);
  art = art.clamp(artworkMinSize, (h * 0.44).clamp(artworkMinSize, artworkMaxWidth));
  // fixed chrome estimate: text block ~132 + rail 56 + next peek 64 + gaps ~46
  const chrome = 132.0 + railHeight + nextPeekHeight + 46.0;
  var showPrev = true;
  var total = prevPeekHeight + 10 + art + gapAfterArtwork + chrome;
  if (total > h) { showPrev = false; total -= (prevPeekHeight + 10); }
  if (total > h) { art = (art - (total - h)).clamp(artworkMinSize, artworkMaxWidth); }
  return ExploreLayoutSpec(
    artworkSize: art,
    showPrevPeek: showPrev,
    showReason: true,
    prevPeekHeight: prevPeekHeight,
    nextPeekHeight: nextPeekHeight,
    gapAfterArtwork: gapAfterArtwork,
    contentMaxWidth: contentMaxWidth,
  );
}
static bool shouldShowReason(double confidence) =>
    confidence >= ExploreTokens.reasonConfidenceFloor;
```

- [ ] **Step 1: Write failing test** `test/explore_layout_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/presentation/explore/explore_layout.dart';

void main() {
  group('ExploreLayout.plan', () {
    test('390x844 phone: artwork in 0.72-0.82 band, fits', () {
      final spec = ExploreLayout.plan(const Size(390, 700));
      final contentW = 390 - 40;
      expect(spec.artworkSize / contentW, inExclusiveRange(0.71, 0.83));
      final total = spec.artworkSize + 132 + 56 + 64 + 46 +
          (spec.showPrevPeek ? 56 : 0);
      expect(total, lessThanOrEqualTo(700));
      expect(spec.showPrevPeek, isTrue);
    });
    test('360x640 small phone: fits, drops prev peek first', () {
      final spec = ExploreLayout.plan(const Size(360, 457));
      final total = spec.artworkSize + 132 + 56 + 64 + 46 +
          (spec.showPrevPeek ? 56 : 0);
      expect(total, lessThanOrEqualTo(457));
      expect(spec.showPrevPeek, isFalse);
      expect(spec.artworkSize, greaterThanOrEqualTo(150));
    });
    test('412x915 large phone: bigger artwork, fits', () {
      final spec = ExploreLayout.plan(const Size(412, 760));
      expect(spec.artworkSize, greaterThan(260));
      expect(spec.showPrevPeek, isTrue);
    });
    test('tablet 820x1180: artwork capped, centered column bounded', () {
      final spec = ExploreLayout.plan(const Size(820, 1000));
      expect(spec.artworkSize, lessThanOrEqualTo(430));
      expect(spec.contentMaxWidth, 560);
    });
    test('deterministic: same viewport twice → identical spec', () {
      final a = ExploreLayout.plan(const Size(390, 700));
      final b = ExploreLayout.plan(const Size(390, 700));
      expect(a.artworkSize, b.artworkSize);
      expect(a.showPrevPeek, b.showPrevPeek);
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
- [ ] **Step 2: Run** `flutter test test/explore_layout_test.dart` — expect compile errors (file missing).
- [ ] **Step 3: Implement** both files exactly as above.
- [ ] **Step 4: Run** — green.
- [ ] **Step 5: Commit** `feat(explore): deterministic layout planner + tokens`.

### Task 2: Deck recomposition (the refactor)

**Files:**
- Modify: `lib/presentation/explore/explore_screen.dart` (page composition, header, peeks, rail, metadata, artwork tap, hideMiniPlayer, artist tap, progress line, EXPLORE_LOAD log)
- Modify: `lib/services/explore/explore_controller.dart` (2 debugPrint line swaps ONLY: EXPLORE_PLAY before play issuance, EXPLORE_SKIP in dislikeCurrent)
- Test: `test/explore_screen_widget_test.dart` (update + extend)

**Consumes:** `ExploreLayout.plan(viewport)`, `ExploreLayout.shouldShowReason(confidence)`, existing controller/session/engine APIs (unchanged signatures), `ArtistPickerSheet.showArtistOptions(context, provider, artistName)`, `provider.setHideMiniPlayer(bool)`.

**Produces:** new private widgets `_DeckPage`, `_PrevPeek`, `_NextPeek`, `_SlimRail`, `_FloatingMetadata`, `_ThinProgress`, `_ExploreSkeleton`.

**Exact structural changes:**

1. **State (`_ExploreScreenState`):** add in `initState` post-frame: `context.read<MusicProvider>().setHideMiniPlayer(true);` add in `dispose` (before `_pageController.dispose()`): `context.read<MusicProvider>().setHideMiniPlayer(false);` — guard with `try { } catch (_) {}`? No — provider always present on route; keep direct (tests use FakeExploreProvider which inherits the real method — harmless notify).

2. **Header (`_ExploreHeader`):** replace counter + autoplay-off label with: back(38) + `Explore` 19w700 + Spacer + autoplay toggle(38, semantic 'Toggle autoplay') + below-row `_ThinProgress(value: (currentIndex+1)/max(1,items.length), height: 2, track white12, fill accent)`. Keep autoplay-off micro state INSIDE the toggle: when off, icon `play_disabled_rounded` + tooltip; the play rail already shows the affordance. Delete the `n · m left` Text and `Autoplay off` Text.

3. **Page (`_DeckPage`, replaces `_ExplorePage`):**
```dart
// LayoutBuilder(viewport) → spec = ExploreLayout.plan(Size(w, h))
// Center → ConstrainedBox(maxWidth: spec.contentMaxWidth) → Padding(20,8)
// Column(mainAxisSize: min? NO — max, mainAxisAlignment: center):
//   if (spec.showPrevPeek && prev != null) _PrevPeek(item: prev, onTap: jump(prevIndex)) + SizedBox(10)
//   GestureDetector(onTap: togglePlay, child: _ArtworkPanel(size: spec.artworkSize)) + progress line (width = art size)
//   SizedBox(spec.gapAfterArtwork)
//   _FloatingMetadata (no GlassSurface panel)
//   SizedBox(12)
//   _SlimRail
//   SizedBox(10)
//   if (next != null) _NextPeek(item: next, onJump: jump(nextIndex))
//   tiny 'Not interested' TextButton (12sp white38 → controller.dislikeCurrent())
```
No scroll view. `jump(i)`: `_pageController.animateToPage(i, 350ms, easeOut)` — settle fires via onPageChanged.

4. **`_FloatingMetadata`:** Semantics title/artist; title 28w700 maxLines 2; artist row: `GestureDetector(onTap: () => ArtistPickerSheet.showArtistOptions(context, provider, track.artistName), child: Text(artist 17 accent))`; context line 13sp white55: `[albumName • ]reasonLabel` iff `shouldShowReason(confidence)` else album-only iff non-empty else SizedBox.shrink. Provider needed → pass in (page already watches provider).

5. **`_SlimRail` (replaces `_Controls`):** GlassSurface floating radius 28, padding h10/v8, Row spaceEvenly, buttons size `controlSizeSmall`(42): Like (same), primary play: keep `LiquidPlayButton` (60dp circle — primary emphasis vs 42 siblings satisfies #28/#29 hierarchy), Queue (same + snackbar), Share (same), More: `ThemedOptionsSheet.show(context, track: track).then((_) { if (context.mounted) context.read<MusicProvider>().setHideMiniPlayer(true); })`.

6. **`_togglePlay(track, isCurrent)` helper** (used by artwork tap AND play button — single path): if isCurrent → isPlaying ? pause : resume; else playTrack(track, playlistTracks: [track, ...upcoming], setContext, clearQueue). Same args as today.

7. **`_PrevPeek`:** Opacity(0.45) → InkWell(onTap: jump) → Row: ClipRRect(10) thumb 34 + Column(title 13w600 1-line, artist 11 white50 1-line). Height 46. Left-aligned (no offset).

8. **`_NextPeek`:** Padding(left: 56) (deterministic diagonal offset) → Opacity(0.8) → GlassSurface card radius 18, padding 10 → Row: ClipOval thumb 44 (circular discovery chip — secondary object, primary artwork keeps 24dp cover geometry) + Expanded title/artist + GlassCircleButton(play_arrow 30dp, 'Play next') → jump. Height 64. Reason micro-label? No — keep clean.

9. **Progress line:** under artwork: `SizedBox(width: art, child: StreamBuilder<Duration>(stream: provider.positionStream, ...))` 2dp rounded bar, value = isCurrent ? pos/dur : 0, color accent. Same math as mini_player lines 184-210.

10. **`EXPLORE_LOAD` log** in bootstrap `fetchSources` after pools resolve:
```dart
debugPrint('EXPLORE_LOAD seed=${relatedSeed?.trackName ?? 'none'} '
  'related=${related.length} quickPicks=${provider.quickPicks.length} '
  'favorites=${provider.likedSongs.length} recents=${provider.recentlyPlayed.length} '
  'charts=${charts.length} releases=${releases.length}');
```
Needs `import 'package:flutter/foundation.dart';` — check current imports (material covers debugPrint? material exports foundation — yes, debugPrint available).

11. **Controller log swaps** (only changes in that file):
- In `settle`, before `await _play(item.track, upcoming);` add: `debugPrint('EXPLORE_PLAY title=${item.track.trackName} gen=$gen');`
- In `dislikeCurrent`, change `debugPrint('EXPLORE_ITEM dislike title=...')` → `debugPrint('EXPLORE_SKIP title=${item.track.trackName} artist=${...}')`.

12. **Skeleton (`_ExploreSkeleton`, replaces bare spinner for session==null only):** album placeholder (rounded 24, white6, music-note icon, size from planner with Size fallback 300) + 2 bars (title 180×22, artist 120×14, white8 rounded) + rail pill placeholder. Static (no shimmer lib; AnimatedOpacity pulse via existing `_showHint`-style? Keep STATIC — ponytail: skeleton geometry without animation lib; a 1-line `TweenAnimationBuilder` opacity pulse is cheap though — include simple pulse, 1200ms loop). Keep `_LoadingStub` (trailing refill page) and `_EmptyState` as-is.

- [ ] **Step 1: Update widget tests first** (RED): rewrite `test/explore_screen_widget_test.dart`:
  - keep: loading skeleton (find `_ExploreSkeleton`? private — assert via `find.byIcon(Icons.music_note_rounded)` in skeleton state + no spinner? skeleton has no CircularProgressIndicator → `find.byType(CircularProgressIndicator), findsNothing` when session==null), empty state, autoplay-off (toggle icon `play_disabled_rounded` present), reason gating (high-confidence item shows label; low-confidence hides), next-peek present with 'Play next' label, artwork tap calls play on fake (fake `playedTracks` list; tap artwork finder → playTrack recorded), Not-interested advances index (controller real, items 3), stable keys.
  - FakeExploreProvider additions: `pauseCalls/resumeCalls/playedTracks` lists, `pauseTrack/resumeTrack` overrides, `Future<void> navigateToArtist(String name) async {}` no-op guard.
  - Fake items need confidence: ExploreItem ctor has `confidence` field (verify exists — controller test used `confidence`? ExploreItem has `confidence` param per screen code `item.confidence` — yes).
  - Step expects FAIL (widgets missing).
- [ ] **Step 2: Implement** screen changes per §1–12.
- [ ] **Step 3: Run** widget test file — green.
- [ ] **Step 4: `flutter analyze`** touched dirs — clean.
- [ ] **Step 5: Commit** `feat(explore): immersive deck recomposition`.

### Task 3: Full verification + docs + report

- [ ] **Step 1:** `flutter analyze` whole repo → 0 errors (204 pre-existing infos/warnings baseline acceptable only if count unchanged — verify no NEW ones in explore files).
- [ ] **Step 2:** `flutter test` → all green (235 + ~12 new ≈ 247).
- [ ] **Step 3:** Update `CONTEXT.md` Explore file-map rows (add explore_layout.dart) + NEXT STEPS (deck tuning from live run).
- [ ] **Step 4:** Commit docs.
- [ ] **Step 5:** Final report in the mandated shape (UI / INTERACTION→fold into UI per new template sections: UI, INTERACTION, DISCOVERY, QUEUE, PERFORMANCE, TESTS, RUNTIME, LIMITATIONS).

## Self-Review

- Spec coverage: engine/session/playback/prefetch/feedback/palette sections map to UNCHANGED existing code (explicitly stated, not re-implemented) — presentation + planner + rail + peeks + header + skeleton + hideMiniPlayer + artist tap + reason gate + progress + 3 log lines are the delta. Gaps called out as LIMITATIONS, not silently dropped: queue view sheet (#93), scrubber (#63 optional), animated bars (#62), long-press (#92 optional), double-tap (#91 — explicitly do NOT implement), goldens (#135 — no infra), tablet 2-col (bounded column instead), time-of-day.
- No placeholders: all code/signatures/values above are exact.
- Type consistency: `ExploreItem.confidence` (double), `controller.upcomingTracks()` (List<Track>), `ArtistPickerSheet.showArtistOptions(context, provider, artistName)` (static, per artist_picker_sheet.dart:46-56), `setHideMiniPlayer(bool)` (music_provider.dart:459), `ShareParams(text:)` (existing usage), planner returns spec consumed by `_DeckPage` only.

## Execution

Plan saved. Executing inline — same session, full context loaded.
