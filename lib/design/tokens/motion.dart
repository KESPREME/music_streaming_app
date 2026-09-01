import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';

/// Global motion vocabulary. One source of truth — screens must not invent
/// durations. Assign every animation to a purpose (state change, navigation,
/// spatial continuity, direct manipulation, playback feedback, loading,
/// content arrival) or remove it.
abstract final class Motion {
  // --- Durations ------------------------------------------------------------
  /// Micro-feedback: press, icon morph, haptic echo. 100–180 ms.
  static const Duration fast = Duration(milliseconds: 140);

  /// State transition: selection, chip activation, small color shifts.
  static const Duration normal = Duration(milliseconds: 220);

  /// Emphasized state: control cluster changes, artwork crossfade.
  static const Duration emphasized = Duration(milliseconds: 320);

  /// Surface expansion: mini-player growth, sheet settle.
  static const Duration sheet = Duration(milliseconds: 380);

  /// Page transition / large gesture completion. 300–500 ms.
  static const Duration page = Duration(milliseconds: 420);

  /// Ambient material morph: artwork-derived environment blend. Slow but rare.
  static const Duration ambient = Duration(milliseconds: 900);

  // --- Curves ----------------------------------------------------------------
  /// Content movement entering: decelerate strongly.
  static const Curve enter = Curves.easeOutCubic;

  /// Content movement exiting: accelerate.
  static const Curve exit = Curves.easeInCubic;

  /// Standard state easing.
  static const Curve standard = Curves.easeOutCubic;

  /// Spring for physical surfaces (glass press, nav pill, sheets).
  static final SpringDescription spring = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 520.0,
    ratio: 0.78,
  );

  /// Softer spring for large surfaces (player expansion).
  static final SpringDescription springSoft =
      SpringDescription.withDampingRatio(mass: 1.0, stiffness: 340.0, ratio: 0.85);

  /// Snappier spring for tiny glass elements.
  static final SpringDescription springSnappy =
      SpringDescription.withDampingRatio(mass: 0.8, stiffness: 760.0, ratio: 0.72);

  /// Approximate spring as a curve for TweenAnimationBuilder usage.
  static const Curve springCurve = Curves.easeOutBack;

  /// Overshoot for settle moments (mini-player landing).
  static const Curve settle = Curves.easeOutBack;
}
