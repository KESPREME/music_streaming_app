// lib/widgets/update/update_hero.dart
//
// The picture at the top of Software Update: the app mark inside a ring that
// says what is happening without a word.
//
//   checking / verifying / installing   an arc circles the mark
//   downloading                         the ring fills with the real progress
//   available                           the mark breathes; a dot waits on it
//   ready                               a full ring and a check
//   up to date                          a quiet green check
//   failed                              an amber ring and a mark of warning
//
// Reduce Motion: nothing loops or breathes; the ring still shows progress.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/update/update_models.dart';
import 'update_copy.dart';

class UpdateHero extends StatefulWidget {
  const UpdateHero({
    super.key,
    required this.status,
    required this.progress,
    required this.tone,
    this.size = 168,
    this.accent,
  });

  final UpdateStatus status;
  final double progress;
  final UpdateTone tone;
  final double size;
  final Color? accent;

  @override
  State<UpdateHero> createState() => _UpdateHeroState();
}

class _UpdateHeroState extends State<UpdateHero> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  double _shownProgress = 0;
  double _fromProgress = 0;

  bool get _indeterminate =>
      widget.status == UpdateStatus.checking ||
      widget.status == UpdateStatus.verifying ||
      widget.status == UpdateStatus.installing;

  @override
  void initState() {
    super.initState();
    _shownProgress = widget.progress;
    _fromProgress = widget.progress;
    _settle.addListener(() {
      final t = Curves.easeOutCubic.transform(_settle.value);
      setState(() => _shownProgress =
          _fromProgress + (widget.progress - _fromProgress) * t);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Needs MediaQuery (Reduce Motion), which initState may not read.
    _sync();
  }

  @override
  void didUpdateWidget(UpdateHero old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress || old.status != widget.status) {
      _fromProgress = _shownProgress;
      _settle
        ..reset()
        ..forward();
    }
    if (old.status != widget.status) _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_indeterminate && !reduce) {
      _spin.repeat();
    } else {
      _spin.stop();
    }
    if (widget.status == UpdateStatus.available && !reduce) {
      _breathe.repeat(reverse: true);
    } else {
      _breathe
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _breathe.dispose();
    _settle.dispose();
    super.dispose();
  }

  Color _ringColor(Color accent) => switch (widget.tone) {
        UpdateTone.good => const Color(0xFF63D68D),
        UpdateTone.bad => const Color(0xFFFFB347),
        _ => accent,
      };

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? Theme.of(context).colorScheme.primary;
    final color = _ringColor(accent);
    final s = widget.size;
    final iconSize = s * 0.56;

    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _breathe]),
        builder: (context, _) {
          final breathe = Curves.easeInOut.transform(_breathe.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              // A soft halo that follows the state's colour.
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: s * 0.86 + 10 * breathe,
                height: s * 0.86 + 10 * breathe,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.2 + 0.08 * breathe),
                      blurRadius: 42,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              CustomPaint(
                size: Size.square(s),
                painter: _RingPainter(
                  color: color,
                  progress: _shownProgress,
                  status: widget.status,
                  spin: _spin.value,
                ),
              ),
              Transform.scale(
                scale: 1 + 0.025 * breathe,
                child: Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(iconSize * 0.24),
                    color: const Color(0xFF0C0C0E),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    image: const DecorationImage(
                      image: AssetImage('assets/images/mine_music_mark.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: s * 0.14,
                bottom: s * 0.14,
                child: _Badge(status: widget.status, color: color),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.status, required this.color});

  final UpdateStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final IconData? icon = switch (status) {
      UpdateStatus.upToDate => Icons.check_rounded,
      UpdateStatus.ready => Icons.check_rounded,
      UpdateStatus.available => Icons.arrow_downward_rounded,
      UpdateStatus.failed => Icons.priority_high_rounded,
      UpdateStatus.needsPermission => Icons.lock_open_rounded,
      _ => null,
    };
    return AnimatedScale(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      scale: icon == null ? 0 : 1,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.black, width: 3),
        ),
        child: Icon(icon ?? Icons.check_rounded, size: 20, color: Colors.black),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.color,
    required this.progress,
    required this.status,
    required this.spin,
  });

  final Color color;
  final double progress;
  final UpdateStatus status;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = color;

    switch (status) {
      case UpdateStatus.checking:
      case UpdateStatus.verifying:
      case UpdateStatus.installing:
        final start = spin * 2 * math.pi - math.pi / 2;
        // The arc breathes in length as it goes round.
        final sweep = math.pi * (0.45 + 0.25 * math.sin(spin * 2 * math.pi));
        canvas.drawArc(rect, start, sweep, false, stroke);
      case UpdateStatus.downloading:
        final p = progress.clamp(0.0, 1.0);
        if (p > 0) {
          canvas.drawArc(
            rect,
            -math.pi / 2,
            2 * math.pi * p,
            false,
            stroke
              ..shader = SweepGradient(
                startAngle: -math.pi / 2,
                endAngle: -math.pi / 2 + 2 * math.pi * p.clamp(0.02, 1.0),
                colors: [color.withValues(alpha: 0.55), color],
              ).createShader(rect),
          );
        }
      case UpdateStatus.ready:
      case UpdateStatus.upToDate:
      case UpdateStatus.failed:
      case UpdateStatus.needsPermission:
        canvas.drawCircle(c, r, stroke..color = color.withValues(alpha: 0.9));
      case UpdateStatus.available:
        canvas.drawCircle(c, r, stroke..color = color.withValues(alpha: 0.45));
      case UpdateStatus.idle:
        break;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color ||
      old.progress != progress ||
      old.status != status ||
      old.spin != spin;
}
