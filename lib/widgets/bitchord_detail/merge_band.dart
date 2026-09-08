import 'package:flutter/material.dart';

/// One pane of glass laid across the join between the top artwork and the page wash.
///
/// Centered on the bottom edge of the artwork, it blurs both surfaces together
/// so color from the sleeve carries down past where the sleeve ends, and page wash
/// carries up into it, erasing any harsh edge line (BitChord DetailScreen.kt parity).
class MergeBand extends StatelessWidget {
  final double? topOffset;
  final ScrollController? scrollController;
  final double? artHeight;
  final double height;
  final double sigma;
  final Color washColor;

  const MergeBand({
    super.key,
    this.topOffset,
    this.scrollController,
    this.artHeight,
    this.height = 320.0,
    this.sigma = 50.0,
    required this.washColor,
  });

  @override
  Widget build(BuildContext context) {
    if (scrollController != null && artHeight != null) {
      return AnimatedBuilder(
        animation: scrollController!,
        builder: (context, _) {
          final offset = scrollController!.hasClients ? scrollController!.offset : 0.0;
          final dynamicTop = -offset.clamp(0.0, artHeight! * 1.5) + artHeight! - (height / 2.0);
          return _buildBand(dynamicTop);
        },
      );
    }
    return _buildBand(topOffset ?? 0.0);
  }

  Widget _buildBand(double computedTop) {
    return Positioned(
      top: computedTop,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.35, 0.65, 1.0],
                colors: [
                  Colors.transparent,
                  washColor.withValues(alpha: 0.18),
                  washColor.withValues(alpha: 0.55),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
