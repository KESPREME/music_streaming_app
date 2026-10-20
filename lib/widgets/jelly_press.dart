// lib/widgets/jelly_press.dart
//
// The one touch language of the app's pills, circles, chips and toggles
// (plan: docs/PLAN-pill-physics.md). Wrap a control in [JellyPress] and it
// flexes under the finger the way the bottom bar's glass does: it compresses on
// press, stays compressed while held, leans and stretches toward a dragging
// finger with its volume kept, and springs back past rest on release.
//
// The numbers live in design/tokens/jelly.dart and are measured by tests.
//
// RULES THIS WIDGET KEEPS
//   * It never joins a gesture arena for movement. The physics listens with a
//     passive Listener, so a Dismissible, a PageView, a horizontal rail or the
//     mini player's pull-up are never fought over. Only tap and long-press use
//     a GestureDetector.
//   * The Listener sits OUTSIDE the transform, so the finger's coordinates do
//     not wobble with the body they are moving.
//   * The child is built once. A press repaints a transform and nothing else.
//   * ONE haptic per touch, on confirm. Sites that play their own pass
//     [JellyHaptic.none].
//   * Reduce motion: no transform, no ticker; the tap still works.
//   * No semantics are added. The call site keeps its own labels (the tests
//     find controls by them); [semanticLabel] is for controls that had none.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../design/tokens/jelly.dart';

export '../design/tokens/jelly.dart' show JellyHaptic, JellyProfile;

class JellyPress extends StatefulWidget {
  const JellyPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.profile = JellyProfile.pill,
    this.haptic = JellyHaptic.selection,
    this.enabled = true,
    this.borderRadius = 0,
    this.behavior = HitTestBehavior.opaque,
    this.semanticLabel,
  })  : passive = false,
        quietInk = false;

  /// The body flexes; the tap stays the child's. For a control that already owns
  /// its gesture, semantics and tooltip (an [IconButton], an [InkWell] row) and
  /// should keep them untouched - the tests and screen readers find it as they
  /// always did. It listens to raw pointers only, so it adds nothing to the
  /// gesture arena and cannot swallow or steal a tap. No haptic: the child's own
  /// handler owns that.
  ///
  /// [quietInk] switches the Material splash and press-overlay off for the child
  /// subtree: the body's give IS the feedback, and the ink on top of it reads as
  /// two answers to one touch.
  const JellyPress.passive({
    super.key,
    required this.child,
    this.profile = JellyProfile.icon,
    this.enabled = true,
    this.quietInk = false,
  })  : onTap = null,
        onLongPress = null,
        haptic = JellyHaptic.none,
        borderRadius = 0,
        behavior = HitTestBehavior.opaque,
        semanticLabel = null,
        passive = true;

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final JellyProfile profile;
  final JellyHaptic haptic;
  final bool enabled;

  /// The shape the glow is clipped to (profiles with `glow`). A circle is
  /// half its size; 0 is a rectangle.
  final double borderRadius;
  final HitTestBehavior behavior;
  final String? semanticLabel;

  /// See [JellyPress.passive].
  final bool passive;
  final bool quietInk;

  @override
  State<JellyPress> createState() => _JellyPressState();
}

class _JellyPressState extends State<JellyPress> with SingleTickerProviderStateMixin {
  late JellySpring _spring = JellySpring(widget.profile);
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  Offset _pointer = Offset.zero;
  bool _still = false;
  bool _tracking = false;

  /// The scrollables above this control, watched while a finger is down: a scroll
  /// starting means the touch was a scroll, not a press. (A tap recogniser's
  /// cancel cannot tell that from a deliberate drag across the control, and a
  /// drag across it is exactly what the body is meant to follow.)
  final List<ValueNotifier<bool>> _scrolling = [];

  bool get _live => widget.enabled && (widget.passive || widget.onTap != null || widget.onLongPress != null);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void didUpdateWidget(JellyPress old) {
    super.didUpdateWidget(old);
    if (old.profile != widget.profile) {
      _spring = JellySpring(widget.profile);
      _tracking = false;
    }
    if (!_live && _tracking) _letGo();
  }

  @override
  void dispose() {
    _unwatchScrolls();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _watchScrolls() {
    _unwatchScrolls();
    BuildContext at = context;
    for (var i = 0; i < 4; i++) {
      final s = Scrollable.maybeOf(at);
      if (s == null) break;
      final n = s.position.isScrollingNotifier;
      n.addListener(_onScrollingChanged);
      _scrolling.add(n);
      at = s.context;
    }
  }

  void _unwatchScrolls() {
    for (final n in _scrolling) {
      n.removeListener(_onScrollingChanged);
    }
    _scrolling.clear();
  }

  void _onScrollingChanged() {
    if (_scrolling.any((n) => n.value)) _letGo();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final moving = _spring.step(dt);
    _frame.value++;
    if (!moving && !_spring.isDown && _ticker.isActive) _ticker.stop();
  }

  void _wake() {
    if (_ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  void _down(PointerDownEvent e) {
    if (!_live || _still) return;
    _tracking = true;
    _pointer = e.localPosition;
    _watchScrolls();
    _spring.press();
    _spring.dragTo(_pointer, context.size ?? Size.zero);
    _wake();
  }

  void _move(PointerMoveEvent e) {
    if (!_tracking) return;
    _pointer = e.localPosition;
    final size = context.size ?? Size.zero;
    // Left the control (plus a thumb's worth): the touch is no longer a press
    // on it. Same as dragging a finger off a button on any phone.
    if (!(Offset.zero & size).inflate(24).contains(_pointer)) {
      _letGo();
      return;
    }
    _spring.dragTo(_pointer, size);
    _wake();
  }

  void _letGo() {
    if (!_tracking) return;
    _tracking = false;
    _unwatchScrolls();
    _spring.release();
    _wake();
  }

  void _fireHaptic() {
    switch (widget.haptic) {
      case JellyHaptic.none:
        break;
      case JellyHaptic.selection:
        HapticFeedback.selectionClick();
      case JellyHaptic.light:
        HapticFeedback.lightImpact();
      case JellyHaptic.medium:
        HapticFeedback.mediumImpact();
    }
  }

  void _tap() {
    // On confirm, before the callback: the buzz belongs to the touch, the
    // callback may navigate away.
    _fireHaptic();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.quietInk ? _QuietInk(child: widget.child) : widget.child;
    if (!_live) return body;

    final profile = widget.profile;
    final animated = AnimatedBuilder(
      animation: _frame,
      child: profile.glow ? null : body,
      builder: (context, cached) {
        final s = _spring;
        final matrix = Matrix4.identity()
          ..translateByDouble(s.dx, s.dy, 0, 1)
          ..scaleByDouble(s.scaleX, s.scaleY, 1, 1);
        Widget child = cached ?? body;
        if (profile.glow) {
          child = Stack(
            fit: StackFit.passthrough,
            children: [
              body,
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    child: CustomPaint(painter: _GlowPainter(depth: s.depth, at: _pointer)),
                  ),
                ),
              ),
            ],
          );
        }
        return Transform(transform: matrix, alignment: Alignment.center, child: child);
      },
    );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (_) => _letGo(),
      onPointerCancel: (_) => _letGo(),
      child: widget.passive
          ? animated
          : GestureDetector(
              behavior: widget.behavior,
              onTap: widget.onTap == null ? null : _tap,
              onLongPress: widget.onLongPress,
              child: animated,
            ),
    );
  }
}

/// Material ink off for a subtree: no splash, no press overlay. Only what the
/// jelly body replaces - hover and focus keep their normal look.
class _QuietInk extends StatelessWidget {
  const _QuietInk({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final quiet = (base.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
    );
    return Theme(
      data: base.copyWith(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        iconButtonTheme: IconButtonThemeData(style: quiet),
      ),
      child: child,
    );
  }
}

/// The light that blooms under the fingertip on floating glass: strongest where
/// the finger is, fading with the press depth. Apple: "the material illuminates
/// from within ... starting right under your fingertips".
class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.depth, required this.at});

  final double depth;
  final Offset at;

  @override
  void paint(Canvas canvas, Size size) {
    if (depth <= 0.01) return;
    final r = size.longestSide * 0.95;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.26 * depth),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: at, radius: r));
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.depth != depth || old.at != at;
}
