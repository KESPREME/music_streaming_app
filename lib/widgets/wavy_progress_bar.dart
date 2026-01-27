import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/music_provider.dart';

class WavyProgressBar extends StatefulWidget {
  final MusicProvider provider;
  final Color accentColor;

  const WavyProgressBar({required this.provider, required this.accentColor, super.key});

  @override
  State<WavyProgressBar> createState() => _WavyProgressBarState();
}

class _WavyProgressBarState extends State<WavyProgressBar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    // Continuous animation for the wave phase
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.provider.positionStream,
      builder: (context, snapshot) {
        final duration = widget.provider.duration;
        final position = _isDragging ? Duration(seconds: _dragValue.toInt()) : (snapshot.data ?? Duration.zero);
        final maxSeconds = duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
        final currentSeconds = position.inSeconds.toDouble().clamp(0.0, maxSeconds);
        final progress = currentSeconds / maxSeconds;

        return Column(
          children: [
             SizedBox(
              height: 40,
              child: GestureDetector(
                onHorizontalDragStart: (details) {
                  setState(() { _isDragging = true; _dragValue = currentSeconds; });
                },
                onHorizontalDragUpdate: (details) {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final width = box.size.width;
                  final dx = details.localPosition.dx.clamp(0.0, width);
                  final newProgress = dx / width;
                  setState(() { _dragValue = newProgress * maxSeconds; });
                },
                onHorizontalDragEnd: (details) {
                  widget.provider.seekTo(Duration(seconds: _dragValue.toInt()));
                  setState(() { _isDragging = false; });
                },
                onTapDown: (details) {
                   final RenderBox box = context.findRenderObject() as RenderBox;
                   final width = box.size.width;
                   final dx = details.localPosition.dx.clamp(0.0, width);
                   final newProgress = dx / width;
                   widget.provider.seekTo(Duration(seconds: (newProgress * maxSeconds).toInt()));
                },
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: WavySliderPainter(
                        progress: progress,
                        color: widget.accentColor,
                        phase: widget.provider.isPlaying ? _controller.value * 2 * math.pi : 0, 
                      ),
                      size: Size.infinite,
                    );
                  },
                ),
              ),
            ),
             // Time Labels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(position),
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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

  WavySliderPainter({required this.progress, required this.color, required this.phase});

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

    // Draw Inactive Line (Straight & Gray)
    final activeWidth = size.width * progress;
    
    // Inactive Path (Straight Line)
    paint.color = Colors.white.withOpacity(0.2);
    final inactivePath = Path();
    inactivePath.moveTo(activeWidth, centerY);
    inactivePath.lineTo(size.width, centerY);
    canvas.drawPath(inactivePath, paint);

    // active Path (Wavy Line)
    final activePath = Path();
    paint.color = color;
    
    // Calculate initial Y to avoid "hook"
    double startY = centerY + math.sin((0 * waveFrequency) + phase) * waveAmplitude;
    activePath.moveTo(0, startY);
    
    double lastX = 0;
    double lastY = startY;

    // Draw waves only up to the active width
    for (double x = 0; x <= activeWidth; x++) {
      final y = centerY + math.sin((x * waveFrequency) + phase) * waveAmplitude;
      activePath.lineTo(x, y);
      lastX = x;
      lastY = y;
    }
    canvas.drawPath(activePath, paint);

    // Draw Thumb at the tip of the wave
    final thumbPaint = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastX, lastY), 8.0, thumbPaint);
    
    // Thumb Glow
    final glowPaint = Paint()..color = color.withOpacity(0.4)..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastX, lastY), 16.0, glowPaint);
  }

  @override
  bool shouldRepaint(covariant WavySliderPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.phase != phase || oldDelegate.color != color;
  }
}
