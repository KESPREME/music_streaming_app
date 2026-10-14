import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/animated_equalizer_icon.dart';

/// THE ICON THIS FILE PINS.
///
/// The playing-track indicator used to rebuild a Row of three Containers on
/// every animation tick - a build, a layout and a paint, sixty (or a hundred and
/// twenty) times a second, for sixteen pixels of bars, and it dirtied the queue
/// row around it. It is now one painter that repaints by itself inside its own
/// layer. The picture must not change, so it is compared with the layout it
/// replaced.

const double _size = 16;
const Color _color = Color(0xFFE89838);

/// The widget tree the icon used to build, for the given bar heights (in
/// pixels), reproduced here as the reference.
Widget _legacy(List<double> heights) {
  const barWidth = _size / 6.0;
  const spacing = _size / 7.0;
  Widget bar(double h) => Container(
        width: barWidth,
        height: h.clamp(3.0, _size),
        decoration: BoxDecoration(
          color: _color,
          borderRadius: BorderRadius.circular(barWidth / 2),
        ),
      );
  return SizedBox(
    width: _size,
    height: _size,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        bar(heights[0]),
        const SizedBox(width: spacing),
        bar(heights[1]),
        const SizedBox(width: spacing),
        bar(heights[2]),
      ],
    ),
  );
}

Widget _modern(double animationValue, bool isPlaying) => SizedBox(
      width: _size,
      height: _size,
      child: CustomPaint(
        size: const Size.square(_size),
        painter: EqualizerBarsPainter(
          animation: AlwaysStoppedAnimation<double>(animationValue),
          isPlaying: isPlaying,
          color: _color,
        ),
      ),
    );

Widget _framed(GlobalKey key, Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFF101010),
            child: Padding(padding: const EdgeInsets.all(4), child: child),
          ),
        ),
      ),
    );

Future<ByteData> _render(WidgetTester tester, Widget child) async {
  final key = GlobalKey();
  await tester.pumpWidget(_framed(key, child));
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 4.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!;
  }))!;
}

int _maxDiff(ByteData a, ByteData b) {
  expect(a.lengthInBytes, b.lengthInBytes);
  var max = 0;
  for (var i = 0; i < a.lengthInBytes; i++) {
    final d = (a.getUint8(i) - b.getUint8(i)).abs();
    if (d > max) max = d;
  }
  return max;
}

/// The heights exactly as the old build computed them, pixels.
List<double> _legacyHeights(double value, bool playing) {
  final t = value * 2 * pi;
  return playing
      ? [
          (0.35 + 0.60 * ((sin(t * 1.6) + 1) / 2)) * _size,
          (0.45 + 0.55 * ((sin(t * 2.3 + 1.2) + 1) / 2)) * _size,
          (0.30 + 0.65 * ((sin(t * 1.9 + 2.4) + 1) / 2)) * _size,
        ]
      : [_size * 0.45, _size * 0.75, _size * 0.35];
}

void main() {
  group('EqualizerBarsPainter', () {
    test('heights follow the original curves exactly', () {
      for (var i = 0; i <= 20; i++) {
        final v = i / 20;
        final modern = EqualizerBarsPainter.heightsAt(v, true);
        final legacy = _legacyHeights(v, true);
        for (var b = 0; b < 3; b++) {
          expect(modern[b] * _size, closeTo(legacy[b], 1e-9));
        }
      }
    });

    test('paused heights are the original resting shape', () {
      final h = EqualizerBarsPainter.heightsAt(0.37, false);
      expect(h, [0.45, 0.75, 0.35]);
    });

    testWidgets('paused: draws the same picture as the layout it replaced',
        (tester) async {
      final legacy = await _render(tester, _legacy(_legacyHeights(0, false)));
      final modern = await _render(tester, _modern(0, false));
      expect(_maxDiff(legacy, modern), lessThanOrEqualTo(2));
    });

    for (final v in [0.0, 0.17, 0.5, 0.83]) {
      testWidgets('playing at $v: draws the same picture', (tester) async {
        final legacy = await _render(tester, _legacy(_legacyHeights(v, true)));
        final modern = await _render(tester, _modern(v, true));
        expect(_maxDiff(legacy, modern), lessThanOrEqualTo(2));
      });
    }
  });

  group('AnimatedEqualizerIcon', () {
    testWidgets('animates only while playing, and repaints without rebuilding',
        (tester) async {
      var builds = 0;
      final playing = ValueNotifier<bool>(true);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<bool>(
          valueListenable: playing,
          builder: (context, isPlaying, _) {
            builds++;
            return AnimatedEqualizerIcon(isPlaying: isPlaying, color: _color);
          },
        ),
      ));
      final built = builds;

      // Frames pass; nothing above the painter is rebuilt for them.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(builds, built);
      expect(tester.hasRunningAnimations, isTrue);

      playing.value = false;
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse,
          reason: 'a paused icon must not keep the frame loop alive');
    });

    testWidgets('keeps its 16-square footprint', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: AnimatedEqualizerIcon(isPlaying: false, color: _color),
        ),
      ));
      expect(tester.getSize(find.byType(AnimatedEqualizerIcon)),
          const Size(16, 16));
    });
  });
}
