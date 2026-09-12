import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../stagger_in.dart';

/// Full-width Promotional Brand Card matching the Mine Music reference design.
///
/// Upgraded with `liquid_glass_easy` primitives:
/// - Outer shell is a soft-flexing obsidian LiquidGlassLens with squircle curvature and contact shadow.
/// - The right emblem is an interactive living LiquidGlassLens sphere with soft-body liquid physics.
/// - Left typography remains dominant: Eyebrow + "Listen\nyour way."
/// - 3D Mine Music mark suspended inside the refractive liquid glass sphere.
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
        child: SizedBox(
          height: 116,
          child: LiquidGlassLens(
            touch: const LiquidGlassTouch(
              flex: LiquidGlassFlex.subtle(),
            ),
            style: LiquidGlassStyle(
              shape: LiquidGlassShape.squircle(
                cornerRadius: 20,
                borderWidth: 0.8,
                lightColor: Colors.white.withValues(alpha: 0.28),
                lightIntensity: 0.85,
                lightDirection: 135,
                borderType: const OpticalBorder(
                  borderSaturation: 1.3,
                  ambientIntensity: 0.8,
                  borderSolidity: 0.05,
                  lightSpread: 1.0,
                ),
              ),
              appearance: const LiquidGlassAppearance(
                color: Color(0xE00C0D11), // Deep obsidian liquid glass
                blur: LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
                saturation: 1.08,
                shadow: LiquidGlassShadow(
                  blur: 6.0,
                  opacity: 0.35,
                ),
              ),
              refraction: const LiquidGlassRefraction(
                distortion: 0.06,
                distortionWidth: 20,
                refractionType: OpticalRefraction(),
              ),
            ),
            child: Stack(
              children: [
                // 1. Fluid liquid wave merging the card surface toward the orb
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RefinedPromoCausticPainter(),
                  ),
                ),
                // 2. Embedded Living 3D Liquid Glass Orb on the right with soft-body touch
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
        ),
      ),
    );
  }
}

/// 3D Liquid Glass Orb visually embedded into the promo card with soft-body liquid physics.
class _EmbeddedBrandGlassOrb extends StatelessWidget {
  const _EmbeddedBrandGlassOrb({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: LiquidGlassLens(
        touch: const LiquidGlassTouch(
          flex: LiquidGlassFlex.pronounced(),
        ),
        style: LiquidGlassStyle(
          shape: LiquidGlassShape.roundedRectangle(
            cornerRadius: size / 2,
            borderWidth: 1.4,
            lightColor: const Color(0xFFFFE0A2), // Warm caustic rim
            lightIntensity: 1.25,
            lightDirection: 135,
            borderType: const OpticalBorder(
              borderSaturation: 1.6,
              ambientIntensity: 1.15,
              borderSolidity: 0.15,
              lightSpread: 1.15,
            ),
          ),
          appearance: const LiquidGlassAppearance(
            color: Color(0x10FFFFFF),
            blur: LiquidGlassBlur(sigmaX: 7, sigmaY: 7),
            saturation: 1.15,
            shadow: LiquidGlassShadow(
              blur: 5.0,
              opacity: 0.35,
            ),
          ),
          refraction: const LiquidGlassRefraction(
            distortion: 0.12,
            distortionWidth: 22,
            refractionType: OpticalRefraction(),
          ),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            HapticFeedback.lightImpact();
          },
          child: Center(
            child: Image.asset(
              'assets/images/mine_music_mark.png',
              width: size * 0.50,
              fit: BoxFit.contain,
            ),
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
