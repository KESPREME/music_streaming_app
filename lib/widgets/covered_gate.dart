// lib/widgets/covered_gate.dart
//
// Stops spending frames on whatever the open player is sitting on top of.
//
// WHY THIS EXISTS
//
// The player card is opaque and full-screen. At rest, everything under it - the
// page, the tab bar, the mini pill - is invisible, yet it kept being drawn:
// Impeller has no raster cache, so a retained layer still costs a replay every
// frame the scene is redrawn, and the player redraws at display rate while a
// word-synced lyric sweeps. Tickers under the card kept running as well (Explore
// drifts a mesh and decodes a video under it).
//
// WHAT IT DOES
//
//   * [CoveredGate] mutes tickers and skips painting and hit-testing its child
//     while covered. Layout is NOT touched: the child keeps its size and its
//     constraints, so nothing re-lays out when the gate flips (the glass tab bar
//     in particular must never be re-measured mid-flight - see
//     liquid_glass_nav_bar.dart).
//   * [CoveredScope] publishes the same flag to descendants that own work no
//     widget-level gate can stop (a video decoder, a position subscription).
//
// WHEN IT FLIPS (decided by the overlay, not here)
//
//   covered  <- the panel has been fully open AND still for a short settle delay
//   uncovered <- the first frame the panel moves, in the same frame
//
// The asymmetry is the point: closing must show the page the instant the card
// starts to leave, while a quick open/close/open must not thrash the page.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Decides when the open player covers the page: [value] is true once the panel
/// has been fully open and still for [delay], and false again in the very frame
/// it starts to move.
///
/// Driven by the panel itself rather than by the provider's "expanded" intent,
/// which flips at the halfway point of a flight; the panel is the truth about
/// what is on screen. The delay is hysteresis: open -> close -> open (a fumbled
/// tap, a back gesture) never switches the page off and straight back on.
class PanelCover extends ValueNotifier<bool> {
  PanelCover(
    this._panel, {
    this.delay = const Duration(milliseconds: 250),
    bool Function()? isFrozen,
  })  : _isFrozen = isFrozen,
        super(false) {
    _panel.addListener(sync);
    _panel.addStatusListener(_onStatus);
  }

  final AnimationController _panel;
  final Duration delay;

  /// True while something outside is parking the panel on purpose (the visual
  /// test harness): the page must stay drawn so a frame can be compared.
  final bool Function()? _isFrozen;

  Timer? _timer;
  bool _disposed = false;

  bool get _settledOpen =>
      !(_isFrozen?.call() ?? false) &&
      _panel.value >= 1.0 &&
      !_panel.isAnimating;

  void _onStatus(AnimationStatus _) => sync();

  /// Re-evaluates. Cheap enough to call on every tick of the panel.
  void sync() {
    if (_disposed) return;
    if (!_settledOpen) {
      _timer?.cancel();
      _timer = null;
      if (value) value = false;
      return;
    }
    if (value || _timer != null) return;
    _timer = Timer(delay, () {
      _timer = null;
      if (_disposed || !_settledOpen) return;
      value = true;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _panel.removeListener(sync);
    _panel.removeStatusListener(_onStatus);
    super.dispose();
  }
}

/// Publishes "the open player is covering the page" to descendants.
class CoveredScope extends InheritedNotifier<ValueListenable<bool>> {
  const CoveredScope({
    super.key,
    required ValueListenable<bool> covered,
    required super.child,
  }) : super(notifier: covered);

  /// Whether the player covers this subtree, subscribing to changes.
  ///
  /// False when there is no scope (tests, a widget used outside the overlay), so
  /// callers behave exactly as they did before the gate existed.
  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CoveredScope>();
    return scope?.notifier?.value ?? false;
  }

  /// The current flag without subscribing.
  static bool peek(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<CoveredScope>();
    return scope?.notifier?.value ?? false;
  }
}

/// Mutes tickers and skips paint + hit-testing under [child] while [covered].
///
/// The child stays mounted, laid out and alive; only the work that is invisible
/// is skipped. Painting resumes from the child's retained layer, so uncovering
/// costs a composite, not a repaint of the page.
class CoveredGate extends StatelessWidget {
  const CoveredGate({super.key, required this.covered, required this.child});

  final ValueListenable<bool> covered;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: covered,
      // Handed through unchanged so a flip rebuilds this wrapper and never the
      // subtree.
      child: child,
      builder: (context, isCovered, page) => TickerMode(
        enabled: !isCovered,
        child: _PaintGate(covered: isCovered, child: page),
      ),
    );
  }
}

class _PaintGate extends SingleChildRenderObjectWidget {
  const _PaintGate({required this.covered, super.child});

  final bool covered;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPaintGate(covered: covered);

  @override
  void updateRenderObject(BuildContext context, RenderPaintGate renderObject) {
    renderObject.covered = covered;
  }
}

/// A proxy box that keeps its child's layout and drops its paint and hits.
///
/// Not `Offstage`: that also collapses the child's size, which would re-lay out
/// everything under it on every flip.
@visibleForTesting
class RenderPaintGate extends RenderProxyBox {
  RenderPaintGate({required bool covered}) : _covered = covered;

  bool _covered;
  bool get covered => _covered;
  set covered(bool value) {
    if (value == _covered) return;
    _covered = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_covered) return;
    super.paint(context, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_covered) return false;
    return super.hitTest(result, position: position);
  }
}
