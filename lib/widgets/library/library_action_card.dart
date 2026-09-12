import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../stagger_in.dart';

/// 2-Column Action Card matching the Mine Music reference design.
///
/// Upgraded with `liquid_glass_easy` primitives:
/// - Living obsidian liquid glass surface (`LiquidGlassLens` + `LiquidGlassTouch`).
/// - Soft-body touch deformation on press and pull (`LiquidGlassFlex.subtle()`).
/// - `OpticalBorder` rim lighting with background-tinted specular reflection.
/// - Integrated contact shadow hugging the rim with `LiquidGlassShadow`.
/// - Broad, soft volumetric light transmission in the lower-right.
/// - Crisp typography hierarchy with zero RenderFlex overflow.
class LibraryActionCard extends StatelessWidget {
  const LibraryActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: LiquidGlassLens(
        touch: const LiquidGlassTouch(
          flex: LiquidGlassFlex.subtle(),
        ),
        style: LiquidGlassStyle(
          shape: LiquidGlassShape.squircle(
            cornerRadius: 20,
            borderWidth: 0.8,
            lightColor: Colors.white.withValues(alpha: 0.35),
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
            color: Color(0xE80C0D11), // Deep obsidian glass
            blur: LiquidGlassBlur(sigmaX: 7, sigmaY: 7),
            saturation: 1.08,
            shadow: LiquidGlassShadow(
              blur: 5.0,
              opacity: 0.35,
            ),
          ),
          refraction: const LiquidGlassRefraction(
            distortion: 0.06,
            distortionWidth: 18,
            refractionType: OpticalRefraction(),
          ),
        ),
        child: SquishOnPress(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Stack(
            children: [
              // 1. Broad Volumetric Caustic Transmission (Liquid light through glass)
              Positioned.fill(
                child: CustomPaint(
                  painter: _RefinedCardCausticPainter(color: color),
                ),
              ),
              // 2. Card Content Layout with Bounded Responsive Sizing
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth;
                  final cardHeight = constraints.maxHeight;

                  // Derive sizing dynamically within user-approved ranges
                  final padH = (cardWidth * 0.075).clamp(11.0, 14.0);
                  final padV = (cardHeight * 0.065).clamp(7.0, 10.0);
                  final badgeSize = (cardHeight * 0.34).clamp(36.0, 40.0);
                  final iconSize = (badgeSize * 0.50).clamp(18.0, 20.0);
                  final chevronSize = (cardHeight * 0.27).clamp(28.0, 32.0);
                  final chevronIconSize = (chevronSize * 0.48).clamp(13.5, 16.0);

                  // Responsive typography: fits wide & narrow devices without cramping
                  final titleSize = (cardWidth * 0.084).clamp(13.5, 15.5);
                  final subtitleSize = (cardWidth * 0.068).clamp(11.0, 13.0);

                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Upper Controls: Squircle icon badge + Subtle chevron pill
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Squircle Icon Badge
                            Container(
                              width: badgeSize,
                              height: badgeSize,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(badgeSize * 0.28),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.22),
                                  width: 0.6,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  icon,
                                  color: color,
                                  size: iconSize,
                                ),
                              ),
                            ),
                            // Subordinate Circular Chevron
                            Container(
                              width: chevronSize,
                              height: chevronSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.06),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  width: 0.5,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  size: chevronIconSize,
                                  color: Colors.white.withValues(alpha: 0.60),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Lower Information: Title & Subtitle Hierarchy
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700,
                                    fontSize: titleSize,
                                    letterSpacing: -0.2,
                                    height: 1.12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 1.5),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white.withValues(alpha: 0.48),
                                  fontSize: subtitleSize,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter for soft, organic volumetric light transmission in the lower-right quadrant.
/// Uses minimal GPU-friendly draw operations without diagonal stripes or continuous animation.
class _RefinedCardCausticPainter extends CustomPainter {
  const _RefinedCardCausticPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Broad diffuse ambient pool (lower-right quadrant, soft optical falloff)
    final poolPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.85, 0.85),
        radius: 0.95,
        colors: [
          color.withValues(alpha: 0.12),
          color.withValues(alpha: 0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), poolPaint);

    // 2. Organic curved refraction wave (smooth curve, no diagonal vector lines)
    final wavePath = Path()
      ..moveTo(w * 0.38, h)
      ..cubicTo(
        w * 0.58,
        h * 0.76,
        w * 0.72,
        h * 0.50,
        w,
        h * 0.45,
      )
      ..lineTo(w, h)
      ..close();

    final wavePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          color.withValues(alpha: 0.12),
          color.withValues(alpha: 0.05),
          Colors.transparent,
        ],
        stops: const [0.0, 0.40, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(wavePath, wavePaint);

    // 3. Subtle specular top-edge glint simulating physical glass thickness
    final specularPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.topRight,
        colors: [
          Colors.white.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.03),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final specularPath = Path()
      ..moveTo(20, 0.6)
      ..lineTo(w * 0.55, 0.6);
    canvas.drawPath(specularPath, specularPaint);
  }

  @override
  bool shouldRepaint(covariant _RefinedCardCausticPainter oldDelegate) =>
      oldDelegate.color != color;
}
