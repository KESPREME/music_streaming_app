import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/design/tokens/jelly.dart';

/// The jelly is a number before it is a feeling. These tests MEASURE it: how far
/// it overshoots, how long it takes to settle, whether volume is kept, whether
/// it can blow up. The old house spring measured 0.12% overshoot (invisible);
/// the bands below are what makes a release visibly give.
const double _dt = 1 / 120;

({double peak, double trough, double settleMs, int crossings}) _release(JellySpring s, {double ms = 1500}) {
  var peak = s.scale, trough = s.scale, settle = 0.0;
  var crossings = 0;
  var prev = s.scale - 1;
  for (var i = 1; i <= ms / (_dt * 1000); i++) {
    s.step(_dt);
    peak = math.max(peak, s.scale);
    trough = math.min(trough, s.scale);
    if ((s.scale - 1).abs() > 0.002) settle = i * _dt * 1000;
    if ((s.scale - 1) * prev < 0) crossings++;
    prev = s.scale - 1;
  }
  return (peak: peak, trough: trough, settleMs: settle, crossings: crossings);
}

JellySpring _held(JellyProfile p, {double holdMs = 600}) {
  final s = JellySpring(p)..press();
  for (var i = 0; i < holdMs / (_dt * 1000); i++) {
    s.step(_dt);
  }
  return s;
}

void main() {
  const profiles = {
    'icon': JellyProfile.icon,
    'circle': JellyProfile.circle,
    'pill': JellyProfile.pill,
    'chrome': JellyProfile.chrome,
  };

  group('rest', () {
    test('a new jelly is at rest and exactly 1', () {
      final s = JellySpring(JellyProfile.pill);
      expect(s.atRest, isTrue);
      expect([s.scale, s.scaleX, s.scaleY, s.dx, s.dy], [1, 1, 1, 0, 0]);
      expect(s.depth, 0);
    });

    test('stepping a jelly at rest keeps it at rest and costs nothing', () {
      final s = JellySpring(JellyProfile.pill);
      expect(s.step(_dt), isFalse);
      expect(s.scale, 1);
    });
  });

  group('press and hold', () {
    for (final e in profiles.entries) {
      test('${e.key}: lands on its press scale and STAYS there while held', () {
        final s = _held(e.value, holdMs: 400);
        expect(s.scale, closeTo(e.value.pressScale, 0.01));
        // Two more seconds of holding: no creep, no drift, no timeout.
        final at400 = s.scale;
        for (var i = 0; i < 240; i++) {
          s.step(_dt);
        }
        expect(s.scale, closeTo(at400, 1e-3));
        expect(s.isDown, isTrue);
        expect(s.atRest, isFalse, reason: 'still held, not at rest');
        expect(s.depth, closeTo(1, 0.15));
      });
    }
  });

  group('release: the wobble', () {
    // Overshoot bands, by measurement. Too little reads as flat (the old
    // 0.12%); too much reads as cartoon. Wide pills get the least.
    const bands = {
      'icon': (0.040, 0.085),
      'circle': (0.030, 0.065),
      'pill': (0.020, 0.050),
      'chrome': (0.030, 0.070),
    };
    for (final e in profiles.entries) {
      test('${e.key}: passes rest by ${bands[e.key]!.$1 * 100}-${bands[e.key]!.$2 * 100}% and settles fast', () {
        final s = _held(e.value)..release();
        final r = _release(s);
        final over = r.peak - 1;
        expect(over, greaterThanOrEqualTo(bands[e.key]!.$1), reason: 'peak ${r.peak}');
        expect(over, lessThanOrEqualTo(bands[e.key]!.$2), reason: 'peak ${r.peak}');
        expect(r.settleMs, lessThan(650), reason: 'settles in ${r.settleMs}ms');
        expect(s.atRest, isTrue);
        expect([s.scale, s.scaleX, s.scaleY], [1, 1, 1], reason: 'snaps to exactly 1');
      });

      test('${e.key}: never undershoots past its own press depth', () {
        final s = _held(e.value)..release();
        final r = _release(s);
        expect(r.trough, greaterThanOrEqualTo(e.value.pressScale - 0.02));
      });
    }

    test('a quick tap (released mid-press) still wobbles and still settles', () {
      final s = JellySpring(JellyProfile.pill)..press();
      for (var i = 0; i < 4; i++) {
        s.step(_dt); // ~33 ms: the press has not landed
      }
      expect(s.scale, greaterThan(JellyProfile.pill.pressScale));
      s.release();
      final r = _release(s);
      expect(r.peak, greaterThan(1.01));
      expect(r.settleMs, lessThan(650));
      expect(s.atRest, isTrue);
    });

    test('the kick is what makes it wobble: without it the old spring is invisible', () {
      const flat = JellyProfile(pressScale: 0.95, kick: 0, stretch: 0.08, damping: 0.78);
      final s = _held(flat)..release();
      expect(_release(s).peak - 1, lessThan(0.005));
    });
  });

  group('drag: stretch toward the finger, volume kept', () {
    const size = Size(120, 48);

    JellySpring dragged(Offset local) {
      final s = JellySpring(JellyProfile.pill)..press();
      s.dragTo(local, size);
      for (var i = 0; i < 90; i++) {
        s.step(_dt);
      }
      return s;
    }

    test('a pull along x widens and shortens; along y the opposite', () {
      final x = dragged(const Offset(150, 24));
      expect(x.scaleX, greaterThan(x.scale));
      expect(x.scaleY, lessThan(x.scale));
      final y = dragged(const Offset(60, 80));
      expect(y.scaleY, greaterThan(y.scale));
      expect(y.scaleX, lessThan(y.scale));
    });

    test('VOLUME is kept at every moment of a drag', () {
      final s = JellySpring(JellyProfile.chrome)..press();
      for (var i = 0; i < 200; i++) {
        s.dragTo(Offset(60 + 90 * math.sin(i / 17), 24 + 40 * math.cos(i / 11)), size);
        s.step(_dt);
        expect(s.scaleX * s.scaleY, closeTo(s.scale * s.scale, 1e-9));
      }
    });

    test('leans toward the finger', () {
      final right = dragged(const Offset(150, 24));
      expect(right.dx, greaterThan(0));
      expect(right.dy.abs(), lessThan(0.5));
      final up = dragged(const Offset(60, -30));
      expect(up.dy, lessThan(0));
    });

    test('rubber band: a huge pull is no bigger than a modest one plus the limit', () {
      final far = dragged(const Offset(5000, 24));
      final limit = JellyProfile.pill.stretch;
      expect(far.scaleX / far.scale, lessThanOrEqualTo(1 + limit + 1e-6));
      expect(far.scaleY / far.scale, greaterThanOrEqualTo(1 / (1 + limit) - 1e-6));
      expect(far.dx, lessThanOrEqualTo(JellyProfile.pill.follow * 48 + 1e-6));
    });

    test('a pull at the centre does nothing', () {
      final s = dragged(const Offset(60, 24));
      expect(s.scaleX, closeTo(s.scale, 1e-6));
      expect([s.dx.abs() < 1e-6, s.dy.abs() < 1e-6], [true, true]);
    });

    test('releasing a drag returns the lean and the stretch to nothing', () {
      final s = dragged(const Offset(150, 40));
      s.release();
      _release(s);
      expect(s.atRest, isTrue);
      expect([s.dx, s.dy], [0, 0]);
      expect(s.scaleX, 1);
    });

    test('dragTo without a finger down is ignored', () {
      final s = JellySpring(JellyProfile.pill)..dragTo(const Offset(150, 24), size);
      s.step(_dt);
      expect(s.atRest, isTrue);
    });
  });

  group('stability', () {
    test('any frame length is safe: 0, tiny, huge, NaN, infinity', () {
      for (final dt in [0.0, 1e-9, 0.004, 0.016, 0.1, 1.0, 30.0, double.nan, double.infinity, -1.0]) {
        final s = _held(JellyProfile.chrome)..release();
        s.step(dt);
        expect(s.scale.isFinite, isTrue, reason: 'dt=$dt');
        expect(s.scale, inInclusiveRange(0.5, 1.5), reason: 'dt=$dt');
      }
    });

    test('a long frame lands in the same place as many short ones', () {
      JellySpring one() => _held(JellyProfile.circle)..release();
      final a = one(), b = one();
      for (var i = 0; i < 12; i++) {
        a.step(1 / 120);
      }
      b.step(12 / 120);
      expect(a.scale, closeTo(b.scale, 0.01));
    });

    test('hammering press / release never accumulates', () {
      final s = JellySpring(JellyProfile.pill);
      for (var i = 0; i < 100; i++) {
        s.press();
        for (var j = 0; j < 3; j++) {
          s.step(_dt);
        }
        s.release();
        for (var j = 0; j < 2; j++) {
          s.step(_dt);
        }
      }
      for (var i = 0; i < 400; i++) {
        s.step(_dt);
      }
      expect(s.atRest, isTrue);
      expect(s.scale, 1);
    });
  });
}
