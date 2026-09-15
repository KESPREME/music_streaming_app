import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../stagger_in.dart';
import 'library_hero_artwork.dart';

/// Full-width Promotional Brand Card matching the Mine Music reference design.
///
/// Refined composition:
/// - Visually merges the liquid glass orb into the card's obsidian material surface.
/// - Left typography remains dominant: Eyebrow + "Listen\nyour way."
/// - Suspended 3D Mine Music mark inside an interactive 3D Liquid Glass Orb
///   with true 3D parallax depth, elastic spring squish, and responsive caustic reflections.
class LibraryBrandPromoCard extends StatelessWidget {
  const LibraryBrandPromoCard({
    super.key,
    this.horizontalPadding = 20.0,
  });

  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 4, horizontalPadding, 10),
      child: SquishOnPress(
        onTap: () {
          HapticFeedback.lightImpact();
        },
        child: Container(
          height: 116,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF0C0D11), // Deep obsidian
            borderRadius: BorderRadius.circular(20),
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
              // 2. Embedded Interactive 3D Crystal Liquid Glass Orb on the right
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: LiquidOrb(
                    size: const Size(90, 90),
                    lightAlignment: Alignment.topLeft,
                    enableParallax: true,
                    parallaxScale: 4.8,
                    child: Image.asset(
                      'assets/images/mine_music_mark.png',
                      width: 45,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              // 3. Dominant Editorial Typography on the left
              Positioned(
                left: 20,
                top: 0,
                bottom: 0,
                right: 115, // Keep clean clearance from the orb
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
      ),
    );
  }
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
