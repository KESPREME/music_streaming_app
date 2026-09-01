import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';

import '../design/tokens/motion.dart';
import '../providers/music_provider.dart';
import '../utils/color_utils.dart';

/// Ambient album-art canvas behind the whole app (v5.2 shell z-layer 0).
///
/// The current track's artwork renders oversized, blurred and darkened
/// beneath every screen, cross-fading on track change. Static content —
/// no per-frame backdrop filters, so it costs one image composite.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final artUrl = context.select<MusicProvider, String?>(
      (p) => p.currentTrack?.albumArtUrl,
    );
    final palette = context.select<MusicProvider, PaletteGenerator?>(
      (p) => p.paletteGenerator,
    );
    final accent = ColorUtils.getVibrantAccent(
        palette, Theme.of(context).colorScheme.primary);

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred artwork, cross-faded on track change.
          AnimatedSwitcher(
            duration: Motion.ambient,
            switchInCurve: Motion.settle,
            switchOutCurve: Motion.exit,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            child: _BlurredArt(key: ValueKey(artUrl), artUrl: artUrl),
          ),
          // Dark scrim: keeps every screen legible over any artwork.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.72),
                  Colors.black.withValues(alpha: 0.88),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // Accent bloom, top-anchored — ties ambient to the active palette.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.4, -0.9),
                  radius: 1.4,
                  colors: [
                    accent.withValues(alpha: 0.10),
                    accent.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurredArt extends StatelessWidget {
  const _BlurredArt({super.key, this.artUrl});

  final String? artUrl;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final url = artUrl;
    if (url == null || url.isEmpty) {
      return const SizedBox.shrink();
    }

    return Transform.scale(
      scale: 1.2,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
        child: Opacity(
          opacity: 0.85,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: 240,
            fadeInDuration: Motion.ambient,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
            // Oversized decode so the blur never samples edges.
            width: size.width,
            height: size.height,
          ),
        ),
      ),
    );
  }
}
