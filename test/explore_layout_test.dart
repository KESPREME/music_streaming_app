import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/presentation/explore/explore_layout.dart';

void main() {
  group('ExploreLayout.plan', () {
    test('390x844 phone: artwork in 0.72-0.82 band, fits', () {
      final spec = ExploreLayout.plan(const Size(390, 700));
      final contentW = 390 - 40;
      expect(spec.artworkSize / contentW, inExclusiveRange(0.71, 0.83));
      final total = spec.artworkSize + 132 + 56 + 64 + 46 +
          (spec.showPrevPeek ? 56 : 0);
      expect(total, lessThanOrEqualTo(700));
      expect(spec.showPrevPeek, isTrue);
    });
    test('360x640 small phone: fits, drops prev peek first', () {
      final spec = ExploreLayout.plan(const Size(360, 457));
      final total = spec.artworkSize + 132 + 56 + 64 + 46 +
          (spec.showPrevPeek ? 56 : 0);
      expect(total, lessThanOrEqualTo(457));
      expect(spec.showPrevPeek, isFalse);
      expect(spec.artworkSize, greaterThanOrEqualTo(150));
    });
    test('412x915 large phone: bigger artwork, fits', () {
      final spec = ExploreLayout.plan(const Size(412, 760));
      expect(spec.artworkSize, greaterThan(260));
      expect(spec.showPrevPeek, isTrue);
    });
    test('tablet 820x1180: artwork capped, centered column bounded', () {
      final spec = ExploreLayout.plan(const Size(820, 1000));
      expect(spec.artworkSize, lessThanOrEqualTo(430));
      expect(spec.contentMaxWidth, 560);
    });
    test('deterministic: same viewport twice → identical spec', () {
      final a = ExploreLayout.plan(const Size(390, 700));
      final b = ExploreLayout.plan(const Size(390, 700));
      expect(a.artworkSize, b.artworkSize);
      expect(a.showPrevPeek, b.showPrevPeek);
    });
  });
  group('shouldShowReason', () {
    test('gates low confidence', () {
      expect(ExploreLayout.shouldShowReason(0.2), isFalse);
      expect(ExploreLayout.shouldShowReason(0.5), isTrue);
    });
  });
}
