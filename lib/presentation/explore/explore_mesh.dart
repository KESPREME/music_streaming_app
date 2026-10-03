import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/test_environment.dart';

import '../../services/explore/explore_palette.dart';
import 'explore_tokens.dart';

/// Fluid album-adaptive liquid atmosphere:
/// Multi-stop chromatic gradient canvas (deep -> bg -> vibrant -> accent)
/// with continuous organic ambient drift and an animated soundwave equalizer
/// visualizer inspired by Gradient Builder (Sky / Aurora / Soundwave: Bars).
class LiquidMeshBackground extends StatefulWidget {
  const LiquidMeshBackground({
    super.key,
    required this.palette,
    required this.seed,
    this.isPlaying = false,
  });

  final ExplorePalette palette;
  final String seed;
  final bool isPlaying;

  @override
  State<LiquidMeshBackground> createState() => _LiquidMeshBackgroundState();
}

class _LiquidMeshBackgroundState extends State<LiquidMeshBackground>
    with TickerProviderStateMixin {
  late final AnimationController _mesh = AnimationController(
    vsync: this,
    duration: ExploreTokens.meshTransition,
  );

  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  late final AnimationController _eqAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _isTesting => TestEnvironment.isTesting;

  late ExplorePalette _from;
  late ExplorePalette _to;
  late List<Alignment> _fromAlign;
  late List<Alignment> _toAlign;

  static const _layouts = [
    [Alignment(-0.8, -0.6), Alignment(0.8, 0.5), Alignment(0.4, -0.2)],
    [Alignment(0.8, -0.7), Alignment(-0.7, 0.6), Alignment(-0.4, 0.2)],
    [Alignment(-0.2, -0.8), Alignment(0.4, 0.7), Alignment(0.1, -0.1)],
  ];

  static List<Alignment> _layoutFor(String seed) =>
      _layouts[seed.hashCode.abs() % _layouts.length];

  @override
  void initState() {
    super.initState();
    _from = _to = widget.palette;
    _fromAlign = _toAlign = _layoutFor(widget.seed);
    _mesh.value = 1.0;
    if (!_isTesting) {
      _drift.repeat();
      if (widget.isPlaying) {
        _eqAnim.repeat();
      }
    }
  }

  @override
  void didUpdateWidget(LiquidMeshBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isTesting) {
      if (widget.isPlaying && !_eqAnim.isAnimating) {
        _eqAnim.repeat();
      } else if (!widget.isPlaying && _eqAnim.isAnimating) {
        _eqAnim.stop();
      }
    }
    if (widget.seed != oldWidget.seed) {
      _from = _to;
      _to = widget.palette;
      _fromAlign = _toAlign;
      _toAlign = _layoutFor(widget.seed);
      _mesh.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _mesh.dispose();
    _drift.dispose();
    _eqAnim.dispose();
    super.dispose();
  }

  Alignment _lerpAlign(int i, double v) => Alignment.lerp(
      _fromAlign[i], _toAlign[i], Curves.easeOutCubic.transform(v))!;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_mesh, _drift, _eqAnim]),
        builder: (context, _) {
          final v = Curves.easeOutCubic.transform(_mesh.value);
          final d = _drift.value * 2 * pi;
          final vib = Color.lerp(_from.vibrant, _to.vibrant, v)!;
          final acc = Color.lerp(_from.accent, _to.accent, v)!;
          final deep = Color.lerp(_from.deep, _to.deep, v)!;
          final bg = Color.lerp(_from.background, _to.background, v)!;

          // Gentle ambient drift offsets for organic fluid breathing
          final driftX1 = sin(d) * 0.15;
          final driftY1 = cos(d) * 0.12;
          final driftX2 = cos(d) * 0.16;
          final driftY2 = sin(d) * 0.14;

          final align1 = _lerpAlign(0, v) + Alignment(driftX1, driftY1);
          final align2 = _lerpAlign(1, v) + Alignment(driftX2, driftY2);

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Deep atmospheric canvas base
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      deep,
                      bg,
                      deep.withValues(alpha: 0.95),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),

              // 2. Primary luminous Aurora bloom (Vibrant album tone)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: align1,
                      radius: 1.25,
                      colors: [
                        vib.withValues(alpha: 0.45),
                        vib.withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),

              // 3. Secondary drifting atmosphere bloom (Accent tone)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: align2,
                      radius: 1.35,
                      colors: [
                        acc.withValues(alpha: 0.40),
                        acc.withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.50, 1.0],
                    ),
                  ),
                ),
              ),

              // 4. Center ambient glow spot for rotary arc depth
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.55, 0.05),
                      radius: 0.95,
                      colors: [
                        vib.withValues(alpha: 0.22),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.75],
                    ),
                  ),
                ),
              ),

              // 5. Soundwave Equalizer visualizer (inspired by video at 02:25)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 240,
                child: CustomPaint(
                  painter: _SoundwaveBarsPainter(
                    phase: _eqAnim.value,
                    isPlaying: widget.isPlaying,
                    colorStart: acc.withValues(alpha: 0.35),
                    colorEnd: vib.withValues(alpha: 0.12),
                  ),
                ),
              ),

              // 6. Ethereal specular glass refraction light wash
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.fromRGBO(255, 255, 255, 0.14),
                        Color.fromRGBO(255, 255, 255, 0.02),
                        Color.fromRGBO(0, 0, 0, 0.18),
                      ],
                      stops: [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Visualizer painter rendering animated soundwave equalizer bars across
/// the lower background canvas (matching "Soundwave: Bars" at 02:25 in video).
class _SoundwaveBarsPainter extends CustomPainter {
  const _SoundwaveBarsPainter({
    required this.phase,
    required this.isPlaying,
    required this.colorStart,
    required this.colorEnd,
  });

  final double phase;
  final bool isPlaying;
  final Color colorStart;
  final Color colorEnd;

  static const int barCount = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / barCount;
    final maxBarHeight = size.height * 0.85;

    // One Paint + one gradient shader for all bars.
    //
    // Previously each bar built its own `Paint`, `LinearGradient` and
    // `createShader` inside the loop: 28 gradient shader allocations on every
    // frame (~1,680/second at 60fps).
    //
    // The gradient is built once across the whole canvas. `LinearGradient` from
    // `topCenter` to `bottomCenter` is purely vertical, so one shader over the
    // canvas gives every bar the same fade at its own height - and the bars
    // read as one surface with a shared light falloff rather than 28 separate
    // gradients that each restart at their own top.
    final barPaint = Paint();
    barPaint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [colorStart, colorEnd],
    ).createShader(Offset.zero & size);

    for (var i = 0; i < barCount; i++) {
      final normalizedX = i / barCount;
      // Multi-harmonic sinusoidal wave for natural audio ripple motion
      final wave1 = sin(2 * pi * (phase + normalizedX * 1.5));
      final wave2 = cos(2 * pi * (phase * 1.5 - normalizedX * 2.0));
      final rawHeight = isPlaying
          ? (0.20 + 0.80 * ((wave1 * 0.6 + wave2 * 0.4).abs()))
          : (0.12 + 0.10 * sin(pi * (phase + normalizedX)).abs());

      // Center bell-curve weighting so edges taper off elegantly
      final envelope = sin(pi * (i + 0.5) / barCount);
      final height = (rawHeight * maxBarHeight * envelope).clamp(12.0, maxBarHeight);

      final left = i * barWidth + barWidth * 0.18;
      final width = barWidth * 0.64;
      final top = size.height - height;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, height),
        Radius.circular(width / 2),
      );

      canvas.drawRRect(rect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SoundwaveBarsPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.isPlaying != isPlaying ||
      oldDelegate.colorStart != colorStart ||
      oldDelegate.colorEnd != colorEnd;
}
