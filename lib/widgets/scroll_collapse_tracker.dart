import 'package:flutter/widgets.dart';

// Gesture-phase-aware scroll-collapse driver, shared by the queue list and
// the lyrics body so both speak one threshold language.
//
// Two things a naive per-frame delta gate gets wrong (measured ~70% hit
// rate before this existed):
//  1. Slow drags emit sub-threshold deltas forever: accumulate travel since
//     the last state change instead of gating each frame.
//  2. Fling ballistics carry no dragDetails: follow only gestures that
//     STARTED with a finger (ScrollStart carrying dragDetails), so
//     programmatic jumps (track-change auto-scroll) can never collapse
//     chrome, while a flicked list still collapses as it coasts.
// ScrollEnd intentionally changes nothing: the ballistic tail still belongs
// to the finger. The next touch (or any programmatic start) resets.
//
// State lives in the host State object, never in a Stateless build:
// progress-tick rebuilds must not reset a gesture mid-flight.
class ScrollCollapseTracker {
  bool _finger = false;
  double _accum = 0;

  static const double threshold = 24;
  static const double headroom = 40;

  bool handle(ScrollNotification n, ValueChanged<bool> report) {
    if (n is ScrollStartNotification) {
      if (n.dragDetails != null) {
        _finger = true;
        _accum = 0;
      } else {
        _finger = false;
        _accum = 0;
      }
    } else if (n is ScrollUpdateNotification && _finger) {
      _accum += n.scrollDelta ?? 0;
      if (_accum > threshold && n.metrics.pixels > headroom) {
        _accum = 0;
        report(true);
      } else if (_accum < -threshold && n.dragDetails != null) {
        // Reveal takes finger travel only: the ballistic bounce-back off
        // a slammed edge must not pop chrome back the instant a fling
        // lands - that flicker read as "it didn't go away".
        _accum = 0;
        report(false);
      } else if (n.metrics.pixels < 8 && (n.scrollDelta ?? 0) <= 0) {
        // At (or coasted back to) the very top while moving up or still:
        // chrome returns, so a flick home never strands the list topless.
        // Moving DOWN from the top reports nothing (still revealing).
        _accum = 0;
        report(false);
      }
    } else if (n is OverscrollNotification && _finger) {
      // Yanked past the bottom edge: collapsing.
      if (n.overscroll > 8) report(true);
    }
    return false;
  }

  void reset() {
    _finger = false;
    _accum = 0;
  }
}
