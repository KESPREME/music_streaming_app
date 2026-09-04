import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/presentation/explore/explore_layout.dart';

void main() {
  group('ExploreWheelMath', () {
    test('extent clamps: ~5 rows visible', () {
      expect(ExploreWheelMath.itemExtentFor(660), closeTo(128, 0.01));
      expect(ExploreWheelMath.itemExtentFor(457), closeTo(96, 0.01));
      expect(ExploreWheelMath.itemExtentFor(560), closeTo(112, 0.01));
    });
    test('arc: center 0, edges ≈46px', () {
      expect(ExploreWheelMath.arcDx(0, 72, 1.2), 0);
      expect(ExploreWheelMath.arcDx(1, 72, 1.2), closeTo(45.9, 0.2));
      expect(ExploreWheelMath.arcDx(-1, 72, 1.2), closeTo(45.9, 0.2));
    });
    test('curves: center full, edge minimums', () {
      expect(ExploreWheelMath.scaleFor(1), 1.0);
      expect(ExploreWheelMath.scaleFor(0), 0.65);
      expect(ExploreWheelMath.opacityFor(0), 0.2);
      expect(ExploreWheelMath.textOpacityFor(0), 0.0);
      expect(ExploreWheelMath.textOpacityFor(1), 1.0);
      expect(ExploreWheelMath.glassFor(0.4), 0.0);
      expect(ExploreWheelMath.glassFor(1), 1.0);
    });
    test('tForIndex: centered row → 0 (with centering pad)', () {
      // extent 120, viewport 600, pad 240: row 2 centered at offset 240.
      expect(ExploreWheelMath.tForIndex(2, 240, 120, 600, 240),
          closeTo(0, 1e-9));
      expect(ExploreWheelMath.tForIndex(0, 240, 120, 600, 240),
          closeTo(-0.8, 1e-9));
    });
    test('deterministic', () {
      final a = ExploreWheelMath.plan(const Size(390, 700));
      final b = ExploreWheelMath.plan(const Size(390, 700));
      expect(a.itemExtent, b.itemExtent);
    });
  });
  group('shouldShowReason', () {
    test('gates low confidence', () {
      expect(ExploreLayout.shouldShowReason(0.2), isFalse);
      expect(ExploreLayout.shouldShowReason(0.5), isTrue);
    });
  });
}
