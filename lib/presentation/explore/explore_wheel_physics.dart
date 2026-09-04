import 'package:flutter/widgets.dart';

/// Magnetic snap-to-row physics over a uniform itemExtent.
/// Parent with a ClampingScrollPhysics at the use site (Android).
class SnapScrollPhysics extends ScrollPhysics {
  const SnapScrollPhysics({super.parent, required this.itemExtent});

  final double itemExtent;

  @override
  SnapScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      SnapScrollPhysics(parent: buildParent(ancestor), itemExtent: itemExtent);

  @visibleForTesting
  static double snapTarget(double pixels, double extent) =>
      (pixels / extent).round() * extent;

  /// Nearest row index for a scroll offset (production snap path).
  static int indexFor(double pixels, double extent) =>
      (pixels / extent).round();

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final tolerance = toleranceFor(position);
    final page = position.pixels / itemExtent;
    double target;

    // Clean velocity-aware paging:
    // Flick up (negative velocity) -> retreat to floor
    // Flick down (positive velocity) -> advance to ceil
    // Slow drag -> round to nearest row
    const flickVelocity = 140.0;
    if (velocity < -flickVelocity) {
      target = (page - 0.1).floorToDouble() * itemExtent;
    } else if (velocity > flickVelocity) {
      target = (page + 0.1).ceilToDouble() * itemExtent;
    } else {
      target = page.roundToDouble() * itemExtent;
    }

    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);

    if ((velocity.abs() < tolerance.velocity) &&
        ((target - position.pixels).abs() < tolerance.distance)) {
      return null;
    }

    // Critically damped spring (damping ratio 1.1):
    // Ultra smooth settle with ZERO oscillation, ZERO see-saw jumping!
    final spring = SpringDescription.withDampingRatio(
      mass: 0.5,
      stiffness: 120.0,
      ratio: 1.1,
    );

    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}
