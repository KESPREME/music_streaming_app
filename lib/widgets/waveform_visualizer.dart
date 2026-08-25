import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated bar waveform — the player's signature visual.
///
/// Decorative (not FFT): bars dance on a layered-sine field while playing
/// and settle flat when paused. Upgrade path: swap in real FFT via the
/// Android Visualizer API (audify package) behind the same widget API.
class WaveformVisualizer extends StatefulWidget {
  const WaveformVisualizer({
    super.key,
    required this.isPlaying,
    this.color,
    this.barCount = 42,
    this.height = 56,
  });

  final bool isPlaying;
  final Color? color;
  final int barCount;
  final double height;

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _WaveformPainter(
              progress: _controller.value,
              isPlaying: widget.isPlaying,
              color: accent,
              barCount: widget.barCount,
            ),
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.isPlaying,
    required this.color,
    required this.barCount,
  });

  final double progress;
  final bool isPlaying;
  final Color color;
  final int barCount;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.9);
    final barWidth = size.width / (barCount * 1.6);
    final gap = barWidth * 0.6;
    final midY = size.height / 2;
    final t = progress * 2 * math.pi;

    for (var i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap);
      double amplitude;
      if (!isPlaying) {
        amplitude = 0.06; // settled flat
      } else {
        // Layered sines = organic pseudo-music motion, stable per bar index.
        final phase = i * 0.7;
        amplitude = 0.18 +
            0.30 * (math.sin(t * 1.4 + phase) * 0.5 + 0.5) *
                (0.6 + 0.4 * math.sin(t * 0.6 + i * 0.23));
      }
      final barHeight = size.height * amplitude.clamp(0.04, 0.95);
      final rounded = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, midY - barHeight / 2, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rounded, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.isPlaying != isPlaying ||
      old.color != color;
}
