// lib/widgets/player_dock.dart
//
// Where the open player's artwork docks into the mini player.
// Plan: docs/PLAN-motion-perf-downloads.md (P3). Behaviour and numbers from
// BitChord's PlayerDock / NowPlayingScreen sleeve (GPLv3; no code copied).
//
// Opening and closing the player reads as one movement: the artwork travels
// between its place in the player and the mini player's cover while the rest
// of the player fades. The two ends live in different subtrees (the cover in
// the nav bar or the floating pill, the artwork inside the player's own
// navigator), so nothing is shared layout. Each end reports itself here and the
// overlay meets them in screen coordinates.
//
// Rules that keep it cheap and legal:
//   * Rects are read from the previous frame's layout during the overlay's
//     build. Nothing here triggers a rebuild.
//   * Hiding the two real artworks while the copy flies is a paint-level gate
//     (markNeedsPaint), so it may be flipped mid-build and costs no layout.
//   * When an end is missing (pill hidden, lyrics or queue open, reduce
//     motion) the overlay keeps its plain slide. Nothing is guessed.

import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// One frame of the artwork's trip, worked out by [dockFrame].
@immutable
class DockFrame {
  const DockFrame({required this.rect, required this.corner, required this.playerAlpha, required this.edgeFade});

  /// Where the travelling artwork is drawn, in global coordinates.
  final Rect rect;
  final double corner;

  /// How opaque the rest of the player is.
  final double playerAlpha;

  /// How much of the hero's soft bottom edge is still shown (1 = as in the
  /// open player, 0 = the cover's hard edge).
  final double edgeFade;
}

/// The share of travel the player has left to go when it is fully faded, so
/// the cover lands on the bar and not on a ghost of the player.
const double kDockFadeLead = 0.15;

/// The artwork at progress [t] (1 open, 0 on the cover).
///
/// It rides the sheet as much as it can without ever passing the cover:
/// `ride` is the cover's distance below the open artwork as a share of the
/// travel, so the artwork follows the finger most of the way and its speed
/// runs out exactly on the cover (tangential landing). Riding all of it sent
/// the artwork below the bar before it climbed back; riding none left it
/// standing still under a finger dragging the player down.
DockFrame dockFrame({
  required double t,
  required Rect mini,
  required Rect open,
  required double travel,
  required double miniCorner,
  required double openCorner,
}) {
  final p = t.clamp(0.0, 1.0);
  final offset = (1 - p) * travel;
  final ride = travel <= 0 ? 0.0 : ((mini.top - open.top) / travel).clamp(0.0, 1.0);
  final target = open.shift(Offset(0, offset * ride));
  return DockFrame(
    rect: Rect.lerp(mini, target, p)!,
    corner: lerpDouble(miniCorner, openCorner, p)!,
    playerAlpha: ((p - kDockFadeLead) / (1 - kDockFadeLead)).clamp(0.0, 1.0),
    edgeFade: p,
  );
}

class PlayerDock extends ChangeNotifier {
  PlayerDock._();

  static final PlayerDock instance = PlayerDock._();

  BuildContext? _mini;
  double _miniCorner = 8;
  BuildContext? _art;
  double _artCorner = 0;
  WidgetBuilder? _sleeve;
  bool _docking = false;

  /// The flight is drawing its own copy: both real artworks stand aside.
  bool get docking => _docking;

  void setDocking(bool value) {
    if (_docking == value) return;
    _docking = value;
    notifyListeners();
  }

  void attachMini(BuildContext context, double corner) {
    _mini = context;
    _miniCorner = corner;
  }

  void detachMini(BuildContext context) {
    if (identical(_mini, context)) _mini = null;
  }

  void attachArt(BuildContext context, {required double corner, required WidgetBuilder sleeve}) {
    _art = context;
    _artCorner = corner;
    _sleeve = sleeve;
  }

  void detachArt(BuildContext context) {
    if (!identical(_art, context)) return;
    _art = null;
    _sleeve = null;
  }

  double get miniCorner => _miniCorner;
  double get artCorner => _artCorner;
  WidgetBuilder? get sleeve => _sleeve;

  /// The mini player's cover on screen (through every transform above it),
  /// as last laid out.
  Rect? miniRect() => _rectOf(_mini);

  /// The player's artwork on screen, as last laid out.
  Rect? artRect() => _rectOf(_art);

  /// Upward pulls on a mini player hosted where the overlay's own drag
  /// handlers do not reach (the nav bar). Set by the overlay.
  void Function(double dy)? onPull;
  void Function(double velocity)? onPullEnd;

  @visibleForTesting
  void debugReset() {
    _mini = null;
    _art = null;
    _sleeve = null;
    _docking = false;
    onPull = null;
    onPullEnd = null;
  }

  static Rect? _rectOf(BuildContext? context) {
    if (context == null) return null;
    final Element element;
    try {
      element = context as Element;
      if (!element.mounted) return null;
    } catch (_) {
      return null;
    }
    final box = element.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final size = box.size;
    if (size.isEmpty) return null;
    return Rect.fromPoints(box.localToGlobal(Offset.zero), box.localToGlobal(size.bottomRight(Offset.zero)));
  }
}

/// Reports [child] as the mini player's cover, and hides it while the
/// player's artwork is flying to or from it.
class DockMiniArt extends StatefulWidget {
  const DockMiniArt({super.key, required this.corner, required this.child});

  final double corner;
  final Widget child;

  @override
  State<DockMiniArt> createState() => _DockMiniArtState();
}

class _DockMiniArtState extends State<DockMiniArt> {
  @override
  void initState() {
    super.initState();
    PlayerDock.instance.attachMini(context, widget.corner);
  }

  @override
  void didUpdateWidget(DockMiniArt old) {
    super.didUpdateWidget(old);
    PlayerDock.instance.attachMini(context, widget.corner);
  }

  @override
  void dispose() {
    PlayerDock.instance.detachMini(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DockGate(child: widget.child);
}

/// Reports [child] as the open player's artwork (while [enabled]) and hides it
/// while its copy flies. [sleeve] builds that copy: the same image, from the
/// same cache entry.
class DockPlayerArt extends StatefulWidget {
  const DockPlayerArt({
    super.key,
    required this.enabled,
    required this.corner,
    required this.sleeve,
    required this.child,
  });

  final bool enabled;
  final double corner;
  final WidgetBuilder sleeve;
  final Widget child;

  @override
  State<DockPlayerArt> createState() => _DockPlayerArtState();
}

class _DockPlayerArtState extends State<DockPlayerArt> {
  void _sync() {
    if (widget.enabled) {
      PlayerDock.instance.attachArt(context, corner: widget.corner, sleeve: widget.sleeve);
    } else {
      PlayerDock.instance.detachArt(context);
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(DockPlayerArt old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    PlayerDock.instance.detachArt(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DockGate(off: !widget.enabled, child: widget.child);
}

class _DockGate extends SingleChildRenderObjectWidget {
  const _DockGate({super.child, this.off = false});

  /// Never hide (the artwork is not the one taking part).
  final bool off;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderDockGate(PlayerDock.instance, off);

  @override
  void updateRenderObject(BuildContext context, _RenderDockGate renderObject) => renderObject.off = off;
}

class _RenderDockGate extends RenderProxyBox {
  _RenderDockGate(this._dock, this._off);

  final PlayerDock _dock;
  bool _off;
  set off(bool v) {
    if (v == _off) return;
    _off = v;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _dock.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _dock.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_off && _dock.docking) return;
    super.paint(context, offset);
  }
}
