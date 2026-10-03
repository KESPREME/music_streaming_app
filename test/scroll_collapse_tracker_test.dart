import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/scroll_collapse_tracker.dart';

ScrollMetrics _m(double pixels) => FixedScrollMetrics(
      minScrollExtent: 0.0,
      maxScrollExtent: 500.0,
      pixels: pixels,
      viewportDimension: 400.0,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1.0,
    );

ScrollStartNotification _start(
  BuildContext context,
  double pixels, {
  bool finger = true,
}) =>
    ScrollStartNotification(
      metrics: _m(pixels),
      context: context,
      dragDetails:
          finger ? DragStartDetails(globalPosition: Offset.zero) : null,
    );

ScrollUpdateNotification _update(
  BuildContext context,
  double pixels,
  double delta, {
  bool finger = true,
}) =>
    ScrollUpdateNotification(
      metrics: _m(pixels),
      context: context,
      scrollDelta: delta,
      dragDetails: finger
          ? DragUpdateDetails(
              globalPosition: Offset.zero,
              delta: Offset(0, delta),
            )
          : null,
    );

void main() {
  testWidgets('tracker: finger, slow, programmatic, ballistic, bounce',
      (tester) async {
    await tester.pumpWidget(Container());
    final context = tester.element(find.byType(Container));

    {
      // Finger drag down past headroom hides; small continued travel
      // does not re-report without another full threshold of travel
      // (the setState gate would drop dupes anyway).
      final t = ScrollCollapseTracker();
      final reported = <bool>[];
      t.handle(_start(context, 0), reported.add);
      t.handle(_update(context, 60, 60), reported.add);
      expect(reported, [true]);
      t.handle(_update(context, 65, 5), reported.add);
      expect(reported, [true]);
    }

    {
      // Slow sub-threshold drags accumulate into a hide.
      final t = ScrollCollapseTracker();
      final reported = <bool>[];
      t.handle(_start(context, 0), reported.add);
      for (var i = 1; i <= 10; i++) {
        t.handle(_update(context, i * 6.0, 6.0), reported.add);
      }
      expect(reported, [true]);
    }

    {
      // Finger drag up reveals.
      final t = ScrollCollapseTracker();
      final reported = <bool>[];
      t.handle(_start(context, 300), reported.add);
      t.handle(_update(context, 270, -30, finger: true), reported.add);
      expect(reported, [false]);
    }

    {
      // Programmatic scroll never reports.
      final t = ScrollCollapseTracker();
      final reported = <bool>[];
      t.handle(_start(context, 0, finger: false), reported.add);
      t.handle(_update(context, 300, 300, finger: false), reported.add);
      t.handle(_update(context, 450, 150, finger: false), reported.add);
      expect(reported, isEmpty);
    }

    {
      // Ballistic tail after finger lift still hides (short flick + coast).
      final t = ScrollCollapseTracker();
      final reported = <bool>[];
      t.handle(_start(context, 0), reported.add);
      t.handle(_update(context, 10, 10), reported.add);
      t.handle(_update(context, 120, 110, finger: false), reported.add);
      expect(reported, [true]);
    }

    {
      // Edge bounce-back (ballistic, upward, no finger) does NOT reveal:
      // the slam-landing flicker that read as "it didn't go away".
      final t = ScrollCollapseTracker();
      final reported = <bool>[];
      t.handle(_start(context, 0), reported.add);
      t.handle(_update(context, 300, 300), reported.add);
      expect(reported, [true]);
      t.handle(_update(context, 250, -50, finger: false), reported.add);
      t.handle(_update(context, 220, -30, finger: false), reported.add);
      expect(reported, [true]);
    }

    {
      // Coasting back to the very top reveals even without finger travel.
      final t = ScrollCollapseTracker();
      final reported = <bool>[];
      t.handle(_start(context, 0), reported.add);
      t.handle(_update(context, 300, 300), reported.add);
      expect(reported, [true]);
      t.handle(_update(context, 4, -296, finger: false), reported.add);
      expect(reported, [true, false]);
    }
  });
}
