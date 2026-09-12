import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../stagger_in.dart';

/// Full-width Promotional Brand Card matching the Mine Music reference design.
///
/// Refined composition:
/// - Visually merges the liquid glass orb into the card's obsidian material surface.
/// - Left typography remains dominant: Eyebrow + "Listen\nyour way."
/// - Suspended 3D Mine Music mark inside an interactive 3D crystal liquid glass sphere
///   with 3D parallax depth, elastic spring squish, and responsive caustic reflections.
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
              const Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _InteractiveBrandGlassOrb(size: 90),
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

/// 3D Crystal Liquid Glass Orb with true 3D parallax depth for the internal logo,
/// elastic touch squish physics, dynamic specular highlights, and idle floating motion.
class _InteractiveBrandGlassOrb extends StatefulWidget {
  const _InteractiveBrandGlassOrb({required this.size});

  final double size;

  @override
  State<_InteractiveBrandGlassOrb> createState() => _InteractiveBrandGlassOrbState();
}

class _InteractiveBrandGlassOrbState extends State<_InteractiveBrandGlassOrb>
    with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _springController;

  double _touchNormalizedX = 0.0;
  double _touchNormalizedY = 0.0;

  @override
  void initState() {
    super.initState();
    // Subtle idle floating pulse
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    // Elastic spring physics for touch squish
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
  }

  @override
  void dispose() {
    _idleController.dispose();
    _springController.dispose();
    super.dispose();
  }

  void _handlePanDown(DragDownDetails details) {
    HapticFeedback.lightImpact();
    setState(() {
      _touchNormalizedX = ((details.localPosition.dx / widget.size) - 0.5) * 2;
      _touchNormalizedY = ((details.localPosition.dy / widget.size) - 0.5) * 2;
    });
    _springController.forward();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    setState(() {
      _touchNormalizedX =
          (((details.localPosition.dx / widget.size) - 0.5) * 2).clamp(-1.0, 1.0);
      _touchNormalizedY =
          (((details.localPosition.dy / widget.size) - 0.5) * 2).clamp(-1.0, 1.0);
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
    final size = widget.size;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: _handlePanDown,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: (_) => _handlePanEnd(),
      onPanCancel: _handlePanEnd,
      child: AnimatedBuilder(
        animation: Listenable.merge([_idleController, _springController]),
        builder: (context, child) {
          final idleProgress = _idleController.value * 2 * math.pi;
          final idleFloatY = math.sin(idleProgress) * 1.8;
          final idleScale = 1.0 + (math.cos(idleProgress) * 0.012);

          final springVal = _springController.value;
          final currentScale = idleScale * (1.0 - (springVal * 0.08));

          // 3D perspective tilt
          final tiltX = -_touchNormalizedY * 0.15 * springVal;
          final tiltY = _touchNormalizedX * 0.15 * springVal;

          // Parallax depth offset for suspended 3D logo inside the sphere
          final parallaxX = _touchNormalizedX * 4.5 * springVal;
          final parallaxY = _touchNormalizedY * 4.5 * springVal;

          final bloom = 1.0 + (springVal * 0.35);

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
                child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 1. 3D Crystal Liquid Glass Sphere Volume
                    CustomPaint(
                      size: Size(size, size),
                      painter: _CrystalGlassOrbPainter(
                        bloom: bloom,
                        pulse: math.sin(idleProgress),
                        lightShiftX: _touchNormalizedX * springVal,
                        lightShiftY: _touchNormalizedY * springVal,
                      ),
                    ),
                    // 2. Suspended 3D Mine Music Ribbon Mark with 3D Parallax
                    Transform.translate(
                      offset: Offset(parallaxX, parallaxY),
                      child: Image.asset(
                        'assets/images/mine_music_mark.png',
                        width: size * 0.50,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        },
      ),
    );
  }
}

/// Custom painter rendering a hyper-realistic 3D crystal liquid glass sphere
/// matching the approved design reference (`media_1789192390759.png`).
class _CrystalGlassOrbPainter extends CustomPainter {
  const _CrystalGlassOrbPainter({
    required this.bloom,
    required this.pulse,
    required this.lightShiftX,
    required this.lightShiftY,
  });

  final double bloom;
  final double pulse;
  final double lightShiftX;
  final double lightShiftY;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Soft atmospheric back-glow (deep cyan-slate dispersion)
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF2E4059).withValues(alpha: (0.24 + pulse * 0.04) * bloom),
          const Color(0xFF16202E).withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.60, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.30));
    canvas.drawCircle(center, radius * 1.30, glowPaint);

    // 2. Dark smoky crystal glass sphere volume (optical depth)
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(-0.28 + lightShiftX * 0.15, -0.28 + lightShiftY * 0.15),
        radius: 1.0,
        colors: [
          Colors.white.withValues(alpha: 0.12 * bloom),
          const Color(0xFF1E2838).withValues(alpha: 0.35),
          const Color(0xFF080B10).withValues(alpha: 0.85),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bodyPaint);

    final rimRect = Rect.fromCircle(center: center, radius: radius);

    // 3. Primary Specular Rim Arc (Top-left quadrant, intense champagne/white peak)
    final primaryRimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi * 2,
        colors: [
          Colors.white.withValues(alpha: (0.90 * bloom).clamp(0.0, 1.0)),
          const Color(0xFFFFE0A2).withValues(alpha: (0.95 * bloom).clamp(0.0, 1.0)), // Warm caustic peak
          Colors.white.withValues(alpha: (0.45 * bloom).clamp(0.0, 1.0)),
          Colors.transparent,
          Colors.transparent,
          Colors.white.withValues(alpha: (0.25 * bloom).clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: (0.90 * bloom).clamp(0.0, 1.0)),
        ],
        stops: const [0.0, 0.14, 0.28, 0.45, 0.80, 0.92, 1.0],
        transform: GradientRotation(-math.pi / 3.2 + (lightShiftX * 0.2)),
      ).createShader(rimRect);

    canvas.drawArc(
      rimRect,
      -math.pi * 0.75,
      math.pi * 1.15,
      false,
      primaryRimPaint,
    );

    // 4. Secondary Specular Rim Bounce (Bottom-right ambient reflection)
    final bouncePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi * 2,
        colors: [
          Colors.transparent,
          const Color(0xFFFFE0A2).withValues(alpha: (0.40 * bloom).clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: (0.50 * bloom).clamp(0.0, 1.0)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.18, 0.35, 0.55],
        transform: GradientRotation(math.pi * 0.65 + (lightShiftX * 0.2)),
      ).createShader(rimRect);

    canvas.drawArc(
      rimRect,
      math.pi * 0.20,
      math.pi * 0.60,
      false,
      bouncePaint,
    );

    // 5. Caustic Apex Flare Point
    final flareCenter = Offset(
      center.dx - (radius * 0.62) + (lightShiftX * 4),
      center.dy - (radius * 0.62) + (lightShiftY * 4),
    );
    final flarePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: (0.75 * bloom).clamp(0.0, 1.0)),
          const Color(0xFFFFE0A2).withValues(alpha: (0.50 * bloom).clamp(0.0, 1.0)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(Rect.fromCircle(center: flareCenter, radius: 8 * bloom));
    canvas.drawCircle(flareCenter, 8 * bloom, flarePaint);

    // 6. Subtle inner refraction curve giving true spherical depth
    final innerHighlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: (0.35 * bloom).clamp(0.0, 1.0)),
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
  bool shouldRepaint(covariant _CrystalGlassOrbPainter oldDelegate) =>
      oldDelegate.bloom != bloom ||
      oldDelegate.pulse != pulse ||
      oldDelegate.lightShiftX != lightShiftX ||
      oldDelegate.lightShiftY != lightShiftY;
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

