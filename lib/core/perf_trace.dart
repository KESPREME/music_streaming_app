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

  /// How often a rolling `PERF_WINDOW` line is printed.
  static const Duration windowPeriod = Duration(seconds: 5);

  static final List<double> _winBuild = <double>[];
  static final List<double> _winRaster = <double>[];
  static final List<double> _winTotal = <double>[];
  static DateTime? _winStart;

  /// The `q`-quantile (0..1) of [values], nearest-rank. 0 for an empty list.
  @visibleForTesting
  static double percentile(List<double> values, double q) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.of(values)..sort();
    final rank = (q * sorted.length).ceil().clamp(1, sorted.length);
    return sorted[rank - 1];
  }

  /// One line describing a window of frames: how many were drawn per second and
  /// how heavy the middle and the tail were.
  ///
  /// Frames per second is the number that matters for heat: a screen that draws
  /// 120 frames a second to show motion nobody asked for costs twice what it
  /// would at 60, whatever each frame costs. A scene that draws 4 is nearly free.
  @visibleForTesting
  static String describeWindow({
    required List<double> build,
    required List<double> raster,
    required List<double> total,
    required Duration span,
  }) {
    final seconds = span.inMicroseconds / 1e6;
    final fps = seconds <= 0 ? 0.0 : total.length / seconds;
    String f(double v) => v.toStringAsFixed(2);
    return 'PERF_WINDOW frames=${total.length} fps=${fps.toStringAsFixed(1)} '
        'build_p50=${f(percentile(build, 0.5))} build_p90=${f(percentile(build, 0.9))} '
        'raster_p50=${f(percentile(raster, 0.5))} raster_p90=${f(percentile(raster, 0.9))} '
        'total_p90=${f(percentile(total, 0.9))}';
  }

  static void _accumulate(double build, double raster, double total) {
    final now = DateTime.now();
    final start = _winStart ??= now;
    _winBuild.add(build);
    _winRaster.add(raster);
    _winTotal.add(total);
    if (now.difference(start) < windowPeriod) return;
    debugPrint(describeWindow(
      build: _winBuild,
      raster: _winRaster,
      total: _winTotal,
      span: now.difference(start),
    ));
    _winBuild.clear();
    _winRaster.clear();
    _winTotal.clear();
    _winStart = now;
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
      _accumulate(build, raster, ms);
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