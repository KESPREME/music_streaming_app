import 'package:flutter/material.dart';

/// Two overlapping rings with the overlap filled - the picture of one song
/// joining another. Apple Music's queue uses two overlapping turntables for
/// AutoMix; this is the same idea in the weight of the app's other glyphs.
class TransitionGlyph extends StatelessWidget {
  const TransitionGlyph({super.key, this.size = 20, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: TransitionGlyphPainter(color),
      );
}

class TransitionGlyphPainter extends CustomPainter {
  TransitionGlyphPainter(this.color, {this.overlap = 1.0});

  final Color color;

  /// 0..1: how far the rings have slid into each other. 1 is the resting glyph;
  /// the Now Playing badge animates it with the mix.
  final double overlap;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final r = w * 0.27;
    final apart = w * (0.46 - 0.12 * overlap.clamp(0.0, 1.0));
    final cy = size.height / 2;
    final left = Offset(w / 2 - apart / 2, cy);
    final right = Offset(w / 2 + apart / 2, cy);

    final a = Path()..addOval(Rect.fromCircle(center: left, radius: r));
    final b = Path()..addOval(Rect.fromCircle(center: right, radius: r));
    final lens = Path.combine(PathOperation.intersect, a, b);

    canvas.drawPath(
      lens,
      Paint()
        ..color = color.withValues(alpha: 0.38)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..isAntiAlias = true;
    canvas.drawPath(a, ring);
    canvas.drawPath(b, ring);
  }

  @override
  bool shouldRepaint(TransitionGlyphPainter old) =>
      old.color != color || old.overlap != overlap;
}
