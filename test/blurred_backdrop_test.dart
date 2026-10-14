import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/blurred_backdrop.dart';

/// THE BAKE THIS FILE PINS.
///
/// The player's wash used to be `ImageFiltered(blur 60)` over a 1.6x-scaled,
/// full-screen image - re-blurred on the GPU every frame, because Impeller has
/// no raster cache. [BlurredBackdrop] bakes it once per track into a small image
/// and draws that.
///
/// A bake is only a win if it is the SAME picture, so the first half of this
/// file renders the live widget tree and the baked image side by side and
/// compares their pixels. The second half pins the widget's behaviour: no empty
/// frame between tracks, no needless re-bake, a quiet failure.

const Size _box = Size(180, 400);

/// A source with hard edges, strong colour contrast and detail at several
/// scales - the worst case for a blur-parity check, which a flat or smooth image
/// would pass trivially.
Future<ui.Image> _makeSource({bool flipped = false}) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  c.drawRect(const Rect.fromLTWH(0, 0, 128, 128), Paint()..color = const Color(0xFF204080));
  c.drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = const Color(0xFFE04040));
  c.drawRect(const Rect.fromLTWH(64, 0, 64, 40), Paint()..color = const Color(0xFF30C060));
  c.drawCircle(const Offset(96, 96), 30, Paint()..color = const Color(0xFFF0E060));
  c.drawRect(const Rect.fromLTWH(10, 90, 30, 30), Paint()..color = const Color(0xFFFFFFFF));
  if (flipped) {
    c.drawRect(const Rect.fromLTWH(0, 0, 128, 128),
        Paint()..color = const Color(0x80FF00FF));
  }
  return recorder.endRecording().toImage(128, 128);
}

Future<ByteData> _pixels(RenderRepaintBoundary boundary) async {
  final image = await boundary.toImage(pixelRatio: 1.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

/// Mean and max absolute per-channel difference (0-255) over RGB.
({double mean, int max}) _diff(ByteData a, ByteData b) {
  expect(a.lengthInBytes, b.lengthInBytes);
  var sum = 0;
  var max = 0;
  var n = 0;
  for (var i = 0; i < a.lengthInBytes; i += 4) {
    for (var ch = 0; ch < 3; ch++) {
      final d = (a.getUint8(i + ch) - b.getUint8(i + ch)).abs();
      sum += d;
      if (d > max) max = d;
      n++;
    }
  }
  return (mean: sum / n, max: max);
}

Widget _framed(GlobalKey key, Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: _box.width,
            height: _box.height,
            child: ColoredBox(color: const Color(0xFF08080A), child: child),
          ),
        ),
      ),
    );

/// Gives real async work (decode, bake) time to finish under the fake clock.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('bakeBlurredBackdrop parity', () {
    Future<({double mean, int max})> compare(
      WidgetTester tester, {
      required double sigma,
      required double scale,
      required Alignment alignment,
    }) async {
      final source = (await tester.runAsync(_makeSource))!;

      final liveKey = GlobalKey();
      await tester.pumpWidget(_framed(
        liveKey,
        ClipRect(
          child: Transform.scale(
            scale: scale,
            alignment: alignment,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: SizedBox.expand(
                child: RawImage(image: source, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
      ));
      final live = (await tester.runAsync(() => _pixels(
          liveKey.currentContext!.findRenderObject()! as RenderRepaintBoundary)))!;

      final baked = (await tester.runAsync(() => bakeBlurredBackdrop(
            source: source,
            size: _box,
            sigma: sigma,
            scale: scale,
            alignment: alignment,
          )))!;
      final bakedKey = GlobalKey();
      await tester.pumpWidget(_framed(
        bakedKey,
        RawImage(
          image: baked,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
        ),
      ));
      final bakedPx = (await tester.runAsync(() => _pixels(
          bakedKey.currentContext!.findRenderObject()! as RenderRepaintBoundary)))!;

      return _diff(live, bakedPx);
    }

    testWidgets('now playing: blur 60, 1.6x about the top centre',
        (tester) async {
      final d = await compare(tester,
          sigma: 60, scale: 1.6, alignment: Alignment.topCenter);
      // Reported so a drift is visible in the log, not only when it fails.
      // ignore: avoid_print
      print('backdrop parity (now playing): mean=${d.mean.toStringAsFixed(3)} '
          'max=${d.max}');
      expect(d.mean, lessThan(1.5),
          reason: 'the bake must look like the live blur');
      expect(d.max, lessThan(8));
    });

    testWidgets('queue: blur 65, 1.25x about the centre', (tester) async {
      final d = await compare(tester,
          sigma: 65, scale: 1.25, alignment: Alignment.center);
      // ignore: avoid_print
      print('backdrop parity (queue): mean=${d.mean.toStringAsFixed(3)} '
          'max=${d.max}');
      expect(d.mean, lessThan(2.0));
      expect(d.max, lessThan(8));
    });

    testWidgets('a bake is a small image, not a screen', (tester) async {
      final source = (await tester.runAsync(_makeSource))!;
      final baked = (await tester.runAsync(() => bakeBlurredBackdrop(
            source: source,
            size: const Size(360, 800),
            sigma: 60,
            scale: 1.6,
            alignment: Alignment.topCenter,
          )))!;
      expect(baked.width, 90);
      expect(baked.height, 200);
      baked.dispose();
      source.dispose();
    });
  });

  group('BlurredBackdrop widget', () {
    late Uint8List redPng;
    late Uint8List bluePng;

    Future<Uint8List> png(Color color) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 32, 32), Paint()..color = color);
      final image = await recorder.endRecording().toImage(32, 32);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    }

    Future<void> mount(WidgetTester tester, ImageProvider image) =>
        tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: _box.width,
              height: _box.height,
              child: BlurredBackdrop(image: image, sigma: 60, scale: 1.6),
            ),
          ),
        ));

    testWidgets('bakes the image and draws it as ONE image', (tester) async {
      redPng = (await tester.runAsync(() => png(Colors.red)))!;
      await mount(tester, MemoryImage(redPng));
      expect(find.byType(RawImage), findsNothing, reason: 'nothing yet');

      await _settle(tester);
      expect(find.byType(RawImage), findsOneWidget);
      final raw = tester.widget<RawImage>(find.byType(RawImage));
      expect(raw.image!.width, 45);
      expect(raw.image!.height, 100);
    });

    testWidgets('an equal provider does not bake again', (tester) async {
      redPng = (await tester.runAsync(() => png(Colors.red)))!;
      final provider = MemoryImage(redPng);
      await mount(tester, provider);
      await _settle(tester);
      final first = tester.widget<RawImage>(find.byType(RawImage)).image;

      await mount(tester, provider);
      await _settle(tester);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(first));
    });

    testWidgets('changing track never leaves the screen empty', (tester) async {
      redPng = (await tester.runAsync(() => png(Colors.red)))!;
      bluePng = (await tester.runAsync(() => png(Colors.blue)))!;
      await mount(tester, MemoryImage(redPng));
      await _settle(tester);
      final red = tester.widget<RawImage>(find.byType(RawImage)).image;

      await mount(tester, MemoryImage(bluePng));
      // The new wash has not been made yet; the old one is still up.
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(red));

      await _settle(tester);
      await tester.pump(const Duration(seconds: 1)); // the cross-fade ends
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image,
          isNot(same(red)));
    });

    testWidgets('an image that cannot load shows a flat colour, quietly',
        (tester) async {
      await mount(tester, MemoryImage(Uint8List.fromList([1, 2, 3])));
      await _settle(tester);
      expect(find.byType(RawImage), findsNothing);
      expect(
        find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == Colors.grey.shade900),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
