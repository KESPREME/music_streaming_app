import 'package:flutter/material.dart';

/// Fade-through page switcher (Muzo parity).
///
/// IndexedStack keeps every tab alive (state + scroll positions) while the
/// fade gives a soft cross-fade on switch. Crucially there is NO horizontal
/// swipe gesture - so horizontal drag owners inside pages (swipe deck)
/// never fight a PageView in the gesture arena.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 150),
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _animation =
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.index;
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != _index) {
      _controller.reverse().then((_) {
        if (mounted) {
          setState(() => _index = widget.index);
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: IndexedStack(index: _index, children: widget.children),
    );
  }
}
