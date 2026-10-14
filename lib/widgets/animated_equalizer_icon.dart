import 'dart:math';
import 'package:flutter/material.dart';

/// Animated equalizer waveform icon matching the playing track indicator in Apple Music / Muzo.
///
/// Drawn by a painter that listens to the controller directly, inside its own
/// repaint boundary. The earlier version rebuilt a Row of three Containers on
/// every tick, which meant a build, a layout and a paint per frame for sixteen
/// pixels of bars - and, because it sat in the queue row's layer, dirtied the
/// row around it too. Now a tick repaints only this icon.
class AnimatedEqualizerIcon extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double size;

  const AnimatedEqualizerIcon({
    super.key,
    required this.isPlaying,
    required this.color,
    this.size = 16,
  });

  @override
  State<AnimatedEqualizerIcon> createState() => _AnimatedEqualizerIconState();
}

class _AnimatedEqualizerIconState extends State<AnimatedEqualizerIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedEqualizerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: EqualizerBarsPainter(
          animation: _controller,
          isPlaying: widget.isPlaying,
          color: widget.color,
        ),
      ),
    );
  }
}

/// Three rounded bars, bottom-aligned and centred in a square, each on its own
/// phase. Geometry matches the Row-of-Containers it replaces: bar width is a
/// sixth of the size, gap a seventh, radius half the width, height clamped to
/// [3, size].
class EqualizerBarsPainter extends CustomPainter {
  EqualizerBarsPainter({
    required this.animation,
    required this.isPlaying,
    required this.color,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final bool isPlaying;
  final Color color;

  /// Bar heights as a fraction of the icon size at animation value [value].
  static List<double> heightsAt(double value, bool isPlaying) {
    if (!isPlaying) return const [0.45, 0.75, 0.35];
    final t = value * 2 * pi;
    return [
      0.35 + 0.60 * ((sin(t * 1.6) + 1) / 2),
      0.45 + 0.55 * ((sin(t * 2.3 + 1.2) + 1) / 2),
      0.30 + 0.65 * ((sin(t * 1.9 + 2.4) + 1) / 2),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final barWidth = side / 6.0;
    final spacing = side / 7.0;
    final total = barWidth * 3 + spacing * 2;
    final left = (side - total) / 2;
    final heights = heightsAt(animation.value, isPlaying);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    for (var i = 0; i < 3; i++) {
      final h = (heights[i] * side).clamp(3.0, side).toDouble();
      final x = left + i * (barWidth + spacing);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, side - h, barWidth, h),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(EqualizerBarsPainter old) =>
      old.isPlaying != isPlaying ||
      old.color != color ||
      old.animation != animation;
}
