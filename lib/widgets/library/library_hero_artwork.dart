import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// Hero editorial typography and living liquid glass depth artwork for LibraryScreen.
///
/// Refined visual composition with live `liquid_glass_easy` primitives:
/// - Interactive, soft-body liquid glass bubble (`LiquidGlassLens` + `LiquidGlassTouch`).
/// - Physically realistic Snell's law refraction bending the cursive script and background.
/// - `OpticalBorder` rim lighting with warm caustic highlights (`#FFE0A2`).
/// - Contact shadow pooling underneath with `LiquidGlassShadow`.
/// - Editorial typography: Eyebrow + Two-line Display Title ("Your\nLibrary").
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
            // 1. Soft atmospheric back-glow behind the liquid glass orb
            Positioned(
              top: -38,
              right: -20,
              width: 195,
              height: 195,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF2E4059).withValues(alpha: 0.22),
                        const Color(0xFF16202E).withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // 2. Interactive Living Liquid Glass Orb with Soft-Body Physics & Refraction
            Positioned(
              top: -30,
              right: -10,
              width: 172,
              height: 172,
              child: LiquidGlassLens(
                touch: const LiquidGlassTouch(
                  flex: LiquidGlassFlex.pronounced(),
                ),
                style: const LiquidGlassStyle(
                  shape: LiquidGlassShape.roundedRectangle(
                    cornerRadius: 86.0,
                    borderWidth: 1.4,
                    lightColor: Color(0xFFFFE0A2), // Warm caustic peak
                    lightIntensity: 1.25,
                    lightDirection: 135,
                    borderType: OpticalBorder(
                      borderSaturation: 1.6,
                      ambientIntensity: 1.15,
                      borderSolidity: 0.15,
                      lightSpread: 1.15,
                    ),
                  ),
                  appearance: LiquidGlassAppearance(
                    color: Color(0x0CFFFFFF), // Restrained dark smoked glass
                    blur: LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
                    saturation: 1.15,
                    shadow: LiquidGlassShadow(
                      blur: 6.0,
                      opacity: 0.35,
                    ),
                  ),
                  refraction: LiquidGlassRefraction(
                    distortion: 0.14,
                    distortionWidth: 28,
                    refractionType: OpticalRefraction(),
                  ),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    HapticFeedback.lightImpact();
                  },
                  child: Center(
                    child: Transform.rotate(
                      angle: -7 * math.pi / 180,
                      child: Text(
                        'Music\nlives\nhere.',
                        style: GoogleFonts.caveat(
                          color: const Color(0x75E8DAC6), // Organic warm script
                          fontSize: 18,
                          height: 1.05,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
