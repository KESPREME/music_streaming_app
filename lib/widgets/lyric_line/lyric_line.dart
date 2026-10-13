// lib/widgets/lyric_line/lyric_line.dart
// One lyric line, drawn by ONE render object, repainting from the clock.
//
// WHY A RENDER OBJECT AND NOT A WIDGET TREE
//
// The line is lit by a sweep that moves sixty times a second. The old widget
// version rebuilt a Stack of Text widgets on every tick (a dim base, a clipped
// lit copy, one Text per lifted word, one Text per grown letter), and it
// measured only the caret's x, which is a fact about a single row - so a line
// that wrapped had its second row painted over its first.
//
// Here the line is ONE TextPainter laid out once, and per frame the only work
// is `markNeedsPaint` and a handful of clipped `drawParagraph` calls. There are
// no widget rebuilds, no LayoutBuilder, no AnimatedBuilder and no overlay Text.
//
// WHAT IS DRAWN (mirrors BitChord `SweptLyricLine`, `PlayerLyrics.kt`)
//
//   dim pass   the whole line at the unsung alpha
//   lit pass   the same line clipped PER VISUAL ROW to where the voice has got
//              to, with a 30dp soft leading edge on the active line only
//   lift       each word being sung is drawn as a slice clipped to its own box
//              and shifted up a couple of dp - per row, so a word on row two
//              rises on row two
//   swell      a held note's letters, one by one, scaled about their own centre
//              with a soft bloom behind them
//
// ALPHA AND BLUR ARE ONE LAYER
//
// `TextPainter` rebuilds AND re-lays-out its paragraph whenever a paint property
// of the text (its colour) changes, so animating alpha through the text colour
// costs a full layout per frame per row. Instead every paragraph is a FIXED
// colour, and the row's alpha and blur ride one `saveLayer` (alpha as the
// layer paint, blur as its image filter). The active line - alpha 1, blur 0 -
// takes no layer at all.
//
// WHEN IT REPAINTS
//
// A line subscribes to the clock only if it is word-synced, and repaints on a
// tick only while inside its own animation window (plus once on each edge of
// it). Every other line on screen costs nothing per frame.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../models/lyrics_entry.dart';
import '../../services/lyrics/lyric_clock.dart';
import '../../services/lyrics/lyric_growth.dart';
import '../../services/lyrics/lyric_sweep.dart';
import '../../services/lyrics/lyric_words.dart' show LyricWord;
import '../../services/lyrics/word_lift.dart';
import 'lyric_line_geometry.dart';

/// BitChord `WIPE_FEATHER`: how far back from the leading edge the lit pass
/// fades to the dim one.
const double lyricWipeFeather = 30.0;

/// How far the soft edge reaches behind and ahead of the voice at [x] on a row
/// that spans [left]..[right].
///
/// Three quarters behind, a quarter ahead, and BOTH shrink to nothing as [x]
/// nears either end of the row. That is what makes progress continuous: with
/// nothing sung there is nothing lit, with the row sung there is no ramp left
/// to remove, and in between the edge is where the voice is.
@visibleForTesting
({double behind, double ahead}) lyricFeatherZone(
  double x,
  double left,
  double right,
) {
  final room = math.max(0.0, math.min(x - left, right - x));
  return (
    behind: math.min(lyricWipeFeather * 0.75, room),
    ahead: math.min(lyricWipeFeather * 0.25, room),
  );
}

/// BitChord `GLOW_ALPHA`.
const double lyricGlowAlpha = 0.62;

/// Gaussian sigma of the held-note bloom, in logical px. BitChord blurs its
/// glow copy by 6dp, which is a radius; this is the matching sigma.
const double lyricGlowSigma = 3.0;

/// A word lifted by less than this is not a movement, it is a sub-pixel
/// re-layout of the word on top of itself, which at 60Hz reads as shimmer.
const double _liftFloor = 0.01;

/// Room around the line that a lift, a swell, a bloom or a blur may paint into.
const double _paintMargin = 14.0;

enum _Phase { before, moving, after }

/// A lyric line that lights progressively as the song reaches it.
///
/// Word-synced entries sweep; anything else is drawn once, in one colour.
class LyricLine extends StatelessWidget {
  const LyricLine({
    super.key,
    required this.entry,
    required this.clock,
    required this.style,
    this.timingSource,
    this.alpha = 1.0,
    this.lit = 1.0,
    this.blurSigma = 0.0,
    this.tailAlpha = 0.45,
    this.feather = false,
    this.rise = true,
    this.glow = false,
    this.maxLines,
    this.ellipsis = false,
  });

  /// The line to draw.
  final LyricsEntry entry;

  final LyricClock clock;

  /// The line's type. Its colour is ignored: lines are drawn white and faded by
  /// [alpha], so the colour never has to change (see the file header).
  final TextStyle style;

  /// Drives the sweep INSTEAD of [entry]'s own timings.
  ///
  /// For a translation or romanization: it has no word timings of its own, so
  /// it advances in proportion to the original it sits under.
  final LyricsEntry? timingSource;

  /// The row's alpha: the ladder, the browsing flatten.
  final double alpha;

  /// 0..1: how lit a line-synced line is (animated by the row). Word-synced
  /// lines ignore it; the sweep decides.
  final double lit;

  /// Gaussian sigma in logical px; 0 draws sharp with no layer.
  final double blurSigma;

  /// Alpha of the unsung part. 0.45 in the panel, 0.55 in the strip.
  final double tailAlpha;

  /// Soft leading edge. The active line only.
  final bool feather;

  /// Whether the word being sung rises. Panel only: on a single pinned line the
  /// movement stops reading as emphasis and starts reading as the strip
  /// twitching once a second.
  final bool rise;

  /// Whether a held note swells and blooms. Panel, active line, motion allowed.
  final bool glow;

  final int? maxLines;

  /// Ellipsise at [maxLines]. The strip clamps to one row: a wrapped line there
  /// grows the deck, the one surface that must never resize itself.
  final bool ellipsis;

  @override
  Widget build(BuildContext context) {
    return _LyricLineRender(
      entry: entry,
      clock: clock,
      style: style,
      timingSource: timingSource,
      alpha: alpha,
      lit: lit,
      blurSigma: blurSigma,
      tailAlpha: tailAlpha,
      feather: feather,
      rise: rise,
      glow: glow,
      maxLines: maxLines,
      ellipsis: ellipsis,
      textScaler: MediaQuery.textScalerOf(context),
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      // A subtree in a route that is not current has its tickers muted. Its
      // lines must stop listening to the clock too, or a hidden panel keeps the
      // frame loop running for nothing.
      clockEnabled: TickerMode.valuesOf(context).enabled,
    );
  }
}

class _LyricLineRender extends LeafRenderObjectWidget {
  const _LyricLineRender({
    required this.entry,
    required this.clock,
    required this.style,
    required this.timingSource,
    required this.alpha,
    required this.lit,
    required this.blurSigma,
    required this.tailAlpha,
    required this.feather,
    required this.rise,
    required this.glow,
    required this.maxLines,
    required this.ellipsis,
    required this.textScaler,
    required this.reduceMotion,
    required this.clockEnabled,
  });

  final LyricsEntry entry;
  final LyricClock clock;
  final TextStyle style;
  final LyricsEntry? timingSource;
  final double alpha;
  final double lit;
  final double blurSigma;
  final double tailAlpha;
  final bool feather;
  final bool rise;
  final bool glow;
  final int? maxLines;
  final bool ellipsis;
  final TextScaler textScaler;
  final bool reduceMotion;
  final bool clockEnabled;

  @override
  RenderLyricLine createRenderObject(BuildContext context) => RenderLyricLine(
        entry: entry,
        clock: clock,
        style: style,
        timingSource: timingSource,
        alpha: alpha,
        lit: lit,
        blurSigma: blurSigma,
        tailAlpha: tailAlpha,
        feather: feather,
        rise: rise,
        glow: glow,
        maxLines: maxLines,
        ellipsis: ellipsis,
        textScaler: textScaler,
        reduceMotion: reduceMotion,
        clockEnabled: clockEnabled,
      );

  @override
  void updateRenderObject(BuildContext context, RenderLyricLine renderObject) {
    renderObject
      ..entry = entry
      ..clock = clock
      ..style = style
      ..timingSource = timingSource
      ..alpha = alpha
      ..lit = lit
      ..blurSigma = blurSigma
      ..tailAlpha = tailAlpha
      ..feather = feather
      ..rise = rise
      ..glow = glow
      ..maxLines = maxLines
      ..ellipsis = ellipsis
      ..textScaler = textScaler
      ..reduceMotion = reduceMotion
      ..clockEnabled = clockEnabled;
  }
}

/// The render object behind [LyricLine]. Public so tests can reach it.
class RenderLyricLine extends RenderBox {
  RenderLyricLine({
    required LyricsEntry entry,
    required LyricClock clock,
    required TextStyle style,
    LyricsEntry? timingSource,
    double alpha = 1.0,
    double lit = 1.0,
    double blurSigma = 0.0,
    double tailAlpha = 0.45,
    bool feather = false,
    bool rise = true,
    bool glow = false,
    int? maxLines,
    bool ellipsis = false,
    TextScaler textScaler = TextScaler.noScaling,
    bool reduceMotion = false,
    bool clockEnabled = true,
  })  : _entry = entry,
        _clock = clock,
        _style = style,
        _timingSource = timingSource,
        _alpha = alpha,
        _lit = lit,
        _blurSigma = blurSigma,
        _tailAlpha = tailAlpha,
        _feather = feather,
        _rise = rise,
        _glow = glow,
        _maxLines = maxLines,
        _ellipsis = ellipsis,
        _textScaler = textScaler,
        _reduceMotion = reduceMotion,
        _clockEnabled = clockEnabled;

  // ── Properties ─────────────────────────────────────────────────────────────

  LyricsEntry _entry;
  LyricsEntry get entry => _entry;
  set entry(LyricsEntry value) {
    if (identical(_entry, value)) return;
    final textChanged = _entry.text != value.text;
    _entry = value;
    _syncClockListener();
    if (textChanged) _invalidateText();
    markNeedsSemanticsUpdate();
    markNeedsPaint();
  }

  LyricClock _clock;
  LyricClock get clock => _clock;
  set clock(LyricClock value) {
    if (identical(_clock, value)) return;
    _removeClockListener();
    _clock = value;
    _syncClockListener();
    markNeedsPaint();
  }

  TextStyle _style;
  TextStyle get style => _style;
  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _invalidateText();
  }

  LyricsEntry? _timingSource;
  set timingSource(LyricsEntry? value) {
    if (identical(_timingSource, value)) return;
    _timingSource = value;
    _syncClockListener();
    markNeedsPaint();
  }

  double _alpha;

  /// The row alpha currently applied. For tests that pin the reveal's fade.
  @visibleForTesting
  double get debugAlpha => _alpha;

  set alpha(double value) {
    if (_alpha == value) return;
    _alpha = value;
    markNeedsPaint();
  }

  double _lit;
  set lit(double value) {
    if (_lit == value) return;
    _lit = value;
    markNeedsPaint();
  }

  double _blurSigma;
  set blurSigma(double value) {
    if (_blurSigma == value) return;
    _blurSigma = value;
    markNeedsPaint();
  }

  double _tailAlpha;
  set tailAlpha(double value) {
    if (_tailAlpha == value) return;
    _tailAlpha = value;
    _dim?.dispose();
    _dim = null;
    markNeedsPaint();
  }

  bool _feather;
  set feather(bool value) {
    if (_feather == value) return;
    _feather = value;
    markNeedsPaint();
  }

  bool _rise;
  set rise(bool value) {
    if (_rise == value) return;
    _rise = value;
    markNeedsPaint();
  }

  bool _glow;
  set glow(bool value) {
    if (_glow == value) return;
    _glow = value;
    markNeedsPaint();
  }

  int? _maxLines;
  set maxLines(int? value) {
    if (_maxLines == value) return;
    _maxLines = value;
    _invalidateText();
  }

  bool _ellipsis;
  set ellipsis(bool value) {
    if (_ellipsis == value) return;
    _ellipsis = value;
    _invalidateText();
  }

  TextScaler _textScaler;
  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    _invalidateText();
  }

  bool _reduceMotion;
  set reduceMotion(bool value) {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    markNeedsPaint();
  }

  bool _clockEnabled;
  set clockEnabled(bool value) {
    if (_clockEnabled == value) return;
    _clockEnabled = value;
    _syncClockListener();
    markNeedsPaint();
  }

  // ── Text, geometry ─────────────────────────────────────────────────────────

  /// White at full alpha: the lit pass, and the whole line when it is not
  /// synced. Fixed colour, so it is laid out once.
  TextPainter? _litPainter;

  /// White at [_tailAlpha]: the unsung pass.
  TextPainter? _dim;

  LyricLineGeometry? _geometry;
  double _laidOutWidth = double.nan;

  void _invalidateText() {
    _litPainter?.dispose();
    _litPainter = null;
    _dim?.dispose();
    _dim = null;
    _geometry = null;
    _laidOutWidth = double.nan;
    markNeedsLayout();
  }

  TextPainter _makePainter(Color color) => TextPainter(
        text: TextSpan(text: _entry.text, style: _style.copyWith(color: color)),
        textDirection: TextDirection.ltr,
        textScaler: _textScaler,
        maxLines: _maxLines,
        ellipsis: _ellipsis ? '\u2026' : null,
      );

  TextPainter get _lit0 => _litPainter ??= _makePainter(const Color(0xFFFFFFFF));

  TextPainter get _dim0 {
    var painter = _dim;
    if (painter == null) {
      painter = _makePainter(
        const Color(0xFFFFFFFF).withValues(alpha: _tailAlpha),
      );
      final w = _laidOutWidth;
      if (!w.isNaN) painter.layout(maxWidth: w);
      _dim = painter;
    }
    return painter;
  }

  LyricLineGeometry get _geometry0 =>
      _geometry ??= LyricLineGeometry.measure(_lit0, _entry.text);

  /// The geometry, measured on first use and kept until the layout changes.
  /// Lazy because a line that is never in its window (most of a song) never
  /// needs it.
  @visibleForTesting
  LyricLineGeometry get geometry => _geometry0;

  void _layoutText(double maxWidth) {
    if (_laidOutWidth == maxWidth && _litPainter != null) return;
    _lit0.layout(maxWidth: maxWidth);
    _dim?.layout(maxWidth: maxWidth);
    _geometry = null;
    _laidOutWidth = maxWidth;
  }

  @override
  void performLayout() {
    if (_entry.text.isEmpty) {
      size = constraints.constrain(Size.zero);
      return;
    }
    final bounded = constraints.hasBoundedWidth;
    final available = bounded ? constraints.maxWidth : double.infinity;
    _layoutText(available);
    final width = bounded ? constraints.maxWidth : _lit0.width;
    size = constraints.constrain(Size(width, _lit0.height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (_entry.text.isEmpty) return constraints.constrain(Size.zero);
    final painter = _makePainter(const Color(0xFFFFFFFF))
      ..layout(
        maxWidth:
            constraints.hasBoundedWidth ? constraints.maxWidth : double.infinity,
      );
    final width =
        constraints.hasBoundedWidth ? constraints.maxWidth : painter.width;
    final size = constraints.constrain(Size(width, painter.height));
    painter.dispose();
    return size;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    final painter = _makePainter(const Color(0xFFFFFFFF))..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final painter = _makePainter(const Color(0xFFFFFFFF))
      ..layout(maxWidth: width.isFinite ? width : double.infinity);
    final h = painter.height;
    painter.dispose();
    return h;
  }

  @override
  Rect get paintBounds => (Offset.zero & size).inflate(_paintMargin);

  // The line paints outside its own box (a lift, a swell, a bloom). The parent
  // gives it room; this makes the boundary's cull rect honest about it.
  @override
  Rect get semanticBounds => Offset.zero & size;

  @override
  bool hitTestSelf(Offset position) => true;

  // ── Clock ──────────────────────────────────────────────────────────────────

  bool _listening = false;
  bool _holdingFrames = false;
  _Phase _phase = _Phase.before;

  /// How far ahead of its window a line asks for frames.
  ///
  /// The clock ticks coarsely (every 100ms) until somebody needs every frame, so
  /// a line has to see its window coming: asking only once the window opened
  /// would lose the first syllable to the ticker's start-up.
  static const int _frameLeadInMs = 300;

  /// The entry whose timings drive the sweep.
  LyricsEntry get _timing => _timingSource ?? _entry;

  bool get _animated => _clockEnabled && _timing.isWordSynced;

  void _syncClockListener() {
    final want = attached && _animated;
    if (want == _listening) return;
    if (want) {
      _clock.addListener(_onClock);
      _listening = true;
      final now = _clock.positionMs;
      _phase = _phaseAt(now);
      _syncFrameDemand(now);
    } else {
      _removeClockListener();
    }
  }

  void _removeClockListener() {
    if (_holdingFrames) {
      _clock.releaseFrames(this);
      _holdingFrames = false;
    }
    if (!_listening) return;
    _clock.removeListener(_onClock);
    _listening = false;
  }

  /// Holds the clock's frame loop exactly while this line is (about to be) moving.
  void _syncFrameDemand(int nowMs) {
    final t = _timing;
    final want = nowMs >= t.animatesFromMs - _frameLeadInMs &&
        nowMs <= t.animatesUntilMs + 1;
    if (want == _holdingFrames) return;
    _holdingFrames = want;
    if (want) {
      _clock.retainFrames(this);
    } else {
      _clock.releaseFrames(this);
    }
  }

  _Phase _phaseAt(int nowMs) {
    final t = _timing;
    if (nowMs < t.animatesFromMs - 1) return _Phase.before;
    if (nowMs > t.animatesUntilMs + 1) return _Phase.after;
    return _Phase.moving;
  }

  void _onClock() {
    final now = _clock.positionMs;
    _syncFrameDemand(now);
    final phase = _phaseAt(now);
    // Repaint while inside the window, and once on each edge of it so a line
    // lands in its final state. Outside, a tick costs this comparison.
    if (phase == _phase && phase != _Phase.moving) return;
    _phase = phase;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _syncClockListener();
  }

  @override
  void detach() {
    _removeClockListener();
    super.detach();
  }

  @override
  void dispose() {
    _removeClockListener();
    _litPainter?.dispose();
    _dim?.dispose();
    super.dispose();
  }

  // ── Semantics ──────────────────────────────────────────────────────────────

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _entry.text
      ..textDirection = TextDirection.ltr;
  }

  // ── Paint ──────────────────────────────────────────────────────────────────

  /// Records the clip rects of the lit pass, for tests. Off by default.
  @visibleForTesting
  bool debugRecordClips = false;

  /// Lit-pass clip rects of the last paint, in line-local coordinates.
  @visibleForTesting
  final List<Rect> debugLitClips = <Rect>[];

  /// Dim-pass clip rects of the last paint.
  @visibleForTesting
  final List<Rect> debugDimClips = <Rect>[];

  /// How many paragraph draws the last paint made. A cost counter.
  @visibleForTesting
  int debugParagraphDraws = 0;

  /// How many `saveLayer`s the last paint made. The expensive thing on a phone,
  /// so it is counted: the active line at full alpha and no blur must make none.
  @visibleForTesting
  int debugLayers = 0;

  bool get _sweeps => _timing.isWordSynced;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_entry.text.isEmpty || _litPainter == null) return;

    final canvas = context.canvas;
    final sweeps = _sweeps;
    debugLitClips.clear();
    debugDimClips.clear();
    debugParagraphDraws = 0;
    debugLayers = 0;

    // A line-synced line is ONE colour whose alpha the row animates, so it folds
    // into the layer alpha. A synced line keeps the layer for the row's alpha
    // alone; its lit/unsung split is the passes below.
    final layerAlpha = sweeps
        ? _alpha
        : _alpha * (_tailAlpha + (1.0 - _tailAlpha) * _lit.clamp(0.0, 1.0));

    final needsLayer = layerAlpha < 0.995 || _blurSigma > 0.01;

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    if (needsLayer) {
      final margin = _paintMargin + _blurSigma * 3;
      final layerPaint = Paint()
        ..color = Color.fromRGBO(0, 0, 0, layerAlpha.clamp(0.0, 1.0));
      if (_blurSigma > 0.01) {
        layerPaint.imageFilter = ui.ImageFilter.blur(
          sigmaX: _blurSigma,
          sigmaY: _blurSigma,
          tileMode: ui.TileMode.decal,
        );
      }
      canvas.saveLayer((Offset.zero & size).inflate(margin), layerPaint);
      debugLayers++;
    }

    if (!sweeps) {
      _lit0.paint(canvas, Offset.zero);
      debugParagraphDraws++;
    } else {
      _paintSwept(canvas);
    }

    if (needsLayer) canvas.restore();
    canvas.restore();
  }

  void _paintSwept(Canvas canvas) {
    final now = _clock.positionMs;
    switch (_phaseAt(now)) {
      case _Phase.before:
        _dim0.paint(canvas, Offset.zero);
        debugParagraphDraws++;
        return;
      case _Phase.after:
        _lit0.paint(canvas, Offset.zero);
        debugParagraphDraws++;
        return;
      case _Phase.moving:
        _paintMoving(canvas, now);
    }
  }

  /// The sung position as a fractional character index into THIS line's text.
  double _revealedAt(int now) {
    final source = _timingSource;
    if (source == null) {
      return revealedChars(_entry, now).clamp(0.0, _entry.text.length.toDouble());
    }
    // A translation advances in proportion to the original it sits under.
    final sourceLength = source.text.length;
    if (sourceLength == 0) return 0;
    final fraction = revealedChars(source, now) / sourceLength;
    return (fraction * _entry.text.length)
        .clamp(0.0, _entry.text.length.toDouble());
  }

  // Scratch, reused across frames so a steady sweep allocates nothing.
  final List<List<double>> _specials = <List<double>>[];
  final List<List<double>> _segments = <List<double>>[];

  void _paintMoving(Canvas canvas, int now) {
    final length = _entry.text.length;
    final revealed = _revealedAt(now);
    final g = _geometry0;
    final dim = _dim0;
    final lit = _lit0;

    final ownTimings = _timingSource == null;
    final words = _entry.timedWords;
    final spans = _entry.wordSpans;

    // Held words currently mid-flight take over their sung letters from the
    // plain passes, so a letter is never drawn twice.
    final growing = (_glow && !_reduceMotion && ownTimings)
        ? _entry.growingWords
        : const <GrowingWord>[];

    final wantSlices = ownTimings && _rise && words.isNotEmpty;
    final hasSpecials = _collectSpecials(
      g,
      now,
      revealed,
      words,
      spans,
      growing,
      wantSlices,
    );

    // Nothing sung yet and nothing lifting: the dim line, drawn once.
    if (revealed <= 0 && !hasSpecials) {
      dim.paint(canvas, Offset.zero);
      debugParagraphDraws++;
      return;
    }

    // ── Dim pass: the whole line, at the unsung alpha ──
    if (!hasSpecials) {
      dim.paint(canvas, Offset.zero);
      debugParagraphDraws++;
    } else {
      _buildSegments(g);
      _paintPass(canvas, dim, g, null, debugDimClips);
    }

    if (revealed <= 0) return;

    // ── Lit pass: clipped per visual row to where the voice has got to ──
    final fullyLit = revealed >= length;
    final useFeather = _feather && !fullyLit;
    if (useFeather) {
      canvas.saveLayer((Offset.zero & size).inflate(_paintMargin), Paint());
      debugLayers++;
    }

    if (!hasSpecials && fullyLit) {
      lit.paint(canvas, Offset.zero);
      debugParagraphDraws++;
    } else {
      if (!hasSpecials) _buildSegments(g);
      _paintLit(canvas, lit, g, revealed, fullyLit, useFeather);
    }

    if (useFeather) canvas.restore();

    // ── Swell: held letters, one by one ──
    if (growing.isNotEmpty) {
      _paintGrowth(canvas, lit, g, now, revealed, words, spans, growing);
    }
  }

  /// Fills [_specials] with each row's non-flat segments, in x order: lifted
  /// words (positive dy) and holes (NaN) that the swell draws itself.
  ///
  /// Returns whether any row has one. Almost every frame of almost every line
  /// has none worth drawing separately, and then the line is a single draw.
  bool _collectSpecials(
    LyricLineGeometry g,
    int now,
    double revealed,
    List<LyricWord> words,
    List<(int, int)?> spans,
    List<GrowingWord> growing,
    bool wantSlices,
  ) {
    while (_specials.length < g.rowCount) {
      _specials.add(<double>[]);
    }
    for (var r = 0; r < g.rowCount; r++) {
      _specials[r].clear();
    }
    var any = false;

    // Index the animating growing words so the loop below can recognise them.
    GrowingWord? growingFor(int wordIndex) {
      for (final w in growing) {
        if (w.index == wordIndex && w.isAnimatingAt(now)) return w;
      }
      return null;
    }

    for (var i = 0; i < words.length && i < spans.length; i++) {
      final span = spans[i];
      if (span == null) continue;
      final (start, end) = span;

      final grower = growing.isEmpty ? null : growingFor(i);
      if (grower != null) {
        // The sung letters of a held word are the swell's, not the plain
        // passes': a hole here, drawn by [_paintGrowth].
        final soFar = (revealed - start).floor().clamp(0, end - start);
        if (soFar > 0) {
          g.forEachRowSegment(start, start + soFar, (row, x0, x1) {
            _specials[row]..add(x0)..add(x1)..add(double.nan);
          });
          any = true;
        }
        continue;
      }

      if (!wantSlices) continue;
      final lift = wordLiftPx(_entry.timedWords, i, now);
      if (lift <= _liftFloor) continue;
      g.forEachRowSegment(start, end, (row, x0, x1) {
        _specials[row]..add(x0)..add(x1)..add(lift);
      });
      any = true;
    }
    return any;
  }

  /// Turns each row's specials into a full tiling of the row: the specials
  /// themselves plus the flat runs between them, so every pixel of the row is
  /// drawn exactly once.
  void _buildSegments(LyricLineGeometry g) {
    while (_segments.length < g.rowCount) {
      _segments.add(<double>[]);
    }
    final far = size.width + _paintMargin;
    for (var r = 0; r < g.rowCount; r++) {
      final out = _segments[r]..clear();
      final specials = _specials[r];
      var cursor = -_paintMargin;
      for (var k = 0; k + 2 < specials.length; k += 3) {
        final x0 = specials[k];
        final x1 = specials[k + 1];
        final dy = specials[k + 2];
        if (x0 > cursor + 0.01) {
          out..add(cursor)..add(x0)..add(0.0);
        }
        out..add(x0)..add(x1)..add(dy);
        cursor = math.max(cursor, x1);
      }
      if (far > cursor + 0.01) {
        out..add(cursor)..add(far)..add(0.0);
      }
    }
  }

  /// Draws [painter] over every row's segments, each in its own clip and shifted
  /// by its own lift. [limit] caps a row's right edge (the lit pass); null
  /// means the whole row.
  void _paintPass(
    Canvas canvas,
    TextPainter painter,
    LyricLineGeometry g,
    double Function(int row)? limit,
    List<Rect> record,
  ) {
    for (var r = 0; r < g.rowCount; r++) {
      final row = g.rows[r];
      final cap = limit?.call(r) ?? double.infinity;
      final segs = _segments[r];
      for (var k = 0; k + 2 < segs.length; k += 3) {
        final dy = segs[k + 2];
        if (dy.isNaN) continue; // a hole: the swell draws it
        final a = segs[k];
        final b = math.min(segs[k + 1], cap);
        if (b <= a) continue;
        // A lifted word paints above its own row by exactly its lift.
        final top = row.top - (dy > 0 ? dy + 1 : 0);
        final clip = Rect.fromLTRB(a, top, b, row.bottom);
        canvas.save();
        canvas.clipRect(clip);
        if (dy > 0) canvas.translate(0, -dy);
        painter.paint(canvas, Offset.zero);
        debugParagraphDraws++;
        canvas.restore();
        if (debugRecordClips) record.add(clip);
      }
    }
  }

  final List<double> _edgeScratch = <double>[];
  final List<double> _softScratch = <double>[];

  List<double> _softScratchFor(int rows) {
    while (_softScratch.length < rows) {
      _softScratch.add(0);
    }
    return _softScratch;
  }

  List<double> _edgesFor(int rows) {
    while (_edgeScratch.length < rows) {
      _edgeScratch.add(0);
    }
    return _edgeScratch;
  }

  void _paintLit(
    Canvas canvas,
    TextPainter lit,
    LyricLineGeometry g,
    double revealed,
    bool fullyLit,
    bool feather,
  ) {
    final sweepSpans = _timingSource == null
        ? _entry.sweepSpans
        : const <(int, int)>[];

    // Where the leading edge is on each row. Rows wholly before the voice are
    // lit to their end; the row the voice is on is cut at x; rows after it are
    // not lit at all.
    final edges = _edgesFor(g.rowCount);
    final softFrom = _softScratchFor(g.rowCount);
    for (var r = 0; r < g.rowCount; r++) {
      final row = g.rows[r];
      edges[r] = double.negativeInfinity;
      softFrom[r] = double.nan;
      if (fullyLit || revealed >= row.end) {
        edges[r] = double.infinity;
      } else if (revealed > row.start) {
        final x = g.xAt(r, revealed, sweepSpans);
        if (!feather) {
          edges[r] = x;
        } else {
          // The soft edge is CENTRED on where the voice is, not trailing it.
          //
          // It used to run from 30dp behind the voice up to it, so the lit
          // letters were always 30dp short of the audio, a word that had just
          // been sung was still partly dim, and the instant the line finished
          // the whole feather vanished in one frame: the fill appeared to
          // finish EARLY at a slower pace and then jump. Here the ramp is mostly
          // behind the voice and a little ahead of it (as Apple Music's is), and
          // it narrows to nothing at both ends of the row - at the start there is
          // nothing lit, at the end the row is exactly fully lit - so progress is
          // continuous from the first pixel to the last, with no pop at the end.
          final zone = lyricFeatherZone(x, row.left, row.right);
          edges[r] = x + zone.ahead;
          softFrom[r] = x - zone.behind;
        }
      }
    }

    _paintPass(canvas, lit, g, (r) => edges[r], debugLitClips);

    if (!feather) return;
    for (var r = 0; r < g.rowCount; r++) {
      final edge = edges[r];
      final x0 = softFrom[r];
      if (edge.isInfinite || edge.isNaN || x0.isNaN) continue; // whole row / not reached
      if (edge <= x0) continue;
      final row = g.rows[r];
      canvas.drawRect(
        Rect.fromLTRB(x0, row.top - _paintMargin * 0.5, edge, row.bottom),
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            Offset(x0, 0),
            Offset(edge, 0),
            const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          ),
      );
    }
  }

  void _paintGrowth(
    Canvas canvas,
    TextPainter lit,
    LyricLineGeometry g,
    int now,
    double revealed,
    List<LyricWord> words,
    List<(int, int)?> spans,
    List<GrowingWord> growing,
  ) {
    final em = _textScaler.scale(_style.fontSize ?? 32);
    final sample = CharGrowth();

    for (final word in growing) {
      if (!word.isAnimatingAt(now)) continue;
      final span = spans[word.index];
      if (span == null) continue;
      final fall = wordFall(_entry.timedWords, word.index, now);

      for (var i = 0; i < word.length; i++) {
        final ci = span.$1 + i;
        if (ci >= g.length) break;
        // Not yet sung, so not yet grown: the swell follows the voice.
        if (revealed < ci + 1) break;

        word.sampleInto(i, now, sample);

        final left = g.charLeft[ci];
        final right = g.charRight[ci];
        if (right <= left) continue;
        final row = g.rows[g.charRow[ci]];
        final cx = (left + right) / 2;
        final cy = (row.top + row.bottom) / 2;
        // The lift is in MULTIPLES of the ordinary sung-word rise - the same
        // 2dp the flat words use - times the word's shared settle, so a grown
        // letter comes to rest at exactly the lift a flat word would have.
        final dy = sample.rise * wordRiseDp * fall;
        final dx = sample.shift * em;

        canvas.save();
        canvas.translate(cx + dx, cy - dy);
        canvas.scale(sample.scale);
        canvas.translate(-cx, -cy);

        final box = Rect.fromLTRB(left - 0.5, row.top, right + 0.5, row.bottom);

        if (sample.bloom > 0.01) {
          // Bloom: the letter, blurred, behind itself.
          final glowBounds = box.inflate(lyricGlowSigma * 3 + 4);
          canvas.saveLayer(
            glowBounds,
            Paint()
              ..color = Color.fromRGBO(
                0,
                0,
                0,
                (lyricGlowAlpha * sample.bloom).clamp(0.0, 1.0),
              )
              ..imageFilter = ui.ImageFilter.blur(
                sigmaX: lyricGlowSigma,
                sigmaY: lyricGlowSigma,
                tileMode: ui.TileMode.decal,
              ),
          );
          debugLayers++;
          canvas.clipRect(box);
          lit.paint(canvas, Offset.zero);
          debugParagraphDraws++;
          canvas.restore();
        }

        // Clipped in the SAME transformed space as the glyph, so the box scales
        // with the letter and neighbours (whose boxes lie outside it) stay out.
        canvas.clipRect(box);
        lit.paint(canvas, Offset.zero);
        debugParagraphDraws++;
        canvas.restore();
      }
    }
  }
}
