import 'package:flutter/material.dart';

/// Custom painter for Apple Music / Muzo 3-wave Canvas visualizer icon (Image 1, 2, 4).
class AppleCanvasIcon extends StatelessWidget {
  final Color color;
  final double size;

  const AppleCanvasIcon({
    super.key,
    required this.color,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CanvasWavesPainter(color: color),
      ),
    );
  }
}

class _CanvasWavesPainter extends CustomPainter {
  final Color color;

  _CanvasWavesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final double width = size.width;
    final double height = size.height;

    // Draw 3 horizontal wavy lines stacked vertically
    final double spacing = height * 0.26;
    final double startY = height * 0.24;

    for (int i = 0; i < 3; i++) {
      final y = startY + (i * spacing);
      final path = Path();
      path.moveTo(width * 0.12, y);

      // Two sinusoidal humps
      final cp1x = width * 0.32;
      final cp1y = y - (height * 0.10);
      final midX = width * 0.50;
      final midY = y;

      final cp2x = width * 0.68;
      final cp2y = y + (height * 0.10);
      final endX = width * 0.88;
      final endY = y;

      path.cubicTo(cp1x, cp1y, midX, midY, midX, midY);
      path.cubicTo(midX, midY, cp2x, cp2y, endX, endY);

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasWavesPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Custom painter for Apple Music Lyrics icon: speech bubble with quotes (Image 1, 2).
class AppleLyricsIcon extends StatelessWidget {
  final Color color;
  final double size;

  const AppleLyricsIcon({
    super.key,
    required this.color,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LyricsBubblePainter(color: color),
      ),
    );
  }
}

class _LyricsBubblePainter extends CustomPainter {
  final Color color;

  _LyricsBubblePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Speech bubble outline
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.10, h * 0.12, w * 0.80, h * 0.62),
      Radius.circular(w * 0.20),
    );

    final bubblePath = Path()..addRRect(bubbleRect);

    // Bubble tail at bottom left
    final tailPath = Path()
      ..moveTo(w * 0.24, h * 0.74)
      ..lineTo(w * 0.18, h * 0.88)
      ..lineTo(w * 0.38, h * 0.74)
      ..close();

    final fullBubble = Path.combine(PathOperation.union, bubblePath, tailPath);
    canvas.drawPath(fullBubble, strokePaint);

    // Two small quote marks inside the bubble
    // Left quote dot/comma
    canvas.drawCircle(Offset(w * 0.38, h * 0.40), w * 0.055, fillPaint);
    final leftComma = Path()
      ..moveTo(w * 0.38, h * 0.40)
      ..cubicTo(w * 0.38, h * 0.46, w * 0.33, h * 0.50, w * 0.31, h * 0.52);
    canvas.drawPath(leftComma, strokePaint..strokeWidth = w * 0.04);

    // Right quote dot/comma
    canvas.drawCircle(Offset(w * 0.60, h * 0.40), w * 0.055, fillPaint);
    final rightComma = Path()
      ..moveTo(w * 0.60, h * 0.40)
      ..cubicTo(w * 0.60, h * 0.46, w * 0.55, h * 0.50, w * 0.53, h * 0.52);
    canvas.drawPath(rightComma, strokePaint..strokeWidth = w * 0.04);
  }

  @override
  bool shouldRepaint(covariant _LyricsBubblePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Custom painter for Apple Music / Muzo Film / Canvas icon: 35mm film strip cell (Image 2).
class AppleFilmIcon extends StatelessWidget {
  final Color color;
  final double size;

  const AppleFilmIcon({
    super.key,
    required this.color,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _FilmStripPainter(color: color),
      ),
    );
  }
}

class _FilmStripPainter extends CustomPainter {
  final Color color;

  _FilmStripPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Outer film frame (rounded rect)
    final frameRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.10, h * 0.16, w * 0.80, h * 0.68),
      Radius.circular(w * 0.14),
    );
    canvas.drawRRect(frameRect, strokePaint);

    // Inner main frame / window
    final innerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.28, h * 0.28, w * 0.44, h * 0.44),
      Radius.circular(w * 0.06),
    );
    canvas.drawRRect(innerRect, strokePaint..strokeWidth = w * 0.065);

    // Left sprocket holes (2 small rectangles)
    final spWidth = w * 0.09;
    final spHeight = h * 0.13;
    final spRadius = Radius.circular(w * 0.03);

    // Left top sprocket
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.14, h * 0.28, spWidth, spHeight),
        spRadius,
      ),
      fillPaint,
    );
    // Left bottom sprocket
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.14, h * 0.59, spWidth, spHeight),
        spRadius,
      ),
      fillPaint,
    );

    // Right top sprocket
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.77, h * 0.28, spWidth, spHeight),
        spRadius,
      ),
      fillPaint,
    );
    // Right bottom sprocket
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.77, h * 0.59, spWidth, spHeight),
        spRadius,
      ),
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FilmStripPainter oldDelegate) =>
      oldDelegate.color != color;
}
