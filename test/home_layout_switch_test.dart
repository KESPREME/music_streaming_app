import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/presentation/home/home_view_mode.dart';
import 'package:music_streaming_app/widgets/home_layout_switch.dart';
import 'package:music_streaming_app/widgets/section_view_toggle.dart';

/// Scale applied by the nearest [Transform] at or above [finder].
///
/// [BuildContext.visitAncestorElements] walks parent to root, so the FIRST
/// transform found is the one that actually scales this subtree. Taking the last
/// reports whatever transform the app root applies, which is a constant 1.0 and
/// makes every assertion here pass for the wrong reason.
double _scaleAbove(WidgetTester tester, Finder finder) {
  final matches = finder.evaluate();
  if (matches.isEmpty) return -1.0; // absent
  final context = matches.first;
  double? scale;
  final self = context.widget;
  if (self is Transform) {
    scale = self.transform.storage[0];
  }
  context.visitAncestorElements((element) {
    if (scale == null) {
      final widget = element.widget;
      if (widget is Transform) {
        scale = widget.transform.storage[0];
      }
    }
    return scale == null;
  });
  return scale ?? 1.0;
}

/// Single-finder convenience wrapper around [_recordSwapPair].
Future<List<double>> _recordSwap1(
  WidgetTester tester,
  Finder finder, {
  int frames = 12,
}) async {
  final (first, _) = await _recordSwapPair(tester, finder, finder, frames: frames);
  return first;
}

/// Samples two finders' scales together across one transition.
///
/// Recording them in separate passes does not work: the first pass consumes the
/// whole animation, so the second reads a settled tree.
Future<(List<double>, List<double>)> _recordSwapPair(
  WidgetTester tester,
  Finder a,
  Finder b, {
  int frames = 12,
}) async {
  final first = <double>[];
  final second = <double>[];
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    first.add(_scaleAbove(tester, a));
    second.add(_scaleAbove(tester, b));
  }
  return (first, second);
}

Widget _switch({required bool isCard}) => MaterialApp(
      home: Scaffold(
        body: HomeLayoutSwitch(
          isCard: isCard,
          card: const SizedBox(
            height: 400,
            child: Text('CARD', textDirection: TextDirection.ltr),
          ),
          list: const SizedBox(
            height: 100,
            child: Text('LIST', textDirection: TextDirection.ltr),
          ),
        ),
      ),
    );

void main() {
  group('layout swap has no ghost', () {
    testWidgets('the departing body shrinks away instead of lingering',
        (tester) async {
      await tester.pumpWidget(_switch(isCard: true));
      await tester.pump();
      await tester.pumpWidget(_switch(isCard: false));

      final samples = await _recordSwap1(tester, find.text('CARD'));
      final whilePresent = samples.where((s) => s >= 0).toList();

      expect(whilePresent, isNotEmpty,
          reason: 'the outgoing body should be observable mid-swap');
      // A shared 0.94-to-1.0 scale ends the departing body at 0.94: fully
      // painted on top of the arriving one until the switcher drops it, which is
      // what made the swap look like it arrived before it finished.
      expect(whilePresent.last, lessThan(0.2),
          reason: 'departing body must reach ~0, not park near full size');
    });

    testWidgets('the arriving body grows in rather than shrinking away',
        (tester) async {
      await tester.pumpWidget(_switch(isCard: true));
      await tester.pump();
      await tester.pumpWidget(_switch(isCard: false));

      final samples = await _recordSwap1(tester, find.text('LIST'));
      final whilePresent = samples.where((s) => s >= 0).toList();

      // Reading the roles backwards - which inferring them from the animation
      // did - made the NEW layout run to zero while the old one stayed put.
      expect(whilePresent.first, greaterThan(0.9),
          reason: 'arriving body must start near full size');
      expect(whilePresent.last, closeTo(1.0, 0.01));
    });

    testWidgets('the roles are right in BOTH directions', (tester) async {
      // Only the card-to-list direction was exercised above; a morph that works
      // one way and not the other is still broken. Both bodies are sampled in a
      // single pass - a second pass would read a tree that has already settled.
      await tester.pumpWidget(_switch(isCard: false));
      await tester.pump();
      await tester.pumpWidget(_switch(isCard: true));

      final (arriving, departing) = await _recordSwapPair(
        tester,
        find.text('CARD'),
        find.text('LIST'),
      );
      final arrivingLive = arriving.where((s) => s >= 0).toList();
      final departingLive = departing.where((s) => s >= 0).toList();

      expect(arrivingLive.first, greaterThan(0.9));
      expect(arrivingLive.last, closeTo(1.0, 0.01));
      expect(departingLive.last, lessThan(0.2));
    });

    testWidgets('the height collapses in one pass', (tester) async {
      await tester.pumpWidget(_switch(isCard: true));
      await tester.pump();
      await tester.pumpWidget(_switch(isCard: false));

      final heights = <double>[];
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        heights.add(tester.getSize(find.byType(HomeLayoutSwitch)).height);
      }

      // Monotonic and continuous: no plateau at the old height followed by a
      // second collapse, which is what a Stack that still sizes to the departing
      // body produces.
      for (var i = 1; i < heights.length; i++) {
        expect(heights[i], lessThanOrEqualTo(heights[i - 1] + 0.5));
      }
      expect(heights.last, closeTo(100.0, 0.5));
    });

    testWidgets('nothing overflows or throws during the swap', (tester) async {
      await tester.pumpWidget(_switch(isCard: true));
      await tester.pump();
      await tester.pumpWidget(_switch(isCard: false));
      await _recordSwap1(tester, find.text('CARD'));
      expect(tester.takeException(), isNull);
    });
  });

  group('view toggle glyph morph', () {
    Future<void> tapOnce(WidgetTester tester) async {
      var mode = HomeSectionViewMode.card;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(builder: (context, setState) {
          return Scaffold(
            body: Center(
              child: SectionViewToggle(
                mode: mode,
                onToggle: () => setState(() => mode = mode.toggled),
              ),
            ),
          );
        }),
      ));
      await tester.pump();
      await tester.tap(find.byType(SectionViewToggle));
    }

    testWidgets('the old glyph leaves instead of ghosting', (tester) async {
      await tapOnce(tester);

      // The control shows the layout it will switch TO, so while mode=card the
      // glyph on screen is the "go to list" one, and that is the glyph that has
      // to leave.
      final old = await _recordSwap1(
        tester,
        find.byIcon(Icons.view_agenda_outlined),
      );
      final whilePresent = old.where((s) => s >= 0).toList();
      expect(whilePresent, isNotEmpty);
      // Shared with the arriving glyph, this parked the old one at 0.6, fully
      // painted, for the entire transition.
      expect(whilePresent.last, lessThan(0.2));
    });

    testWidgets('the new glyph arrives and completes', (tester) async {
      await tapOnce(tester);

      final incoming =
          (await _recordSwap1(tester, find.byIcon(Icons.grid_view_rounded)))
              .where((s) => s >= 0)
              .toList();
      expect(incoming.first, greaterThan(0.5));
      expect(incoming.last, closeTo(1.0, 0.01));
    });

    testWidgets('only one glyph is left when the morph ends', (tester) async {
      await tapOnce(tester);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.view_agenda_outlined), findsNothing);
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    });
  });
}

