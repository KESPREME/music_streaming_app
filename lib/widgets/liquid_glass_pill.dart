import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart'
    show LiquidGlassFlex, LiquidGlassTouch, liquidGlassSpringStep;

import '../design/glass/lens_surface.dart';

// Shared liquid-glass bottom controls for Now Playing and Queue.
//
// BitChord parity: one joined capsule with a sliding white thumb, dividers
// that hide next to the active segment, lyrics + queue as side buttons
// (the shared app `GlassCircleButton`, not here).
//
// Both glass dependencies do real work in this file:
//  * shell: `LiquidLens` (liquid_glass_easy) - live backdrop refraction on
//    Impeller, frosted fallback on Skia. Works standalone, no view/scope
//    setup needed. Children are lens-safe (icons + thumb over transparency;
//    no Material ink surfaces inside - segments use GestureDetector).
//  * thumb physics: `liquidGlassSpringStep` (liquid_glass_easy) - the same
//    sub-stepped spring integrator behind the package's own tab-bar pill,
//    driven here by a Ticker that runs ONLY while the thumb is travelling
//    and parks the moment it settles. Zero cost at rest; retargets
//    mid-flight on rapid taps instead of restarting like a tween.
//  * press physics: 90ms scale-down (house pattern, matches
//    SearchPillPressable/SquishOnPress language).
//
// Battery rules: one lens per bar (never per segment), never animate sigma,
// ticker stops on settle, `disableAnimations` jumps instead of springing.

/// One tappable segment inside [LiquidGlassSegmented].
class GlassSegment {
  final Widget icon;
  final String semanticLabel;
  final bool isActive;
  final VoidCallback onTap;

  const GlassSegment({
    required this.icon,
    required this.semanticLabel,
    required this.isActive,
    required this.onTap,
  });
}

/// The three queue-control segments (shuffle | repeat | autoplay) as pure
/// data. Both the standalone queue sheet and the persistent Now Playing bar
/// build from this one helper so the two pills can never drift apart.
/// Repeat cycles off-all-one on its single segment; repeat-one shows "1".
List<GlassSegment> queueControlSegments({
  required bool shuffleActive,
  required bool repeatActive,
  required bool repeatOne,
  required bool autoplayActive,
  required VoidCallback onShuffle,
  required VoidCallback onRepeat,
  required VoidCallback onAutoplay,
}) {
  const inactive = Color(0xCCFFFFFF);
  return [
    GlassSegment(
      semanticLabel: 'Shuffle',
      isActive: shuffleActive,
      onTap: onShuffle,
      icon: Icon(
        Icons.shuffle_rounded,
        size: 20,
        color: shuffleActive ? Colors.black : inactive,
      ),
    ),
    GlassSegment(
      semanticLabel: 'Repeat',
      isActive: repeatActive,
      onTap: onRepeat,
      icon: repeatOne
          ? Text(
              '1',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            )
          : Icon(
              Icons.repeat_rounded,
              size: 20,
              color: repeatActive ? Colors.black : inactive,
            ),
    ),
    GlassSegment(
      semanticLabel: 'Autoplay',
      isActive: autoplayActive,
      onTap: onAutoplay,
      icon: Icon(
        Icons.all_inclusive_rounded,
        size: 20,
        color: autoplayActive ? Colors.black : inactive,
      ),
    ),
  ];
}

/// A glass capsule with a spring-driven sliding thumb. Equal-flex segments
/// never change width, so glyphs never slide when selection moves.
class LiquidGlassSegmented extends StatelessWidget {
  final List<GlassSegment> segments;
  final double height;

  const LiquidGlassSegmented({
    super.key,
    required this.segments,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final n = segments.length;
    final activeIndex = segments.indexWhere((s) => s.isActive);
    // Whole-pill jiggle (Explore top-pill recipe): press compresses fast,
    // release springs back THROUGH resting on easeOutBack - that overshoot
    // past 1.0 is the visible wobble. Listener is purely passive, so the
    // segment taps inside never compete for the gesture.
    return _JiggleWrap(
      child: LiquidLens(
        tier: GlassTier.floating,
        // Cranked past the package defaults (3%/2% read as nothing): the
        // body visibly compresses on press, pops on tap, swells while
        // held, and wobbles back on release. Still the package's own
        // ticker, running only while a finger is down.
        touch: const LiquidGlassTouch.flexing(
          LiquidGlassFlex(
            stretch: 20,
            holdScale: 0.08,
            tapScale: 0.06,
          ),
        ),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              if (activeIndex >= 0 && n > 0)
                _SpringThumb(
                  position: activeIndex.toDouble(),
                  count: n,
                  height: height,
                ),
              Row(
                children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) _PillDivider(height: height - 12),
                    Expanded(
                      child: _PressableSegment(segment: segments[i]),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill-level jiggle wrapper (Explore `_PillIconButton` language): fast
/// compress on finger-down, overshooting spring-back on release. No loops,
/// no tickers of its own - two one-shot implicit tweens.
class _JiggleWrap extends StatefulWidget {
  final Widget child;

  const _JiggleWrap({required this.child});

  @override
  State<_JiggleWrap> createState() => _JiggleWrapState();
}

class _JiggleWrapState extends State<_JiggleWrap> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: Duration(milliseconds: _pressed ? 140 : 280),
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Full-height separator, always drawn: 1px white, top to bottom, exactly
/// like BitChord's own PillDivider (no hide-next-to-active, no dark
/// variant - a dark line on the white thumb read as a crack, not a cut).
/// Slightly stronger than theirs (0.28 vs 0.20) per the bolder ask; over
/// the white thumb it softens to a sheen instead of dirt.
class _PillDivider extends StatelessWidget {
  final double height;

  const _PillDivider({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      color: Colors.white.withValues(alpha: 0.28),
    );
  }
}

/// Segment with press physics: quick scale-down on finger-down, release on
/// up. Haptics stay with the caller's onTap (single source).
class _PressableSegment extends StatefulWidget {
  final GlassSegment segment;

  const _PressableSegment({required this.segment});

  @override
  State<_PressableSegment> createState() => _PressableSegmentState();
}

class _PressableSegmentState extends State<_PressableSegment> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.segment.semanticLabel,
      button: true,
      selected: widget.segment.isActive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.segment.onTap,
        child: AnimatedScale(
          // Explore pill recipe: harder press, overshoot-capable release.
          scale: _pressed ? 0.86 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: Container(
            alignment: Alignment.center,
            child: widget.segment.icon,
          ),
        ),
      ),
    );
  }
}

/// The sliding thumb, driven by the package spring integrator instead of a
/// tween: position AND velocity carry across retargets, so hammering
/// segments mid-flight bends the trajectory instead of snapping it.
/// The ticker only runs while travelling and stops on settle.
class _SpringThumb extends StatefulWidget {
  /// Target as a fractional segment index.
  final double position;
  final int count;
  final double height;

  const _SpringThumb({
    required this.position,
    required this.count,
    required this.height,
  });

  @override
  State<_SpringThumb> createState() => _SpringThumbState();
}

class _SpringThumbState extends State<_SpringThumb>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late double _x;
  double _v = 0;
  Duration? _last;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _x = widget.position;
    _ticker = createTicker(_step);
  }

  @override
  void didUpdateWidget(_SpringThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position == oldWidget.position) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _x = widget.position;
      _v = 0;
      _stop();
      return;
    }
    _last = null;
    if (!_running) {
      _running = true;
      _ticker.start();
    }
  }

  void _step(Duration elapsed) {
    final dt = _last == null
        ? 1 / 120.0
        : (elapsed - _last!).inMicroseconds / 1e6;
    _last = elapsed;
    final (nx, nv) = liquidGlassSpringStep(
      x: _x,
      vel: _v,
      target: widget.position,
      dt: dt.clamp(0.0, 0.05),
    );
    _x = nx;
    _v = nv;
    if ((_x - widget.position).abs() < 0.0005 && _v.abs() < 0.05) {
      _x = widget.position;
      _v = 0;
      _stop();
    }
    setState(() {});
  }

  void _stop() {
    if (_running) {
      _running = false;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    return Align(
      alignment: n == 1
          ? Alignment.center
          : Alignment(-1.0 + 2.0 * _x / (n - 1), 0),
      child: FractionallySizedBox(
        widthFactor: 1.0 / n,
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(widget.height / 2 - 3),
          ),
        ),
      ),
    );
  }
}
