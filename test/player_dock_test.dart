import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/player_dock.dart';

/// THE DOCK: the open player's artwork flies home into the mini player's cover
/// (BitChord's numbers), the rest of the player fades ahead of it, and the two
/// real artworks stand aside only while the copy flies.

class _CountPaints extends CustomPainter {
  _CountPaints(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) => onPaint();
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

void main() {
  const mini = Rect.fromLTWH(24, 760, 36, 36);
  const open = Rect.fromLTWH(0, 0, 412, 760);
  const travel = 860.0;

  DockFrame at(double t) =>
      dockFrame(t: t, mini: mini, open: open, travel: travel, miniCorner: 10, openCorner: 20);

  group('geometry', () {
    test('open is the player\'s artwork, closed is the cover', () {
      expect(at(1).rect, open);
      expect(at(1).corner, 20);
      expect(at(1).playerAlpha, 1);
      expect(at(0).rect, mini);
      expect(at(0).corner, 10);
      expect(at(0).playerAlpha, 0);
    });

    test('the player is fully faded with 15% of the way still to go', () {
      expect(at(kDockFadeLead).playerAlpha, 0);
      expect(at(0.1).playerAlpha, 0);
      expect(at((1 + kDockFadeLead) / 2).playerAlpha, closeTo(0.5, 1e-9));
    });

    test('it never passes the cover and moves monotonically toward it', () {
      var lastTop = -double.infinity;
      for (var i = 100; i >= 0; i--) {
        final r = at(i / 100).rect;
        expect(r.top, lessThanOrEqualTo(mini.top + 1e-9), reason: 't=${i / 100}');
        expect(r.top, greaterThanOrEqualTo(lastTop - 1e-9), reason: 'no climbing back at t=${i / 100}');
        lastTop = r.top;
      }
    });

    test('it follows the sheet most of the way (rides with the finger)', () {
      // Halfway, the artwork has come down by much more than a plain lerp of
      // the two rects would put it: it is carried by the sheet.
      final half = at(0.5).rect;
      final plain = Rect.lerp(mini, open, 0.5)!;
      expect(half.top, greaterThan(plain.top + 100));
    });
  });

  group('the real artworks', () {
    setUp(() => PlayerDock.instance.debugReset());

    testWidgets('stand aside only while the copy flies', (tester) async {
      var miniPaints = 0, artPaints = 0;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: [
          Positioned(
            left: 0,
            top: 0,
            width: 200,
            height: 200,
            child: DockPlayerArt(
              enabled: true,
              corner: 20,
              sleeve: (_) => const SizedBox(),
              child: CustomPaint(painter: _CountPaints(() => artPaints++)),
            ),
          ),
          Positioned(
            left: 10,
            top: 500,
            width: 36,
            height: 36,
            child: DockMiniArt(corner: 10, child: CustomPaint(painter: _CountPaints(() => miniPaints++))),
          ),
        ]),
      ));
      expect(PlayerDock.instance.miniRect(), const Rect.fromLTWH(10, 500, 36, 36));
      expect(PlayerDock.instance.artRect(), const Rect.fromLTWH(0, 0, 200, 200));
      expect(PlayerDock.instance.miniCorner, 10);
      expect(PlayerDock.instance.sleeve, isNotNull);

      final m0 = miniPaints, a0 = artPaints;
      PlayerDock.instance.setDocking(true);
      await tester.pump();
      expect(miniPaints, m0, reason: 'cover hidden while docking');
      expect(artPaints, a0, reason: 'player artwork hidden while docking');

      PlayerDock.instance.setDocking(false);
      await tester.pump();
      expect(miniPaints, greaterThan(m0));
      expect(artPaints, greaterThan(a0));
    });

    testWidgets('a disabled player artwork takes no part (lyrics or queue open)', (tester) async {
      var paints = 0;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: DockPlayerArt(
          enabled: false,
          corner: 20,
          sleeve: (_) => const SizedBox(),
          child: CustomPaint(painter: _CountPaints(() => paints++)),
        ),
      ));
      expect(PlayerDock.instance.artRect(), isNull);
      final p0 = paints;
      PlayerDock.instance.setDocking(true);
      await tester.pump();
      // Not hidden: nothing is flying in its place.
      expect(paints, greaterThan(p0));
      PlayerDock.instance.setDocking(false);
    });

    testWidgets('a cover that leaves is forgotten; a newer one is not cleared by an older one', (tester) async {
      Widget cover(Key k) => DockMiniArt(key: k, corner: 8, child: const SizedBox(width: 30, height: 30));
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [cover(const ValueKey('a'))]),
      ));
      expect(PlayerDock.instance.miniRect(), isNotNull);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [cover(const ValueKey('a')), cover(const ValueKey('b'))]),
      ));
      final withB = PlayerDock.instance.miniRect();
      expect(withB!.top, 30, reason: 'the newest cover wins');
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [cover(const ValueKey('b'))]),
      ));
      expect(PlayerDock.instance.miniRect(), isNotNull, reason: 'a leaving the tree did not clear b');
      await tester.pumpWidget(const SizedBox());
      expect(PlayerDock.instance.miniRect(), isNull);
    });

    testWidgets('a header cover docks with a hard edge; the hero keeps its fade', (tester) async {
      Widget art({required bool hero, required bool queue}) => Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(children: [
              Positioned(
                left: 20,
                top: 56,
                width: 46,
                height: 46,
                child: DockPlayerArt(
                  key: const ValueKey('hero'),
                  enabled: hero,
                  corner: 8,
                  softEdge: false,
                  sleeve: (_) => const SizedBox(),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: 20,
                top: 300,
                width: 46,
                height: 46,
                child: DockPlayerArt(
                  key: const ValueKey('queue'),
                  enabled: queue,
                  corner: 8,
                  softEdge: false,
                  sleeve: (_) => const SizedBox(),
                  child: const SizedBox.expand(),
                ),
              ),
            ]),
          );
      // Lyrics open: the landed hero is the docking end.
      await tester.pumpWidget(art(hero: true, queue: false));
      expect(PlayerDock.instance.artRect(), const Rect.fromLTWH(20, 56, 46, 46));
      expect(PlayerDock.instance.artSoftEdge, isFalse);
      // Queue takes the header over: its cover docks, the hero is let go.
      await tester.pumpWidget(art(hero: false, queue: true));
      expect(PlayerDock.instance.artRect(), const Rect.fromLTWH(20, 300, 46, 46));
      // Mid-flight neither end is attached: the plain slide.
      await tester.pumpWidget(art(hero: false, queue: false));
      expect(PlayerDock.instance.artRect(), isNull);
    });
  });

  group('edge fade', () {
    const mini = Rect.fromLTWH(10, 700, 40, 40);
    const open = Rect.fromLTWH(20, 56, 46, 46);
    test('a soft-edged hero fades in with progress', () {
      final f = dockFrame(t: 0.6, mini: mini, open: open, travel: 800, miniCorner: 8, openCorner: 8);
      expect(f.edgeFade, closeTo(0.6, 1e-9));
    });
    test('a hard-edged header cover never fades', () {
      for (final t in [0.0, 0.3, 1.0]) {
        final f = dockFrame(
            t: t, mini: mini, open: open, travel: 800, miniCorner: 8, openCorner: 8, softEdge: false);
        expect(f.edgeFade, 0);
      }
    });
  });
}
