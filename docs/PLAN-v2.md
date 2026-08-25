# Plan v2 — Stability, Liquid-Glass Motion, Swipe Discovery

Trigger: user field report + screenshots (docs/screenshots-current). Playback skips
through queue and stops; For You spinner forever; Settings opens black; UI reads
"mediocre" vs Muzo v5 reference (Muzo/Muzo-main/images/latest-screenshots).

## Phase A — Stability & Diagnostics (P0, blocks everything)
1. **Log capture**: `adb logcat | findstr flutter` (or `flutter run`) while
   reproducing: tap song → observe resolve → player error text. Classify:
   resolution failure (no URL) vs player failure (URL rejected).
2. **Playback resilience** (music_provider):
   - `_handlePlaybackError`: per-track failure memo (no re-skip loop on same id),
     cap auto-skip at 1, surface error via SnackBar + error tile with Retry in
     mini-player area. Never silent-stop.
   - Verify `resolvedHeaders` path: Saavn URLs must NOT get VR UA (only
     googlevideo does). Sniffer already keys off `c=` param — confirm Saavn
     leg passes `headers: null`.
3. **For You fallback chain**: recommendedTracks empty → trending → homeTracks.
   Replace tiny red spinner with skeleton list (reuse _SectionSkeleton pattern).
4. **Settings blackout**: reproduce in debug; likely exception swallowed by
   glass surface or pure-black scaffold with black content. Fix + add
   FlutterError.onError logging in that route.

## Phase B — Liquid Glass Motion (the "droplet")
1. Research `liquid_glass_widgets` gesture/morph API (LiquidGlassInteraction,
   custom shaders) — 30 min spike, decide custom vs package.
2. NavBar long-press: icon melts into draggable droplet blob; release over
   another tab → spring-merge morph into its pill (spring: stiffness 380,
   damping 24). FPS-gated: falls back to plain glow on jank.
3. Press fluidity: squish+sheen on all GlassTier.chrome surfaces.

## Phase C — Nav restructure (Muzo split-pill)
- Pill holds 3: **Home · Social · Library**. **Search** = floating glass circle
  (left), **Settings** = floating glass circle (right). Matches Muzo ref.
- Remove inner home tabs (Feed/Discover/Explore) → Home becomes single scroll:
  Top Picks heroes → swipe deck teaser → Jump Back In → What's Hot.
- Discover tab content moves to its own nav destination (Phase D) replacing the
  stub Social placeholder position decision: Social stays (styled empty-state),
  Discover becomes 4th element? NO — per user: pill=3, circles=2, total 5
  destinations max: Home, Search(circle), Social, Library, Settings(circle).
  Discover swipe deck lives INSIDE Home as hero section (see D).

## Phase D — Swipe Discovery (dating-style deck)
1. `SwipeDeck` widget: card stack, next card peeks (scale 0.94, y+12).
   Drag: rotate ±12°, opacity fade at threshold; spring return on cancel.
2. Gestures: right=like (records positive signal + plays), left=skip (negative
   signal), up=queue next. Buttons: undo/like/skip under deck.
3. Signal feed → RecommendationAgent.recordSwipe() (new) → taste weighting
   (merges old Phase 5.2): genre/artist affinity vector, decay 14 days.
4. Pool: trending + new releases + mood tracks, deduped, taste-ranked.
5. Peek carousel above deck: HeroTrackCard row with 0.86 viewportFraction.

## Phase E — Settings & Library redesign
1. Settings: Muzo-minimal list — grouped glass list tiles, 16px rhythm, no
   blackout, accent header. Sections: Playback (Auto Queue, quality), Appearance
   (accent, album-adaptive), Storage, About.
2. Library: real glass depth on tiles (chrome tier where static), animated
   press, count badges (playlists/downloads), sticky chip bar fix (clip bug),
   staggered entrance (30ms/item).

## Phase F — Social tab v1
- Styled empty-state now; v1 scope: "Friends' rotation" from local listening
  history share link (defer backend). Keep honest placeholder.

## Phase G — Final gate
- analyze 0 errors, full test suite, APK, manual smoke (play/search/discover/
  swipe/settings), then commit (user approval).

Order: A → B → C → D → E → F → G. A blocks D (recommendation signals need
working playback).
