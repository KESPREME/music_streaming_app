# Explore Liquid-Glass Rotary Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Explore to authentic liquid-glass fidelity: cosine arc (center-rightmost), bespoke glass pill (gradient border + bevel + elevation, disc hanging over edge), blurred vibrant glow mesh, grooved vinyl with white spindle, retuned type, slim glass tab bar with working tab switches, track actions re-homed (heart in pill, rest in More sheet + new Not-interested row).

**Architecture:** Same wheel engine (ListView + snap physics + debounce settle, untouched). `ExploreWheelMath` retuned to `dx=−A(1−cos(|t|π/2))` + anchor-calibrated scale/opacity. New `_LiquidGlassPill` (nested-container gradient-border trick + BackdropFilter sigma 12, NO custom painter). Mesh gains one ImageFiltered glow blob. Minimal tab plumbing: `MusicProvider.requestedTab` + MainScreen post-frame consume (~20 lines, zero visual change elsewhere).

**Tech Stack:** Flutter 3.47.1, existing glass tokens (untouched system), `GlassCircleButton`, `ThemedOptionsSheet`→`GlassOptionsSheet` (+`onDislike` thread-through), `ArtistPickerSheet`, provider, services.

## Global Constraints

- NO engine/session/controller/ranker changes. NO new deps. NO `Random()`. NO `Hero`.
- Transform/opacity-only per-frame work; one ImageFiltered glow layer (bounded 380×520, repaint-boundaried).
- Stable keys kept: `explore_row_<id>`, `vinyl_spin`, `eq_bar_<i>`.
- MY variant files frozen — `onDislike` threads glass sheet only (documented).
- Baseline 248 tests green; `flutter analyze` 0 errors; format touched files only.

---

### Task 1: Arc math retune + tokens (test-first)

**Files:**
- Modify: `lib/presentation/explore/explore_layout.dart` (arcDx/scaleFor/opacityFor bodies only)
- Modify: `lib/presentation/explore/explore_tokens.dart` (values below)
- Test: modify `test/explore_layout_test.dart` (new expectations)

**Exact changes:**
```dart
// layout:
static double arcDx(double t, double a) => -a * (1 - cos(t.abs() * pi / 2));
// NOTE: signature change (t, a) — update wheel call site in Task 3.
static double scaleFor(double c) {
  final u = ((1 - c) * 2).clamp(0.0, 1.0);
  return 1 - 0.40 * u;   // c=1→1.0, c≈0.67→0.74, c=0→0.60
}
static double opacityFor(double c) {
  final u = ((1 - c) * 2).clamp(0.0, 1.0);
  return 1 - 0.82 * u;   // c=1→1.0, c≈0.67→0.46, c=0→0.18
}
// textOpacityFor / glassFor / tForIndex / centrality / plan UNCHANGED.
```
Tokens: `arcK 72→32.0` (keep name), `arcThetaMax` DELETE (formula bakes π/2; remove param from arcDx — see above), `titleSize 20→17`, `artistSize 14→13`, `spinDuration 9s→6s`, ADD: `pillHeight 80`, `pillMarginH 12`, `pillRadius 40`, `pillFillAlpha 0.08`, `pillBorderTop 0.5`, `pillBorderBottom 0.04`, `pillBlurSigma 12.0`, `spindleSize 14.0`, `grooveCount 5`, `tabBarWidth 230.0`, `tabBarHeight 58.0`, `glowBlurSigma 30.0`. DELETE dead: check `slotDx*`(already gone?), `reasonSize`? — verify by analyze after Task 3, prune then.

- [ ] Step 1: Update layout tests (RED):
```dart
test('arc: center 0, edges curve left', () {
  expect(ExploreWheelMath.arcDx(0, 32), 0);
  expect(ExploreWheelMath.arcDx(1, 32), closeTo(-32, 0.01));
  expect(ExploreWheelMath.arcDx(-1, 32), closeTo(-32, 0.01));
});
test('anchors match spec steps', () {
  expect(ExploreWheelMath.scaleFor(1), 1.0);
  expect(ExploreWheelMath.scaleFor(0), closeTo(0.60, 0.001));
  expect(ExploreWheelMath.opacityFor(1), 1.0);
  expect(ExploreWheelMath.opacityFor(0), closeTo(0.18, 0.001));
  expect(ExploreWheelMath.opacityFor(0.67), closeTo(0.46, 0.03));
  expect(ExploreWheelMath.scaleFor(0.67), closeTo(0.74, 0.03));
});
```
- [ ] Step 2: Run — FAIL.
- [ ] Step 3: Implement math + tokens exactly as above.
- [ ] Step 4: Run layout + physics tests — green.
- [ ] Step 5: Commit `feat(explore): cosine arc + glass tokens`.

### Task 2: Vinyl grooves + spindle + mesh glow

**Files:**
- Modify: `lib/presentation/explore/explore_vinyl.dart`
- Modify: `lib/presentation/explore/explore_mesh.dart`
- Test: none new (covered by widget spin test; grooves/spindle are static paint)

**Exact changes — vinyl:**
```dart
// Inside ClipOval Stack, between artwork and hole:
CustomPaint(painter: _GroovePainter(), size: Size.infinite)
// NEW private painter:
class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.05);
    final maxR = size.shortestSide / 2;
    for (var i = 1; i <= ExploreTokens.grooveCount; i++) {
      canvas.drawCircle(c, maxR * i / (ExploreTokens.grooveCount + 1), paint);
    }
  }
  @override
  bool shouldRepaint(_) => false;
}
// Spindle: replace dark-hole+dot with 14px white label + metallic ring:
Container(width: 14, height: 14, decoration: BoxDecoration(
  shape: BoxShape.circle, color: Colors.white,
  border: Border.all(color: Color(0xFF9AA0AE), width: 2),
  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 3)],
))
```
**Exact changes — mesh:** keep tween/state/scrim; replace blob stack with:
```dart
Positioned.fill(child: ColoredBox(color: deep)),
// Stop 1: vibrant glow, center-left behind card, blurred 80px-ish:
Align(
  alignment: const Alignment(-0.55, 0.05),
  child: SizedBox(
    width: 380, height: 520,
    child: ImageFiltered(
      imageFilter: ImageFilter.blur(
          sigmaX: ExploreTokens.glowBlurSigma,
          sigmaY: ExploreTokens.glowBlurSigma),
      child: Container(decoration: BoxDecoration(
        gradient: RadialGradient(colors: [
          vib.withValues(alpha: 0.35),
          vib.withValues(alpha: 0.0),
        ]),
      )),
    ),
  ),
),
// Stop 2 support: faint accent aura top-right:
_blob(align top-right tweened, acc, 1.0) // reuse existing _blob helper
// scrim UNCHANGED
```
(drift layouts keep tweening the accent blob; glow stays anchored.)

- [ ] Steps: implement → `flutter analyze` dirs clean → widget spin test still green → commit `feat(explore): grooved vinyl + glow mesh`.

### Task 3: Liquid pill + bare rows + wheel rewire

**Files:**
- Modify: `lib/presentation/explore/explore_wheel.dart` (rows, pill, delete WheelActions + WheelActionWiring.share? keep wiring class minus share? — share moves to sheet: DELETE whole WheelActionWiring class; screen uses ThemedOptionsSheet/ArtistPickerSheet directly)

**Exact widgets:**
```dart
/// Authentic liquid-glass capsule, active row only. Gradient border via
/// nested containers (no custom painter); bevel via top highlight overlay.
class LiquidGlassPill extends StatelessWidget { // private _LiquidGlassPill
  // Layout: Container(height: 80, margin: h12) > Stack(clipBehavior: none) [
  //   Positioned.fill(child: _pillBody()),
  //   Positioned(left: -14, top: 4, child: disc 72 w/ semantics+tap),
  //   Positioned(left: 68, right: 10, top: 0, bottom: 0,
  //     child: Row[ Expanded(text col: title 17w600 white shadow / artist 13 accent tap) ,
  //                  heart 34 (IconButton, semantic Like/Unlike, accent when liked),
  //                  eq-or-play ]),
  // ]
  // _pillBody(): ClipRRect(40) > BackdropFilter(blur 12,12) >
  //   Container(gradient TL white .5 → BR white .04, radius 40, padding 1) >
  //   Container(color white .08, radius 39, shadow [0 16 40 -8 black .45]) >
  //   Container(gradient top white .25 → transparent 35%, radius 39)
  // Long-press anywhere on pill → onMore (haptic medium inside handler? screen wraps).
}
```
Row (inactive): disc 56 + texts ONLY (no glass/shadow/border; drop accent glow on inactive discs — pass accent:null unless settled). Keep row tap→jump, key `explore_row_<id>`, semantics 'Jump to…' (merged-value announcements, per prior finding).

`_WheelRow` gains: `liked`, `onLike`, `onMore`, `onTogglePlay`, `onOpenPlayer`, `onOpenArtist` pass-throughs; settled→pill else bare. Trailing in pill: `activePlaying ? eq(tap→toggle) : GlassCircleButton(play,'Play',toggle)`.

- [ ] Steps: implement → analyze clean → commit `feat(explore): liquid pill + bare rows`.

### Task 4: Screen chrome — header, tabs, cluster removal

**Files:**
- Modify: `lib/presentation/explore/explore_screen.dart`
- Modify: `lib/providers/music_provider.dart` (+9 lines tab request)
- Modify: `lib/main.dart` (+10 lines consume)

**Exact changes:**
- Header: title 19→28 (w700 kept), DELETE autoplay toggle button. Back stays.
- DELETE `_buildCluster` + WheelActions usage + Not-interested link + showGlassSnackBar/share/themed? (themed still used by long-press) imports as analyze dictates.
- ADD `_ExploreTabBar` (private, screen file): Center > GlassSurface(floating, 28) > SizedBox(w230,h58) > Row(spaceEvenly, 3× _TabBtn(icon, label, active, onTap)): Home(home_rounded,'Home') → request+pop; Orbit(explore_rounded,'Explore', active permanent) → no-op; Library(library_music_rounded,'Library') → request+pop. Active: accent icon + 4px dot under.
```dart
void _tabTo(int index) {
  if (!mounted) return;
  context.read<MusicProvider>().requestTab(index);
  Navigator.of(context).pop();
}
```
- Long-press pill → More sheet: pill `onMore` callback = screen handler:
```dart
void _openMore(Track track) {
  HapticFeedback.mediumImpact().catchError((_) {}); // Future catch, guarded
  ThemedOptionsSheet.show(context, track: track, onDislike: () {
    _invalidateSnap();
    context.read<ExploreController>().dislikeCurrent();
  }).then((_) => _hidePill());
}
```
(HapticFeedback.mediumImpact returns Future — use `.catchError` + also wrap try/catch? `.catchError((_) {})` suffices for MissingPlugin in tests. For lightImpact existing helper uses try/catch — mirror that style: make _buzz(Future<void> Function() fn) helper? Keep two tiny guarded helpers.)
- Heart: `onLike: () => provider.toggleLike(track)` + `liked` from isSongLiked.
- Provider append (after setHideMiniPlayer block ~line 465):
```dart
int? _requestedTab;
/// Tab switch requested from a pushed route (Explore tab bar).
int? get requestedTab => _requestedTab;
void requestTab(int index) {
  if (_requestedTab == index) return;
  _requestedTab = index;
  notifyListeners();
}
void clearRequestedTab() {
  if (_requestedTab == null) return;
  _requestedTab = null;
  notifyListeners();
}
```
- main.dart in `_MainScreenState.build`, after `final themeProvider = ...` line:
```dart
final requestedTab =
    context.select<MusicProvider, int?>((p) => p.requestedTab);
if (requestedTab != null) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    Provider.of<MusicProvider>(context, listen: false).clearRequestedTab();
    _onItemTapped(requestedTab);
  });
}
```

- [ ] Steps: implement → analyze whole repo clean → commit `feat(explore): tab bar + chrome cleanup (+tab plumbing)`.

### Task 5: Not-interested sheet row

**Files:**
- Modify: `lib/widgets/themed_options_sheet.dart` (show signature + pass-through x2)
- Modify: `lib/widgets/glass_options_sheet.dart` (show signature + ctor field + conditional row)

**Exact changes:**
```dart
// themed show(): add `VoidCallback? onDislike` param → pass to GlassOptionsSheet.show only (MY frozen).
// glass show(): add `VoidCallback? onDislike` → builder passes to ctor.
// ctor: `this.onDislike` field.
// options list, after the Share row (line ~304-318): 
if (onDislike != null)
  _buildOption(context, icon: Icons.heart_broken_rounded,
    label: 'Not interested', onTap: () {
      Navigator.pop(context);
      onDislike!.call();
    }),
```
(Verify `_buildOption(context, {icon, label, onTap})` named params from lines 163-175 before writing.)

- [ ] Steps: implement → analyze clean → commit `feat(explore): sheet Not-interested row`.

### Task 6: Tests + verify + docs

- [ ] Rewrite `test/explore_screen_widget_test.dart`:
  - harness: same batches; FakeExploreProvider += `int? tabRequested` via base methods (no override needed — test base methods directly in unit group below).
  - `header: Explore 28, no toggle` — find.text('Explore'); findsNothing Toggle autoplay.
  - `pill renders exact geometry` — pill key? keep `explore_pill_<id>` ValueKey on pill; heart Like found; long-press pill → sheet with 'Not interested' → tap → index advances. (tester.longPress(find.byKey(pillKey)) — long-press location center of pill; center hits TEXT (no gesture) → bubbles to pill long-press ✓. Then sheet (bottom sheet animation) pumpAndSettle; tap text; pumpAndSettle.)
  - `tab bar switches` — tap Library semantic → route popped (pumpAndSettle; expect find ExploreScreen gone / find Discover? test app root is ExploreScreen... popping the only route → black. Assert `find.byType(ExploreScreen), findsNothing` + provider.requestedTab cleared? After pop, requestedTab consumed by NOBODY in test (no MainScreen) → stays 2. Assert requestedTab == 2 pre-pop? After pop the provider object persists (created in test) → expect(provider.requestedTab, 2). And Home similarly.)
  - `provider tab request unit` — `fake.requestTab(0); expect(fake.requestedTab, 0); fake.requestTab(0); fake.clearRequestedTab(); expect(fake.requestedTab, isNull);`
  - keep: rows keys, drag-snap-play, eq/spin, expand, skeleton/empty. DROP: rail action finds (Like stays — in pill now; queue/share/more/not-interested-link finds removed), autoplay toggle test, jump-key test? (jump keys deleted with _NeighborRow — tap row key `explore_row_bbb` still works: row onTap→jump ✓ keep with new key).
  - `flutter test` file green.
- [ ] `flutter analyze` 0 errors; `flutter test` full green (≈248 − ~6 + ~10 ≈ 252).
- [ ] CONTEXT.md touch (tab plumbing note + pill/mesh rows).
- [ ] Commit `test(explore): glass pill + tabs coverage`, then docs commit.
- [ ] Final report (UI / INTERACTION / DISCOVERY / QUEUE / PERFORMANCE / TESTS / RUNTIME / LIMITATIONS).

## Self-Review

- Coverage: §1 arc+scale+opacity ✓ Task 1; card-strip ✓ Task 3; §2 pill exact values ✓ Task 3; §3 mesh ✓ Task 2 (palette API already ours); §4 vinyl grooves/spindle/6s ✓ Task 2, type 17/13 ✓ Task 3/tokens, EQ vibrant ✓ (accent==vibrant chain, no change); §5 header 28 + toggle removal ✓ Task 4, tab bar ✓ Task 4, breathing room ✓ (cluster deleted).
- Gaps (documented, not silent): saturate(190%) skipped (no Flutter BackdropFilter equivalent; our glass identity is blur-based); MY theme sheet omits Not-interested (frozen); autoplay toggle UI removed (controller capability kept); MainScreen consume path device-verified only.
- Types: `arcDx(double t, double a)` — update the ONE call site in explore_wheel.dart (`arcDx(t, spec.arcK, spec.maxTheta)` → `arcDx(t, spec.arcK)`); spec keeps arcK/maxTheta? maxTheta unused after — DELETE maxTheta from spec + plan() to avoid dead field (update layout tests if they reference maxTheta — they use arcDx directly; check).
- No placeholders: all code/signatures/values exact.

## Execution
Plan saved. Executing inline — same session, full context loaded.
