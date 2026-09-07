import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Renders BitChord's signature ArtworkWash backdrop.
///
/// Built from a vertical gradient and two soft organic radial mesh blobs
/// placed just below the artwork edge, creating an ambient color wash that
/// prevents any visible boundary between the artwork and the page background.
class ArtworkWash extends StatelessWidget {
  final Color backgroundColor;
  final Color washColor;
  final Color accentColor;
  final Color elevatedColor;
  final double washFraction;

  const ArtworkWash({
    super.key,
    required this.backgroundColor,
    required this.washColor,
    required this.accentColor,
    required this.elevatedColor,
    this.washFraction = 0.62,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _ArtworkWashPainter(
        backgroundColor: backgroundColor,
        washColor: washColor,
        accentColor: accentColor,
        elevatedColor: elevatedColor,
        washFraction: washFraction,
      ),
    );
  }
}

class _ArtworkWashPainter extends CustomPainter {
  final Color backgroundColor;
  final Color washColor;
  final Color accentColor;
  final Color elevatedColor;
  final double washFraction;

  _ArtworkWashPainter({
    required this.backgroundColor,
    required this.washColor,
    required this.accentColor,
    required this.elevatedColor,
    required this.washFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Vertical base gradient: wash -> background
    final stop1 = washFraction.clamp(0.0, 1.0);
    final stop2 = ui.lerpDouble(stop1, 1.0, 0.35)!;
    final stop3 = ui.lerpDouble(stop1, 1.0, 0.70)!;

    final baseGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0.0, stop1, stop2, stop3, 1.0],
      colors: [
        washColor,
        washColor,
        Color.lerp(washColor, backgroundColor, 0.12)!,
        Color.lerp(washColor, backgroundColor, 0.55)!,
        backgroundColor,
      ],
    );

    final basePaint = Paint()..shader = baseGradient.createShader(rect);
    canvas.drawRect(rect, basePaint);

    // 2. Mesh Blob 1: Left accent blob under artwork foot
    _drawBlob(
      canvas: canvas,
      size: size,
      color: accentColor.withValues(alpha: 0.13),
      at: Offset(0.12, washFraction + 0.08),
      radiusFraction: 0.80,
    );

    // 3. Mesh Blob 2: Right elevated blob further down
    _drawBlob(
      canvas: canvas,
      size: size,
      color: elevatedColor.withValues(alpha: 0.30),
      at: Offset(0.96, washFraction + 0.30),
      radiusFraction: 0.95,
    );
  }

  void _drawBlob({
    required Canvas canvas,
    required Size size,
    required Color color,
    required Offset at,
    required double radiusFraction,
  }) {
    final center = Offset(at.dx * size.width, at.dy * size.height);
    final radius = size.width * radiusFraction;

    final blobGradient = RadialGradient(
      colors: [
        color,
        color.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 1.0],
    );

    final blobPaint = Paint()
      ..shader = blobGradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );

    canvas.drawCircle(center, radius, blobPaint);
  }

  @override
  bool shouldRepaint(covariant _ArtworkWashPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.washColor != washColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.elevatedColor != elevatedColor ||
        oldDelegate.washFraction != washFraction;
  }
}
