import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Hero editorial typography and living liquid glass depth artwork for LibraryScreen.
///
/// Features:
/// - Compact vertical footprint (108px) for an intentional, uncluttered layout.
/// - Living, interactive 3D liquid glass bubble with fluid spring physics,
///   touch tilt, dynamic specular caustic lighting, and idle breathing float.
/// - Embedded organic cursive script *"Music lives here."* seamlessly integrated into the glass.
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
            // 1. Living Interactive 3D Liquid Glass Orb on the right
            const Positioned(
              top: -12,
              right: -6,
              width: 160,
              height: 150,
              child: _InteractiveHeroGlassOrb(),
            ),

            // 2. Editorial Typography on the left (Leading hierarchy)
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

/// Interactive Living Liquid Glass Orb with elastic spring squish, 3D tilt,
/// touch-responsive specular light caustics, and idle floating motion.
class _InteractiveHeroGlassOrb extends StatefulWidget {
  const _InteractiveHeroGlassOrb();

  @override
  State<_InteractiveHeroGlassOrb> createState() => _InteractiveHeroGlassOrbState();
}

class _InteractiveHeroGlassOrbState extends State<_InteractiveHeroGlassOrb>
    with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _springController;

  double _touchNormalizedX = 0.0;
  double _touchNormalizedY = 0.0;

  @override
  void initState() {
    super.initState();
    // Ambient breathing / floating animation (gentle 3.5s wave)
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();

    // Elastic spring physics for touch squish and release
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _idleController.dispose();
    _springController.dispose();
    super.dispose();
  }

  void _handlePanDown(DragDownDetails details, Size size) {
    HapticFeedback.lightImpact();
    setState(() {
      _touchNormalizedX = ((details.localPosition.dx / size.width) - 0.5) * 2;
      _touchNormalizedY = ((details.localPosition.dy / size.height) - 0.5) * 2;
    });
    _springController.forward();
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    setState(() {
      _touchNormalizedX =
          (((details.localPosition.dx / size.width) - 0.5) * 2).clamp(-1.0, 1.0);
      _touchNormalizedY =
          (((details.localPosition.dy / size.height) - 0.5) * 2).clamp(-1.0, 1.0);
    });
  }

  void _handlePanEnd() {
    HapticFeedback.lightImpact();
    setState(() {
      _touchNormalizedX = 0.0;
      _touchNormalizedY = 0.0;
    });
    _springController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _handlePanDown(d, size),
          onPanUpdate: (d) => _handlePanUpdate(d, size),
          onPanEnd: (_) => _handlePanEnd(),
          onPanCancel: () => _handlePanEnd(),
          child: AnimatedBuilder(
            animation: Listenable.merge([_idleController, _springController]),
            builder: (context, child) {
              final idleProgress = _idleController.value * 2 * math.pi;
              final idleFloatY = math.sin(idleProgress) * 2.5;
              final idleScale = 1.0 + (math.cos(idleProgress) * 0.015);

              // Spring scale: squishes to ~0.93 on press
              final springVal = _springController.value;
              final currentScale = idleScale * (1.0 - (springVal * 0.07));

              // 3D perspective tilt towards finger
              final tiltX = -_touchNormalizedY * 0.12 * springVal;
              final tiltY = _touchNormalizedX * 0.12 * springVal;

              // Caustic light angle tracks finger touch position
              final baseLightAngle = -math.pi / 2.8;
              final dynamicLightAngle = baseLightAngle +
                  (_touchNormalizedX * 0.45 * springVal) +
                  (_touchNormalizedY * 0.30 * springVal);

              final bloomIntensity = 1.0 + (springVal * 0.40);

              return Transform.translate(
                offset: Offset(0, idleFloatY),
                child: Transform.scale(
                  scale: currentScale,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0015)
                      ..rotateX(tiltX)
                      ..rotateY(tiltY),
                    child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1. Crystal Liquid Glass Orb Painter
                      CustomPaint(
                        size: size,
                        painter: _RefinedHeroGlassOrbPainter(
                          lightAngle: dynamicLightAngle,
                          bloomIntensity: bloomIntensity,
                          pulse: math.sin(idleProgress),
                        ),
                      ),
                      // 2. Cursive script nested inside the glass volume
                      Positioned(
                        right: 24,
                        top: 48,
                        child: Transform.rotate(
                          angle: -8 * math.pi / 180,
                          child: Text(
                            'Music\nlives\nhere.',
                            style: GoogleFonts.caveat(
                              color: Color.lerp(
                                const Color(0x60D6C8B4),
                                const Color(0xB8FFE8D0),
                                springVal,
                              ),
                              fontSize: 16.5,
                              height: 1.05,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.50),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            },
          ),
        );
      },
    );
  }
}

/// Custom painter rendering a physical liquid-glass form with soft optical transmission,
/// asymmetric specular caustic rim highlights, and a warm golden lens flare peak.
class _RefinedHeroGlassOrbPainter extends CustomPainter {
  const _RefinedHeroGlassOrbPainter({
    required this.lightAngle,
    required this.bloomIntensity,
    required this.pulse,
  });

  final double lightAngle;
  final double bloomIntensity;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.52, size.height * 0.52);
    final radius = size.width * 0.44;

    // 1. Soft atmospheric back-glow (cool slate-blue dispersion)
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF2E4059).withValues(alpha: (0.18 + pulse * 0.03) * bloomIntensity),
          const Color(0xFF16202E).withValues(alpha: 0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.35));
    canvas.drawCircle(center, radius * 1.35, glowPaint);

    // 2. Liquid glass volume (soft transmission, dark obsidian catching ambient light)
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        radius: 1.0,
        colors: [
          Colors.white.withValues(alpha: 0.07 * bloomIntensity),
          const Color(0xFF1E2A3A).withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bodyPaint);

    // 3. Asymmetric Specular Rim Arc (Upper-right quadrant with smooth gradient)
    final rimRect = Rect.fromCircle(center: center, radius: radius);

    // Soft caustic bloom behind rim
    final bloomPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi * 2,
        colors: [
          Colors.transparent,
          const Color(0xFFFFDF9E).withValues(alpha: (0.22 * bloomIntensity).clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: (0.20 * bloomIntensity).clamp(0.0, 1.0)),
          Colors.transparent,
          Colors.transparent,
        ],
        stops: const [0.0, 0.12, 0.24, 0.42, 1.0],
        transform: GradientRotation(lightAngle),
      ).createShader(rimRect);

    canvas.drawArc(
      rimRect,
      -math.pi * 0.45,
      math.pi * 0.80,
      false,
      bloomPaint,
    );

    // Sharp specular core with warm champagne peak
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi * 2,
        colors: [
          Colors.transparent,
          const Color(0xFFFFE0A2).withValues(alpha: (0.80 * bloomIntensity).clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: (0.75 * bloomIntensity).clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: 0.20),
          Colors.transparent,
          Colors.transparent,
        ],
        stops: const [0.0, 0.08, 0.18, 0.32, 0.48, 1.0],
        transform: GradientRotation(lightAngle),
      ).createShader(rimRect);

    canvas.drawArc(
      rimRect,
      -math.pi * 0.45,
      math.pi * 0.80,
      false,
      arcPaint,
    );

    // 4. Caustic Flare Point (Warm golden apex corona)
    final flareX = center.dx + (radius * 0.72);
    final flareY = center.dy - (radius * 0.68);
    final flareCenter = Offset(flareX, flareY);

    final flarePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: (0.65 * bloomIntensity).clamp(0.0, 1.0)),
          const Color(0xFFFFDF9E).withValues(alpha: (0.45 * bloomIntensity).clamp(0.0, 1.0)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(Rect.fromCircle(center: flareCenter, radius: 10 * bloomIntensity));
    canvas.drawCircle(flareCenter, 10 * bloomIntensity, flarePaint);

    // 5. Subtle secondary inner caustic glint
    final innerArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Colors.white.withValues(alpha: 0.30 * bloomIntensity),
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
  bool shouldRepaint(covariant _RefinedHeroGlassOrbPainter oldDelegate) =>
      oldDelegate.lightAngle != lightAngle ||
      oldDelegate.bloomIntensity != bloomIntensity ||
      oldDelegate.pulse != pulse;
}

