import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/presentation/explore/explore_layout.dart';

void main() {
  group('ExploreLayout.plan stream', () {
    test('390 phone: far peeks visible, diagonal offsets', () {
      final spec = ExploreLayout.plan(const Size(390, 700));
      expect(spec.showFar, isTrue);
      expect(spec.slotDx, [56, 28, 0, -28, -56]);
      expect(spec.activeArt, 76);
      final total = spec.activeRowH + 2 * spec.nearRowH + 2 * spec.farRowH +
          48.0 + 28.0 + 7 * 12.0 + 24.0;
      expect(total, lessThanOrEqualTo(700));
    });
    test('360x640 small: far peeks drop, fits', () {
      final spec = ExploreLayout.plan(const Size(360, 457));
      expect(spec.showFar, isFalse);
      final total = spec.activeRowH + 2 * spec.nearRowH +
          48.0 + 28.0 + 5 * 12.0 + 24.0;
      expect(total, lessThanOrEqualTo(457));
    });
    test('tablet: column bounded', () {
      final spec = ExploreLayout.plan(const Size(820, 1000));
      expect(spec.contentMaxWidth, 560);
      expect(spec.showFar, isTrue);
    });
    test('deterministic', () {
      final a = ExploreLayout.plan(const Size(390, 700));
      final b = ExploreLayout.plan(const Size(390, 700));
      expect(a.slotDx, b.slotDx);
      expect(a.showFar, b.showFar);
    });
  });
  group('shouldShowReason', () {
    test('gates low confidence', () {
      expect(ExploreLayout.shouldShowReason(0.2), isFalse);
      expect(ExploreLayout.shouldShowReason(0.5), isTrue);
    });
  });
}
