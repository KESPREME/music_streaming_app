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
  const LibraryHeroArtwork({
    super.key,
    this.horizontalPadding = 20.0,
  });

  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: 108,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Atmospheric liquid glass depth on the right (positioned behind header actions)
            Positioned(
              top: -34,
              right: -16,
              width: 190,
              height: 190,
              child: CustomPaint(
                painter: _RefinedHeroGlassOrbPainter(),
              ),
            ),
            // 2. Subordinate cursive script "Music lives here."
            Positioned(
              top: 30,
              right: 28,
              child: Transform.rotate(
                angle: -7 * math.pi / 180,
                child: Text(
                  'Music\nlives\nhere.',
                  style: GoogleFonts.caveat(
                    color: const Color(0x38D6C8B4), // Restrained whisper
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
              left: horizontalPadding,
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
                      letterSpacing: 1.4,
                      color: const Color(0xFF7E8492),
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 5),
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 33,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.0,
                        height: 0.98,
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
/// and an asymmetric caustic rim highlight (subtle yet clearly perceptible).
class _RefinedHeroGlassOrbPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.52, size.height * 0.52);
    final radius = size.width * 0.44;

    // 1. Soft atmospheric back-glow (cool slate-blue dispersion)
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF2E4059).withValues(alpha: 0.16),
          const Color(0xFF16202E).withValues(alpha: 0.05),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.3));
    canvas.drawCircle(center, radius * 1.3, glowPaint);

    // 2. Liquid glass volume (soft transmission, dark glass barely catching ambient light)
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.2),
        radius: 1.0,
        colors: [
          Colors.white.withValues(alpha: 0.06),
          const Color(0xFF1E2A3A).withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bodyPaint);

    // 3. Asymmetric Specular Rim Arc (Upper-right quadrant only, fading smoothly)
    final rimRect = Rect.fromCircle(center: center, radius: radius);

    // Soft bloom behind rim
    final bloomPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi * 2,
        colors: [
          Colors.transparent,
          const Color(0xFFFFDF9E).withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.18),
          Colors.transparent,
          Colors.transparent,
        ],
        stops: const [0.0, 0.12, 0.24, 0.42, 1.0],
        transform: const GradientRotation(-math.pi / 2.8),
      ).createShader(rimRect);

    canvas.drawArc(
      rimRect,
      -math.pi * 0.45,
      math.pi * 0.75,
      false,
      bloomPaint,
    );

    // Sharp specular core
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi * 2,
        colors: [
          Colors.transparent,
          const Color(0xFFFFE0A2).withValues(alpha: 0.75), // Warm caustic peak
          Colors.white.withValues(alpha: 0.70),
          Colors.white.withValues(alpha: 0.18),
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
      ..strokeWidth = 0.7
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Colors.white.withValues(alpha: 0.30),
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
