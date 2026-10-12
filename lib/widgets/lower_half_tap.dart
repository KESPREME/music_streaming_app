// lib/widgets/lower_half_tap.dart
// A tap in the lower half of its child, told apart from everything else a finger
// does there.
//
// Used by the player to bring the controls back when they are away: the lyric
// panel they were put away for is under the finger, and the finger's other
// business there - seeking to a line, dragging the list - must be left alone.
//
// RAW POINTER EVENTS, NOT A GESTURE RECOGNIZER
//
// A recognizer joins the gesture arena, and in the arena it competes: a tap
// recognizer around a list either steals the tap from the line the reader aimed
// at (the line never seeks) or loses to the list's drag and fires on a gesture
// that was a scroll. A `Listener` is outside the arena. It sees every event,
// claims none of them, and so the lyric row underneath still gets its tap and the
// list still gets its drag. (BitChord intercepts the lower-half tap before the
// row can seek, `LyricsControlsGesture.kt`; here a tap on a line both seeks and
// brings the controls back, which is the kinder way to be wrong.)
//
// WHAT COUNTS AS A TAP
//
//   * down in the lower half of this box, released again;
//   * a single finger;
//   * never more than `kTouchSlop * 2.5` from where it landed. The reference's
//     factor: a tap that wandered a hair past the list's own slop was a tap
//     somebody meant, and every shortfall here is one they did not get;
//   * and no scroll the finger started: the list takes the gesture at exactly
//     one slop, so a finger that scrolled the list 30px is inside 2.5 slops and
//     is still not a tap. That is read off the scroll notifications, the one
//     fact the pointer events cannot tell us.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class LowerHalfTap extends StatefulWidget {
  const LowerHalfTap({
    super.key,
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  /// Whether a tap has anything to do. Disabled, the widget watches nothing.
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  /// How far a finger may wander and still be tapping, as a multiple of the
  /// platform's touch slop.
  static const double slopFactor = 2.5;

  @override
  State<LowerHalfTap> createState() => _LowerHalfTapState();
}

class _LowerHalfTapState extends State<LowerHalfTap> {
  /// The pointer being followed, or null when none qualifies.
  int? _pointer;
  Offset _origin = Offset.zero;

  /// Whether the pointer being followed is still a tap.
  bool _isTap = false;

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    // A second finger turns whatever this was into a gesture (a pinch, a two-
    // finger scroll); neither is a tap.
    if (_pointer != null) {
      _isTap = false;
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    if (event.localPosition.dy < box.size.height / 2) return;
    _pointer = event.pointer;
    _origin = event.position;
    _isTap = true;
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || !_isTap) return;
    final limit = kTouchSlop * LowerHalfTap.slopFactor;
    if ((event.position - _origin).distance > limit) _isTap = false;
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final tapped = _isTap && widget.enabled;
    _forget();
    if (tapped) widget.onTap();
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) _forget();
  }

  void _forget() {
    _pointer = null;
    _isTap = false;
  }

  bool _onScroll(ScrollStartNotification notification) {
    // A drag the finger started is a scroll, not a tap, however short it was.
    if (_pointer != null && notification.dragDetails != null) _isTap = false;
    // Never consumed: the player above still routes every notification.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: NotificationListener<ScrollStartNotification>(
        onNotification: _onScroll,
        child: widget.child,
      ),
    );
  }
}
