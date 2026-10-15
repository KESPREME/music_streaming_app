import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'seek_zone.dart';

/// Apple Music & BitChord style capsule slider with no thumb knob.
///
/// Features:
/// - Drawn directly via CustomPainter to eliminate Flutter's default 24px slider track insets.
/// - Capsule shape (RRect with radius = height / 2).
/// - Thickens dynamically from [idleHeight] to [activeHeight] with fluid spring physics on touch/drag.
/// - Starts at x = 0 and ends at x = width so timestamps placed in a Row below it
///   are 100% pixel-perfect aligned with the track ends.
/// - Generous invisible touch target ([touchHeight]) supporting both tap-to-seek and dragging.
/// - Can show the song's transition inside the bar itself ([zone], see seek_zone.dart).
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

  /// The stretch of the bar where the next song comes in, tinted and dyed into
  /// the played fill (see seek_zone.dart). Null: a plain bar.
  final SeekZoneFrame? zone;

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
    this.zone,
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
      hint: widget.zone?.zone?.label,
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
                      zone: widget.zone ?? SeekZoneFrame.none,
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
  final SeekZoneFrame zone;

  // The zone's animations repaint this painter directly: a zone sweeping in
  // or a mix running moves no widget, only pixels.
  _ThinSliderPainter({
    required this.fraction,
    required this.trackHeight,
    required this.activeColor,
    required this.inactiveColor,
    required this.zone,
  }) : super(repaint: zone.repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final double centerY = size.height / 2.0;
    final double top = centerY - trackHeight / 2.0;
    final double radius = trackHeight / 2.0;
    final track = Rect.fromLTWH(0, top, size.width, trackHeight);

    // 1. Inactive full background capsule
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    final inactiveRRect = RRect.fromRectAndRadius(track, Radius.circular(radius));
    canvas.drawRRect(inactiveRRect, inactivePaint);

    // 2. The transition's own stretch of the bar: its tint and hatching, inside
    //    the capsule, under the played fill.
    if (zone.zone != null) {
      canvas.save();
      canvas.clipRRect(inactiveRRect);
      SeekZonePaint.under(canvas, track, zone);
      canvas.restore();
    }

    // 3. Active played progress capsule - dyed across the zone as the playhead
    //    passes through it.
    if (fraction > 0.0) {
      final double activeWidth =
          (size.width * fraction).clamp(trackHeight, size.width);

      final activeRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, activeWidth, trackHeight),
        Radius.circular(radius),
      );
      canvas.drawRRect(
          activeRRect, SeekZonePaint.fillPaint(track, zone, activeColor));
    }
  }

  @override
  bool shouldRepaint(covariant _ThinSliderPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.trackHeight != trackHeight ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.zone != zone;
  }
}