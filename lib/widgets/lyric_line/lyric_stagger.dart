// lib/widgets/lyric_line/lyric_stagger.dart
// The fan-out: as the panel moves to a new line, the rows below it set off a
// beat after it instead of travelling as one block.
//
// A block of text sliding rigidly is a list being scrolled; the same lines
// arriving one behind another is the panel handing over. BitChord does it with a
// per-row `translationY` held back against the list's own movement
// (`PlayerLyrics.kt:359-366, 1801-1868`):
//
//     shift(k, t) = delta * (E(t / d) - E((t - 0.06 * k * d) / d))
//
// `delta` is how far the list is travelling, `d` how long it takes, `E` the same
// ease the scroll uses and `k` how many rows below the focus row this one is.
// The list has already taken a row part of the way; giving back what it has not
// earned yet is what leaves it trailing. ONE curve for both, so a row with no
// delay (the focus row, and every row above it) sits exactly still against the
// list - only the rows that fan out move at all.
//
// WHAT THIS IS NOT
//
//   * Not layout. A row's slot never changes; the shift is applied when the row
//     is PAINTED, so a handover costs a repaint of the few rows fanning out, and
//     no frame re-lays-out the list. (A `Padding` or a `SizedBox` here would
//     re-layout every row below it, sixty times a second.)
//   * Not alpha. Nothing here is an `Opacity`; a lyric row is already one layer.
//   * Not a second scroll. The list scrolls exactly as it did; this only draws
//     the rows a little behind where it has put them.
//
// CLAMPED, NOT SKIPPED
//
// The delay saturates at three steps: row 3 and every row below it share it.
// The plan text said rows past the third are "untouched", and that is the
// obvious reading of "k <= 3" - but it makes row 3 lag by up to 0.18 of the
// travel while row 4 does not move at all, and the two overlap for the middle of
// the run. Held at the same delay they travel together and the stagger can only
// ever pull rows APART (the delay is non-decreasing in k, so the gap between
// neighbours is never smaller than the layout's own). The reference clamps for
// the same reason.

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'lyric_line_style.dart';

/// How many rows fan out before the delay stops growing.
const int lyricStaggerSteps = 3;

/// Each step's delay, as a fraction of the scroll's duration.
///
/// Deliberately under half of what the renderer this came from uses: its lines
/// carry the whole scroll themselves, so a long delay only means arriving late;
/// here the list has already moved underneath them, and the same delay reads as
/// the rows being dragged rather than following.
const double lyricStaggerFraction = 0.06;

/// How far a row [rowsBehind] the focus row is held back, in logical px, [elapsedMs]
/// into a scroll of [delta] px that takes [durationMs].
///
/// Pure, so the arithmetic is pinned without a layout pass. Positive means
/// "lower than the list put it" for a forward scroll ([delta] > 0) and "higher"
/// for a backward one - either way, behind the list.
///
/// Exactly 0.0 for a row with no delay, before the scroll starts, and once the
/// last row has arrived (see [LyricScrollRun.spanMs]). That last one is checked
/// rather than left to the curve: `E(1) - E(1)` is 0, but `E(0.9999999)` is not,
/// and a row that ends a millionth of a pixel off is a row that drifts.
double lyricStaggerShift({
  required double delta,
  required int rowsBehind,
  required double elapsedMs,
  required double durationMs,
  Curve ease = LyricLineStyle.lyricEase,
}) {
  if (rowsBehind <= 0 || delta == 0 || durationMs <= 0) return 0.0;
  final spanMs = durationMs * (1 + lyricStaggerFraction * lyricStaggerSteps);
  if (elapsedMs >= spanMs) return 0.0;
  final steps = rowsBehind < lyricStaggerSteps ? rowsBehind : lyricStaggerSteps;
  final delayMs = steps * lyricStaggerFraction * durationMs;
  final lead = ease.transform(clampDouble(elapsedMs / durationMs, 0.0, 1.0));
  final lag = ease.transform(
    clampDouble((elapsedMs - delayMs) / durationMs, 0.0, 1.0),
  );
  return delta * (lead - lag);
}

/// One handover: which row the list is travelling to, how far, and how long.
@immutable
class LyricScrollRun {
  const LyricScrollRun({
    required this.focusIndex,
    required this.delta,
    required this.durationMs,
  });

  /// The row the list is scrolling to. Rows after it (before it, for a backward
  /// run) fan out.
  final int focusIndex;

  /// Signed travel in logical px: positive scrolls forward through the song.
  final double delta;

  /// The scroll's duration.
  final int durationMs;

  /// The last row to arrive does so this long after the list sets off.
  int get spanMs =>
      (durationMs * (1 + lyricStaggerFraction * lyricStaggerSteps)).round();

  /// How far behind the focus row [index] is, in the direction of travel. Zero
  /// or less means the row travels with the list.
  int rowsBehind(int index) =>
      delta >= 0 ? index - focusIndex : focusIndex - index;
}

/// The clock and the run that the rows read their shift from.
///
/// ONE controller for the whole list, not one animation per row: sixty rows each
/// with their own animation is sixty tickers to start and stop on every
/// handover. The rows are listeners; the ones with nothing to catch up on never
/// repaint.
class LyricStagger extends ChangeNotifier {
  LyricStagger({required TickerProvider vsync})
      : _controller = AnimationController(vsync: vsync) {
    _controller
      ..addListener(notifyListeners)
      ..addStatusListener(_onStatus);
  }

  final AnimationController _controller;
  LyricScrollRun? _run;

  /// The handover in flight, or null.
  LyricScrollRun? get run => _run;

  bool get isRunning => _run != null;

  /// How far into the run's [LyricScrollRun.spanMs] the clock is.
  double get elapsedMs {
    final run = _run;
    return run == null ? 0.0 : _controller.value * run.spanMs;
  }

  /// Starts [run]. A run already in flight is replaced, not queued: the next
  /// line has arrived and the rows are following THAT.
  ///
  /// Call it on the same frame as the scroll it describes. Both tickers take
  /// their start time from their first tick, so two animations begun in one
  /// synchronous call share a time base - which is the whole of keeping the rows
  /// and the list on one curve.
  void start(LyricScrollRun run) {
    _run = run;
    _controller
      ..duration = Duration(milliseconds: run.spanMs)
      ..forward(from: 0.0);
  }

  /// Ends the run and puts every row back where the list has it, now.
  ///
  /// For the moments the list stops being driven by us: a finger takes it, it is
  /// jumped, the lyric is replaced, the panel is hidden. The alternative - letting
  /// the clock run on - would keep pulling rows around under the reader's finger
  /// for a few hundred milliseconds.
  void cancel() {
    if (_run == null) return;
    _run = null;
    _controller.stop();
    notifyListeners();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // The last tick has painted the settled frame; drop the run so a row reads
    // a flat zero rather than evaluating the curve at its end.
    _run = null;
    notifyListeners();
  }

  /// How far row [index] is held back right now.
  double shiftFor(int index) {
    final run = _run;
    if (run == null) return 0.0;
    return lyricStaggerShift(
      delta: run.delta,
      rowsBehind: run.rowsBehind(index),
      elapsedMs: elapsedMs,
      durationMs: run.durationMs.toDouble(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Paints [child] [LyricStagger.shiftFor] px off the slot it was laid out in.
///
/// The child is its own repaint boundary, so a shift is a layer OFFSET: the row's
/// text is not re-recorded for any frame of the handover, and the rows that have
/// nothing to catch up on are not touched at all.
class LyricStaggerShift extends StatelessWidget {
  const LyricStaggerShift({
    super.key,
    required this.stagger,
    required this.index,
    required this.child,
  });

  final LyricStagger stagger;

  /// The row's index in the lyric, which is what its delay is derived from.
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => _StaggerShift(
        stagger: stagger,
        index: index,
        child: RepaintBoundary(child: child),
      );
}

class _StaggerShift extends SingleChildRenderObjectWidget {
  const _StaggerShift({
    required this.stagger,
    required this.index,
    required super.child,
  });

  final LyricStagger stagger;
  final int index;

  @override
  RenderLyricStaggerShift createRenderObject(BuildContext context) =>
      RenderLyricStaggerShift(stagger: stagger, index: index);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLyricStaggerShift renderObject,
  ) {
    renderObject
      ..stagger = stagger
      ..index = index;
  }
}

class RenderLyricStaggerShift extends RenderProxyBox {
  RenderLyricStaggerShift({required LyricStagger stagger, required int index})
      : _stagger = stagger,
        _index = index;

  LyricStagger _stagger;
  int _index;

  /// What the last paint drew, so a tick that moves nothing costs nothing.
  double _paintedShift = 0.0;

  set stagger(LyricStagger value) {
    if (identical(_stagger, value)) return;
    if (attached) _stagger.removeListener(_onStagger);
    _stagger = value;
    if (attached) _stagger.addListener(_onStagger);
    markNeedsPaint();
  }

  set index(int value) {
    if (_index == value) return;
    _index = value;
    markNeedsPaint();
  }

  /// The lyric row this shift belongs to.
  int get index => _index;

  /// The shift the next paint will use. Public for tests: what reaches the
  /// screen is the thing to pin, not the function that is supposed to produce it.
  double get shift => _stagger.shiftFor(_index);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _stagger.addListener(_onStagger);
  }

  @override
  void detach() {
    _stagger.removeListener(_onStagger);
    super.detach();
  }

  void _onStagger() {
    // A row with no delay reads 0 on every tick and never repaints.
    if (shift != _paintedShift) markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    _paintedShift = shift;
    context.paintChild(child, offset + Offset(0.0, _paintedShift));
  }

  // The same offset for hit-testing and for every `localToGlobal` through this
  // row. A shift painted but not reported would leave a tap landing where the
  // row WAS, and the panel's own measuring (`_topAnchorOffsetFor`) reading a row
  // that is not where it is drawn.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final dy = shift;
    if (dy == 0.0) return super.hitTestChildren(result, position: position);
    return result.addWithPaintOffset(
      offset: Offset(0.0, dy),
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) =>
          child?.hitTest(result, position: transformed) ?? false,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final dy = shift;
    if (dy != 0.0) transform.translateByDouble(0.0, dy, 0.0, 1.0);
  }
}
