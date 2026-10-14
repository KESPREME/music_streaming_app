import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/covered_gate.dart';

/// THE GATE THIS FILE PINS.
///
/// The open player is an opaque, full-screen card. The page under it was still
/// being painted and animated every frame - on Impeller a retained layer is not
/// free, there is no raster cache to make it so. [CoveredGate] stops that work
/// without touching layout, and [PanelCover] decides when it is safe to.

/// Counts how often it paints, and how often a ticker under it has fired.
class _Probe extends StatefulWidget {
  const _Probe({required this.paints});
  final List<int> paints;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: const Size(100, 100),
          painter: _CountingPainter(widget.paints, controller),
        ),
      );
}

class _CountingPainter extends CustomPainter {
  _CountingPainter(this.paints, Listenable repaint) : super(repaint: repaint);
  final List<int> paints;
  @override
  void paint(Canvas canvas, Size size) => paints.add(1);
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

void main() {
  group('CoveredGate', () {
    testWidgets('uncovered, the child paints and its tickers run',
        (tester) async {
      final covered = ValueNotifier<bool>(false);
      final paints = <int>[];
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: CoveredGate(covered: covered, child: _Probe(paints: paints)),
      ));
      final before = paints.length;
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(paints.length, greaterThan(before));
    });

    testWidgets('covered, nothing paints and the ticker is muted',
        (tester) async {
      final covered = ValueNotifier<bool>(false);
      final paints = <int>[];
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: CoveredGate(covered: covered, child: _Probe(paints: paints)),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      covered.value = true;
      await tester.pump();
      final frozenAt = paints.length;
      final state = tester.state<_ProbeState>(find.byType(_Probe));
      final valueAt = state.controller.value;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(paints.length, frozenAt,
          reason: 'a covered page must not paint, or animate to paint');
      expect(state.controller.value, valueAt,
          reason: 'a muted ticker does not advance its animation');
    });

    testWidgets('uncovering resumes painting in the next frame',
        (tester) async {
      final covered = ValueNotifier<bool>(true);
      final paints = <int>[];
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: CoveredGate(covered: covered, child: _Probe(paints: paints)),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      final frozenAt = paints.length;

      covered.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(paints.length, greaterThan(frozenAt));
    });

    testWidgets('layout is untouched: the child keeps its size either way',
        (tester) async {
      final covered = ValueNotifier<bool>(false);
      var layouts = 0;
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: CoveredGate(
          covered: covered,
          child: LayoutBuilder(
            builder: (context, c) {
              layouts++;
              return SizedBox(key: key, width: 120, height: 80);
            },
          ),
        ),
      ));
      final size = tester.getSize(find.byKey(key));
      final laidOut = layouts;

      covered.value = true;
      await tester.pump();
      expect(tester.getSize(find.byKey(key)), size,
          reason: 'Offstage would have collapsed it');
      covered.value = false;
      await tester.pump();

      expect(layouts, laidOut,
          reason: 'flipping the gate must not re-lay the page out');
    });

    testWidgets('covered, hits do not reach the page', (tester) async {
      final covered = ValueNotifier<bool>(false);
      var taps = 0;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: CoveredGate(
          covered: covered,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox(width: 200, height: 200),
          ),
        ),
      ));
      await tester.tap(find.byType(GestureDetector));
      expect(taps, 1);

      covered.value = true;
      await tester.pump();
      await tester.tap(find.byType(GestureDetector), warnIfMissed: false);
      expect(taps, 1);
    });

    testWidgets(
        'a STATIC page (retained layer, nothing repainting) comes back intact',
        (tester) async {
      // The case that matters most: a page that is not animating has no reason
      // to repaint, so uncovering must re-attach its retained layer rather than
      // rely on the page redrawing itself.
      final covered = ValueNotifier<bool>(false);
      final shot = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: shot,
          child: ColoredBox(
            color: const Color(0xFF000000),
            child: CoveredGate(
              covered: covered,
              child: const RepaintBoundary(
                child: ColoredBox(color: Color(0xFFFF0000)),
              ),
            ),
          ),
        ),
      ));

      Future<int> centreRed() async => (await tester.runAsync(() async {
            final boundary =
                shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final data = await image.toByteData();
            final w = image.width, h = image.height;
            final i = ((h ~/ 2) * w + (w ~/ 2)) * 4;
            final red = data!.getUint8(i);
            image.dispose();
            return red;
          }))!;

      expect(await centreRed(), 255, reason: 'drawn while uncovered');

      covered.value = true;
      await tester.pump();
      expect(await centreRed(), 0, reason: 'not drawn while covered');

      covered.value = false;
      await tester.pump();
      expect(await centreRed(), 255,
          reason: 'back, from its retained layer, with no repaint requested');
    });

    testWidgets('flipping rebuilds the wrapper, never the child',
        (tester) async {
      final covered = ValueNotifier<bool>(false);
      var builds = 0;
      final child = Builder(builder: (_) {
        builds++;
        return const SizedBox();
      });
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: CoveredGate(covered: covered, child: child),
      ));
      expect(builds, 1);
      covered.value = true;
      await tester.pump();
      covered.value = false;
      await tester.pump();
      expect(builds, 1);
    });
  });

  group('CoveredScope', () {
    testWidgets('is false with no scope, so a widget used alone is unchanged',
        (tester) async {
      bool? seen;
      await tester.pumpWidget(Builder(builder: (context) {
        seen = CoveredScope.of(context);
        return const SizedBox();
      }));
      expect(seen, isFalse);
    });

    testWidgets('subscribers rebuild when the flag flips', (tester) async {
      final covered = ValueNotifier<bool>(false);
      final seen = <bool>[];
      await tester.pumpWidget(CoveredScope(
        covered: covered,
        child: Builder(builder: (context) {
          seen.add(CoveredScope.of(context));
          return const SizedBox();
        }),
      ));
      covered.value = true;
      await tester.pump();
      covered.value = false;
      await tester.pump();
      expect(seen, [false, true, false]);
    });

    testWidgets('peek reads without subscribing', (tester) async {
      final covered = ValueNotifier<bool>(true);
      var builds = 0;
      bool? peeked;
      await tester.pumpWidget(CoveredScope(
        covered: covered,
        child: Builder(builder: (context) {
          builds++;
          peeked = CoveredScope.peek(context);
          return const SizedBox();
        }),
      ));
      covered.value = false;
      await tester.pump();
      expect(peeked, isTrue);
      expect(builds, 1);
    });
  });

  group('PanelCover', () {
    late AnimationController panel;
    late PanelCover cover;

    Future<void> mount(WidgetTester tester, {bool Function()? frozen}) async {
      await tester.pumpWidget(_Host(
        onReady: (vsync) {
          panel = AnimationController(vsync: vsync);
          cover = PanelCover(panel, isFrozen: frozen);
        },
        // Disposed with the host: a controller outliving its TickerProvider
        // trips the framework's assertions.
        onDispose: () {
          cover.dispose();
          panel.dispose();
        },
      ));
    }

    testWidgets('covers 250ms after the panel settles fully open',
        (tester) async {
      await mount(tester);
      panel.value = 1.0;
      expect(cover.value, isFalse, reason: 'not on the same frame');

      await tester.pump(const Duration(milliseconds: 200));
      expect(cover.value, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(cover.value, isTrue);
    });

    testWidgets('uncovers in the same frame the panel starts to move',
        (tester) async {
      await mount(tester);
      panel.value = 1.0;
      await tester.pump(const Duration(milliseconds: 300));
      expect(cover.value, isTrue);

      panel.animateTo(0.0, duration: const Duration(milliseconds: 300));
      expect(cover.value, isFalse,
          reason: 'the page must be there from the first frame of a close');
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a drag from fully open uncovers immediately', (tester) async {
      await mount(tester);
      panel.value = 1.0;
      await tester.pump(const Duration(milliseconds: 300));
      expect(cover.value, isTrue);

      panel.value = 0.97;
      expect(cover.value, isFalse);
    });

    testWidgets('open -> close -> open inside the delay never covers',
        (tester) async {
      await mount(tester);
      panel.value = 1.0;
      await tester.pump(const Duration(milliseconds: 100));
      panel.value = 0.5;
      await tester.pump(const Duration(milliseconds: 50));
      panel.value = 1.0;
      await tester.pump(const Duration(milliseconds: 200));
      expect(cover.value, isFalse,
          reason: 'the delay restarts from the second settle');
      await tester.pump(const Duration(milliseconds: 100));
      expect(cover.value, isTrue);
    });

    testWidgets('never covers while a flight is still running',
        (tester) async {
      await mount(tester);
      panel.animateTo(1.0, duration: const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(cover.value, isFalse);
      await tester.pump(const Duration(milliseconds: 200)); // lands
      await tester.pump(const Duration(milliseconds: 300));
      expect(cover.value, isTrue);
    });

    testWidgets('a half-open panel is never covered', (tester) async {
      await mount(tester);
      panel.value = 0.9;
      await tester.pump(const Duration(seconds: 2));
      expect(cover.value, isFalse);
    });

    testWidgets('a frozen panel (the visual harness) is never covered',
        (tester) async {
      await mount(tester, frozen: () => true);
      panel.value = 1.0;
      await tester.pump(const Duration(seconds: 2));
      expect(cover.value, isFalse);
    });
  });
}

/// Hands the test a [TickerProvider].
class _Host extends StatefulWidget {
  const _Host({required this.onReady, required this.onDispose});
  final void Function(TickerProvider vsync) onReady;
  final VoidCallback onDispose;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.onReady(this);
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
