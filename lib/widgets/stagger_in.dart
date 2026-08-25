import 'package:flutter/material.dart';

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
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, child) => Opacity(
        opacity: _fade.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - _fade.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Scale-to-0.96 while pressed; springs back on release.
class SquishOnPress extends StatefulWidget {
  const SquishOnPress({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<SquishOnPress> createState() => _SquishOnPressState();
}

class _SquishOnPressState extends State<SquishOnPress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
