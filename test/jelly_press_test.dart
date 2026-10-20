import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/jelly_press.dart';

/// JellyPress as a widget: that a touch is routed correctly (a tap taps once, a
/// hold holds, a drag-off cancels), that the body really moves, that nothing
/// buzzes twice, and that the child is left alone. The feel is the physics'
/// (jelly_spring_test.dart); this is the plumbing around it.
class _Probe extends StatefulWidget {
  const _Probe({this.counter});

  final List<int>? counter;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) {
    widget.counter?[0]++;
    return const SizedBox(key: ValueKey('body'), width: 120, height: 48);
  }
}

Widget _host(Widget child, {bool reduce = false, Alignment at = Alignment.center}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduce),
        child: Scaffold(body: Align(alignment: at, child: child)),
      ),
    );

double _scaleX(WidgetTester t) {
  final tr = t.widget<Transform>(find.descendant(of: find.byType(JellyPress), matching: find.byType(Transform)).first);
  return tr.transform.storage[0];
}

double _scaleY(WidgetTester t) {
  final tr = t.widget<Transform>(find.descendant(of: find.byType(JellyPress), matching: find.byType(Transform)).first);
  return tr.transform.storage[5];
}

void main() {
  final haptics = <String>[];

  setUp(() {
    haptics.clear();
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('taps', () {
    testWidgets('a tap taps exactly once', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(JellyPress(onTap: () => taps++, child: const _Probe())));
      await tester.tap(find.byKey(const ValueKey('body')));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('the callback fires on release, not after the spring (tests and users both need that)',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(JellyPress(onTap: () => taps++, child: const _Probe())));
      await tester.tap(find.byKey(const ValueKey('body')));
      expect(taps, 1, reason: 'before any pump');
    });

    testWidgets('a long press long-presses and does not tap', (tester) async {
      var taps = 0, longs = 0;
      await tester.pumpWidget(_host(JellyPress(
        onTap: () => taps++,
        onLongPress: () => longs++,
        child: const _Probe(),
      )));
      await tester.longPress(find.byKey(const ValueKey('body')));
      await tester.pumpAndSettle();
      expect([taps, longs], [0, 1]);
    });

    testWidgets('a disabled or empty JellyPress is just its child', (tester) async {
      await tester.pumpWidget(_host(const JellyPress(child: _Probe())));
      expect(find.descendant(of: find.byType(JellyPress), matching: find.byType(Listener)), findsNothing);
      await tester.pumpWidget(_host(JellyPress(enabled: false, onTap: () {}, child: const _Probe())));
      expect(find.descendant(of: find.byType(JellyPress), matching: find.byType(Listener)), findsNothing);
    });
  });

  group('motion', () {
    testWidgets('at rest the body is untouched (scale exactly 1)', (tester) async {
      await tester.pumpWidget(_host(JellyPress(onTap: () {}, child: const _Probe())));
      expect([_scaleX(tester), _scaleY(tester)], [1, 1]);
    });

    testWidgets('a finger down compresses it, and HOLDING keeps it compressed', (tester) async {
      await tester.pumpWidget(_host(JellyPress(
        onTap: () {},
        profile: JellyProfile.pill,
        child: const _Probe(),
      )));
      final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('body'))));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_scaleX(tester), closeTo(JellyProfile.pill.pressScale, 0.02));
      // Held for two seconds: still down there.
      await tester.pump(const Duration(seconds: 2));
      expect(_scaleX(tester), closeTo(JellyProfile.pill.pressScale, 0.02));
      await g.up();
      await tester.pumpAndSettle();
      expect([_scaleX(tester), _scaleY(tester)], [1, 1], reason: 'settles to exactly 1');
    });

    testWidgets('on release it passes rest (the wobble) before it settles', (tester) async {
      await tester.pumpWidget(_host(JellyPress(onTap: () {}, child: const _Probe())));
      final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('body'))));
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      var peak = 0.0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        peak = peak > _scaleX(tester) ? peak : _scaleX(tester);
      }
      expect(peak, greaterThan(1.015), reason: 'peak $peak');
      expect(peak, lessThan(1.06));
    });

    testWidgets('a drag toward the side stretches it wider and shorter, keeping its volume', (tester) async {
      await tester.pumpWidget(_host(JellyPress(onTap: () {}, child: const _Probe())));
      final c = tester.getCenter(find.byKey(const ValueKey('body')));
      final g = await tester.startGesture(c);
      await g.moveTo(c + const Offset(45, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 250));
      final sx = _scaleX(tester), sy = _scaleY(tester);
      expect(sx / sy, greaterThan(1.0), reason: 'wider than tall: $sx x $sy');
      // Area equals the pressed scale squared.
      expect(sx * sy, closeTo(JellyProfile.pill.pressScale * JellyProfile.pill.pressScale, 0.01));
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('it leans toward the finger', (tester) async {
      await tester.pumpWidget(_host(JellyPress(onTap: () {}, child: const _Probe())));
      final body = find.byKey(const ValueKey('body'));
      final c = tester.getCenter(body);
      // getCenter reads the LAYOUT rect, which a paint-time transform leaves
      // alone; where the body is actually drawn is its paint transform.
      Offset painted() {
        final box = tester.renderObject<RenderBox>(body);
        return MatrixUtils.transformPoint(box.getTransformTo(null), box.size.center(Offset.zero));
      }

      expect(painted().dx, closeTo(c.dx, 0.01));
      final g = await tester.startGesture(c);
      await g.moveTo(c + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 250));
      expect(painted().dx, greaterThan(c.dx + 1), reason: 'leaning right');
      expect(painted().dx, lessThan(c.dx + JellyProfile.pill.follow * 48 + 0.5), reason: 'rubber-banded');
      await g.up();
      await tester.pumpAndSettle();
      expect(painted().dx, closeTo(c.dx, 0.01));
    });

    testWidgets('dragging OFF the control lets go and does not tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(JellyPress(onTap: () => taps++, child: const _Probe())));
      final c = tester.getCenter(find.byKey(const ValueKey('body')));
      final g = await tester.startGesture(c);
      await tester.pump(const Duration(milliseconds: 200));
      await g.moveTo(c + const Offset(0, 160));
      await tester.pumpAndSettle();
      expect([_scaleX(tester), _scaleY(tester)], [1, 1], reason: 'it let go of the body');
      await g.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
    });

    testWidgets('a scroll taking the gesture releases the body', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              JellyPress(onTap: () => taps++, child: const SizedBox(key: ValueKey('row'), height: 60)),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ));
      final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('row'))));
      await tester.pump(const Duration(milliseconds: 150));
      await g.moveBy(const Offset(0, -120));
      await tester.pumpAndSettle();
      await g.up();
      await tester.pumpAndSettle();
      expect(taps, 0, reason: 'a scroll is not a tap');
      expect(_scaleX(tester), 1);
    });
  });

  group('reduce motion', () {
    testWidgets('no movement at all, and the tap still works', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(JellyPress(onTap: () => taps++, child: const _Probe()), reduce: true));
      final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('body'))));
      await tester.pump(const Duration(milliseconds: 300));
      expect([_scaleX(tester), _scaleY(tester)], [1, 1]);
      await g.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('the child', () {
    testWidgets('is built ONCE however long it is pressed, dragged and released', (tester) async {
      final builds = [0];
      await tester.pumpWidget(_host(JellyPress(onTap: () {}, child: _Probe(counter: builds))));
      final base = builds[0];
      final c = tester.getCenter(find.byKey(const ValueKey('body')));
      final g = await tester.startGesture(c);
      await g.moveTo(c + const Offset(30, 8));
      await tester.pump(const Duration(milliseconds: 400));
      await g.up();
      await tester.pumpAndSettle();
      expect(builds[0], base);
    });
  });

  group('haptics: one per touch', () {
    testWidgets('a tap buzzes exactly once, of the kind asked for', (tester) async {
      await tester.pumpWidget(_host(JellyPress(onTap: () {}, haptic: JellyHaptic.light, child: const _Probe())));
      await tester.tap(find.byKey(const ValueKey('body')));
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('selection by default', (tester) async {
      await tester.pumpWidget(_host(JellyPress(onTap: () {}, child: const _Probe())));
      await tester.tap(find.byKey(const ValueKey('body')));
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('none stays silent (the call site plays its own)', (tester) async {
      await tester.pumpWidget(_host(JellyPress(onTap: () {}, haptic: JellyHaptic.none, child: const _Probe())));
      await tester.tap(find.byKey(const ValueKey('body')));
      await tester.pumpAndSettle();
      expect(haptics, isEmpty);
    });

    testWidgets('pressing and dragging away buzzes nothing', (tester) async {
      await tester.pumpWidget(_host(JellyPress(onTap: () {}, child: const _Probe())));
      final c = tester.getCenter(find.byKey(const ValueKey('body')));
      final g = await tester.startGesture(c);
      await g.moveTo(c + const Offset(0, 200));
      await g.up();
      await tester.pumpAndSettle();
      expect(haptics, isEmpty);
    });
  });

  group('glow (floating glass only)', () {
    testWidgets('chrome blooms a light under the finger; pill does not', (tester) async {
      await tester.pumpWidget(_host(JellyPress(onTap: () {}, profile: JellyProfile.chrome, borderRadius: 24, child: const _Probe())));
      expect(find.descendant(of: find.byType(JellyPress), matching: find.byType(CustomPaint)), findsWidgets);
      await tester.pumpWidget(_host(JellyPress(onTap: () {}, profile: JellyProfile.pill, child: const _Probe())));
      final glow = find.descendant(of: find.byType(JellyPress), matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null));
      expect(glow, findsNothing);
    });
  });

  group('beside a drag arena', () {
    testWidgets('does not steal a horizontal drag from an ancestor', (tester) async {
      var dragged = 0.0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            onHorizontalDragUpdate: (d) => dragged += d.delta.dx,
            child: Center(child: JellyPress(onTap: () {}, child: const _Probe())),
          ),
        ),
      ));
      final c = tester.getCenter(find.byKey(const ValueKey('body')));
      await tester.dragFrom(c, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(dragged, greaterThan(60));
    });
  });
}
