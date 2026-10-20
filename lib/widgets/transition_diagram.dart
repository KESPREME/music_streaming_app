import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_font.dart';

import '../services/transition/fade_curves.dart';
import '../services/transition/transition_settings.dart';

/// A live picture of what the settings below it do: two songs as lanes of
/// bars, the leaving one fading as the arriving one rises, over exactly the
/// curves the player uses. The overlap WIDENS and NARROWS as the slider moves.
///
/// A looping playhead sweeps across so the fade is seen happening, not just
/// drawn. The loop runs only while the card is on screen and transitions are on
/// (a static frame otherwise): the screen costs nothing at rest.
class TransitionDiagram extends StatefulWidget {
  const TransitionDiagram({
    super.key,
    required this.seconds,
    required this.style,
    required this.enabled,
    this.height = 132,
  });

  final int seconds;
  final TransitionStyle style;
  final bool enabled;
  final double height;

  @override
  State<TransitionDiagram> createState() => _TransitionDiagramState();
}

class _TransitionDiagramState extends State<TransitionDiagram>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _sweep.repeat();
  }

  @override
  void didUpdateWidget(covariant TransitionDiagram old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!widget.enabled && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce && _sweep.isAnimating) _sweep.stop();
    return Semantics(
      label: widget.enabled
          ? 'Preview: a ${widget.seconds} second ${widget.style == TransitionStyle.automix ? 'AutoMix' : 'crossfade'} between two songs'
          : 'Preview: song transitions are off',
      child: RepaintBoundary(
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _DiagramPainter(
                    sweep: _sweep,
                    seconds: widget.seconds,
                    automix: widget.style == TransitionStyle.automix,
                    enabled: widget.enabled,
                    accent: accent,
                  ),
                ),
              ),
              Positioned(
                left: 14,
                top: 10,
                child: _Label(widget.enabled ? 'SONG A' : 'SONG A  →  SONG B'),
              ),
              if (widget.enabled)
                const Positioned(
                  right: 14,
                  bottom: 10,
                  child: _Label('SONG B'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppFont.style(
          color: Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      );
}

class _DiagramPainter extends CustomPainter {
  _DiagramPainter({
    required this.sweep,
    required this.seconds,
    required this.automix,
    required this.enabled,
    required this.accent,
  }) : super(repaint: sweep);

  final Animation<double> sweep;
  final int seconds;
  final bool automix;
  final bool enabled;
  final Color accent;

  /// The picture spans this many seconds, so a 12 s fade fills 60% of it.
  static const double spanSeconds = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final padX = 14.0;
    final left = padX;
    final width = size.width - padX * 2;
    final laneH = (size.height - 52) / 2;
    final topLane = Rect.fromLTWH(left, 28, width, laneH);
    final bottomLane = Rect.fromLTWH(left, 28 + laneH + 10, width, laneH);

    final pxPerSec = width / spanSeconds;
    final mid = width / 2;
    final overlap = seconds * pxPerSec;
    final overlapStart = mid - overlap / 2;
    final overlapEnd = mid + overlap / 2;
    final head = sweep.value * width;

    const barW = 3.0;
    const gap = 2.5;
    final count = (width / (barW + gap)).floor();

    final bar = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final x = i * (barW + gap);
      final h = _height(i);

      // Song A: the first lane, falling across the overlap.
      var aGain = 1.0;
      if (x > overlapEnd) {
        aGain = 0.0;
      } else if (x >= overlapStart) {
        aGain = fallGain((x - overlapStart) / (overlapEnd - overlapStart));
      }
      // Song B: the second lane, rising across it.
      var bGain = 0.0;
      if (x >= overlapEnd) {
        bGain = 1.0;
      } else if (x >= overlapStart) {
        bGain = riseGain((x - overlapStart) / (overlapEnd - overlapStart));
      }

      final lit = enabled && (x - head).abs() < 22 ? 1.0 : 0.0;
      if (aGain > 0.01) {
        bar.color = Color.lerp(Colors.white, accent, lit)!
            .withValues(alpha: (enabled ? 0.18 + 0.5 * aGain : 0.3) * (0.7 + 0.3 * (1 - lit) + 0.3 * lit));
        _bar(canvas, bar, topLane, x, h * (0.35 + 0.65 * aGain));
      }
      if (enabled && bGain > 0.01) {
        bar.color = Color.lerp(Colors.white, accent, lit)!
            .withValues(alpha: (0.18 + 0.5 * bGain));
        _bar(canvas, bar, bottomLane, x, h * (0.35 + 0.65 * bGain));
      } else if (!enabled && x > mid) {
        bar.color = Colors.white.withValues(alpha: 0.18);
        _bar(canvas, bar, bottomLane, x, h);
      }
    }

    if (!enabled) return;

    // The overlap, held in an accent veil.
    final veil = Rect.fromLTRB(
        left + overlapStart, 22, left + overlapEnd, size.height - 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(veil, const Radius.circular(10)),
      Paint()..color = accent.withValues(alpha: 0.10),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(veil, const Radius.circular(10)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.35),
    );

    // The two gain laws, drawn over the veil.
    final curveArea = Rect.fromLTRB(veil.left + 4, veil.top + 6, veil.right - 4, veil.bottom - 6);
    final fall = Path();
    final rise = Path();
    const steps = 32;
    for (var i = 0; i <= steps; i++) {
      final p = i / steps;
      final x = curveArea.left + curveArea.width * p;
      final yf = curveArea.bottom - curveArea.height * fallGain(p);
      final yr = curveArea.bottom - curveArea.height * riseGain(p);
      if (i == 0) {
        fall.moveTo(x, yf);
        rise.moveTo(x, yr);
      } else {
        fall.lineTo(x, yf);
        rise.lineTo(x, yr);
      }
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(fall, line..color = Colors.white.withValues(alpha: 0.55));
    canvas.drawPath(rise, line..color = accent.withValues(alpha: 0.95));

    // AutoMix: the bar lines both songs are joined on.
    if (automix) {
      final tick = Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.22);
      final bars = math.max(2, (seconds / 2).round());
      for (var i = 0; i <= bars; i++) {
        final x = veil.left + veil.width * (i / bars);
        canvas.drawLine(Offset(x, veil.top + 2), Offset(x, veil.bottom - 2), tick);
      }
    }

    // The playhead.
    final x = left + head;
    canvas.drawLine(
      Offset(x, 20),
      Offset(x, size.height - 14),
      Paint()
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.65),
    );
  }

  void _bar(Canvas canvas, Paint paint, Rect lane, double x, double h) {
    final cx = lane.left + x + 1.5;
    paint.strokeWidth = 3.0;
    canvas.drawLine(
      Offset(cx, lane.center.dy - h * lane.height / 2),
      Offset(cx, lane.center.dy + h * lane.height / 2),
      paint,
    );
  }

  /// A fixed, music-shaped bar height for bar [i] (not random per frame).
  double _height(int i) {
    final a = math.sin(i * 0.43) * 0.5 + math.sin(i * 0.17 + 1.3) * 0.5;
    return (0.35 + 0.65 * ((a + 1) / 2)).clamp(0.2, 1.0);
  }

  @override
  bool shouldRepaint(_DiagramPainter old) =>
      old.seconds != seconds ||
      old.automix != automix ||
      old.enabled != enabled ||
      old.accent != accent;
}
