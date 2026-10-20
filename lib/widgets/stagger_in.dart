import 'package:flutter/material.dart';

import 'jelly_press.dart';

/// Fade + slide-up entrance, staggered by [index] (40ms per step, capped).
/// Transform/opacity only — no layout animation.
class StaggerIn extends StatefulWidget {
  const StaggerIn({
    super.key,
    required this.index,
    required this.child,
    this.step = const Duration(milliseconds: 40),
    this.duration = const Duration(milliseconds: 320),
  });

  final int index;
  final Widget child;
  final Duration step;
  final Duration duration;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    final delay = widget.step * widget.index.clamp(0, 8);
    Future.delayed(delay, () {
      if (!mounted) return;
      // Reduce motion: there, not arriving.
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FadeTransition, not a rebuilt Opacity: the alpha goes straight to the
    // layer, and at 1.0 there is no layer at all.
    return FadeTransition(
      opacity: _fade,
      child: AnimatedBuilder(
        animation: _fade,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 18 * (1 - _fade.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Jelly press for bare glyph buttons (see [JellyPress]); no haptic of its own.
class SquishOnPress extends StatelessWidget {
  const SquishOnPress({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Silent: every caller plays its own haptic (navigation calls, toggles).
    return JellyPress(
      profile: JellyProfile.icon,
      haptic: JellyHaptic.none,
      onTap: onTap,
      child: child,
    );
  }
}
