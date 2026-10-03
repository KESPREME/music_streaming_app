import 'package:flutter/material.dart';

/// Gradient-only veil straddling the artwork/wash seam (BitChord `MergeBand`
/// role parity, `DetailScreen.kt` lines 1001-1066).
///
/// BitChord centers a 320dp Haze-blurred band on the artwork's bottom edge so
/// sleeve color carries down past the edge and wash carries up into it. This
/// is the no-hardware-blur equivalent: a 96px veil with an opaque wash core
/// covering the container clip edge and eased feathers dissolving into the
/// image above and the pure wash below.
///
/// Deliberately NO `BackdropFilter`/`ShaderMask`: a naive blur band re-ran a
/// full-width saveLayer every scroll frame (~20fps stutter) and its hard rect
/// edges drew a second seam. Tests lock this in. The foot fade + wash hold do
/// half the merge; this veil finishes it for the price of one gradient rect.
class MergeBand extends StatelessWidget {
  final double? topOffset;
  final ScrollController? scrollController;
  final double? artHeight;
  final double height;

  /// Kept for API compatibility; unused (no live blur by design).
  final double sigma;
  final Color washColor;

  const MergeBand({
    super.key,
    this.topOffset,
    this.scrollController,
    this.artHeight,
    this.height = 96.0,
    this.sigma = 50.0,
    required this.washColor,
  });

  @override
  Widget build(BuildContext context) {
    final baseTop = topOffset ?? (artHeight != null ? artHeight! - (height / 2.0) : 0.0);

    final bandContent = RepaintBoundary(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.22, 0.38, 0.62, 0.78, 1.0],
            colors: [
              Colors.transparent,
              washColor.withValues(alpha: 0.45),
              washColor,
              washColor,
              washColor.withValues(alpha: 0.45),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );

    if (scrollController != null && artHeight != null) {
      return Positioned(
        top: baseTop,
        left: 0,
        right: 0,
        height: height,
        child: AnimatedBuilder(
          animation: scrollController!,
          builder: (context, child) {
            final raw = scrollController!.hasClients ? scrollController!.offset : 0.0;
            // Same clamp as the artwork parallax layer so veil and seam move as one.
            final offset = raw.clamp(0.0, artHeight! * 1.5);
            // Past the artwork there is no seam left; skip compositing entirely.
            if (offset > artHeight! + height) return const SizedBox.shrink();
            return Transform.translate(
              offset: Offset(0, -offset),
              child: child,
            );
          },
          child: bandContent,
        ),
      );
    }
    return Positioned(
      top: baseTop,
      left: 0,
      right: 0,
      height: height,
      child: bandContent,
    );
  }
}
