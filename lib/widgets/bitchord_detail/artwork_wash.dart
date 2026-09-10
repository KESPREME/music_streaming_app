import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'artwork_seam_fade.dart';

/// Ambient backdrop matching NowPlayingScreen and BitChord ArtworkMeshBackdrop.
///
/// BitChord `ArtworkWash` parity (`ArtworkBackdrop.kt` lines 126-163):
/// - Holds [wash] flat across the artwork zone AND [seamOverhang] past the
///   seam, so the veil hands over to identical color (no C0 step).
/// - Ramps wash -> background with a smoothstep-sampled curve (no slope kink
///   at any stop — the eye finds kinks, not colors).
/// - Mesh blobs sit below the overhang so nothing tints the handoff zone.
///
/// Gradient-only: never spawns blurred images (light covers wash out).
class ArtworkWash extends StatelessWidget {
  final Color backgroundColor;
  final Color washColor;
  final Color accentColor;
  final Color elevatedColor;
  final double washFraction;
  final String? imageUrl;

  /// Flat-wash hold past the seam in logical px (see [kSeamOverhang]).
  final double seamOverhang;

  const ArtworkWash({
    super.key,
    required this.backgroundColor,
    required this.washColor,
    required this.accentColor,
    required this.elevatedColor,
    this.washFraction = 0.62,
    this.imageUrl,
    this.seamOverhang = kSeamOverhang,
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
        seamOverhang: seamOverhang,
      ),
    );
  }
}

double _smoothstep(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3.0 - 2.0 * x);
}

class _ArtworkWashPainter extends CustomPainter {
  final Color backgroundColor;
  final Color washColor;
  final Color accentColor;
  final Color elevatedColor;
  final double washFraction;
  final double seamOverhang;

  _ArtworkWashPainter({
    required this.backgroundColor,
    required this.washColor,
    required this.accentColor,
    required this.elevatedColor,
    required this.washFraction,
    required this.seamOverhang,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0 || size.width <= 0) return;
    final rect = Offset.zero & size;

    // Flat wash through the seam + overhang, then smoothstep ramp to background.
    final seam = washFraction.clamp(0.0, 1.0);
    final holdStop = (seam + seamOverhang / size.height).clamp(0.0, 1.0);

    const rampSamples = 6;
    final stops = <double>[0.0, seam, holdStop];
    final colors = <Color>[washColor, washColor, washColor];
    for (var i = 1; i <= rampSamples; i++) {
      final u = i / rampSamples;
      stops.add(ui.lerpDouble(holdStop, 1.0, u)!);
      // Match legacy mid distribution (0.12 / 0.55 lean) with flat slopes both ends.
      colors.add(Color.lerp(washColor, backgroundColor, _smoothstep(u))!);
    }

    final baseGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: stops,
      colors: colors,
    );

    final basePaint = Paint()..shader = baseGradient.createShader(rect);
    canvas.drawRect(rect, basePaint);

    // Mesh blobs below the handoff zone: widest part of the mesh sits under
    // the seam, never a horizon line across it (BitChord parity).
    _drawBlob(
      canvas: canvas,
      size: size,
      color: accentColor.withValues(alpha: 0.13),
      at: Offset(0.12, holdStop + 0.10),
      radiusFraction: 0.80,
    );

    _drawBlob(
      canvas: canvas,
      size: size,
      color: elevatedColor.withValues(alpha: 0.30),
      at: Offset(0.96, holdStop + 0.32),
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
        oldDelegate.washFraction != washFraction ||
        oldDelegate.seamOverhang != seamOverhang;
  }
}
