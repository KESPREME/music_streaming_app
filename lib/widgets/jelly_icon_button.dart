// lib/widgets/jelly_icon_button.dart
//
// A drop-in for [IconButton] that flexes like the rest of the app's controls
// (see jelly_press.dart). Same arguments, same tooltip, same semantics - it IS
// an IconButton underneath, so the tap, the tooltip and the screen-reader node
// are exactly the ones the tests and TalkBack already know. What changes is the
// answer to a touch: the Material splash is replaced by the body giving under
// the finger.

import 'package:flutter/material.dart';

import 'jelly_press.dart';

class JellyIconButton extends StatelessWidget {
  const JellyIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconSize,
    this.padding,
    this.constraints,
    this.visualDensity,
    this.color,
    this.splashRadius,
    this.alignment,
    this.profile = JellyProfile.icon,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double? iconSize;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final VisualDensity? visualDensity;
  final Color? color;

  /// Kept for call-site parity with [IconButton]; the Material splash it sizes
  /// is switched off here.
  final double? splashRadius;
  final AlignmentGeometry? alignment;
  final JellyProfile profile;

  @override
  Widget build(BuildContext context) {
    return JellyPress.passive(
      profile: profile,
      enabled: onPressed != null,
      quietInk: true,
      child: IconButton(
        icon: icon,
        onPressed: onPressed,
        tooltip: tooltip,
        iconSize: iconSize,
        padding: padding,
        constraints: constraints,
        visualDensity: visualDensity,
        color: color,
        splashRadius: splashRadius,
        alignment: alignment,
      ),
    );
  }
}
