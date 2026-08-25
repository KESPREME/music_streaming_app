import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_surface.dart';

/// Floating liquid-glass navigation pill.
///
/// Identity: chrome-tier shader glass, accent glow on the active tab with a
/// spring squish on press. Accent always comes from the live theme.
///
/// Signature interaction: long-press any tab and the glow pill "melts" into a
/// droplet that follows your finger across tabs; release to merge it into the
/// hovered tab (the glow pill springs to the new index — the merge).
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
  bool _dropletMode = false;
  double _dropletX = 0;
  double _dropletOrigin = 0;
  int _hoverIndex = 0;

  double _itemWidth = 0;

  void _startDroplet(int index, LongPressStartDetails d) {
    HapticFeedback.mediumImpact();
    setState(() {
      _dropletMode = true;
      _hoverIndex = index;
      _dropletOrigin = index * _itemWidth + d.localPosition.dx;
      _dropletX = _dropletOrigin;
    });
  }

  void _moveDroplet(LongPressMoveUpdateDetails d) {
    final max = _itemWidth * widget.items.length;
    final x = (_dropletOrigin + d.offsetFromOrigin.dx).clamp(0.0, max);
    final hover = (x / _itemWidth).floor().clamp(0, widget.items.length - 1);
    if (hover != _hoverIndex) HapticFeedback.selectionClick();
    setState(() {
      _dropletX = x;
      _hoverIndex = hover;
    });
  }

  void _endDroplet(LongPressEndDetails d) {
    final target = _hoverIndex;
    HapticFeedback.lightImpact();
    setState(() => _dropletMode = false);
    if (target != widget.currentIndex) {
      widget.onTap(target);
    }
  }

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
              _itemWidth = constraints.maxWidth / itemCount;
              return Stack(
                children: [
                  // Animated accent glow pill (hidden while the droplet is out)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutBack,
                    left: widget.currentIndex * _itemWidth +
                        (_itemWidth - 58) / 2,
                    top: (66 - 46) / 2,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: _dropletMode ? 0.0 : 1.0,
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
                  ),
                  // Droplet (long-press melt)
                  if (_dropletMode)
                    Positioned(
                      left: (_dropletX - 32).clamp(0.0,
                          _itemWidth * itemCount - 64),
                      top: (66 - 52) / 2,
                      child: Container(
                        width: 64,
                        height: 52,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.55),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.45),
                              blurRadius: 24,
                              spreadRadius: 2,
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
                      final isHovered = _dropletMode && _hoverIndex == index;

                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) => setState(() => _pressedIndex = index),
                          onTapCancel: () => setState(() => _pressedIndex = null),
                          onTapUp: (_) {
                            setState(() => _pressedIndex = null);
                            widget.onTap(index);
                          },
                          onLongPressStart: (d) => _startDroplet(index, d),
                          onLongPressMoveUpdate: _moveDroplet,
                          onLongPressEnd: _endDroplet,
                          child: AnimatedScale(
                            scale: isHovered
                                ? 1.18
                                : isPressed
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
                                    color: isSelected || isHovered
                                        ? accent
                                        : Colors.white.withValues(alpha: 0.55),
                                    size: 24,
                                  ),
                                  child: isSelected || isHovered
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
                                    color: isSelected || isHovered
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
