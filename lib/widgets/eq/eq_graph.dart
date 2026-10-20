// lib/widgets/eq/eq_graph.dart
//
// THE EQUALIZER'S INSTRUMENT: a frequency-response graph you play with.
//
//   * The curve is the estimated response of the device's real bands (see
//     eq_curves.dart) - log frequency across, dB up - drawn with a glow and a
//     fill that fades toward the 0 dB line, so a boost reads as light above it
//     and a cut as shade below.
//   * One node per band sits on the curve at the band's centre frequency. Drag
//     one up or down; it snaps to half a dB, ticks the haptic as it crosses 0 dB
//     and lands at the device's limits. Double-tap a node to zero it.
//   * Presets glide: when the gains change from outside (a preset, a reset) the
//     curve animates there instead of jumping. During a drag it follows the
//     finger exactly.
//
// The drag recogniser is "eager": it claims the touch the moment it lands, so
// the page's scroll view can never steal a vertical drag half-way through a
// gesture. Scrolling the page is done from outside the graph.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/eq/eq_curves.dart';
import '../../services/eq/eq_models.dart';
import '../../theme/app_font.dart';

/// Where the plot sits inside the graph's box.
Rect eqPlotRect(Size size) =>
    Rect.fromLTRB(36, 30, size.width - 14, size.height - 28);

const double _minHz = 20;
const double _maxHz = 20000;

double eqXForHz(double hz, Rect plot) {
  final a = math.log(_minHz), b = math.log(_maxHz);
  return plot.left + (math.log(hz.clamp(_minHz, _maxHz)) - a) / (b - a) * plot.width;
}

double eqYForDb(double db, Rect plot, double minDb, double maxDb) =>
    plot.top + (maxDb - db) / (maxDb - minDb) * plot.height;

double eqDbForY(double y, Rect plot, double minDb, double maxDb) =>
    maxDb - ((y - plot.top) / plot.height) * (maxDb - minDb);

/// Index of the band whose column is closest to [x].
int eqNearestBand(List<EqBand> bands, double x, Rect plot) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < bands.length; i++) {
    final d = (eqXForHz(bands[i].centerHz, plot) - x).abs();
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

class EqGraph extends StatefulWidget {
  const EqGraph({
    super.key,
    required this.bands,
    required this.gains,
    required this.minDb,
    required this.maxDb,
    required this.onChanged,
    this.enabled = true,
    this.interactive = true,
    this.bypass = false,
    this.accent,
    this.height = 260,
    this.onInteraction,
  });

  final List<EqBand> bands;
  final List<double> gains;
  final double minDb;
  final double maxDb;

  /// Called with the full new list of gains while a node is dragged.
  final ValueChanged<List<double>> onChanged;
  final bool enabled;

  /// Whether a touch moves a band. Separate from [enabled] (how it LOOKS): a
  /// graph that is drawn as off still answers to a touch, which is what lets the
  /// equalizer switch itself on when it is played.
  final bool interactive;

  /// Hold-to-compare is down: the curve is shown as a ghost.
  final bool bypass;
  final Color? accent;
  final double height;

  /// True while a finger is on the graph.
  final ValueChanged<bool>? onInteraction;

  @override
  State<EqGraph> createState() => _EqGraphState();
}

class _EqGraphState extends State<EqGraph> with SingleTickerProviderStateMixin {
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late List<double> _from = widget.gains;
  late List<double> _to = widget.gains;
  List<double> _shown = const [];

  int? _active;
  double _grab = 0;
  bool _dragging = false;
  DateTime _lastUp = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastUpBand = -1;
  double _lastZeroSide = 0;
  bool _atLimit = false;

  @override
  void initState() {
    super.initState();
    _shown = List<double>.of(widget.gains);
    _glide.addListener(_onGlide);
  }

  void _onGlide() {
    final t = Curves.easeOutCubic.transform(_glide.value);
    final n = _to.length;
    if (_from.length != n) return;
    setState(() {
      _shown = [for (var i = 0; i < n; i++) _from[i] + (_to[i] - _from[i]) * t];
    });
  }

  @override
  void didUpdateWidget(EqGraph old) {
    super.didUpdateWidget(old);
    if (_dragging || widget.gains.length != _shown.length) {
      _glide.stop();
      _shown = List<double>.of(widget.gains);
      return;
    }
    var same = widget.gains.length == old.gains.length;
    if (same) {
      for (var i = 0; i < widget.gains.length; i++) {
        if (widget.gains[i] != old.gains[i]) {
          same = false;
          break;
        }
      }
    }
    if (!same) {
      _from = List<double>.of(_shown);
      _to = List<double>.of(widget.gains);
      _glide
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  // ── Gestures ─────────────────────────────────────────────────────────────

  Size get _size => context.size ?? Size.zero;

  void _down(Offset p) {
    if (!widget.interactive || widget.gains.isEmpty) return;
    final plot = eqPlotRect(_size);
    final i = eqNearestBand(widget.bands, p.dx, plot);
    final nodeY = eqYForDb(widget.gains[i], plot, widget.minDb, widget.maxDb);
    // Grab the node where it is if the finger lands near it; jump it to the
    // finger otherwise. Either way it never leaps away from a touch on it.
    _grab = (nodeY - p.dy).abs() < 34 ? nodeY - p.dy : 0;
    _dragging = true;
    _glide.stop();
    _shown = List<double>.of(widget.gains);
    _lastZeroSide = widget.gains[i].sign;
    _atLimit = false;
    setState(() => _active = i);
    widget.onInteraction?.call(true);
    _move(p);
  }

  void _move(Offset p) {
    final i = _active;
    if (i == null || !_dragging) return;
    final plot = eqPlotRect(_size);
    final raw = eqDbForY(p.dy + _grab, plot, widget.minDb, widget.maxDb);
    final next = snapDb(raw, widget.minDb, widget.maxDb);
    if (next == widget.gains[i]) return;

    final side = next.sign;
    if (side != _lastZeroSide && (next == 0 || side * _lastZeroSide < 0)) {
      HapticFeedback.selectionClick();
    }
    _lastZeroSide = side;
    final limit = next == widget.minDb || next == widget.maxDb;
    if (limit && !_atLimit) HapticFeedback.lightImpact();
    _atLimit = limit;

    final out = List<double>.of(widget.gains);
    out[i] = next;
    _shown = out;
    widget.onChanged(out);
  }

  void _up() {
    final i = _active;
    if (i == null) return;
    final now = DateTime.now();
    final isDouble =
        _lastUpBand == i && now.difference(_lastUp) < const Duration(milliseconds: 320);
    _lastUp = now;
    _lastUpBand = i;
    _dragging = false;
    setState(() => _active = null);
    widget.onInteraction?.call(false);
    if (isDouble && widget.gains[i] != 0) {
      HapticFeedback.mediumImpact();
      final out = List<double>.of(widget.gains)..[i] = 0;
      widget.onChanged(out);
    }
  }

  void _cancel() {
    _dragging = false;
    if (_active != null) {
      setState(() => _active = null);
      widget.onInteraction?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? Theme.of(context).colorScheme.primary;
    final shown = _shown.length == widget.gains.length ? _shown : widget.gains;

    return Semantics(
      container: true,
      label: 'Equalizer response graph',
      hint: widget.interactive
          ? 'Drag a band up or down to change its gain'
          : 'Equalizer is not available',
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
            _EagerPan.new,
            (r) => r
              ..onDown = _down
              ..onMove = _move
              ..onUp = _up
              ..onCancel = _cancel,
          ),
        },
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: EqGraphPainter(
                bands: widget.bands,
                gains: shown,
                minDb: widget.minDb,
                maxDb: widget.maxDb,
                accent: accent,
                enabled: widget.enabled,
                bypass: widget.bypass,
                active: _active,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Claims the touch immediately, so a scroll view above cannot take it.
class _EagerPan extends OneSequenceGestureRecognizer {
  ValueChanged<Offset>? onDown;
  ValueChanged<Offset>? onMove;
  VoidCallback? onUp;
  VoidCallback? onCancel;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onDown?.call(event.localPosition);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onMove?.call(event.localPosition);
    } else if (event is PointerUpEvent) {
      onUp?.call();
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      onCancel?.call();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'eqEagerPan';
}

class EqGraphPainter extends CustomPainter {
  EqGraphPainter({
    required this.bands,
    required this.gains,
    required this.minDb,
    required this.maxDb,
    required this.accent,
    required this.enabled,
    required this.bypass,
    required this.active,
  });

  final List<EqBand> bands;
  final List<double> gains;
  final double minDb;
  final double maxDb;
  final Color accent;
  final bool enabled;
  final bool bypass;
  final int? active;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = eqPlotRect(size);
    final live = enabled && !bypass;
    final tone = enabled ? accent : Colors.white.withValues(alpha: 0.5);

    _grid(canvas, plot);
    _bandGuides(canvas, plot, tone);

    final pts = responseCurve(bands, gains, count: 120);
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final x = eqXForHz(pts[i].$1, plot);
      final y = eqYForDb(pts[i].$2.clamp(minDb, maxDb), plot, minDb, maxDb);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final y0 = eqYForDb(0, plot, minDb, maxDb);

    canvas.save();
    canvas.clipRect(plot.inflate(2));

    // Fill: light above the zero line for a boost, shade below for a cut.
    final fill = Path.from(path)
      ..lineTo(plot.right, y0)
      ..lineTo(plot.left, y0)
      ..close();
    final f0 = ((y0 - plot.top) / plot.height).clamp(0.02, 0.98);
    final fillAlpha = live ? 0.34 : 0.1;
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tone.withValues(alpha: fillAlpha),
            tone.withValues(alpha: 0),
            tone.withValues(alpha: fillAlpha * 0.8),
          ],
          stops: [0, f0, 1],
        ).createShader(plot),
    );

    if (live) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = tone.withValues(alpha: 0.42)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = LinearGradient(colors: [
          tone,
          Color.lerp(tone, Colors.white, live ? 0.55 : 0.1)!,
          tone,
        ]).createShader(plot)
        ..color = tone,
    );
    canvas.restore();

    if (bypass && enabled) _ghost(canvas, plot, y0);
    _nodes(canvas, plot, tone, live);
    final a = active;
    if (a != null && a < gains.length) _bubble(canvas, size, plot, a, tone);
  }

  void _grid(Canvas canvas, Rect plot) {
    final line = Paint()..strokeWidth = 1;
    final lo = (minDb / 6).ceil() * 6;
    final hi = (maxDb / 6).floor() * 6;
    for (var db = lo; db <= hi; db += 6) {
      final y = eqYForDb(db.toDouble(), plot, minDb, maxDb);
      line.color = Colors.white.withValues(alpha: db == 0 ? 0.2 : 0.055);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), line);
      _text(canvas, db == 0 ? '0' : formatDb(db.toDouble(), unit: false),
          Offset(plot.left - 8, y),
          size: 10, alpha: db == 0 ? 0.6 : 0.34, anchor: _Anchor.rightMiddle);
    }
  }

  void _bandGuides(Canvas canvas, Rect plot, Color tone) {
    final guide = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.045);
    for (var i = 0; i < bands.length; i++) {
      final x = eqXForHz(bands[i].centerHz, plot);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), guide);
      final isActive = active == i;
      _text(canvas, formatHzShort(bands[i].centerHz), Offset(x, plot.bottom + 10),
          size: 10.5,
          alpha: isActive ? 0.95 : 0.46,
          color: isActive ? tone : Colors.white,
          weight: isActive ? FontWeight.w800 : FontWeight.w600,
          anchor: _Anchor.centerTop);
    }
  }

  /// While hold-to-compare is down: the flat original, drawn as a dashed line.
  void _ghost(Canvas canvas, Rect plot, double y0) {
    final p = Paint()
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.7);
    for (var x = plot.left; x < plot.right; x += 10) {
      canvas.drawLine(Offset(x, y0), Offset(math.min(x + 5, plot.right), y0), p);
    }
    _text(canvas, 'ORIGINAL', Offset(plot.center.dx, y0 - 14),
        size: 11, alpha: 0.9, weight: FontWeight.w800, anchor: _Anchor.center);
  }

  void _nodes(Canvas canvas, Rect plot, Color tone, bool live) {
    for (var i = 0; i < bands.length && i < gains.length; i++) {
      final c = Offset(
        eqXForHz(bands[i].centerHz, plot),
        eqYForDb(gains[i].clamp(minDb, maxDb), plot, minDb, maxDb),
      );
      final isActive = active == i;
      if (isActive) {
        canvas.drawCircle(
          c,
          24,
          Paint()
            ..color = tone.withValues(alpha: 0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      final r = isActive ? 11.0 : 8.0;
      canvas.drawCircle(c, r + 3, Paint()..color = Colors.black.withValues(alpha: 0.5));
      canvas.drawCircle(
          c, r, Paint()..color = enabled ? Colors.white : Colors.white54);
      canvas.drawCircle(
          c,
          r - 3.2,
          Paint()
            ..color = live
                ? tone
                : (enabled ? tone.withValues(alpha: 0.5) : Colors.black54));
    }
  }

  void _bubble(Canvas canvas, Size size, Rect plot, int i, Color tone) {
    final c = Offset(
      eqXForHz(bands[i].centerHz, plot),
      eqYForDb(gains[i].clamp(minDb, maxDb), plot, minDb, maxDb),
    );
    final label = formatDb(gains[i]);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: AppFont.style(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 22, h = 28.0;
    var x = (c.dx - w / 2).clamp(4.0, size.width - w - 4);
    var y = c.dy - 46;
    if (y < 2) y = c.dy + 22;
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(14));
    canvas.drawRRect(rr.shift(const Offset(0, 3)),
        Paint()..color = Colors.black.withValues(alpha: 0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawRRect(rr, Paint()..color = const Color(0xE6101012));
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = tone.withValues(alpha: 0.6));
    tp.paint(canvas, Offset(x + 11, y + (h - tp.height) / 2));
  }

  void _text(
    Canvas canvas,
    String s,
    Offset at, {
    double size = 10,
    double alpha = 0.5,
    Color color = Colors.white,
    FontWeight weight = FontWeight.w600,
    _Anchor anchor = _Anchor.center,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: AppFont.style(
            color: color.withValues(alpha: alpha), fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final o = switch (anchor) {
      _Anchor.center => Offset(at.dx - tp.width / 2, at.dy - tp.height / 2),
      _Anchor.centerTop => Offset(at.dx - tp.width / 2, at.dy - tp.height / 2),
      _Anchor.rightMiddle => Offset(at.dx - tp.width, at.dy - tp.height / 2),
    };
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(EqGraphPainter old) =>
      old.gains != gains ||
      old.accent != accent ||
      old.enabled != enabled ||
      old.bypass != bypass ||
      old.active != active ||
      old.minDb != minDb ||
      old.maxDb != maxDb ||
      old.bands != bands;
}

enum _Anchor { center, centerTop, rightMiddle }
