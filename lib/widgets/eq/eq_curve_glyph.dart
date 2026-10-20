// lib/widgets/eq/eq_curve_glyph.dart
//
// A thumbnail of the equalizer's live curve: what the Settings tile shows in
// place of an icon, so the tile is a picture of the sound you have set.

import 'package:flutter/material.dart';

import '../../services/eq/eq_curves.dart';
import '../../services/eq/eq_models.dart';

class EqCurveGlyph extends StatelessWidget {
  const EqCurveGlyph({
    super.key,
    required this.bands,
    required this.gains,
    required this.color,
    this.active = true,
    this.height = 38,
  });

  final List<EqBand> bands;
  final List<double> gains;
  final Color color;

  /// Off draws the same curve, dimmed.
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _GlyphPainter(
          samples: [
            for (final p in responseCurve(bands, gains, count: 48))
              (p.$2 / 12).clamp(-1.0, 1.0).toDouble()
          ],
          color: color,
          active: active,
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.samples, required this.color, required this.active});

  final List<double> samples;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.14),
    );
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = size.width * i / (samples.length - 1);
      final y = mid - samples[i] * size.height * 0.46;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, mid)
      ..lineTo(0, mid)
      ..close();
    final c = active ? color : Colors.white54;
    canvas.drawPath(fill, Paint()..color = c.withValues(alpha: active ? 0.2 : 0.08));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = c.withValues(alpha: active ? 1 : 0.5),
    );
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.active != active || old.color != color || old.samples != samples;
}
