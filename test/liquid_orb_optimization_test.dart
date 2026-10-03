import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/screens/library_screen.dart';
import 'package:music_streaming_app/widgets/library/library_brand_promo_card.dart';
import 'package:music_streaming_app/widgets/library/library_hero_artwork.dart';
import 'package:music_streaming_app/widgets/themed_library_screen.dart';

/// Regression guards for the Phase 2 "zero visual change" performance work.
///
/// The Liquid Orb is the most expensive thing in the app: a per-pixel fragment
/// shader (shaders/liquid_orb.frag evaluates a 4-octave FBM three times per
/// pixel for RGB dispersion). It is driven by an always-repeating
/// AnimationController, so if it ticks while the Library tab is off-screen it
/// burns GPU on a tab nobody can see. `FadeIndexedStack` keeps every tab alive
/// and does not emit TickerMode, so the gating has to be explicit.
///
/// Note: these assert on *frame scheduling*, not pixels — `hasScheduledFrame`
/// going false is the observable proof that the ticker stopped.
void main() {
  group('LiquidOrb visibility gating', () {
    testWidgets('active orb keeps scheduling frames (animation runs)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: LiquidOrb(size: Size(80, 80), isActive: true)),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'an active orb must keep animating');
    });

    testWidgets('inactive orb stops scheduling frames', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: LiquidOrb(size: Size(80, 80), isActive: false)),
      ));
      // Drain anything already queued, then confirm nothing re-schedules.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'an off-screen orb must not tick');
    });

    testWidgets('toggling isActive resumes and suspends without error',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: LiquidOrb(size: Size(80, 80), isActive: false)),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const MaterialApp(
        home: Center(child: LiquidOrb(size: Size(80, 80), isActive: true)),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);

      await tester.pumpWidget(const MaterialApp(
        home: Center(child: LiquidOrb(size: Size(80, 80), isActive: false)),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('disposing an active orb releases the GPU shader cleanly',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: LiquidOrb(size: Size(80, 80))),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      // The FragmentShader is a single reused instance disposed in
      // State.dispose(); this fails if it is double-freed or outlives State.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });
  });

  group('isActive is threaded through the whole orb chain', () {
    // These read the public fields directly, so they need no provider and no
    // pumping. They fail to COMPILE if anyone drops the parameter, which is
    // the guard we actually want for the wiring.
    test('every layer defaults to active (no behaviour regression)', () {
      expect(const LiquidOrb(size: Size(1, 1)).isActive, isTrue);
      expect(const LibraryHeroArtwork().isActive, isTrue);
      expect(const LibraryBrandPromoCard().isActive, isTrue);
      expect(const LibraryScreen().isActive, isTrue);
      expect(const ThemedLibraryScreen().isActive, isTrue);
    });

    test('every layer accepts an explicit inactive flag', () {
      expect(const LiquidOrb(size: Size(1, 1), isActive: false).isActive, isFalse);
      expect(const LibraryHeroArtwork(isActive: false).isActive, isFalse);
      expect(const LibraryBrandPromoCard(isActive: false).isActive, isFalse);
      expect(const LibraryScreen(isActive: false).isActive, isFalse);
      expect(const ThemedLibraryScreen(isActive: false).isActive, isFalse);
    });
  });
}
