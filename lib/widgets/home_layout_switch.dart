import 'package:flutter/material.dart';

import '../design/tokens/motion.dart';

/// Which side of a layout swap a body is on.
enum HomeLayoutRole {
  /// The layout being left behind.
  leaving,

  /// The layout being arrived at.
  arriving,
}

/// Swaps a section's body between a card layout and a list layout.
///
/// Three things this deliberately does not do, each of which was a bug first:
///
/// **No opacity.** The floating nav bar and the mini-player are backdrop
/// lenses. A translucent layer between a lens and its content isolates the
/// backdrop the lens samples, and the glass goes flat for the duration. Reveal
/// by scale and slide instead.
///
/// **No overshooting curve.** [Curves.easeOutBack] passes its target at about
/// 60% of the clock - measured at 1.086 on a 220ms animation - and then spends
/// the remainder unwinding. On a layout change that reads as the new layout
/// arriving before the transition has finished. The curves here are monotonic,
/// so the swap lands exactly when the clock says it does.
///
/// **No two-beat height change.** [AnimatedSwitcher] stacks the outgoing body
/// alongside the incoming one, and a [Stack] is as tall as its tallest child, so
/// a tall outgoing body holds the box open for the whole swap and only then
/// collapses - the height lands in two beats instead of one. Positioning the
/// outgoing body takes it out of the size calculation, leaving the box at the
/// incoming height for [AnimatedSize] to animate in a single pass.
class HomeLayoutSwitch extends StatelessWidget {
  const HomeLayoutSwitch({
    super.key,
    required this.isCard,
    required this.card,
    required this.list,
  });

  final bool isCard;
  final Widget card;
  final Widget list;

  @override
  Widget build(BuildContext context) {
    // The key names the layout currently on screen. The departing body still
    // carries the key it was built with, so comparing against this is what
    // separates the two roles - reliably, and without reading animation state.
    final arrivingKey = ValueKey<String>(isCard ? 'card' : 'list');

    return AnimatedSize(
      duration: Motion.normal,
      curve: Motion.standard,
      alignment: Alignment.topCenter,
      // The outgoing body is positioned inside a box already resizing to the
      // incoming height, so it has to be clipped or it paints over the section
      // below during the swap.
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: Motion.normal,
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [
              for (final child in previous)
                Positioned(left: 0, top: 0, child: child),
              if (current != null) current,
            ],
          ),
          transitionBuilder: (child, animation) => sectionLayoutTransition(
            // AnimatedSwitcher drives both roles with an animation that runs
            // 0 -> 1 for the arriving body and 1 -> 0 for the departing one, and
            // reports the same status for each, so inferring the role from the
            // animation guesses - and guessing backwards makes the new layout
            // shrink to nothing while the old one stays put.
            role: child.key == arrivingKey
                ? HomeLayoutRole.arriving
                : HomeLayoutRole.leaving,
            animation: animation,
            child: child,
          ),
          child: KeyedSubtree(
            key: arrivingKey,
            child: isCard ? card : list,
          ),
        ),
      ),
    );
  }
}

/// Transform for one body of a [HomeLayoutSwitch] as it arrives or leaves.
///
/// The two roles share one monotonic formula, which cannot by itself both
/// settle the arriving body gently from just under full size and shrink the
/// departing one out of existence. Applied naively - a single scale running from
/// 0.94 to 1.0 - the departing body ends at 0.94: fully painted, sitting exactly
/// on top of the arriving one, until the switcher drops it.
Widget sectionLayoutTransition({
  required HomeLayoutRole role,
  required Animation<double> animation,
  required Widget child,
}) {
  final isLeaving = role == HomeLayoutRole.leaving;

  // The curve is applied to the raw value rather than through a CurvedAnimation
  // because this runs inside build, and a fresh CurvedAnimation on every rebuild
  // leaves its listener attached to the controller.
  final curve = isLeaving ? Motion.exit : Motion.enter;

  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      // AnimatedSwitcher runs the arriving body 0 -> 1 and the departing body
      // 1 -> 0, so `animation.value` is already "how far along this body is" in
      // both directions and needs no normalising. Inverting the departing body
      // made it grow back to full size on its way out.
      final v = curve.transform(animation.value.clamp(0.0, 1.0));
      return Transform.translate(
        // Arriving rises into its space, so a body that gets taller reads as
        // growing upward rather than being stretched down into it. Leaving
        // continues upward, out of the way of what replaces it.
        offset: Offset(0, (isLeaving ? -10.0 : 12.0) * (1 - v)),
        child: Transform.scale(
          // Arriving settles from just under 1 - a swap from nothing reads as a
          // pop. Leaving goes all the way to 0, so nothing is left behind.
          scale: isLeaving ? v : 0.94 + 0.06 * v,
          child: child,
        ),
      );
    },
  );
}
