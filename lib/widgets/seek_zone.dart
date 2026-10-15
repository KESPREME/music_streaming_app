// lib/widgets/seek_zone.dart
//
// The transition, drawn INSIDE the seek bar.
//
// The last seconds of a song are where the next one comes in. The bar marks that
// stretch with its own material - no extra element, nothing below or above it:
//
//   * PLANNED   The stretch is tinted, sweeping in left to right when the engine
//               has decided what it will do (as soon as a song starts), and
//               dissolving when the session moves on. An AutoMix zone is the
//               accent colour with fine diagonal hatching; a plain crossfade is a
//               quiet white veil with none, so the two read differently at a
//               glance and a crossfade does not shout.
//   * ENTERED   The played fill is "dyed" as the playhead passes through the
//               zone (one gradient over the fill, so it stays one shape): for AutoMix white drifts to the accent (the next song
//               arriving), for a crossfade white thins out (this song leaving).
//               The bar shows the mix as the playhead crosses it.
//   * LIVE      While the mix actually runs the zone brightens and the hatching
//               flows toward the end of the song, at the speed of a slow breath.
//
// Motion rules: the sweep is a deceleration (520 ms in, 240 ms out - leaving is
// quicker than arriving); nothing overshoots; with reduced motion the zone is
// simply there, still, and the flow does not run.
//
// Everything here paints from animations passed to the painter's `repaint`, so
// a zone coming and going repaints a 7 px bar and rebuilds nothing.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable, immutable;
import 'package:flutter/material.dart';

import '../services/transition/transition_engine.dart';

/// The stretch of a song's bar that the transition occupies.
@immutable
class SeekZone {
  const SeekZone({
    required this.from,
    required this.to,
    required this.color,
    required this.mix,
    this.label,
  });

  /// Where it starts and ends along the bar, 0..1.
  final double from;
  final double to;

  /// The accent of an AutoMix zone (a crossfade is drawn white).
  final Color color;

  /// A real AutoMix (placed, hatched, dyed) rather than a plain crossfade.
  final bool mix;

  /// What a screen reader says about it.
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is SeekZone &&
      other.from == from &&
      other.to == to &&
      other.color == color &&
      other.mix == mix &&
      other.label == label;

  @override
  int get hashCode => Object.hash(from, to, color, mix, label);
}

/// A zone and the three animations that move it, as the painters take them.
class SeekZoneFrame {
  const SeekZoneFrame({
    this.zone,
    this.reveal = kAlwaysDismissedAnimation,
    this.live = kAlwaysDismissedAnimation,
    this.flow = kAlwaysDismissedAnimation,
  });

  static const SeekZoneFrame none = SeekZoneFrame();

  final SeekZone? zone;

  /// 0..1: how much of the zone has swept in.
  final Animation<double> reveal;

  /// 0..1: how strongly the mix is running.
  final Animation<double> live;

  /// 0..1, repeating: the phase of the hatching's flow.
  final Animation<double> flow;

  /// What a painter listens to so it repaints without a rebuild.
  Listenable get repaint => Listenable.merge(<Listenable>[reveal, live, flow]);

  @override
  bool operator ==(Object other) =>
      other is SeekZoneFrame &&
      other.zone == zone &&
      identical(other.reveal, reveal) &&
      identical(other.live, live) &&
      identical(other.flow, flow);

  @override
  int get hashCode => Object.hash(zone, reveal, live, flow);
}

String _clock(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// The zone for [u] on a bar for a song of [totalMs], or null when the engine
/// has planned nothing for THIS song. The length check keeps a plan made for
/// another song (or another cut of it) off this bar.
SeekZone? seekZoneFor(
  UpcomingMix? u,
  int totalMs, {
  required Color mixColor,
}) {
  if (u == null || u.isNone || totalMs <= 0) return null;
  if ((u.durationMs - totalMs).abs() > 1500) return null;
  final from = (u.startAtMs / totalMs).clamp(0.0, 1.0);
  final to = (u.endAtMs / totalMs).clamp(0.0, 1.0);
  if (to <= from) return null;
  return SeekZone(
    from: from,
    to: to,
    color: mixColor,
    mix: u.isMix,
    label: u.isMix
        ? 'AutoMix begins at ${_clock(u.startAtMs)}'
        : 'Crossfade begins at ${_clock(u.startAtMs)}',
  );
}

/// Owns the zone's animations and tells [builder] what to draw.
///
/// It listens to the engine's two notifiers itself and rebuilds only when the
/// ZONE changes (a song starting, the mix ending) - not on the 30 ms ticks of a
/// running mix, which move nothing the painters do not already animate.
class SeekZoneHost extends StatefulWidget {
  const SeekZoneHost({
    super.key,
    required this.upcoming,
    required this.ui,
    required this.totalMs,
    required this.mixColor,
    required this.builder,
  });

  final ValueListenable<UpcomingMix?> upcoming;
  final ValueListenable<TransitionUiState> ui;

  /// The playing song's length, ms.
  final int totalMs;
  final Color mixColor;
  final Widget Function(BuildContext context, SeekZoneFrame frame) builder;

  @override
  State<SeekZoneHost> createState() => _SeekZoneHostState();
}

class _SeekZoneHostState extends State<SeekZoneHost>
    with TickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    reverseDuration: const Duration(milliseconds: 240),
  );
  late final AnimationController _live = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 300),
  );
  late final AnimationController _flow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  late final Animation<double> _revealCurve =
      CurvedAnimation(parent: _reveal, curve: Curves.easeOutCubic);

  /// The zone being drawn - kept while it is dissolving after it is withdrawn.
  SeekZone? _shown;
  bool _wanted = false;

  @override
  void initState() {
    super.initState();
    widget.upcoming.addListener(_sync);
    widget.ui.addListener(_sync);
    _reveal.addStatusListener(_revealStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SeekZoneHost old) {
    super.didUpdateWidget(old);
    if (old.upcoming != widget.upcoming) {
      old.upcoming.removeListener(_sync);
      widget.upcoming.addListener(_sync);
    }
    if (old.ui != widget.ui) {
      old.ui.removeListener(_sync);
      widget.ui.addListener(_sync);
    }
    _sync();
  }

  @override
  void dispose() {
    widget.upcoming.removeListener(_sync);
    widget.ui.removeListener(_sync);
    _reveal.dispose();
    _live.dispose();
    _flow.dispose();
    super.dispose();
  }

  void _revealStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_wanted && _shown != null) {
      setState(() => _shown = null);
    }
  }

  void _sync() {
    if (!mounted) return;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final zone = seekZoneFor(widget.upcoming.value, widget.totalMs,
        mixColor: widget.mixColor);
    final s = widget.ui.value;
    final running =
        zone != null && s.phase == TransitionPhase.fading && !s.handedOff;

    _wanted = zone != null;
    if (zone != null) {
      if (_shown != zone) setState(() => _shown = zone);
      if (reduce) {
        _reveal.value = 1.0;
      } else if (_reveal.status != AnimationStatus.forward &&
          _reveal.value < 1.0) {
        _reveal.forward();
      }
    } else if (_shown != null) {
      if (reduce) {
        _reveal.value = 0.0;
      } else if (_reveal.status != AnimationStatus.reverse &&
          _reveal.value > 0.0) {
        _reveal.reverse();
      }
    }

    if (running) {
      if (reduce) {
        _live.value = 1.0;
      } else {
        _live.forward();
        if (!_flow.isAnimating) _flow.repeat();
      }
    } else {
      if (reduce) {
        _live.value = 0.0;
      } else {
        _live.reverse();
      }
      if (_flow.isAnimating) _flow.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      SeekZoneFrame(
        zone: _shown,
        reveal: _revealCurve,
        live: _live,
        flow: _flow,
      ),
    );
  }
}

/// The painting, shared by the player's capsule scrubber and the mini player's
/// hairline so they cannot disagree about what a zone looks like.
class SeekZonePaint {
  const SeekZonePaint._();

  /// Narrower than this, a zone is not visible; it is widened to it, ending at
  /// the zone's end.
  static const double minWidth = 10.0;

  /// Hatching spacing along the bar, px.
  static const double hatchSpacing = 4.5;

  /// [x1, x2] of the whole zone and [xr] how far the sweep has got.
  static ({double x1, double x2, double xr}) geometry(
      Rect track, SeekZone z, double reveal) {
    final w = track.width;
    var x2 = track.left + z.to * w;
    var x1 = track.left + z.from * w;
    if (x2 - x1 < minWidth) x1 = x2 - minWidth;
    if (x1 < track.left) {
      x1 = track.left;
      x2 = x1 + minWidth;
    }
    final xr = x1 + (x2 - x1) * reveal.clamp(0.0, 1.0);
    return (x1: x1, x2: x2, xr: xr);
  }

  /// The tint and the hatching. Paint this after the empty track and BEFORE the
  /// played fill, inside a clip of the track's shape.
  static void under(Canvas canvas, Rect track, SeekZoneFrame f) {
    final z = f.zone;
    final reveal = f.reveal.value;
    if (z == null || reveal <= 0.0) return;
    final g = geometry(track, z, reveal);
    if (g.xr <= g.x1) return;

    final live = f.live.value;
    final color = z.mix ? z.color : Colors.white;
    final peak = (z.mix ? 0.36 : 0.20) + live * (z.mix ? 0.30 : 0.14);

    // The veil: transparent where the zone begins, full by its middle, so it
    // reads as a stretch that is entered, not a block that is stuck on.
    final tint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(g.x1, 0),
        Offset(g.xr, 0),
        <Color>[color.withValues(alpha: 0.0), color.withValues(alpha: peak)],
        const <double>[0.0, 0.5],
      );
    final rect = Rect.fromLTRB(g.x1, track.top, g.xr, track.bottom);
    canvas.drawRect(rect, tint);

    // Hatching: AutoMix only, and only on a bar tall enough to carry it.
    if (z.mix && track.height >= 5.0) {
      canvas.save();
      canvas.clipRect(rect);
      final alpha = (0.10 + 0.16 * live) * reveal;
      final line = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      final h = track.height;
      // Flows toward the end of the song while the mix runs.
      final phase = f.flow.value * hatchSpacing;
      for (var x = g.x1 - h + phase - hatchSpacing; x < g.xr; x += hatchSpacing) {
        canvas.drawLine(Offset(x, track.bottom), Offset(x + h, track.top), line);
      }
      canvas.restore();
    }
  }

  /// The paint for the PLAYED fill: [fillColor] up to the zone, then dyed across
  /// it. One gradient over the whole bar, so the fill stays one continuous
  /// shape and only its colour changes.
  ///
  /// AutoMix: the fill drifts to the accent (the next song arriving). A
  /// crossfade: the fill thins out (this one leaving).
  static Paint fillPaint(Rect track, SeekZoneFrame f, Color fillColor) {
    final paint = Paint()
      ..color = fillColor
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    final z = f.zone;
    final reveal = f.reveal.value;
    if (z == null || reveal <= 0.0 || track.width <= 0) return paint;
    final g = geometry(track, z, 1.0);
    final target = z.mix ? z.color : fillColor.withValues(alpha: 0.38);
    final end = Color.lerp(fillColor, target, reveal)!;
    final w = track.width;
    paint.shader = ui.Gradient.linear(
      Offset(track.left, 0),
      Offset(track.right, 0),
      <Color>[fillColor, fillColor, end],
      <double>[0.0, (g.x1 - track.left) / w, (g.x2 - track.left) / w],
    );
    return paint;
  }
}