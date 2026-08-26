import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_surface.dart';

/// Floating liquid-glass navigation pill (Muzo parity).
///
/// - Selected tab: a glass blob fills the ENTIRE segment; the accent sits
///   inside it as a radial "ink drop in water" diffusion, never a solid fill.
/// - Long-press: the blob melts into a droplet that tracks the finger 1:1,
///   stretches with velocity like real liquid, and merges into the hovered
///   tab on release (spring handoff).
/// - Search morph: with [searchMode] the buttons cross-fade into a live
///   TextField bound to [searchController]; the companion circle flips to a
///   home icon (owned by MainScreen).
class GlassNavBar extends StatefulWidget {
  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.searchMode = false,
    this.searchController,
    this.searchFocusNode,
    this.onSearchSubmitted,
  });

  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavigationBarItem> items;

  final bool searchMode;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String>? onSearchSubmitted;

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar> {
  static const _pillHeight = 64.0;

  // Droplet state.
  bool _dropletMode = false;
  double _dropletX = 0;
  double _dropletOrigin = 0;
  double _lastMoveX = 0;
  Duration _lastMoveTime = Duration.zero;
  double _velocity = 0;
  int _hoverIndex = 0;

  // Merge handoff: while non-null the indicator starts from here and
  // animates to the selected segment.
  double? _mergeFrom;

  double _itemWidth = 0;

  // Ink-drop diffusion - one drop of accent colour blooming in glass.
  static RadialGradient _inkGradient(Color accent, double strength) {
    return RadialGradient(
      colors: [
        accent.withValues(alpha: strength),
        accent.withValues(alpha: strength * 0.35),
        accent.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.55, 1.0],
    );
  }

  void _startDroplet(int index, LongPressStartDetails d) {
    HapticFeedback.mediumImpact();
    final now = DateTime.now();
    setState(() {
      _dropletMode = true;
      _mergeFrom = null;
      _hoverIndex = index;
      _dropletOrigin = index * _itemWidth + d.localPosition.dx;
      _dropletX = _dropletOrigin;
      _lastMoveX = _dropletX;
      _lastMoveTime = Duration(
          milliseconds: now.millisecondsSinceEpoch);
      _velocity = 0;
    });
  }

  void _moveDroplet(LongPressMoveUpdateDetails d) {
    final max = _itemWidth * widget.items.length;
    final x = (_dropletOrigin + d.offsetFromOrigin.dx).clamp(0.0, max);
    final hover = (x / _itemWidth).floor().clamp(0, widget.items.length - 1);
    if (hover != _hoverIndex) HapticFeedback.selectionClick();

    // Instantaneous velocity for the liquid stretch.
    final now = DateTime.now();
    final t = Duration(milliseconds: now.millisecondsSinceEpoch);
    final dt = (t - _lastMoveTime).inMilliseconds / 1000.0;
    if (dt > 0.008) {
      final v = (x - _lastMoveX) / dt;
      _velocity = _velocity * 0.6 + v * 0.4;
      _lastMoveX = x;
      _lastMoveTime = t;
    }

    setState(() {
      _dropletX = x;
      _hoverIndex = hover;
    });
  }

  void _endDroplet(LongPressEndDetails d) {
    final target = _hoverIndex;
    HapticFeedback.lightImpact();
    setState(() {
      _dropletMode = false;
      // The droplet lands where the finger left it, then springs into the
      // hovered segment - the merge.
      _mergeFrom =
          (_dropletX - _itemWidth / 2).clamp(0.0, _itemWidth * widget.items.length - _itemWidth);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _mergeFrom = null);
      if (target != widget.currentIndex) widget.onTap(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = widget.items.length;
    final accent = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0),
      child: GlassSurface(
        tier: GlassTier.chrome,
        borderRadius: 32,
        child: SizedBox(
          height: _pillHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _itemWidth = constraints.maxWidth / itemCount;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.96, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                child: widget.searchMode
                    ? _buildSearchField(context)
                    : _buildNavButtons(context, accent, itemCount),
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Nav buttons + indicator + droplet
  // ---------------------------------------------------------------------

  Widget _buildNavButtons(BuildContext context, Color accent, int itemCount) {
    final indicatorLeft = _mergeFrom ??
        widget.currentIndex * _itemWidth;

    return Stack(
      key: const ValueKey('nav_buttons'),
      children: [
        // Segment-filling glass blob with an ink-drop accent bloom.
        AnimatedPositioned(
          duration: Duration(milliseconds: _mergeFrom != null ? 320 : 280),
          curve: Curves.easeOutBack,
          left: indicatorLeft,
          top: 5,
          width: _itemWidth,
          height: _pillHeight - 10,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 100),
            opacity: _dropletMode ? 0.0 : 1.0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: _inkGradient(accent, 0.22),
                color: Colors.white.withValues(alpha: 0.07),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.12),
                    blurRadius: 18,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
          ),
        ),
        // The droplet (long-press melt). 1:1 finger tracking, velocity stretch.
        if (_dropletMode)
          Positioned(
            left: (_dropletX - 30).clamp(
                0.0, _itemWidth * itemCount - 60),
            top: (_pillHeight - 56) / 2,
            child: IgnorePointer(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(
                  _dropletStretchX,
                  _dropletStretchY,
                  1,
                ),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _inkGradient(accent, 0.32),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.28),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.20),
                        blurRadius: 22,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Row(
          children:
              widget.items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isSelected = index == widget.currentIndex;
            final isPressed = _pressedIndex == index;
            final isHovered = _dropletMode && _hoverIndex == index;
            final active = isSelected || isHovered;

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
                      ? 1.16
                      : isPressed
                          ? 0.88
                          : 1.0,
                  duration:
                      Duration(milliseconds: isPressed ? 90 : 220),
                  curve: isPressed
                      ? Curves.easeOut
                      : Curves.easeOutBack,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconTheme(
                        data: IconThemeData(
                          color: active
                              ? accent
                              : Colors.white.withValues(alpha: 0.55),
                          size: 23,
                        ),
                        child: active ? item.activeIcon : item.icon,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label ?? '',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color: active
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
  }

  double get _dropletStretchX {
    final s = (_velocity.abs() / 2600).clamp(0.0, 0.38);
    return 1 + s;
  }

  double get _dropletStretchY {
    final s = (_velocity.abs() / 2600).clamp(0.0, 0.38);
    return 1 - s * 0.6;
  }

  int? _pressedIndex;

  // ---------------------------------------------------------------------
  // Search field (morph target)
  // ---------------------------------------------------------------------

  Widget _buildSearchField(BuildContext context) {
    final controller = widget.searchController;
    final focusNode = widget.searchFocusNode;

    return Padding(
      key: const ValueKey('search_field'),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
        cursorColor: Theme.of(context).colorScheme.primary,
        decoration: InputDecoration(
          hintText: 'Search songs, albums, artists...',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.38),
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
          filled: false,
          border: InputBorder.none,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Icon(
              Icons.search_rounded,
              color: Colors.white.withValues(alpha: 0.55),
              size: 22,
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 30, minHeight: 30),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller ?? TextEditingController(),
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: Icon(
                  Icons.cancel_rounded,
                  color: Colors.white.withValues(alpha: 0.4),
                  size: 19,
                ),
                onPressed: () {
                  controller?.clear();
                  focusNode?.requestFocus();
                },
              );
            },
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onSubmitted: widget.onSearchSubmitted,
      ),
    );
  }
}
