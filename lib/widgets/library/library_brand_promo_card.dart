import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Full-width Promotional Brand Card matching the Mine Music reference design.
///
/// Refined composition:
/// - Visually merges the liquid glass orb into the card's obsidian material surface
///   rather than appearing like a separate badge.
/// - Left typography remains dominant: Eyebrow + "Listen\nyour way."
/// - Suspended 3D Mine Music mark inside the refractive sphere with restrained reflection.
class LibraryBrandPromoCard extends StatelessWidget {
  const LibraryBrandPromoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Container(
        height: 120,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0C0D11), // Deep obsidian
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.6,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 1. Fluid liquid wave merging the card surface toward the orb
            Positioned.fill(
              child: CustomPaint(
                painter: _RefinedPromoCausticPainter(),
              ),
            ),
            // 2. Embedded 3D Liquid Glass Orb on the right
            const Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _EmbeddedBrandGlassOrb(size: 92),
              ),
            ),
            // 3. Dominant Editorial Typography on the left
            Positioned(
              left: 20,
              top: 0,
              bottom: 0,
              right: 120, // Keep clean clearance from the orb
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'YOUR MUSIC.\nYOUR WORLD.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: const Color(0xFF7E8492),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Listen\nyour way.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                      height: 1.08,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 3D Liquid Glass Orb visually embedded into the promo card.
class _EmbeddedBrandGlassOrb extends StatelessWidget {
  const _EmbeddedBrandGlassOrb({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glass Sphere Custom Painter
          CustomPaint(
            size: Size(size, size),
            painter: _EmbeddedOrbPainter(),
          ),
          // Suspended 3D Mine Music Ribbon Mark
          Image.asset(
            'assets/images/mine_music_mark.png',
            width: size * 0.50,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}

class _EmbeddedOrbPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Dark smoky glass volume with subtle transmission
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.28),
        radius: 1.0,
        colors: [
          Colors.white.withValues(alpha: 0.10),
          const Color(0xFF19202B).withValues(alpha: 0.30),
          const Color(0xFF07090D).withValues(alpha: 0.80),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bodyPaint);

    // 2. Partial Specular Rim Highlight (Asymmetric top-right caustic arc)
    final rimRect = Rect.fromCircle(center: center, radius: radius);
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi * 2,
        colors: [
          Colors.white.withValues(alpha: 0.85),
          const Color(0xFFFFDF9E).withValues(alpha: 0.90), // Warm caustic peak
          Colors.white.withValues(alpha: 0.35),
          Colors.transparent,
          Colors.transparent,
          Colors.white.withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.85),
        ],
        stops: const [0.0, 0.12, 0.26, 0.42, 0.80, 0.92, 1.0],
        transform: const GradientRotation(-math.pi / 3.5),
      ).createShader(rimRect);

    // Draw localized arc from top-left around to bottom-right
    canvas.drawArc(
      rimRect,
      -math.pi * 0.7,
      math.pi * 1.1,
      false,
      rimPaint,
    );

    // 3. Subtle inner refraction curve
    final innerHighlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.30),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.88),
      -math.pi * 0.80,
      math.pi * 0.50,
      false,
      innerHighlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RefinedPromoCausticPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Organic dark fluid transmission curving toward the right orb
    final path = Path()
      ..moveTo(w * 0.30, 0)
      ..cubicTo(
        w * 0.45,
        h * 0.30,
        w * 0.50,
        h * 0.65,
        w * 0.72,
        h,
      )
      ..lineTo(w, h)
      ..lineTo(w, 0)
      ..close();

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.04),
          const Color(0xFF222C3A).withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
