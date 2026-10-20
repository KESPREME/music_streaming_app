import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../theme/app_font.dart';
import '../../providers/music_provider.dart';

/// Hero editorial typography and living liquid glass depth artwork for LibraryScreen.
///
/// Features:
/// - Compact vertical footprint (108px) for an intentional, uncluttered layout.
/// - Living, interactive 3D Liquid Orb powered by analytic optical diffusion,
///   signed-distance Snell's law refraction, dynamic fluid flow, and glass shell optics.
/// - Fluid spring physics: elastic squish, 3D perspective tilt, and touch caustics.
/// - Embedded organic cursive script *"Music lives here."* seamlessly integrated into the glass.
/// - Dominant editorial typography: Eyebrow + Two-line Display Title ("Your\nLibrary").
class LibraryHeroArtwork extends StatelessWidget {
  const LibraryHeroArtwork({
    super.key,
    this.horizontalPadding = 20.0,
    this.isActive = true,
  });

  final double horizontalPadding;

  /// Forwarded to the Liquid Orb so an off-screen tab stops ticking.
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final dynamicColor = context.select<MusicProvider, Color?>((mp) {
      try {
        return mp.currentPaletteColor;
      } catch (_) {
        return null;
      }
    });

    return RepaintBoundary(
      child: SizedBox(
        height: 108,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Living Interactive 3D Liquid Glass Orb on the right
            Positioned(
              top: -12,
              right: -6,
              width: 160,
              height: 150,
              child: LiquidOrb(
                size: const Size(160, 150),
                lightAlignment: Alignment.topRight,
                childAlignment: const Alignment(0.42, -0.06),
                dynamicColor: dynamicColor,
                isActive: isActive,
                child: Transform.rotate(
                  angle: -8 * math.pi / 180,
                  child: Text(
                    'Music\nlives\nhere.',
                    style: GoogleFonts.caveat(
                      color: const Color(0xB8FFE8D0),
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
                    style: AppFont.style(
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
                      style: AppFont.style(
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

/// Global shader manager that pre-loads and caches the GPU `liquid_orb.frag` program.
class LiquidOrbShaderManager {
  static ui.FragmentProgram? _program;

  /// The in-flight load, shared by every concurrent caller.
  ///
  /// The previous `_isLoading` bool made `ensureLoaded()` return *immediately*
  /// when a load was already running, so a second caller received an
  /// already-completed future while `_program` was still null. Library mounts
  /// two orbs in the same frame, so one of them would silently and permanently
  /// fall back to the Skia painter. Sharing the Future makes all callers await
  /// the same load instead.
  static Future<void>? _pending;

  static ui.FragmentProgram? get program => _program;

  static Future<void> ensureLoaded() {
    if (_program != null) return Future<void>.value();
    return _pending ??= _load();
  }

  static Future<void> _load() async {
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/liquid_orb.frag');
    } catch (_) {
      // Gracefully falls back to high-fidelity procedural Skia painter in
      // environments without native fragment shader compilation.
    } finally {
      // Allow a later caller to retry (e.g. after a transient failure).
      _pending = null;
    }
  }
}

/// Easing curve for transition from idle -> thinking (cubic ease out: 1 - (1-t)^3).
class _ActivationCurve extends Curve {
  const _ActivationCurve();

  @override
  double transformInternal(double t) {
    final inv = 1.0 - t;
    return 1.0 - (inv * inv * inv);
  }
}

/// Easing curve for transition from thinking -> idle (smoothstep: t^2 * (3 - 2t)).
class _SettleCurve extends Curve {
  const _SettleCurve();

  @override
  double transformInternal(double t) => t * t * (3.0 - 2.0 * t);
}

/// Flagship Living Liquid Glass Orb with real GPU fragment shader fluid dynamics,
/// signed-distance refraction profile, dual specular lobes, tactile spring squish physics,
/// 3D perspective tilt, and touch-responsive state transitions (idle <-> thinking).
class LiquidOrb extends StatefulWidget {
  const LiquidOrb({
    super.key,
    required this.size,
    this.lightAlignment = Alignment.topRight,
    this.child,
    this.childAlignment = Alignment.center,
    this.enableParallax = false,
    this.parallaxScale = 4.5,
    this.onTap,
    this.dynamicColor,
    this.isActive = true,
  });

  final Size size;
  final Alignment lightAlignment;
  final Widget? child;
  final Alignment childAlignment;
  final bool enableParallax;
  final double parallaxScale;
  final VoidCallback? onTap;
  final Color? dynamicColor;

  /// Whether this orb is on the visible tab. When false the idle ticker is
  /// stopped and the subtree is wrapped in an inert [TickerMode], so an
  /// off-screen Library tab costs nothing. The orb is a per-pixel shader
  /// (see shaders/liquid_orb.frag) and is by far the most expensive thing on
  /// screen, so it must not tick while hidden.
  ///
  /// Defaults to true so existing call sites keep their exact behaviour.
  final bool isActive;

  @override
  State<LiquidOrb> createState() => _LiquidOrbState();
}

class _LiquidOrbState extends State<LiquidOrb> with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _springController;
  late final AnimationController _transitionController;

  late final Stopwatch _stopwatch;
  double _motionPhase = 0.0;
  double _lastElapsedSeconds = 0.0;

  double _touchNormalizedX = 0.0;
  double _touchNormalizedY = 0.0;

  /// Single reused GPU shader instance.
  ///
  /// Previously `program!.fragmentShader()` was called on *every paint*,
  /// allocating a fresh native shader 60x/second and never disposing it.
  /// One instance is created here and disposed with the State; uniforms are
  /// fully rewritten each frame so there is no stale-value risk.
  ui.FragmentShader? _shader;

  /// Reused paint for the shader pass (avoids a Paint allocation per frame).
  final ui.Paint _shaderPaint = ui.Paint();

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();

    // 1. Ambient breathing / floating animation (gentle 3.5s wave)
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );
    if (widget.isActive) _idleController.repeat();

    _idleController.addListener(_updateMotionPhase);

    // 2. Elastic spring physics for touch squish and release (380ms)
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    // 3. Dynamic transition between idle (0.0) and thinking (1.0) states
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    // Eagerly prewarm shader
    if (LiquidOrbShaderManager.program == null) {
      LiquidOrbShaderManager.ensureLoaded().then((_) {
        if (!mounted) return;
        _adoptProgram();
        setState(() {});
      });
    } else {
      _adoptProgram();
    }
  }

  /// Binds the cached [LiquidOrbShaderManager.program] to this State's
  /// reusable shader instance. Safe to call repeatedly.
  void _adoptProgram() {
    final program = LiquidOrbShaderManager.program;
    if (program == null) return;
    _shader?.dispose();
    _shader = program.fragmentShader();
  }

  @override
  void didUpdateWidget(LiquidOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive == oldWidget.isActive) return;
    if (widget.isActive) {
      // Resync the phase clock so the first delta after a long pause is not
      // a large jump (the shader time is wall-clock derived).
      _lastElapsedSeconds = _stopwatch.elapsedMicroseconds / 1000000.0;
      _idleController.repeat();
    } else {
      _idleController.stop();
    }
  }

  void _updateMotionPhase() {
    final now = _stopwatch.elapsedMicroseconds / 1000000.0;
    final dt = (now - _lastElapsedSeconds).clamp(0.0, 0.1);
    _lastElapsedSeconds = now;

    final progress = _transitionController.value;
    final currentSpeed = ui.lerpDouble(0.27, 0.90, progress) ?? 0.27;
    _motionPhase += dt * currentSpeed;
  }

  @override
  void dispose() {
    _idleController.removeListener(_updateMotionPhase);
    _idleController.dispose();
    _springController.dispose();
    _transitionController.dispose();
    _stopwatch.stop();
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  void _handlePanDown(DragDownDetails details) {
    HapticFeedback.lightImpact();
    setState(() {
      _touchNormalizedX =
          (((details.localPosition.dx / widget.size.width) - 0.5) * 2).clamp(-1.0, 1.0);
      _touchNormalizedY =
          (((details.localPosition.dy / widget.size.height) - 0.5) * 2).clamp(-1.0, 1.0);
    });

    _springController.forward();

    // Activate thinking state over 220ms with cubic ease-out
    _transitionController.duration = const Duration(milliseconds: 220);
    _transitionController.animateTo(
      1.0,
      curve: const _ActivationCurve(),
    );
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    setState(() {
      _touchNormalizedX =
          (((details.localPosition.dx / widget.size.width) - 0.5) * 2).clamp(-1.0, 1.0);
      _touchNormalizedY =
          (((details.localPosition.dy / widget.size.height) - 0.5) * 2).clamp(-1.0, 1.0);
    });
  }

  void _handlePanEnd() {
    HapticFeedback.lightImpact();
    widget.onTap?.call();
    setState(() {
      _touchNormalizedX = 0.0;
      _touchNormalizedY = 0.0;
    });

    _springController.reverse();

    // Settle back to idle state over 650ms with smoothstep
    _transitionController.duration = const Duration(milliseconds: 650);
    _transitionController.animateTo(
      0.0,
      curve: const _SettleCurve(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return TickerMode(
      // Mutes any tickers owned by descendants. The orb's own controllers are
      // gated explicitly in initState/didUpdateWidget, because a TickerMode
      // below this State cannot mute tickers it created.
      enabled: widget.isActive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: _handlePanDown,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: (_) => _handlePanEnd(),
        onPanCancel: _handlePanEnd,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _idleController,
            _springController,
            _transitionController,
          ]),
          builder: (context, child) {
            final idleProgress = _idleController.value * 2 * math.pi;
            final idleFloatY = math.sin(idleProgress) * 2.2;
            final idleScale = 1.0 + (math.cos(idleProgress) * 0.014);

            // Spring scale: squishes subtly to ~0.93 on press
            final springVal = _springController.value;
            final currentScale = idleScale * (1.0 - (springVal * 0.07));

            // 3D perspective tilt towards touch
            final tiltX = -_touchNormalizedY * 0.14 * springVal;
            final tiltY = _touchNormalizedX * 0.14 * springVal;

            final progress = _transitionController.value;
            final currentSpeed = ui.lerpDouble(0.27, 0.90, progress) ?? 0.27;
            final shaderTime = _motionPhase / math.max(currentSpeed, 0.001);

            final parallaxX = widget.enableParallax
                ? _touchNormalizedX * widget.parallaxScale * springVal
                : 0.0;
            final parallaxY = widget.enableParallax
                ? _touchNormalizedY * widget.parallaxScale * springVal
                : 0.0;

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
                    width: size.width,
                    height: size.height,
                    child: Stack(
                      alignment: widget.childAlignment,
                      children: [
                        // 1. Living Crystal Liquid Glass Shader Volume
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: size,
                              painter: _LiquidOrbPainter(
                                time: shaderTime,
                                progress: progress,
                                touchX: _touchNormalizedX * springVal,
                                touchY: _touchNormalizedY * springVal,
                                springVal: springVal,
                                lightAlignment: widget.lightAlignment,
                                shader: _shader,
                                shaderPaint: _shaderPaint,
                                dynamicColor: widget.dynamicColor,
                              ),
                            ),
                          ),
                        ),
                        // 2. Suspended internal element (e.g. Logo mark or Cursive
                        //    script) with Parallax. `widget.child` is a stable
                        //    instance, so this subtree is not rebuilt per frame.
                        if (widget.child != null)
                          Transform.translate(
                            offset: Offset(parallaxX, parallaxY),
                            child: widget.child!,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Dual-mode CustomPainter:
/// - When `ui.FragmentProgram` is available, renders the real GPU fragment shader
///   (`shaders/liquid_orb.frag`) with full analytic optical diffusion and Snell's law refraction.
/// - Composes hyper-crisp champagne specular caustic rims and apex flare on top.
/// - If shader is initializing or running in headless testing, smoothly renders the
///   volumetric Skia glass model with zero layout stutter or blank frames.
class _LiquidOrbPainter extends CustomPainter {
  const _LiquidOrbPainter({
    required this.time,
    required this.progress,
    required this.touchX,
    required this.touchY,
    required this.springVal,
    required this.lightAlignment,
    required this.shaderPaint,
    this.shader,
    this.dynamicColor,
  });

  final double time;
  final double progress;
  final double touchX;
  final double touchY;
  final double springVal;
  final Alignment lightAlignment;

  /// Reused GPU shader instance owned by the State (see [_LiquidOrbState]).
  /// Null until the program finishes compiling, or in headless test runs.
  final ui.FragmentShader? shader;

  /// Reused paint that [shader] is installed into, to avoid a per-frame
  /// `Paint()` allocation. Owned by the State.
  final ui.Paint shaderPaint;

  final Color? dynamicColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.50, size.height * 0.50);
    final minDim = math.min(size.width, size.height);
    final radius = minDim * 0.44;

    // -------------------------------------------------------------
    // 1. GPU Shader Pass (or Volumetric Fallback)
    // -------------------------------------------------------------
    final frag = shader;
    if (frag != null) {
      frag.setFloat(0, size.width);
      frag.setFloat(1, size.height);
      frag.setFloat(2, time);
      frag.setFloat(3, progress);
      frag.setFloat(4, touchX);
      frag.setFloat(5, touchY);
      if (dynamicColor != null) {
        frag.setFloat(6, dynamicColor!.r);
        frag.setFloat(7, dynamicColor!.g);
        frag.setFloat(8, dynamicColor!.b);
        frag.setFloat(9, 1.0);
      } else {
        frag.setFloat(6, 0.0);
        frag.setFloat(7, 0.0);
        frag.setFloat(8, 0.0);
        frag.setFloat(9, 0.0);
      }

      shaderPaint.shader = frag;
      canvas.drawRect(Offset.zero & size, shaderPaint);
    } else {
      // Fallback: Soft atmospheric back-glow
      final baseGlow = dynamicColor ?? const Color(0xFF2E4059);
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            baseGlow.withValues(alpha: (0.22 + progress * 0.12)),
            baseGlow.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0.0, 0.60, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 1.35));
      canvas.drawCircle(center, radius * 1.35, glowPaint);

      // Fallback: Volumetric smoky sapphire glass sphere
      final bodyPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment(-0.25 + touchX * 0.15, -0.25 + touchY * 0.15),
          radius: 1.0,
          colors: [
            Colors.white.withValues(alpha: 0.10 + progress * 0.06),
            const Color(0xFF1E2838).withValues(alpha: 0.35),
            const Color(0xFF080B10).withValues(alpha: 0.88),
          ],
          stops: const [0.0, 0.48, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, bodyPaint);
    }

    // -------------------------------------------------------------
    // 2. Optical Glass Shell Specular Caustics & Flare
    // -------------------------------------------------------------
    final isTopRight = lightAlignment == Alignment.topRight;
    final rimRect = Rect.fromCircle(center: center, radius: radius);
    final bloomIntensity = 1.0 + (springVal * 0.40) + (progress * 0.25);

    if (isTopRight) {
      // Hero Orb specular treatment (Upper-right champagne caustics)
      final baseLightAngle = -math.pi / 2.8;
      final dynamicLightAngle = baseLightAngle + (touchX * 0.35) + (touchY * 0.20);

      // Soft caustic bloom
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
          transform: GradientRotation(dynamicLightAngle),
        ).createShader(rimRect);

      canvas.drawArc(
        rimRect,
        -math.pi * 0.45,
        math.pi * 0.80,
        false,
        bloomPaint,
      );

      // Sharp specular core highlight
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = SweepGradient(
          startAngle: 0.0,
          endAngle: math.pi * 2,
          colors: [
            Colors.transparent,
            const Color(0xFFFFE0A2).withValues(alpha: (0.85 * bloomIntensity).clamp(0.0, 1.0)),
            Colors.white.withValues(alpha: (0.80 * bloomIntensity).clamp(0.0, 1.0)),
            Colors.white.withValues(alpha: 0.20),
            Colors.transparent,
            Colors.transparent,
          ],
          stops: const [0.0, 0.08, 0.18, 0.32, 0.48, 1.0],
          transform: GradientRotation(dynamicLightAngle),
        ).createShader(rimRect);

      canvas.drawArc(
        rimRect,
        -math.pi * 0.45,
        math.pi * 0.80,
        false,
        arcPaint,
      );

      // Caustic apex flare point
      final flareCenter = Offset(
        center.dx + (radius * 0.70) + (touchX * 3.5),
        center.dy - (radius * 0.65) + (touchY * 3.5),
      );
      final flarePaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: (0.70 * bloomIntensity).clamp(0.0, 1.0)),
            const Color(0xFFFFDF9E).withValues(alpha: (0.45 * bloomIntensity).clamp(0.0, 1.0)),
            Colors.transparent,
          ],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(Rect.fromCircle(center: flareCenter, radius: 9 * bloomIntensity));
      canvas.drawCircle(flareCenter, 9 * bloomIntensity, flarePaint);
    } else {
      // Promo Card Orb specular treatment (Upper-left champagne caustics + bottom bounce)
      final baseLightAngle = -math.pi * 0.75;
      final dynamicLightAngle = baseLightAngle + (touchX * 0.25);

      // Primary Specular Rim Arc (Top-left quadrant)
      final primaryRimPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = SweepGradient(
          startAngle: 0.0,
          endAngle: math.pi * 2,
          colors: [
            Colors.white.withValues(alpha: (0.90 * bloomIntensity).clamp(0.0, 1.0)),
            const Color(0xFFFFE0A2).withValues(alpha: (0.95 * bloomIntensity).clamp(0.0, 1.0)),
            Colors.white.withValues(alpha: (0.45 * bloomIntensity).clamp(0.0, 1.0)),
            Colors.transparent,
            Colors.transparent,
            Colors.white.withValues(alpha: (0.25 * bloomIntensity).clamp(0.0, 1.0)),
            Colors.white.withValues(alpha: (0.90 * bloomIntensity).clamp(0.0, 1.0)),
          ],
          stops: const [0.0, 0.14, 0.28, 0.45, 0.80, 0.92, 1.0],
          transform: GradientRotation(dynamicLightAngle),
        ).createShader(rimRect);

      canvas.drawArc(
        rimRect,
        -math.pi * 0.75,
        math.pi * 1.15,
        false,
        primaryRimPaint,
      );

      // Secondary Specular Rim Bounce (Bottom-right)
      final bouncePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = SweepGradient(
          startAngle: 0.0,
          endAngle: math.pi * 2,
          colors: [
            Colors.transparent,
            const Color(0xFFFFE0A2).withValues(alpha: (0.40 * bloomIntensity).clamp(0.0, 1.0)),
            Colors.white.withValues(alpha: (0.50 * bloomIntensity).clamp(0.0, 1.0)),
            Colors.transparent,
          ],
          stops: const [0.0, 0.18, 0.35, 0.55],
          transform: GradientRotation(math.pi * 0.65 + (touchX * 0.2)),
        ).createShader(rimRect);

      canvas.drawArc(
        rimRect,
        math.pi * 0.20,
        math.pi * 0.60,
        false,
        bouncePaint,
      );

      // Caustic Apex Flare Point (Top-left)
      final flareCenter = Offset(
        center.dx - (radius * 0.62) + (touchX * 4),
        center.dy - (radius * 0.62) + (touchY * 4),
      );
      final flarePaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: (0.75 * bloomIntensity).clamp(0.0, 1.0)),
            const Color(0xFFFFE0A2).withValues(alpha: (0.50 * bloomIntensity).clamp(0.0, 1.0)),
            Colors.transparent,
          ],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(Rect.fromCircle(center: flareCenter, radius: 8 * bloomIntensity));
      canvas.drawCircle(flareCenter, 8 * bloomIntensity, flarePaint);
    }

    // Inner refraction crescent for 3D depth
    final innerHighlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..shader = LinearGradient(
        begin: isTopRight ? Alignment.topRight : Alignment.topLeft,
        end: isTopRight ? Alignment.bottomLeft : Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: (0.35 * bloomIntensity).clamp(0.0, 1.0)),
          Colors.transparent,
        ],
      ).createShader(rimRect);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.88),
      isTopRight ? -math.pi * 0.35 : -math.pi * 0.80,
      isTopRight ? math.pi * 0.45 : math.pi * 0.50,
      false,
      innerHighlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidOrbPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.progress != progress ||
      oldDelegate.touchX != touchX ||
      oldDelegate.touchY != touchY ||
      oldDelegate.springVal != springVal ||
      oldDelegate.shader != shader ||
      // The shader instance is now long-lived, so tint/lighting changes are no
      // longer accompanied by an identity change. Without these two the orb
      // would keep a stale album tint whenever it happens to be idle.
      oldDelegate.dynamicColor != dynamicColor ||
      oldDelegate.lightAlignment != lightAlignment;
}
