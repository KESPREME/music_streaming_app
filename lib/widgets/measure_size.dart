// lib/widgets/measure_size.dart
// Reports a child's laid-out size to a callback.
//
// WHY IT EXISTS
//
// The lyric panel is drawn full-page and the player deck floats above it. That is
// the arrangement the whole morph depends on - the deck slides over the artwork,
// and the lyric view opens beneath it - but it has one consequence that has to be
// paid for explicitly: a full-page list has no idea the deck is there, so it
// scrolls its last lines underneath the scrubber.
//
// The alternative - rebuilding the page so the panel is a sibling of the deck in a
// Column - would move the deck out of the overlay it currently is, and that
// overlay is load-bearing for the shared-element flight. Measuring the deck and
// insetting the list by it keeps the arrangement and removes the overlap.
//
// The notifier-style callback rather than a rebuild: this fires from layout, so
// calling setState would rebuild the subtree that is mid-layout.

import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Calls [onChange] with the child's size whenever it is laid out.
///
/// Only fires when the size actually MOVED, and never during layout for a change
/// smaller than [epsilon]. Without that, rounding jitter on a fractional height
/// reports a change on every frame, the caller rebuilds, the caller lays out,
/// which reports again - a feedback loop that shows up as a page that never goes
/// idle.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({
    super.key,
    required this.onChange,
    this.epsilon = 0.5,
    super.child,
  });

  final void Function(Size size) onChange;
  final double epsilon;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange, epsilon);

  @override
  // The render object is private, so the override that names it is too. Same
  // reason: a public signature may not mention a private type.
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    if (renderObject is! _MeasureSizeRenderObject) return;
    renderObject
      ..onChange = onChange
      ..epsilon = epsilon;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this._onChange, this._epsilon);

  void Function(Size size) _onChange;
  double _epsilon;

  set onChange(void Function(Size size) value) => _onChange = value;
  set epsilon(double value) => _epsilon = value;

  @override
  void performLayout() {
    super.performLayout();
    // Named `target`, not `child`: a local called `child` shadows the inherited
    // getter and its own initializer then refers to itself.
    final target = child;
    if (target == null || !target.hasSize) return;
    final size = target.size;
    if ((size.width - lastReported.width).abs() < _epsilon &&
        (size.height - lastReported.height).abs() < _epsilon) {
      return;
    }
    lastReported = size;

    // Reported AFTER the frame, never during it.
    //
    // The obvious callback fires straight from layout, and a caller that rebuilds
    // on it - which is the entire point of measuring - then schedules a frame
    // from inside the frame being built. Flutter asserts on that outright, and it
    // is not a warning: the tree is mid-paint. Deferring costs one frame of lag
    // on the inset, which is imperceptible, and makes the unsafe version
    // impossible to write by accident.
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.idle) {
      _onChange(size);
    } else {
      scheduler.addPostFrameCallback((_) {
        // The widget can be gone by the time this runs - a track change rebuilds
        // the deck - and calling into a dead notifier is its own crash.
        //
        // READS the framework's own `attached` getter. It is deliberately not
        // given a same-named helper here: shadowing it with a looser meaning
        // breaks the parent/child assertion the whole tree depends on.
        if (attached) _onChange(size);
      });
    }
  }

  Size lastReported = Size.zero;
}