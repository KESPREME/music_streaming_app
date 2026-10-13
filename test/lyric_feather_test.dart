import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/widgets/lyric_line/lyric_line.dart';

void main() {
  group('the soft edge of the sweep', () {
    // The edge used to trail the voice by the full 30dp, so lit letters were
    // always short of the audio, and when the line finished the whole ramp
    // vanished in one frame: the fill looked like it finished early and then
    // jumped. These pin the replacement's three properties.

    test('has nothing to draw before anything is sung', () {
      final z = lyricFeatherZone(10, 10, 300);
      expect(z.behind, 0);
      expect(z.ahead, 0);
    });

    test('has nothing left to draw when the row is sung - no pop at the end',
        () {
      final z = lyricFeatherZone(300, 10, 300);
      expect(z.behind, 0);
      expect(z.ahead, 0);
    });

    test('is mostly behind the voice and a little ahead in the middle', () {
      final z = lyricFeatherZone(150, 10, 300);
      expect(z.behind, closeTo(lyricWipeFeather * 0.75, 1e-9));
      expect(z.ahead, closeTo(lyricWipeFeather * 0.25, 1e-9));
    });

    test('changes continuously: no step as the voice nears either end', () {
      double? previous;
      for (var x = 300.0; x >= 270.0; x -= 0.5) {
        final z = lyricFeatherZone(x, 10, 300);
        final reach = z.behind + z.ahead;
        if (previous != null) {
          expect((reach - previous).abs(), lessThan(1.01));
        }
        previous = reach;
      }
      previous = null;
      for (var x = 10.0; x <= 40.0; x += 0.5) {
        final z = lyricFeatherZone(x, 10, 300);
        final reach = z.behind + z.ahead;
        if (previous != null) {
          expect((reach - previous).abs(), lessThan(1.01));
        }
        previous = reach;
      }
    });

    test('never reaches outside the row', () {
      for (var x = 10.0; x <= 300.0; x += 1) {
        final z = lyricFeatherZone(x, 10, 300);
        expect(x - z.behind, greaterThanOrEqualTo(10));
        expect(x + z.ahead, lessThanOrEqualTo(300));
      }
    });
  });
}
