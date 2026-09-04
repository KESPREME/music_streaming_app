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
    final target = snapTarget(position.pixels, itemExtent);
    final tolerance = toleranceFor(position);
    if ((velocity.abs() < tolerance.velocity) &&
        ((target - position.pixels).abs() < tolerance.distance)) {
      return null;
    }
    return ScrollSpringSimulation(
        spring, position.pixels, target, velocity,
        tolerance: tolerance);
  }
}
