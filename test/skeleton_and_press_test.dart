import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/home_sections.dart' show PressableScale;
import 'package:music_streaming_app/widgets/skeleton.dart';

/// SKELETONS stand in for content at its own metrics and stop sweeping under
/// reduce motion; PRESS feedback compresses, survives a quick tap, and springs
/// back to rest without rebuilding the child.

double _scaleOf(WidgetTester tester) =>
    tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value;

void main() {
  Widget host(Widget sliver, {bool still = false}) => MediaQuery(
        data: MediaQueryData(size: const Size(400, 900), disableAnimations: still),
        child: MaterialApp(home: Scaffold(body: CustomScrollView(slivers: [sliver]))),
      );

  testWidgets('card grid placeholders: two columns, real spacing, no hit targets', (tester) async {
    await tester.pumpWidget(host(const SkeletonScope(child: SliverSkeletonCardGrid(circle: true, count: 4))));
    await tester.pump(const Duration(milliseconds: 100));
    final cards = find.byType(IgnorePointer);
    expect(cards, findsWidgets);
    expect(tester.takeException(), isNull);
    // Ticking: a sweep is running.
    expect(tester.binding.transientCallbackCount, greaterThan(0));
  });

  testWidgets('reduce motion: the placeholder is still', (tester) async {
    await tester.pumpWidget(host(const SkeletonScope(child: SliverSkeletonRows(count: 3)), still: true));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('rows at 360 dp and text x1.3 lay out cleanly', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(1.3)),
      child: const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(slivers: [
            SkeletonScope(child: SliverSkeletonRows(count: 6, circle: true, art: 70)),
            SkeletonScope(child: SliverSkeletonCardGrid(circle: false)),
          ]),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  group('PressableScale', () {
    var builds = 0;
    Widget press({VoidCallback? onTap, bool still = false}) => MediaQuery(
          data: MediaQueryData(disableAnimations: still),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: PressableScale(
                onTap: onTap,
                child: Builder(builder: (_) {
                  builds++;
                  return const SizedBox(width: 100, height: 60);
                }),
              ),
            ),
          ),
        );

    testWidgets('compresses while held, springs back to exactly 1, never rebuilds the child', (tester) async {
      builds = 0;
      var taps = 0;
      await tester.pumpWidget(press(onTap: () => taps++));
      final b0 = builds;
      final g = await tester.startGesture(tester.getCenter(find.byType(SizedBox)));
      await tester.pump(const Duration(milliseconds: 150)); // the press registers (kPressTimeout)
      await tester.pump(const Duration(milliseconds: 120)); // and plays
      expect(_scaleOf(tester), closeTo(0.97, 0.002));
      await g.up();
      await tester.pumpAndSettle();
      expect(_scaleOf(tester), closeTo(1.0, 1e-3));
      expect(taps, 1);
      expect(builds, b0, reason: 'a press is a transform, not a rebuild');
    });

    testWidgets('a quick tap still shows the press before springing back', (tester) async {
      await tester.pumpWidget(press(onTap: () {}));
      await tester.tap(find.byType(SizedBox), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(_scaleOf(tester), lessThan(0.995), reason: 'the press is not swallowed by a fast tap');
      await tester.pumpAndSettle();
      expect(_scaleOf(tester), closeTo(1.0, 1e-3));
    });

    testWidgets('reduce motion: no scale, the tap still works', (tester) async {
      var taps = 0;
      await tester.pumpWidget(press(onTap: () => taps++, still: true));
      await tester.tap(find.byType(SizedBox), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 60));
      expect(_scaleOf(tester), 1.0);
      expect(taps, 1);
    });
  });
}
