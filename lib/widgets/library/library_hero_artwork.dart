import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Hero editorial typography and atmospheric liquid glass depth artwork for LibraryScreen.
///
/// Refined visual composition:
/// - Compact vertical footprint (112px) for a tighter, more intentional layout.
/// - Physically believable liquid glass object with asymmetric caustic rim highlights
///   (no hard circular perimeter outline or high-contrast ring).
/// - Subordinate cursive script *"Music lives here."* softly discovered in the glass depth.
/// - Dominant editorial typography: Eyebrow + Two-line Display Title ("Your\nLibrary").
class LibraryHeroArtwork extends StatelessWidget {
  const LibraryHeroArtwork({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: 112,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Atmospheric liquid glass depth on the right (positioned behind header actions)
            Positioned(
              top: -32,
              right: -18,
              width: 190,
              height: 190,
              child: CustomPaint(
                painter: _RefinedHeroGlassOrbPainter(),
              ),
            ),
            // 2. Subordinate cursive script "Music lives here."
            Positioned(
              top: 32,
              right: 28,
              child: Transform.rotate(
                angle: -7 * math.pi / 180,
                child: Text(
                  'Music\nlives\nhere.',
                  style: GoogleFonts.caveat(
                    color: const Color(0x35D6C8B4), // Restrained whisper
                    fontSize: 16,
                    height: 1.05,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
            // 3. Editorial Typography on the left (Leading hierarchy)
            Positioned(
              left: 20,
              bottom: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ALL YOUR SOUNDS,\nIN ONE PLACE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: const Color(0xFF7E8492),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.0,
                        height: 1.0,
                      ),
                      children: const [
                        TextSpan(
                          text: 'Your\n',
                          style: TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: 'Library',
                          style: TextStyle(color: Color(0xFF7B8596)),
                        ),
                      ],
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

/// Custom painter rendering a physical liquid-glass form with soft optical transmission
/// and an asymmetric caustic rim highlight (no continuous hard vector circle).
class _RefinedHeroGlassOrbPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.52, size.height * 0.52);
    final radius = size.width * 0.44;

    // 1. Soft atmospheric back-glow (subtle cool slate-blue dispersion)
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF28384E).withValues(alpha: 0.10),
          const Color(0xFF141C28).withValues(alpha: 0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.3));
    canvas.drawCircle(center, radius * 1.3, glowPaint);

    // 2. Liquid glass volume (very soft transmission, no dark opaque center)
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.2),
        radius: 1.0,
        colors: [
          Colors.white.withValues(alpha: 0.04),
          const Color(0xFF182230).withValues(alpha: 0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bodyPaint);

    // 3. Asymmetric Specular Rim Arc (Upper-right quadrant only, fading smoothly)
    // Avoids completing the full circle and leaves the left/bottom open to void.
    final rimRect = Rect.fromCircle(center: center, radius: radius);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi * 2,
        colors: [
          Colors.transparent,
          const Color(0xFFFFDF9E).withValues(alpha: 0.70), // Warm caustic peak
          Colors.white.withValues(alpha: 0.65),
          Colors.white.withValues(alpha: 0.15),
          Colors.transparent,
          Colors.transparent,
        ],
        stops: const [0.0, 0.08, 0.18, 0.32, 0.48, 1.0],
        transform: const GradientRotation(-math.pi / 2.8),
      ).createShader(rimRect);

    // Draw only the upper-right arc (roughly 120 degrees)
    canvas.drawArc(
      rimRect,
      -math.pi * 0.45,
      math.pi * 0.75,
      false,
      arcPaint,
    );

    // 4. Subtle secondary inner caustic glint
    final innerArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Colors.white.withValues(alpha: 0.25),
          Colors.transparent,
        ],
      ).createShader(rimRect);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.88),
      -math.pi * 0.35,
      math.pi * 0.45,
      false,
      innerArcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
