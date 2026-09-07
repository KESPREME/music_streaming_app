import 'dart:ui';
import 'package:flutter/material.dart';

/// One pane of glass laid across the join between the top artwork and the page wash.
///
/// Centered on the bottom edge of the artwork, it blurs both surfaces together
/// so color from the sleeve carries down past where the sleeve ends, and page wash
/// carries up into it, erasing any harsh edge line (BitChord DetailScreen.kt parity).
class MergeBand extends StatelessWidget {
  final double topOffset;
  final double height;
  final double sigma;
  final Color washColor;

  const MergeBand({
    super.key,
    required this.topOffset,
    this.height = 320.0,
    this.sigma = 40.0,
    required this.washColor,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: topOffset,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.5, 1.0],
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.transparent,
              ],
            ).createShader(bounds);
          },
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: Container(
                color: washColor.withValues(alpha: 0.18),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
