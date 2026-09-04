import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/presentation/explore/explore_wheel_physics.dart';

void main() {
  group('SnapScrollPhysics', () {
    test('snapTarget rounds to nearest row', () {
      expect(SnapScrollPhysics.snapTarget(250, 120), 240);
      expect(SnapScrollPhysics.snapTarget(310, 120), 360);
    });
    test('indexFor', () {
      expect(SnapScrollPhysics.indexFor(250, 120), 2);
      expect(SnapScrollPhysics.indexFor(0, 120), 0);
    });
  });
}
