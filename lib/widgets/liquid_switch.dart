import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Liquid-glass toggle. Track is a frosted pill; when ON an ink-drop
/// radial accent bloom diffuses from the thumb side. Thumb is a white
/// glass circle that slides with a spring.
class LiquidSwitch extends StatelessWidget {
  const LiquidSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onChanged(!value);
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 52,
        height: 32,
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
            width: 0.8,
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
              child: Container(
                margin: const EdgeInsets.all(3),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: value
                      ? Colors.white
                      : (isDark ? Colors.white.withValues(alpha: 0.9) : Colors.white),
                  shape: BoxShape.circle,
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
