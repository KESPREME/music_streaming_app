// lib/widgets/lyric_line/animated_lyric_row.dart
// ONE tween for every dimension of a lyric row.
//
// Blur, alpha, scale and "lit" all move together on
// [LyricLineStyle.lyricEase] over [LyricLineStyle.lyricSettle], so a row that
// recedes dims, blurs and settles as one movement. BitChord runs separate
// `animateXAsState` calls with the identical spec for exactly this reason
// (`PlayerLyrics.kt:1849-2001`).
//
// A handover that arrives mid-settle CONTINUES from what is on screen rather
// than from where the previous target was, so the row never jumps.
//
// THE VALUES ARE HANDED DOWN, NOT APPLIED HERE
//
// This widget used to wrap its child in `DefaultTextStyle` (for alpha) and
// `ImageFiltered` (for blur): two inherited-notify walks and a saveLayer per row.
// The values now go into the [LyricLine] render object, which folds alpha and
// blur into the ONE layer it needs anyway. Only the scale is applied here, and a
// scale is a transform, not a layer.

import 'package:flutter/widgets.dart';

import 'lyric_line_style.dart';

/// What a row should draw with at this instant of its settle.
@immutable
class LyricRowValues {
  const LyricRowValues({
    required this.alpha,
    required this.blurSigma,
    required this.lit,
  });

  /// The row's alpha.
  final double alpha;

  /// Gaussian sigma in logical px.
  final double blurSigma;

  /// 0..1: how lit a line-synced line is.
  final double lit;
}

typedef LyricRowBuilder = Widget Function(
  BuildContext context,
  LyricRowValues values,
);

class AnimatedLyricRow extends StatefulWidget {
  const AnimatedLyricRow({
    super.key,
    required this.alpha,
    required this.blurDp,
    required this.scale,
    required this.lit,
    required this.builder,
    this.duration = LyricLineStyle.lyricSettle,
  });

  /// Targets.
  final double alpha;

  /// The ladder radius in dp. Converted to a sigma per frame, so the TWEEN runs
  /// in the space the ladder is defined in.
  final double blurDp;
  final double scale;
  final double lit;

  final LyricRowBuilder builder;
  final Duration duration;

  @override
  State<AnimatedLyricRow> createState() => _AnimatedLyricRowState();
}

class _AnimatedLyricRowState extends State<AnimatedLyricRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1.0,
  );

  late double _fromAlpha = widget.alpha;
  late double _fromBlur = widget.blurDp;
  late double _fromScale = widget.scale;
  late double _fromLit = widget.lit;

  @override
  void didUpdateWidget(covariant AnimatedLyricRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.alpha == widget.alpha &&
        oldWidget.blurDp == widget.blurDp &&
        oldWidget.scale == widget.scale &&
        oldWidget.lit == widget.lit) {
      return;
    }
    // Continue from what is on screen, not from where the old target was: a
    // handover arriving 120ms into a 400ms settle must not jump.
    final t = LyricLineStyle.lyricEase.transform(_controller.value);
    _fromAlpha = _lerp(_fromAlpha, oldWidget.alpha, t);
    _fromBlur = _lerp(_fromBlur, oldWidget.blurDp, t);
    _fromScale = _lerp(_fromScale, oldWidget.scale, t);
    _fromLit = _lerp(_fromLit, oldWidget.lit, t);
    _controller.forward(from: 0);
  }

  static double _lerp(double from, double to, double t) =>
      t >= 1.0 ? to : from + (to - from) * t;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = LyricLineStyle.lyricEase.transform(_controller.value);
        final alpha = _lerp(_fromAlpha, widget.alpha, t);
        final blurDp = _lerp(_fromBlur, widget.blurDp, t);
        final scale = _lerp(_fromScale, widget.scale, t);
        final lit = _lerp(_fromLit, widget.lit, t);

        final child = widget.builder(
          context,
          LyricRowValues(
            alpha: alpha,
            blurSigma: LyricLineStyle.sigmaFor(blurDp, dpr),
            lit: lit,
          ),
        );
        if ((scale - 1.0).abs() < 0.0005) return child;

        // Anchored to the row's own left edge, matching the reference's
        // `TransformOrigin(0, 0.5)`. Scaling about the centre of a full-width
        // row walks the words sideways as they recede.
        return Transform.scale(
          alignment: Alignment.centerLeft,
          scale: scale,
          child: child,
        );
      },
    );
  }
}
