import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/music_provider.dart';
import '../theme/glass_tokens.dart';
import '../utils/format.dart';

/// Visual style for [WavyProgressBar]. The two former copies
/// (glass + Material You) differed only in these values.
class WavyBarStyle {
  final TextStyle Function(BuildContext, Color)? labelStyleBuilder;
  final Color inactiveColor;
  final double glowRadius;
  final double glowAlpha;

  const WavyBarStyle({
    this.labelStyleBuilder,
    this.inactiveColor = const Color(0x33FFFFFF),
    this.glowRadius = 16.0,
    this.glowAlpha = GlassTokens.playerProgressGlowAlpha,
  });

  /// Glassmorphism look (default): plusJakartaSans white labels.
  static TextStyle glassLabel(BuildContext context, Color color) =>
      GoogleFonts.plusJakartaSans(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      );

  /// Material You look - theme-aware labels, softer glow.
  static WavyBarStyle materialYou(BuildContext context) => WavyBarStyle(
        labelStyleBuilder: (ctx, color) => GoogleFonts.plusJakartaSans(
          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        inactiveColor: Colors.grey.withValues(alpha: 0.3),
        glowRadius: 14.0,
        glowAlpha: 0.3,
      );
}

String _formatUnpadded(Duration d) {
  final raw = formatDuration(d);
  if (raw.length >= 2 && raw[0] == '0' && raw[1] != ':') {
    return raw.substring(1);
  }
  return raw;
}

class WavyProgressBar extends StatefulWidget {
  final MusicProvider provider;
  final Color accentColor;
  final WavyBarStyle style;

  const WavyProgressBar({
    required this.provider,
    required this.accentColor,
    this.style = const WavyBarStyle(),
    super.key,
  });

  @override
  State<WavyProgressBar> createState() => _WavyProgressBarState();
}

class _WavyProgressBarState extends State<WavyProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    // Continuous animation for the wave phase
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = widget.style.labelStyleBuilder
            ?.call(context, Colors.white) ??
        WavyBarStyle.glassLabel(context, Colors.white.withValues(alpha: 0.5));

    return StreamBuilder<Duration>(
      stream: widget.provider.positionStream,
      builder: (context, snapshot) {
        final duration = widget.provider.duration;
        final position = _isDragging
            ? Duration(seconds: _dragValue.toInt())
            : (snapshot.data ?? Duration.zero);
        final maxSeconds =
            duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
        final currentSeconds =
            position.inSeconds.toDouble().clamp(0.0, maxSeconds);
        final progress = currentSeconds / maxSeconds;
        final animationsEnabled = !MediaQuery.of(context).disableAnimations &&
            widget.provider.isPlaying;
        final double phase =
            animationsEnabled ? _controller.value * 2 * math.pi : 0.0;

        return Column(
          children: [
            SizedBox(
              height: 40,
              child: GestureDetector(
                onHorizontalDragStart: (details) {
                  setState(() {
                    _isDragging = true;
                    _dragValue = currentSeconds;
                  });
                },
                onHorizontalDragUpdate: (details) {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final width = box.size.width;
                  final dx = details.localPosition.dx.clamp(0.0, width);
                  final newProgress = dx / width;
                  setState(() {
                    _dragValue = newProgress * maxSeconds;
                  });
                },
                onHorizontalDragEnd: (details) {
                  widget.provider.seekTo(Duration(seconds: _dragValue.toInt()));
                  setState(() {
                    _isDragging = false;
                  });
                },
                onTapDown: (details) {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final width = box.size.width;
                  final dx = details.localPosition.dx.clamp(0.0, width);
                  final newProgress = dx / width;
                  widget.provider.seekTo(
                      Duration(seconds: (newProgress * maxSeconds).toInt()));
                },
                child: TickerMode(
                  enabled: animationsEnabled,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: WavySliderPainter(
                          progress: progress,
                          color: widget.accentColor,
                          phase: phase,
                          inactiveColor: widget.style.inactiveColor,
                          glowRadius: widget.style.glowRadius,
                          glowAlpha: widget.style.glowAlpha,
                        ),
                        size: Size.infinite,
                      );
                    },
                  ),
                ),
              ),
            ),
            // Time Labels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatUnpadded(position), style: labelStyle),
                  Text(_formatUnpadded(duration), style: labelStyle),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class WavySliderPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double phase;
  final Color inactiveColor;
  final double glowRadius;
  final double glowAlpha;

  WavySliderPainter({
    required this.progress,
    required this.color,
    required this.phase,
    required this.inactiveColor,
    required this.glowRadius,
    required this.glowAlpha,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final centerY = size.height / 2;

    // Config
    const double waveAmplitude = 4.0;
    const double waveFrequency = 0.05;
    // Sample the wave every 2px instead of every 1px. At waveFrequency 0.05 a
    // 2px step is 0.1 rad (~63px per wavelength), which is visually identical
    // at this amplitude but halves the per-frame path point count.
    const double step = 2.0;

    // Draw Inactive Line (Straight)
    final activeWidth = size.width * progress;

    paint.color = inactiveColor;
    final inactivePath = Path();
    inactivePath.moveTo(activeWidth, centerY);
    inactivePath.lineTo(size.width, centerY);
    canvas.drawPath(inactivePath, paint);

    // active Path (Wavy Line)
    final activePath = Path();
    paint.color = color;

    // Calculate initial Y to avoid "hook"
    double startY =
        centerY + math.sin((0 * waveFrequency) + phase) * waveAmplitude;
    activePath.moveTo(0, startY);

    // Draw waves only up to the active width
    for (double x = 0.0; x < activeWidth; x += step) {
      final y = centerY + math.sin((x * waveFrequency) + phase) * waveAmplitude;
      activePath.lineTo(x, y);
    }

    // Land the path exactly on the active edge so the stroked line and the
    // thumb are not short of `activeWidth` by up to one step.
    final endX = activeWidth;
    final endY =
        centerY + math.sin((endX * waveFrequency) + phase) * waveAmplitude;
    activePath.lineTo(endX, endY);
    canvas.drawPath(activePath, paint);

    // Draw Thumb at the tip of the wave
    final thumbPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(endX, endY), 8.0, thumbPaint);

    // Thumb Glow — skip when invisible to avoid overdraw.
    if (glowAlpha > 0.0) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: glowAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(endX, endY), glowRadius, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant WavySliderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.color != color ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.glowRadius != glowRadius ||
        oldDelegate.glowAlpha != glowAlpha;
  }
}
