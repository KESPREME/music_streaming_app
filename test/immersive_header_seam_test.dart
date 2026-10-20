import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/artwork_wash.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/immersive_header.dart';

/// THE SEAM, MEASURED.
///
/// The old header drew a visible dark band where the photo met the page. These
/// tests render the header over the worst possible photo (pure white, so any
/// leftover photo at the join is a huge step), read the actual pixels, and
/// assert there is no line: no step bigger than the gradient's own slope
/// anywhere in the fade, and the header's last row IS the page colour.
const _wash = Color(0xFF2A1A18);
const _bg = Color(0xFF0E0A0A);
const double _headerH = 420;
const double _w = 400;
const double _screenH = 900;

int _lum(Uint8List px, int x, int y) {
  final i = (y * _w.toInt() + x) * 4;
  return ((0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2])).round();
}

List<int> _rgb(Uint8List px, int x, int y) {
  final i = (y * _w.toInt() + x) * 4;
  return [px[i], px[i + 1], px[i + 2]];
}

Future<Uint8List> _render(WidgetTester tester, Widget content) async {
  tester.view.physicalSize = const Size(_w, _screenH);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(_w, _screenH), devicePixelRatio: 1.0),
      child: RepaintBoundary(key: key, child: content),
    ),
  ));
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

Widget _page({ScrollController? controller}) {
  return Stack(
    children: [
      Positioned.fill(
        child: ArtworkWash(
          backgroundColor: _bg,
          washColor: _wash,
          accentColor: const Color(0xFFFF8040),
          elevatedColor: const Color(0xFF402820),
          washFraction: _headerH / _screenH,
          seamOverhang: 160,
          meshInset: 120,
        ),
      ),
      CustomScrollView(
        controller: controller,
        slivers: [
          SliverToBoxAdapter(
            child: ImmersiveHeader(
              height: _headerH,
              washColor: _wash,
              scrollController: controller,
              photo: const ColoredBox(color: Colors.white),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 1200)),
        ],
      ),
    ],
  );
}

void main() {
  group('fade maths', () {
    test('smootherstep has zero slope at both ends and is monotonic', () {
      expect(immersiveSmootherstep(0), 0);
      expect(immersiveSmootherstep(1), 1);
      var last = -1.0;
      for (var i = 0; i <= 200; i++) {
        final v = immersiveSmootherstep(i / 200);
        expect(v, greaterThanOrEqualTo(last));
        last = v;
      }
      expect(immersiveSmootherstep(0.005), lessThan(1e-4));
      expect(1 - immersiveSmootherstep(0.995), lessThan(1e-4));
    });

    test('the fade lands before the last row and the tail is flat and opaque', () {
      final g = immersiveFadeGradient(_wash);
      final tail = [for (var i = 0; i < g.stops!.length; i++) if (g.stops![i] >= kImmersiveFadeLandsAt) g.colors[i]];
      expect(tail, isNotEmpty);
      for (final c in tail) {
        expect(c.a, 1.0);
      }
    });

    test('the last stop is exactly opaque', () {
      final g = immersiveFadeGradient(_wash);
      expect(g.colors.first.a, 0);
      expect(g.colors.last.a, 1.0);
      expect(g.colors.last.toARGB32(), _wash.toARGB32());
      expect(g.stops!.last, 1.0);
    });

    test('the title scrim is zero at both ends (it can never make an edge)', () {
      final g = immersiveScrimGradient(0.3);
      expect(g.colors.first.a, 0);
      expect(g.colors.last.a, closeTo(0, 1e-9));
      expect(g.colors[g.colors.length ~/ 2].a, closeTo(0.3, 1e-9));
    });
  });

  group('pixels', () {
    testWidgets('control: a hard edge IS detected (the measurement is not vacuous)', (tester) async {
      final px = await _render(
        tester,
        const Column(children: [
          SizedBox(height: _headerH, width: _w, child: ColoredBox(color: Colors.white)),
          SizedBox(height: 100, width: _w, child: ColoredBox(color: _wash)),
        ]),
      );
      var worst = 0;
      for (var y = 1; y < 500; y++) {
        worst = [worst, (_lum(px, 200, y) - _lum(px, 200, y - 1)).abs()].reduce((a, b) => a > b ? a : b);
      }
      expect(worst, greaterThan(150));
    });

    testWidgets('a pure white photo dissolves into the wash with no step and no band', (tester) async {
      final px = await _render(tester, _page());

      // The photo is really there at the top (the fade is not swallowing it).
      expect(_lum(px, 200, 140), greaterThan(240));

      for (final x in [8, 100, 200, 300, 392]) {
        var worst = 0;
        var worstAt = 0;
        for (var y = 1; y < 560; y++) {
          final d = (_lum(px, x, y) - _lum(px, x, y - 1)).abs();
          if (d > worst) {
            worst = d;
            worstAt = y;
          }
        }
        // The steepest the smootherstep gets over ~230px from white to the wash
        // is about 1.9 levels a row (plus 8-bit rounding): a line would be 10+.
        expect(worst, lessThanOrEqualTo(4), reason: 'x=$x: step of $worst at row $worstAt');
      }
    });

    testWidgets('the header\'s last row IS the page colour, and so is every row under it', (tester) async {
      final px = await _render(tester, _page());
      for (final x in [8, 200, 392]) {
        for (final y in [_headerH.toInt() - 1, _headerH.toInt(), _headerH.toInt() + 1, 430, 450]) {
          final c = _rgb(px, x, y);
          expect((c[0] - _wash.r * 255).abs(), lessThanOrEqualTo(1.5), reason: 'x=$x y=$y r');
          expect((c[1] - _wash.g * 255).abs(), lessThanOrEqualTo(1.5), reason: 'x=$x y=$y g');
          expect((c[2] - _wash.b * 255).abs(), lessThanOrEqualTo(1.5), reason: 'x=$x y=$y b');
        }
      }
    });

    testWidgets('the rows are the same across the width at the join (no diagonal or tint)', (tester) async {
      final px = await _render(tester, _page());
      for (final y in [380, 410, 419, 421, 450]) {
        final a = _lum(px, 8, y);
        final b = _lum(px, 392, y);
        expect((a - b).abs(), lessThanOrEqualTo(2), reason: 'row $y differs across the width');
      }
    });

    testWidgets('scrolled by a fractional amount the join is still clean', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final px = await _render(tester, _page(controller: controller));
      expect(px, isNotEmpty);
      controller.jumpTo(97.37);
      await tester.pump();
      await tester.pump();
      // The join is now at 420 - 97.37 = 322.63: a fractional row.
      final key = find.byType(RepaintBoundary).first;
      final boundary = tester.renderObject<RenderRepaintBoundary>(key);
      final scrolled = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return data!.buffer.asUint8List();
      });
      for (final x in [8, 200, 392]) {
        var worst = 0;
        var worstAt = 0;
        for (var y = 1; y < 480; y++) {
          final d = (_lum(scrolled!, x, y) - _lum(scrolled, x, y - 1)).abs();
          if (d > worst) {
            worst = d;
            worstAt = y;
          }
        }
        expect(worst, lessThanOrEqualTo(4), reason: 'x=$x: step of $worst at row $worstAt');
      }
      // Under the join: the page colour.
      final c = _rgb(scrolled!, 200, 340);
      expect((c[0] - _wash.r * 255).abs(), lessThanOrEqualTo(1.5));
      expect((c[1] - _wash.g * 255).abs(), lessThanOrEqualTo(1.5));
    });
  });

  group('layout', () {
    testWidgets('pull-down stretches the photo from the bottom; nothing opens above it', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(_w, _screenH);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(_w, _screenH), devicePixelRatio: 1.0),
          child: CustomScrollView(
            controller: controller,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: ImmersiveHeader(
                  height: _headerH,
                  washColor: _wash,
                  scrollController: controller,
                  photo: const ColoredBox(key: ValueKey('photo'), color: Colors.white),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 1200)),
            ],
          ),
        ),
      ));
      controller.jumpTo(-100);
      await tester.pump();
      final photo = tester.getRect(find.byKey(const ValueKey('photo')));
      expect(photo.top, closeTo(0, 0.5), reason: 'the top stays on the top of the screen');
      expect(photo.bottom, closeTo(_headerH + 100, 0.5), reason: 'it grew by exactly the pull');
    });

    testWidgets('the title block sits over the bottom of the header', (tester) async {
      tester.view.physicalSize = const Size(_w, _screenH);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: Size(_w, _screenH), devicePixelRatio: 1.0),
          child: Column(children: [
            ImmersiveHeader(
              height: _headerH,
              washColor: _wash,
              photo: ColoredBox(color: Colors.white),
              child: SizedBox(key: ValueKey('title'), height: 80, width: 200),
            ),
          ]),
        ),
      ));
      final r = tester.getRect(find.byKey(const ValueKey('title')));
      expect(r.bottom, closeTo(_headerH, 0.5));
    });
  });
}
