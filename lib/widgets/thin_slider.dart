import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A stretch of the track worth pointing at, drawn as a thin bracket just under
/// it: the song's transition, where the next one is going to come in.
@immutable
class ThinSliderMark {
  const ThinSliderMark({
    required this.from,
    required this.to,
    required this.color,
    this.progress = 0.0,
  });

  /// Where it starts and ends along the track, 0..1.
  final double from;
  final double to;
  final Color color;

  /// How much of it has been played through, 0..1 (brightens the bracket).
  final double progress;

  @override
  bool operator ==(Object other) =>
      other is ThinSliderMark &&
      other.from == from &&
      other.to == to &&
      other.color == color &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(from, to, color, progress);
}

/// Apple Music & BitChord style capsule slider with no thumb knob.
///
/// Features:
/// - Drawn directly via CustomPainter to eliminate Flutter's default 24px slider track insets.
/// - Capsule shape (RRect with radius = height / 2).
/// - Thickens dynamically from [idleHeight] to [activeHeight] with fluid spring physics on touch/drag.
/// - Starts at x = 0 and ends at x = width so timestamps placed in a Row below it
///   are 100% pixel-perfect aligned with the track ends.
/// - Generous invisible touch target ([touchHeight]) supporting both tap-to-seek and dragging.
class ThinSlider extends StatefulWidget {
  final double value; // 0.0 to 1.0
  final ValueChanged<double> onValueChange;
  final VoidCallback? onValueChangeStart;
  final VoidCallback? onValueChangeFinished;
  final double idleHeight;
  final double activeHeight;
  final Color activeColor;
  final Color inactiveColor;
  final double touchHeight;
  final String? semanticLabel;

  /// Brackets under the track (see [ThinSliderMark]).
  final List<ThinSliderMark> marks;

  const ThinSlider({
    super.key,
    required this.value,
    required this.onValueChange,
    this.onValueChangeStart,
    this.onValueChangeFinished,
    this.idleHeight = 6.0,
    this.activeHeight = 11.0,
    this.activeColor = const Color(0xFFFFFFFF),
    this.inactiveColor = const Color(0x38FFFFFF),
    this.touchHeight = 36.0,
    this.semanticLabel,
    this.marks = const <ThinSliderMark>[],
  });

  @override
  State<ThinSlider> createState() => _ThinSliderState();
}

class _ThinSliderState extends State<ThinSlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _heightAnim;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _heightAnim = Tween<double>(
      begin: widget.idleHeight,
      end: widget.activeHeight,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
  }

  @override
  void didUpdateWidget(covariant ThinSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.idleHeight != widget.idleHeight ||
        oldWidget.activeHeight != widget.activeHeight) {
      _heightAnim = Tween<double>(
        begin: widget.idleHeight,
        end: widget.activeHeight,
      ).animate(CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ));
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _startDrag(double localX, double totalW) {
    if (!_isDragging) {
      _isDragging = true;
      _animController.forward();
      HapticFeedback.selectionClick();
      widget.onValueChangeStart?.call();
    }
    _updatePosition(localX, totalW);
  }

  void _updateDrag(double localX, double totalW) {
    if (!_isDragging) {
      _startDrag(localX, totalW);
    } else {
      _updatePosition(localX, totalW);
    }
  }

  void _endDrag() {
    if (_isDragging) {
      _isDragging = false;
      _animController.reverse();
      HapticFeedback.selectionClick();
      widget.onValueChangeFinished?.call();
    }
  }

  void _cancelDrag() {
    if (_isDragging) {
      _isDragging = false;
      _animController.reverse();
      widget.onValueChangeFinished?.call();
    }
  }

  void _updatePosition(double localX, double width) {
    if (width <= 0) return;
    final double fraction = (localX / width).clamp(0.0, 1.0);
    widget.onValueChange(fraction);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: '${(widget.value * 100).round()}%',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalW = constraints.maxWidth;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _startDrag(details.localPosition.dx, totalW),
            onTapUp: (_) => _endDrag(),
            onTapCancel: _cancelDrag,
            onHorizontalDragDown: (details) =>
                _startDrag(details.localPosition.dx, totalW),
            onHorizontalDragStart: (details) =>
                _startDrag(details.localPosition.dx, totalW),
            onHorizontalDragUpdate: (details) =>
                _updateDrag(details.localPosition.dx, totalW),
            onHorizontalDragEnd: (_) => _endDrag(),
            onHorizontalDragCancel: _cancelDrag,
            child: SizedBox(
              width: totalW,
              height: widget.touchHeight,
              child: AnimatedBuilder(
                animation: _heightAnim,
                builder: (context, child) {
                  return CustomPaint(
                    size: Size(totalW, widget.touchHeight),
                    painter: _ThinSliderPainter(
                      fraction: widget.value.clamp(0.0, 1.0),
                      trackHeight: _heightAnim.value,
                      activeColor: widget.activeColor,
                      inactiveColor: widget.inactiveColor,
                      marks: widget.marks,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ThinSliderPainter extends CustomPainter {
  final double fraction;
  final double trackHeight;
  final Color activeColor;
  final Color inactiveColor;
  final List<ThinSliderMark> marks;

  _ThinSliderPainter({
    required this.fraction,
    required this.trackHeight,
    required this.activeColor,
    required this.inactiveColor,
    required this.marks,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double centerY = size.height / 2.0;
    final double top = centerY - trackHeight / 2.0;
    final double radius = trackHeight / 2.0;

    // 1. Inactive full background capsule
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    final inactiveRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, size.width, trackHeight),
      Radius.circular(radius),
    );
    canvas.drawRRect(inactiveRRect, inactivePaint);

    // 2. Active played progress capsule
    if (fraction > 0.0) {
      final double activeWidth =
          (size.width * fraction).clamp(trackHeight, size.width);

      final activePaint = Paint()
        ..color = activeColor
        ..isAntiAlias = true
        ..style = PaintingStyle.fill;

      final activeRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, activeWidth, trackHeight),
        Radius.circular(radius),
      );
      canvas.drawRRect(activeRRect, activePaint);
    }

    // 3. Marks: a bracket a few pixels under the track.
    for (final m in marks) {
      final y = centerY + trackHeight / 2.0 + 5.0;
      final x1 = (m.from.clamp(0.0, 1.0)) * size.width;
      final x2 = (m.to.clamp(0.0, 1.0)) * size.width;
      final end = x2 < x1 + 4.0 ? x1 + 4.0 : x2;
      final base = Paint()
        ..color = m.color.withValues(alpha: 0.38)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawLine(Offset(x1, y), Offset(end, y), base);
      if (m.progress > 0.0) {
        final lit = Paint()
          ..color = m.color.withValues(alpha: 0.95)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;
        canvas.drawLine(
            Offset(x1, y), Offset(x1 + (end - x1) * m.progress.clamp(0.0, 1.0), y), lit);
      }
      // The point where the next song comes in.
      final tick = Paint()
        ..color = m.color.withValues(alpha: 0.9)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawLine(Offset(x1, y - 3.5), Offset(x1, y + 3.5), tick);
    }
  }

  @override
  bool shouldRepaint(covariant _ThinSliderPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.trackHeight != trackHeight ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        !listEquals(oldDelegate.marks, marks);
  }
}
