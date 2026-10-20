import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/jelly_icon_button.dart';
import 'package:music_streaming_app/widgets/jelly_press.dart';
import 'package:music_streaming_app/widgets/liquid_switch.dart';

/// Settings controls: the switch's thumb stretches under the finger, and
/// [JellyIconButton] gives every bare icon button the same give without touching
/// the tap, the tooltip or the semantics it already had.
Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: c!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

/// The thumb is the second AnimatedContainer under the switch (the track is the
/// first). Its own box includes the 3dp margin, so measure the painted body.
Finder _thumb() => find.descendant(
      of: find.descendant(of: find.byType(LiquidSwitch), matching: find.byType(AnimatedContainer)).at(1),
      matching: find.byType(DecoratedBox),
    );

double _bodyScale(WidgetTester t, Finder of) {
  final tr = t.widget<Transform>(find.descendant(of: of, matching: find.byType(Transform)).first);
  return tr.transform.storage[0];
}

void main() {
  group('LiquidSwitch', () {
    Future<void> mount(WidgetTester t, {bool enabled = true, bool reduceMotion = false, void Function(bool)? on}) =>
        t.pumpWidget(_host(
          LiquidSwitch(value: false, enabled: enabled, onChanged: on ?? (_) {}),
          reduceMotion: reduceMotion,
        ));

    testWidgets('the thumb is a true circle at rest (it was before the stretch existed)', (tester) async {
      await mount(tester);
      final s = tester.getSize(_thumb());
      expect(s.width, closeTo(s.height, 0.01));
      expect(s.width, closeTo(24.4, 0.01), reason: 'the size the track has always left it');
    });

    testWidgets('the thumb stretches while held and settles back on release', (tester) async {
      await mount(tester);
      expect(tester.getSize(_thumb()).width, closeTo(LiquidSwitch.restThumb, 0.01));

      final g = await tester.startGesture(tester.getCenter(find.byType(LiquidSwitch)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSize(_thumb()).width, closeTo(LiquidSwitch.heldThumb, 0.5));
      expect(tester.getSize(_thumb()).height, closeTo(LiquidSwitch.restThumb, 0.01),
          reason: 'it stretches along the track; it never grows taller');

      await g.up();
      await tester.pumpAndSettle();
      expect(tester.getSize(_thumb()).width, closeTo(LiquidSwitch.restThumb, 0.01));
    });

    testWidgets('the stretch grows toward the middle: the thumb stays on its edge', (tester) async {
      await mount(tester);
      final track = tester.getRect(find.byType(LiquidSwitch));
      final left0 = tester.getRect(_thumb()).left;
      final g = await tester.startGesture(track.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getRect(_thumb()).left, closeTo(left0, 0.5), reason: 'the left edge does not move');
      expect(tester.getRect(_thumb()).right, greaterThan(left0 + LiquidSwitch.restThumb + 4));
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a tap toggles exactly once', (tester) async {
      final seen = <bool>[];
      await mount(tester, on: seen.add);
      await tester.tap(find.byType(LiquidSwitch));
      await tester.pumpAndSettle();
      expect(seen, [true]);
    });

    testWidgets('dragging off cancels the hold and does not toggle', (tester) async {
      final seen = <bool>[];
      await mount(tester, on: seen.add);
      final g = await tester.startGesture(tester.getCenter(find.byType(LiquidSwitch)));
      await tester.pump(const Duration(milliseconds: 200));
      await g.moveBy(const Offset(0, 160));
      await g.up();
      await tester.pumpAndSettle();
      expect(seen, isEmpty);
      expect(tester.getSize(_thumb()).width, closeTo(LiquidSwitch.restThumb, 0.01));
    });

    testWidgets('a disabled switch neither stretches nor toggles', (tester) async {
      final seen = <bool>[];
      await mount(tester, enabled: false, on: seen.add);
      final g = await tester.startGesture(tester.getCenter(find.byType(LiquidSwitch)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSize(_thumb()).width, closeTo(LiquidSwitch.restThumb, 0.01));
      await g.up();
      await tester.pump();
      expect(seen, isEmpty);
    });

    testWidgets('reduce motion: no stretch, the tap still toggles', (tester) async {
      final seen = <bool>[];
      await mount(tester, reduceMotion: true, on: seen.add);
      final g = await tester.startGesture(tester.getCenter(find.byType(LiquidSwitch)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSize(_thumb()).width, closeTo(LiquidSwitch.restThumb, 0.01));
      await g.up();
      await tester.pump();
      expect(seen, [true]);
    });
  });

  group('JellyIconButton', () {
    testWidgets('is still an IconButton: same tap, same tooltip, same semantics', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(JellyIconButton(
        tooltip: 'More options',
        icon: const Icon(Icons.more_vert_rounded),
        onPressed: () => taps++,
      )));
      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byTooltip('More options'), findsOneWidget);
      final node = tester.getSemantics(find.byTooltip('More options'));
      expect(node.tooltip, 'More options');

      await tester.tap(find.byTooltip('More options'));
      await tester.pump();
      expect(taps, 1, reason: 'a passive body must not swallow or double the tap');
    });

    testWidgets('the body gives under the finger and rests afterwards', (tester) async {
      await tester.pumpWidget(_host(JellyIconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () {},
      )));
      final root = find.byType(JellyPress);
      final g = await tester.startGesture(tester.getCenter(find.byType(IconButton)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_bodyScale(tester, root), lessThan(0.95));
      await g.up();
      await tester.pumpAndSettle();
      expect(_bodyScale(tester, root), closeTo(1.0, 0.002));
    });

    testWidgets('the Material splash is switched off - the body is the answer', (tester) async {
      await tester.pumpWidget(_host(JellyIconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () {},
      )));
      final inside = tester.element(find.byIcon(Icons.close_rounded));
      final theme = Theme.of(inside);
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.iconButtonTheme.style?.splashFactory, NoSplash.splashFactory);
    });

    testWidgets('disabled: no give, no tap', (tester) async {
      await tester.pumpWidget(_host(const JellyIconButton(
        tooltip: 'Paste',
        icon: Icon(Icons.content_paste_rounded),
        onPressed: null,
      )));
      expect(find.byType(Transform).evaluate().where((e) => e.findAncestorWidgetOfExactType<JellyPress>() != null), isEmpty,
          reason: 'a dimmed control does not move');
    });

    testWidgets('a scroll that starts on it is a scroll: it lets go', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            for (var i = 0; i < 30; i++)
              SizedBox(
                height: 56,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: JellyIconButton(
                    tooltip: 'Row $i',
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () {},
                  ),
                ),
              ),
          ]),
        ),
      ));
      final first = find.byTooltip('Row 0');
      final g = await tester.startGesture(tester.getCenter(first));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveBy(const Offset(0, -80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await g.up();
      await tester.pumpAndSettle();
      final root = find.ancestor(of: first, matching: find.byType(JellyPress));
      expect(_bodyScale(tester, root), closeTo(1.0, 0.002));
    });
  });
}
