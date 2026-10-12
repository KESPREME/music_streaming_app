// lib/widgets/lyric_line/lyric_gap_dots.dart
// The three dots that stand for an instrumental break, and fill across it.
//
// BitChord `PlayerLyrics.kt` (gap rows): three 13dp dots, 5dp apart, unlit at
// alpha 0.25, filling left to right over the length of the break. The row is
// full height only while the break is the active line; it swells in over 400ms
// and out over 350ms on the lyric easing, and is otherwise folded to nothing so
// a finished or not-yet-reached break leaves no hole in the verse.
//
// The clock is listened to ONLY while the break is active. A song has a few of
// these; the rest cost nothing per frame.

import 'package:flutter/widgets.dart';

import '../../services/lyrics/lyric_clock.dart';
import 'lyric_line_style.dart';

const double _dot = 13.0;
const double _dotGap = 5.0;
const double _unlit = 0.25;

/// Full height of an active break row.
const double lyricGapRowHeight = 56.0;

/// BitChord scales the dots up from this as the row swells in.
const double _collapsedScale = 0.761;

class LyricGapDots extends StatefulWidget {
  const LyricGapDots({
    super.key,
    required this.clock,
    required this.startMs,
    required this.endMs,
    required this.active,
    this.alpha = 1.0,
  });

  final LyricClock clock;

  /// The break, in song milliseconds.
  final int startMs;
  final int endMs;

  /// Whether this break is the line being sung.
  final bool active;

  /// The row's alpha from the ladder.
  final double alpha;

  @override
  State<LyricGapDots> createState() => _LyricGapDotsState();
}

class _LyricGapDotsState extends State<LyricGapDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _swell = AnimationController(
    vsync: this,
    duration: LyricLineStyle.lyricSettle,
    reverseDuration: const Duration(milliseconds: 350),
    value: widget.active ? 1.0 : 0.0,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) widget.clock.retainFrames(this);
  }

  @override
  void didUpdateWidget(covariant LyricGapDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.clock, widget.clock)) {
      oldWidget.clock.releaseFrames(this);
    }
    if (widget.active) {
      widget.clock.retainFrames(this);
    } else {
      widget.clock.releaseFrames(this);
    }
    if (oldWidget.active == widget.active) return;
    if (widget.active) {
      _swell.forward();
    } else {
      _swell.reverse();
    }
  }

  @override
  void dispose() {
    // The dots fill across the break, so while it is the active line they need
    // every frame; they hold the clock's ticker for exactly that long.
    widget.clock.releaseFrames(this);
    _swell.dispose();
    super.dispose();
  }

  /// 0..1 across the break at [nowMs].
  double _progress(int nowMs) {
    final span = widget.endMs - widget.startMs;
    if (span <= 0) return nowMs >= widget.startMs ? 1.0 : 0.0;
    return ((nowMs - widget.startMs) / span).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _swell,
      builder: (context, _) {
        final swell = LyricLineStyle.lyricEase.transform(_swell.value);
        if (swell <= 0.001) return const SizedBox(height: 0, width: double.infinity);

        final dots = widget.active
            ? ListenableBuilder(
                listenable: widget.clock,
                builder: (context, _) => _row(_progress(widget.clock.positionMs)),
              )
            // A break that is not the active line is either behind the song
            // (fully lit, on its way out) or ahead of it (unlit).
            : _row(widget.clock.positionMs >= widget.endMs ? 1.0 : 0.0);

        return SizedBox(
          height: lyricGapRowHeight * swell,
          width: double.infinity,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minHeight: 0,
              maxHeight: lyricGapRowHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Transform.scale(
                  alignment: Alignment.centerLeft,
                  scale: _collapsedScale + (1 - _collapsedScale) * swell,
                  child: dots,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _row(double progress) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: _dotGap),
          _Dot(lit: (progress * 3 - i).clamp(0.0, 1.0).toDouble(), alpha: widget.alpha),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.lit, required this.alpha});

  final double lit;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    final a = (_unlit + (1.0 - _unlit) * lit) * alpha;
    return Container(
      width: _dot,
      height: _dot,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.fromRGBO(255, 255, 255, a.clamp(0.0, 1.0)),
      ),
    );
  }
}
