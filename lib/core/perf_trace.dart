import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Frame-timing tracer for on-device performance verification.
///
/// `dumpsys gfxinfo` is useless here: Flutter draws through its own engine
/// into a SurfaceView, never through HWUI, so it reports "Total frames
/// rendered: 0" no matter how much the app stutters. The engine's own
/// [FrameTiming] is the only honest source.
///
/// Off unless the build opts in, so release and profile APKs shipped by
/// accident carry nothing:
///
///     flutter build apk --profile --dart-define=PERF_TRACE=true
class PerfTrace {
  const PerfTrace._();

  static const bool enabled = bool.fromEnvironment('PERF_TRACE');

  /// 120Hz panel. Anything slower than this missed a vsync.
  static const double budget120 = 8.33;

  static bool _installed = false;
  static int _seq = 0;
  static int _jank = 0;
  static int _count = 0;
  static double _worst = 0;

  static void install() {
    if (!enabled || _installed) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Marks a region of interest so measured frames can be attributed.
  static void mark(String label) {
    if (!enabled) return;
    _seq++;
    _count = 0;
    _jank = 0;
    _worst = 0;
    // debugPrint, not dart:developer log(): the latter is compiled out of
    // profile/release builds, which is exactly where this needs to work.
    debugPrint('PERF_BEGIN $label');
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      // totalSpan is vsync-to-raster-complete: the number that decides whether
      // a frame was actually shown on time.
      final ms = t.totalSpan.inMicroseconds / 1000.0;
      final build = t.buildDuration.inMicroseconds / 1000.0;
      final raster = t.rasterDuration.inMicroseconds / 1000.0;
      _count++;
      if (ms > budget120) _jank++;
      if (ms > _worst) _worst = ms;
      debugPrint(
        'PERF_FRAME seq=$_seq total=${ms.toStringAsFixed(2)} '
        'build=${build.toStringAsFixed(2)} raster=${raster.toStringAsFixed(2)} '
        'jank=${ms > budget120}',
      );
    }
  }

  /// Emits the running summary for the current [mark] window.
  static void summary(String label) {
    if (!enabled) return;
    debugPrint(
      'PERF_END $label frames=$_count jank=$_jank '
      'worstTotal=${_worst.toStringAsFixed(2)}ms '
      'budget=${budget120}ms',
    );
  }
}