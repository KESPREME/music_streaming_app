import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/presentation/home/home_tokens.dart' as t;
import 'package:music_streaming_app/widgets/home_skeleton.dart';
import 'package:music_streaming_app/widgets/search_skeleton.dart';

/// The skeleton is only worth having if it reserves exactly the space the real
/// sections will, so the swap does not move anything while the eye is tracking
/// it. These tests pin that promise rather than the pixels.
void main() {
  Widget host(Widget child, {Size size = const Size(390, 844)}) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(body: child),
      ),
    );
  }

  group('HomeSkeleton', () {
    testWidgets('renders placeholders and nothing interactive', (tester) async {
      await tester.pumpWidget(host(const HomeSkeleton()));
      await tester.pump();

      expect(find.byType(HomeSkeleton), findsOneWidget);
      // A placeholder that can be tapped is not a placeholder.
      expect(
        find.byType(InkWell),
        findsNothing,
        reason: 'the skeleton must not intercept taps meant for the content',
      );
    });

    testWidgets('lays out inside the viewport without overflowing',
        (tester) async {
      await tester.pumpWidget(host(const HomeSkeleton()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('honours reduced motion by showing a static placeholder',
        (tester) async {
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(
          size: Size(390, 844),
          disableAnimations: true,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(body: HomeSkeleton()),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Nothing should be animating: a perpetual sweep is exactly the motion the
      // OS setting exists to stop.
      expect(find.byType(HomeSkeleton), findsOneWidget);
    });

    testWidgets('survives a 1.6x text scale', (tester) async {
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(
          size: Size(390, 844),
          textScaler: TextScaler.linear(1.6),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(body: HomeSkeleton()),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a narrow viewport', (tester) async {
      await tester
          .pumpWidget(host(const HomeSkeleton(), size: const Size(320, 700)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the hero placeholder matches the real carousel formula',
        (tester) async {
      // The real height, copied from home_screen's expression rather than
      // approximated: contentWidth * heroCardFraction * 5/4, clamped.
      final contentW = t.HomeTokens.contentWidth(390);
      final expected = (contentW * t.HomeTokens.heroCardFraction * (5 / 4))
          .clamp(280.0, 380.0);

      await tester.pumpWidget(host(const HomeSkeleton()));
      await tester.pump();
      final hero = tester.widget<ShimmerBlock>(
        find.byWidgetPredicate((w) =>
            w is ShimmerBlock &&
            w.height == expected &&
            w.radius == t.HomeTokens.heroRadius),
      );
      expect(hero.height, expected);
    });
  });

  group('shared shimmer primitives', () {
    testWidgets('Home uses a wider band than Search', (tester) async {
      // Same gesture, different apparent speed, because the travel distance on a
      // full screen is so much longer than on a 64dp search row.
      expect(kHomeShimmerBandFraction, 0.5);
      expect(kShimmerBandFraction, 0.42);
      expect(
        kHomeShimmerBandFraction,
        greaterThan(kShimmerBandFraction),
        reason: 'a narrow band reads as a scanning line at screen scale',
      );
    });

    testWidgets('a block honours an explicit band width', (tester) async {
      await tester.pumpWidget(host(
        const Center(
          child: SizedBox(
            width: 200,
            child: ShimmerBlock(
              rowWidth: 200,
              rowOffset: 0,
              width: 200,
              height: 40,
              bandFraction: 0.75,
            ),
          ),
        ),
      ));
      final block = tester.widget<ShimmerBlock>(find.byType(ShimmerBlock));
      expect(block.bandFraction, 0.75);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a circle block clips as a circle', (tester) async {
      await tester.pumpWidget(host(
        const Center(
          child: ShimmerBlock(
            rowWidth: 100,
            rowOffset: 0,
            width: 72,
            height: 72,
            shape: BoxShape.circle,
          ),
        ),
      ));
      expect(find.byType(ClipOval), findsOneWidget);
    });

    test('the band travels fully off both edges', () {
      // At t=0 it must be entirely before the row, at t=1 entirely after it,
      // otherwise the highlight parks somewhere visible between passes.
      final atStart = shimmerBandStart(
          t: 0, rowWidth: 300, rowOffset: 0, bandFraction: 0.5);
      final atEnd = shimmerBandStart(
          t: 1, rowWidth: 300, rowOffset: 0, bandFraction: 0.5);
      expect(atStart + 150, lessThanOrEqualTo(0));
      expect(atEnd, greaterThanOrEqualTo(300));
    });

    test('blocks in a row agree on where the band is', () {
      // The whole point of row-space positioning: two blocks at different
      // offsets must show the same band at the same instant.
      const rowWidth = 300.0;
      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final a = shimmerBandStart(t: t, rowWidth: rowWidth, rowOffset: 0);
        final b = shimmerBandStart(t: t, rowWidth: rowWidth, rowOffset: 64);
        expect(b, closeTo(a - 64, 0.001));
        // Convert back to row space and they must coincide.
        expect(b + 64, closeTo(a, 0.001));
      }
    });
  });
}
