import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Liquid-glass toggle. Track is a frosted pill; when ON an ink-drop
/// radial accent bloom diffuses from the thumb side. Thumb is a white
/// glass circle that slides with a spring.
///
/// Touch: the thumb stretches along the track while the finger is down (the
/// way an iOS switch does) and springs back past its rest width on release, so
/// the control is felt before it moves. The stretch grows toward the track's
/// middle - the thumb stays pinned to the edge it sits on. Reduce motion: the
/// thumb stays its size; the tap still toggles.
class LiquidSwitch extends StatefulWidget {
  const LiquidSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  static const double _trackHeight = 32;
  static const double _trackBorder = 0.8;
  static const double _inset = 3;

  /// The room the track leaves the thumb: its height less the hairline border
  /// and the inset on both sides (24.4). A 26dp thumb never fitted - the track
  /// clamped it to this - so the thumb has always been this circle, and it stays
  /// one at rest.
  static const double restThumb = _trackHeight - 2 * _trackBorder - 2 * _inset;

  /// Thumb width while held. The height never changes: a thumb that grew taller
  /// too would stop reading as a thumb and start reading as a pill.
  static const double heldThumb = restThumb + 7;

  @override
  State<LiquidSwitch> createState() => _LiquidSwitchState();
}

class _LiquidSwitchState extends State<LiquidSwitch> {
  bool _held = false;

  void _hold(bool held) {
    if (_held == held || !mounted) return;
    setState(() => _held = held);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final accent = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final stretched = _held && widget.enabled && !still;

    return GestureDetector(
      onTap: widget.enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onChanged(!value);
            }
          : null,
      // Down / up / cancel only drive the thumb; they add no competing
      // recognizer, so a scroll that starts on the switch still wins and cancels.
      onTapDown: widget.enabled ? (_) => _hold(true) : null,
      onTapUp: (_) => _hold(false),
      onTapCancel: () => _hold(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 52,
        height: LiquidSwitch._trackHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          // Ink bloom when ON
          gradient: value
              ? RadialGradient(
                  center: const Alignment(0.55, 0),
                  radius: 1.4,
                  colors: [
                    accent.withValues(alpha: isDark ? 0.32 : 0.22),
                    accent.withValues(alpha: 0.10),
                    Colors.white.withValues(alpha: isDark ? 0.06 : 0.08),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                )
              : null,
          color: value
              ? null
              : (isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.06)),
          border: Border.all(
            color: value
                ? accent.withValues(alpha: 0.35)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: 0.10)),
            width: LiquidSwitch._trackBorder,
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.20),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: AnimatedContainer(
                // Out quickly on touch, back with a hair of overshoot: the same
                // beat as the pills, at a switch's scale.
                duration: Duration(milliseconds: stretched ? 120 : 260),
                curve: stretched ? Curves.easeOutCubic : Curves.easeOutBack,
                margin: const EdgeInsets.all(LiquidSwitch._inset),
                width: stretched ? LiquidSwitch.heldThumb : LiquidSwitch.restThumb,
                height: LiquidSwitch.restThumb,
                decoration: BoxDecoration(
                  color: value
                      ? Colors.white
                      : (isDark ? Colors.white.withValues(alpha: 0.9) : Colors.white),
                  // A circle at rest; a stadium while it stretches. The radius is
                  // fixed rather than switching shape so the widening animates.
                  borderRadius: BorderRadius.circular(LiquidSwitch.restThumb / 2),
                  border: Border.all(
                    color: value
                        ? accent.withValues(alpha: 0.25)
                        : Colors.transparent,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
