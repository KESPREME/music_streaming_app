import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// Floating liquid-glass navigation pill.
///
/// Identity: chrome-tier shader glass, accent glow on the active tab with a
/// spring squish on press. Accent always comes from the live theme.
class GlassNavBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavigationBarItem> items;

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar> {
  int? _pressedIndex;

  @override
  Widget build(BuildContext context) {
    final itemCount = widget.items.length;
    final accent = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
      child: GlassSurface(
        tier: GlassTier.chrome,
        borderRadius: 33,
        child: SizedBox(
          height: 66,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / itemCount;
              return Stack(
                children: [
                  // Animated accent glow pill
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutBack,
                    left: widget.currentIndex * itemWidth +
                        (itemWidth - 58) / 2,
                    top: (66 - 46) / 2,
                    child: Container(
                      width: 58,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(23),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.25),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: widget.items.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final isSelected = index == widget.currentIndex;
                      final isPressed = _pressedIndex == index;

                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) => setState(() => _pressedIndex = index),
                          onTapCancel: () => setState(() => _pressedIndex = null),
                          onTapUp: (_) {
                            setState(() => _pressedIndex = null);
                            widget.onTap(index);
                          },
                          child: AnimatedScale(
                            scale: isPressed
                                ? 0.88
                                : isSelected
                                    ? 1.08
                                    : 1.0,
                            duration: Duration(
                                milliseconds: isPressed ? 90 : 220),
                            curve: isPressed
                                ? Curves.easeOut
                                : Curves.easeOutBack,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconTheme(
                                  data: IconThemeData(
                                    color: isSelected
                                        ? accent
                                        : Colors.white.withValues(alpha: 0.55),
                                    size: 24,
                                  ),
                                  child: isSelected
                                      ? item.activeIcon
                                      : item.icon,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.label ?? '',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? accent
                                        : Colors.white.withValues(alpha: 0.55),
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
