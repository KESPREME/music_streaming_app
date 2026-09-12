import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../stagger_in.dart';

/// 2-Column Action Card matching the Mine Music reference design.
///
/// Refined liquid material system:
/// - Deep obsidian foundation (`#0C0D11`) with subtle internal luminance.
/// - Broad, soft volumetric light transmission in the lower-right (simulating
///   light moving through smoked liquid glass, without vector strokes).
/// - Restrained squircle badge and quiet chevron affordance.
/// - Crisp typography hierarchy (compact title, quiet metadata).
/// - Apple-grade tactile `SquishOnPress` micro-interaction.
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
    return SquishOnPress(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Semantics(
        button: true,
        label: '$title, $subtitle',
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF0C0D11), // Deep obsidian
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08), // Restrained hairline
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.40),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            children: [
              // 1. Broad Volumetric Caustic Transmission (Liquid light through glass)
              Positioned.fill(
                child: CustomPaint(
                  painter: _RefinedCardCausticPainter(color: color),
                ),
              ),
              // 2. Card Content Layout
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Squircle icon badge + Chevron pill
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Restrained Squircle Badge
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: color.withValues(alpha: 0.20),
                              width: 0.6,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              icon,
                              color: color,
                              size: 19,
                            ),
                          ),
                        ),
                        // Quiet Circular Chevron Pill (>)
                        Container(
                          width: 26,
                          height: 26,
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
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.60),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Bottom: Title & Subtitle Hierarchy
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        letterSpacing: -0.2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2.5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
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

/// Custom painter for soft, asymmetric volumetric light transmission in the lower-right quadrant.
/// Replaces sharp vector strokes with broad, organic optical falloff.
class _RefinedCardCausticPainter extends CustomPainter {
  const _RefinedCardCausticPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Broad diffuse ambient pool (lower-right quadrant)
    final poolPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.85, 0.85),
        radius: 0.90,
        colors: [
          color.withValues(alpha: 0.15),
          color.withValues(alpha: 0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), poolPaint);

    // 2. Soft, organic fluid wave with optical falloff (NO hard stroked line)
    final wavePath = Path()
      ..moveTo(w * 0.35, h)
      ..cubicTo(
        w * 0.55,
        h * 0.78,
        w * 0.68,
        h * 0.48,
        w,
        h * 0.42,
      )
      ..lineTo(w, h)
      ..close();

    final wavePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          color.withValues(alpha: 0.16),
          color.withValues(alpha: 0.07),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(wavePath, wavePaint);

    // 3. Very subtle secondary inner refraction wave (feathered, low opacity)
    final secondaryPath = Path()
      ..moveTo(w * 0.50, h)
      ..cubicTo(
        w * 0.68,
        h * 0.82,
        w * 0.78,
        h * 0.62,
        w,
        h * 0.58,
      )
      ..lineTo(w, h)
      ..close();

    final secondaryPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          Colors.white.withValues(alpha: 0.04),
          color.withValues(alpha: 0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.40, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(secondaryPath, secondaryPaint);
  }

  @override
  bool shouldRepaint(covariant _RefinedCardCausticPainter oldDelegate) =>
      oldDelegate.color != color;
}
