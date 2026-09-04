import 'dart:math';
import 'package:flutter/material.dart';

/// Animated equalizer waveform icon matching the playing track indicator in Apple Music / Muzo.
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
    final barWidth = widget.size / 6.0;
    final spacing = widget.size / 7.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * pi;

        // 3 bars with independent phases
        final h1 = widget.isPlaying
            ? (0.35 + 0.60 * ((sin(t * 1.6) + 1) / 2)) * widget.size
            : widget.size * 0.45;
        final h2 = widget.isPlaying
            ? (0.45 + 0.55 * ((sin(t * 2.3 + 1.2) + 1) / 2)) * widget.size
            : widget.size * 0.75;
        final h3 = widget.isPlaying
            ? (0.30 + 0.65 * ((sin(t * 1.9 + 2.4) + 1) / 2)) * widget.size
            : widget.size * 0.35;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBar(barWidth, h1),
              SizedBox(width: spacing),
              _buildBar(barWidth, h2),
              SizedBox(width: spacing),
              _buildBar(barWidth, h3),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBar(double width, double height) {
    return Container(
      width: width,
      height: height.clamp(3.0, widget.size),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(width / 2),
      ),
    );
  }
}
