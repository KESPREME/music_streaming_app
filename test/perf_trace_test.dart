import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/core/perf_trace.dart';

/// The on-device frame probe: the plan for the player's heat and battery is
/// judged by frames per second and raster time, so the summary that reports them
/// is worth being right about.
void main() {
  group('PerfTrace.percentile', () {
    test('nearest rank', () {
      final v = [10.0, 1.0, 5.0, 3.0, 8.0, 2.0, 9.0, 4.0, 7.0, 6.0];
      expect(PerfTrace.percentile(v, 0.5), 5.0);
      expect(PerfTrace.percentile(v, 0.9), 9.0);
      expect(PerfTrace.percentile(v, 1.0), 10.0);
      expect(PerfTrace.percentile(v, 0.0), 1.0);
    });

    test('an empty window is zero, not an error', () {
      expect(PerfTrace.percentile(const [], 0.9), 0);
    });

    test('does not reorder the caller\'s list', () {
      final v = [3.0, 1.0, 2.0];
      PerfTrace.percentile(v, 0.5);
      expect(v, [3.0, 1.0, 2.0]);
    });
  });

  group('PerfTrace.describeWindow', () {
    test('reports frames per second over the span', () {
      final line = PerfTrace.describeWindow(
        build: List.filled(300, 2.0),
        raster: List.filled(300, 4.0),
        total: List.filled(300, 6.0),
        span: const Duration(seconds: 5),
      );
      expect(line, contains('frames=300'));
      expect(line, contains('fps=60.0'));
      expect(line, contains('raster_p50=4.00'));
      expect(line, contains('total_p90=6.00'));
    });

    test('a quiet scene reads as a low frame rate', () {
      final line = PerfTrace.describeWindow(
        build: List.filled(20, 1.0),
        raster: List.filled(20, 1.0),
        total: List.filled(20, 2.0),
        span: const Duration(seconds: 5),
      );
      expect(line, contains('fps=4.0'));
    });

    test('a zero span does not divide by zero', () {
      final line = PerfTrace.describeWindow(
        build: const [],
        raster: const [],
        total: const [],
        span: Duration.zero,
      );
      expect(line, contains('fps=0.0'));
    });
  });
}
