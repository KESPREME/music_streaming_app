// lib/widgets/track_swap.dart
//
// The title and artist changing hands.
//
// A line of text cannot be half of one song and half of the next, so when the
// session moves to the incoming song of a mix (the midpoint, the same instant
// the audio gains cross) the words change once. They do it as a short exchange
// rather than a cut: the old line lifts away fast, the new one settles in from
// below a beat later. Leaving is quicker than arriving (150 ms against 360) and
// the arrival is a deceleration, with no overshoot - this is information, not
// a flourish. The artist line trails the title by a fraction of the entrance,
// so the eye reads them in order.
//
// With reduced motion the words simply change.

import 'package:flutter/material.dart';

class TrackTextSwap extends StatelessWidget {
  const TrackTextSwap({
    super.key,
    required this.identity,
    required this.child,
    this.lag = 0.0,
  });

  /// What the text belongs to (the track id). A change is the swap.
  final Object identity;
  final Widget child;

  /// How far into the entrance this line waits before it starts, 0..0.6.
  final double lag;

  static const Duration enter = Duration(milliseconds: 360);
  static const Duration leave = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final currentKey = ValueKey<Object>(identity);
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : enter,
      reverseDuration: reduce ? Duration.zero : leave,
      switchInCurve: Interval(lag.clamp(0.0, 0.6), 1.0, curve: Curves.easeOutCubic),
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        clipBehavior: Clip.none,
        children: <Widget>[...previous, if (current != null) current],
      ),
      transitionBuilder: (widget, animation) {
        final entering = widget.key == currentKey;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              // Arrives from below, leaves upward: one continuous direction.
              begin: Offset(0, entering ? 0.4 : -0.4),
              end: Offset.zero,
            ).animate(animation),
            child: widget,
          ),
        );
      },
      child: KeyedSubtree(key: currentKey, child: child),
    );
  }
}
