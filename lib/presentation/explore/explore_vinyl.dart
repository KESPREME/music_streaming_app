import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'explore_tokens.dart';

/// Spinning vinyl disc: circular artwork with center-hole cutout.
/// Spins on a slow linear loop only while [spinning]; otherwise static
/// (no RotationTransition in the tree — cheaper + testable).
class VinylDisc extends StatefulWidget {
  const VinylDisc({
    super.key,
    required this.imageUrl,
    required this.size,
    required this.spinning,
    this.accent,
  });

  final String imageUrl;
  final double size;
  final bool spinning;
  final Color? accent;

  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<VinylDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: ExploreTokens.spinDuration);

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _spin.repeat();
  }

  @override
  void didUpdateWidget(VinylDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.spinning && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disc = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          if (widget.accent != null)
            BoxShadow(
              color: widget.accent!.withValues(alpha: 0.3),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: widget.imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: (widget.size * 2).round(),
                    fadeInDuration: const Duration(milliseconds: 250),
                    errorWidget: (_, __, ___) => const _DiscFallback(),
                  )
                : const _DiscFallback(),
            // Center-hole cutout.
            Center(
              child: Container(
                width: ExploreTokens.vinylHoleSize,
                height: ExploreTokens.vinylHoleSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF0A0A10),
                ),
                child: Center(
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!widget.spinning) return disc;
    return RotationTransition(
        key: const ValueKey('vinyl_spin'), turns: _spin, child: disc);
  }
}

class _DiscFallback extends StatelessWidget {
  const _DiscFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.06),
      child: const Icon(Icons.music_note_rounded,
          size: 28, color: Colors.white24),
    );
  }
}

/// Active micro-equalizer: 4 bouncing liquid bars. Mounted only while the
/// active row is playing, so the loop never runs idle.
class MicroEqualizer extends StatefulWidget {
  const MicroEqualizer({super.key, required this.color, this.barCount = 4});

  final Color color;
  final int barCount;

  @override
  State<MicroEqualizer> createState() => _MicroEqualizerState();
}

class _MicroEqualizerState extends State<MicroEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
      vsync: this, duration: ExploreTokens.eqLoop)
    ..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Now playing equalizer',
      child: AnimatedBuilder(
        animation: _loop,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < widget.barCount; i++)
                Container(
                  key: ValueKey('eq_bar_$i'),
                  width: 3,
                  height: 6 +
                      10 *
                          (sin(pi * (_loop.value + i / widget.barCount)))
                              .abs(),
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 2.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1.5),
                    color: widget.color,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
