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
//
// TWO DIALECTS, ONE CLASS
//
// The queue list (default) hides on travel past [threshold] once the list is
// off its first [headroom] px, and a list that coasts home reveals on its own.
// Those rules are about a LONG list the reader is paging through.
//
// The lyric panel ([ScrollCollapseTracker.directional]) is about direction and
// nothing else, as BitChord's `rememberPlayerControlsOnScroll` is: finger travel
// accumulates, the tally RESETS the moment the finger changes its mind, and 20dp
// one way hides while 20dp the other way reveals - wherever the list happens to
// be. A lyric starts near its top and reads downward, so a headroom rule would
// refuse to hide the controls for the first lines of every song, and "coasting
// home" is not a thing a song does.
class ScrollCollapseTracker {
  /// The queue's dialect: [threshold] of travel, off the top by [headroom].
  ScrollCollapseTracker()
      : _slop = threshold,
        _headroom = headroom,
        _directional = false;

  /// The lyric panel's dialect: [slop] dp of travel in one direction, reset by a
  /// flip, with no regard for where the list is.
  ScrollCollapseTracker.directional({double slop = directionalSlop})
      : _slop = slop,
        _headroom = 0,
        _directional = true;

  bool _finger = false;
  double _accum = 0;

  final double _slop;
  final double _headroom;
  final bool _directional;

  static const double threshold = 24;
  static const double headroom = 40;

  /// How far a finger has to carry the lyric list before the player below it
  /// gets out of the way - or comes back. Roughly a line of body text: under it,
  /// a scroll is a nudge to see one more line rather than a decision to go
  /// reading, and answering every nudge put the controls in and out on the same
  /// gesture. BitChord `CONTROLS_SCROLL_SLOP`.
  static const double directionalSlop = 20;

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
      final delta = n.scrollDelta ?? 0;
      // A flip throws the tally away: a scroll that wanders must not bank its
      // way to the wrong answer. (Net accumulation would let 18dp one way, then
      // a wobble back and forth, cross the line on the wobble.)
      if (_directional && delta != 0 && _accum != 0 && (delta > 0) != (_accum > 0)) {
        _accum = 0;
      }
      _accum += delta;
      if (_accum > _slop && (_directional || n.metrics.pixels > _headroom)) {
        _accum = 0;
        report(true);
      } else if (_accum < -_slop && n.dragDetails != null) {
        // Reveal takes finger travel only: the ballistic bounce-back off
        // a slammed edge must not pop chrome back the instant a fling
        // lands - that flicker read as "it didn't go away".
        _accum = 0;
        report(false);
      } else if (!_directional &&
          n.metrics.pixels < 8 &&
          (n.scrollDelta ?? 0) <= 0) {
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
