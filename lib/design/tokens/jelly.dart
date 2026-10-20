// lib/design/tokens/jelly.dart
//
// The touch physics of a pill: how a control flexes under a finger. Pure Dart
// (no widgets), so the numbers can be MEASURED by tests instead of judged by eye.
// Plan: docs/PLAN-pill-physics.md.
//
// What it models (Apple WWDC25 "Meet Liquid Glass": glass "responds to
// interaction by instantly flexing", with "gel-like flexibility" that "moves in
// tandem with your interaction"; Reduced Motion "disables any elastic
// properties"):
//
//   press    -> the body compresses to [JellyProfile.pressScale];
//   hold     -> it stays there (nothing times out);
//   drag     -> it stretches toward the finger and leans after it, with the
//               VOLUME kept constant (wider means shorter), rubber-banded so it
//               can never be pulled far;
//   release  -> it springs back with a velocity kick, passing rest by a few
//               percent before it settles. That overshoot is the wobble.
//
// Why a new spring and not `Motion.spring`: measured, that one (k520, zeta .78)
// released from 0.94 peaks at 1.0012, a 0.12% overshoot, which is invisible. It
// springs back but never gives.

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// One flavour of jelly. Constants are chosen by measurement (see
/// test/jelly_spring_test.dart, which asserts the overshoot band of each).
class JellyProfile {
  const JellyProfile({
    required this.pressScale,
    required this.kick,
    required this.stretch,
    this.stiffness = 520,
    this.damping = 0.55,
    this.reach = 0.7,
    this.follow = 0.12,
    this.glow = false,
  });

  /// Scale while a finger is down.
  final double pressScale;

  /// Velocity (scale units / second) given to the body on release. This is
  /// what makes it pass rest instead of just settling onto it.
  final double kick;

  /// Largest width/height deformation a drag can reach (a fraction).
  final double stretch;

  final double stiffness;

  /// Damping RATIO (1 = critical). Under 1 it rings; .55 passes rest twice.
  final double damping;

  /// How far a drag (in control sizes) takes the stretch most of the way to its
  /// limit. Smaller is tighter.
  final double reach;

  /// How far the body leans toward the finger, as a fraction of its short side.
  final double follow;

  /// Whether a light blooms under the finger. Floating glass only: Apple keeps
  /// the interaction light on the navigation layer, not on content.
  final bool glow;

  /// Transport glyphs and tiny icon buttons. They have the most room to move.
  static const JellyProfile icon = JellyProfile(pressScale: 0.88, kick: 3.9, stretch: 0.06);

  /// Round buttons in content (queue and lyrics headers, sort, view toggles).
  static const JellyProfile circle = JellyProfile(pressScale: 0.92, kick: 2.8, stretch: 0.07);

  /// Chips, pills and text links. Wide, so they get the least overshoot.
  static const JellyProfile pill = JellyProfile(pressScale: 0.95, kick: 2.0, stretch: 0.08);

  /// Floating glass chrome: the full treatment, with the light under the finger.
  static const JellyProfile chrome =
      JellyProfile(pressScale: 0.93, kick: 3.0, stretch: 0.08, glow: true);
}

class _Axis {
  _Axis(this.x) : t = x;

  double x;
  double v = 0;
  double t;

  /// One explicit step of a damped spring with unit mass.
  void step(double dt, double k, double c) {
    final a = -k * (x - t) - c * v;
    v += a * dt;
    x += v * dt;
  }

  bool rest(double eps, double veps) => (x - t).abs() < eps && v.abs() < veps;

  void snap() {
    x = t;
    v = 0;
  }
}

/// The state of one jelly: a scale spring, an x-stretch spring and a two-axis
/// lean spring, advanced together by [step].
class JellySpring {
  JellySpring(this.profile);

  final JellyProfile profile;

  final _Axis _s = _Axis(1);
  final _Axis _tx = _Axis(0);
  final _Axis _ox = _Axis(0);
  final _Axis _oy = _Axis(0);
  bool _down = false;

  bool get isDown => _down;

  /// Uniform scale (compression / overshoot).
  double get scale => _s.x;

  /// Width factor. With [scaleY] it keeps the area: `scaleX * scaleY == scale^2`.
  double get scaleX => _s.x * (1 + _tx.x);

  /// Height factor.
  double get scaleY => _s.x / (1 + _tx.x);

  /// How far the body leans toward the finger, in logical px.
  double get dx => _ox.x;
  double get dy => _oy.x;

  /// 0 at rest, 1 at full press depth (drives the glow).
  double get depth => ((1 - _s.x) / (1 - profile.pressScale)).clamp(0.0, 1.0);

  bool get atRest =>
      !_down && _s.rest(0.0005, 0.01) && _tx.rest(0.0005, 0.01) && _ox.rest(0.02, 0.5) && _oy.rest(0.02, 0.5);

  /// A finger lands.
  void press() {
    _down = true;
    _s.t = profile.pressScale;
  }

  /// The finger is at [local] inside a box of [size] (the control's own
  /// coordinates). Sets where the stretch and the lean are heading.
  void dragTo(Offset local, Size size) {
    if (!_down || size.isEmpty) return;
    final w = size.width, h = size.height;
    final d = local - Offset(w / 2, h / 2);
    final nx = d.dx / w, ny = d.dy / h; // in control sizes
    final r2 = nx * nx + ny * ny;
    if (r2 < 1e-9) {
      _tx.t = 0;
      _ox.t = 0;
      _oy.t = 0;
      return;
    }
    final r = math.sqrt(r2);
    // Rubber band: climbs fast, can never pass profile.stretch.
    final band = 1 - math.exp(-r / profile.reach);
    // +1 when the pull is along x, -1 when along y.
    final along = (nx * nx - ny * ny) / r2;
    _tx.t = profile.stretch * band * along;
    final len = d.distance;
    final shift = band * profile.follow * math.min(w, h);
    _ox.t = d.dx / len * shift;
    _oy.t = d.dy / len * shift;
  }

  /// The finger lifts (or leaves, or is taken by a scroll).
  void release() {
    if (!_down) return;
    _down = false;
    _s.t = 1;
    _tx.t = 0;
    _ox.t = 0;
    _oy.t = 0;
    // Not "add": a body still falling into the press would eat the kick.
    _s.v = _s.v * 0.2 + profile.kick;
  }

  /// Advances by [dt] seconds. Returns true while anything is still moving.
  /// Safe for any dt: long frames are cut into steps small enough for the
  /// explicit integrator to stay stable.
  bool step(double dt) {
    if (dt <= 0 || dt.isNaN || dt.isInfinite) return !atRest;
    final k = profile.stiffness;
    final c = 2 * profile.damping * math.sqrt(k);
    final n = math.max(1, (math.min(dt, 0.25) / 0.004).ceil());
    final h = math.min(dt, 0.25) / n;
    for (var i = 0; i < n; i++) {
      _s.step(h, k, c);
      // Stretch and lean are a little softer than the body, like gel.
      _tx.step(h, k * 0.8, c * 0.9);
      _ox.step(h, k * 0.8, c * 0.9);
      _oy.step(h, k * 0.8, c * 0.9);
    }
    if (!_down) {
      if (_s.rest(0.0005, 0.01)) _s.snap();
      if (_tx.rest(0.0005, 0.01)) _tx.snap();
      if (_ox.rest(0.02, 0.5)) _ox.snap();
      if (_oy.rest(0.02, 0.5)) _oy.snap();
    }
    return !atRest;
  }
}

/// How a touch is confirmed. One buzz per touch, never two.
enum JellyHaptic {
  /// The call site plays its own (or the control is silent).
  none,

  /// Chips, toggles, tabs: a tick.
  selection,

  /// Buttons: a light tap.
  light,

  /// Primary actions.
  medium,
}
