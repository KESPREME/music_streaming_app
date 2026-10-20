import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_font.dart';

import '../../utils/artwork_palette_resolver.dart';

/// Tactile squish-on-press wrapper for BitChord action buttons
class _SquishButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _SquishButton({
    required this.child,
    required this.onTap,
  });

  @override
  State<_SquishButton> createState() => _SquishButtonState();
}

class _SquishButtonState extends State<_SquishButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// BitChord Play Pill button
class PlayPill extends StatelessWidget {
  final VoidCallback onPlay;
  final Color? accentColor;
  final ArtworkPalette? palette;
  final double horizontalPadding;

  const PlayPill({
    super.key,
    required this.onPlay,
    this.accentColor,
    this.palette,
    this.horizontalPadding = 28.0,
  });

  @override
  Widget build(BuildContext context) {
    final fill = palette != null
        ? Color.alphaBlend(palette!.elevated.withValues(alpha: 0.32), const Color(0xFF23201E))
        : const Color(0xFF23201E);

    return _SquishButton(
      onTap: onPlay,
      child: Container(
        height: 50,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: fill,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 6),
            Text(
              'Play',
              style: AppFont.style(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// BitChord Circular Icon Button (Shuffle, Search, More, Add)
class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? iconColor;
  final Color? backgroundColor;
  final ArtworkPalette? palette;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 50.0,
    this.iconColor,
    this.backgroundColor,
    this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final fill = backgroundColor ??
        (palette != null
            ? Color.alphaBlend(palette!.elevated.withValues(alpha: 0.32), const Color(0xFF23201E))
            : const Color(0xFF23201E));

    return _SquishButton(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            icon,
            color: iconColor ?? Colors.white,
            size: size * 0.44,
          ),
        ),
      ),
    );
  }
}

/// BitChord Action Bar with 4 buttons: [ 🔀 ]  [ ▶ Play ]  [ 🔍 ]  [ ••• ]
class BitchordActionBar extends StatelessWidget {
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback? onSearch;
  final VoidCallback? onMore;
  final bool searching;
  final Color? accentColor;
  final ArtworkPalette? palette;

  const BitchordActionBar({
    super.key,
    required this.onPlay,
    required this.onShuffle,
    this.onSearch,
    this.onMore,
    this.searching = false,
    this.accentColor,
    this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final hasSearchAndMore = onSearch != null && onMore != null;
    final circleSize = hasSearchAndMore ? 46.0 : 50.0;
    final pillPadding = hasSearchAndMore ? 20.0 : 28.0;
    final effectiveAccent = palette?.accent ?? accentColor ?? Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleIconButton(
            icon: Icons.shuffle_rounded,
            size: circleSize,
            palette: palette,
            onTap: onShuffle,
          ),
          const SizedBox(width: 10),
          PlayPill(
            onPlay: onPlay,
            accentColor: effectiveAccent,
            palette: palette,
            horizontalPadding: pillPadding,
          ),
          if (onSearch != null) ...[
            const SizedBox(width: 10),
            CircleIconButton(
              icon: Icons.search_rounded,
              size: circleSize,
              palette: palette,
              iconColor: searching ? effectiveAccent : Colors.white,
              backgroundColor: searching
                  ? effectiveAccent.withValues(alpha: 0.25)
                  : null,
              onTap: onSearch!,
            ),
          ],
          if (onMore != null) ...[
            const SizedBox(width: 10),
            CircleIconButton(
              icon: Icons.more_horiz_rounded,
              size: circleSize,
              palette: palette,
              onTap: onMore!,
            ),
          ],
        ],
      ),
    );
  }
}
