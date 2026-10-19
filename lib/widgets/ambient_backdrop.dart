import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';

import '../design/tokens/motion.dart';
import '../providers/music_provider.dart';
import '../theme/amoled_theme.dart';
import '../utils/color_utils.dart';
import 'blurred_backdrop.dart';

/// Ambient canvas behind the whole app (v5.2 shell z-layer 0).
///
/// By default it is the current track's artwork, oversized, blurred and darkened
/// beneath every screen, cross-fading on track change. Static content —
/// no per-frame backdrop filters, so it costs one image composite.
///
/// In pure-black (AMOLED) mode it is nothing at all: `#000000`. The art wash
/// fades out over [Motion.ambient] when the setting is switched on and back in
/// when it is switched off, and once it has fully faded the art, the 48-sigma
/// blur and the accent bloom are not built, so the mode costs the GPU less than
/// it did rather than more. With "reduce motion" on, it cuts instead of fading.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final black = AmoledTheme.isOn(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        // No `begin`: the first build starts AT its target, so a cold start in
        // either mode does not animate, only a change does.
        tween: Tween<double>(end: black ? 1.0 : 0.0),
        duration: reduceMotion ? Duration.zero : Motion.ambient,
        curve: Curves.easeInOutCubic,
        builder: (context, amount, art) {
          // Fully black: draw nothing but the canvas.
          if (amount >= 1.0) return const ColoredBox(color: AmoledTheme.canvas);
          return Stack(
            fit: StackFit.expand,
            children: [
              // `art` is a const child, so a fade does not rebuild or repaint
              // the blurred layer - it only changes the alpha of the veil below.
              art!,
              if (amount > 0)
                ColoredBox(
                  color: AmoledTheme.canvas.withValues(alpha: amount),
                ),
            ],
          );
        },
        child: const _ArtCanvas(),
      ),
    );
  }
}

/// The artwork wash: blurred art, scrim, accent bloom.
class _ArtCanvas extends StatelessWidget {
  const _ArtCanvas();

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
          // Blurred artwork. One baked wash (see blurred_backdrop.dart): the
          // previous track's stays until the next is ready, then cross-fades,
          // so there is never an empty frame between tracks.
          _BlurredArt(artUrl: artUrl),
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
  const _BlurredArt({this.artUrl});

  final String? artUrl;

  @override
  Widget build(BuildContext context) {
    final url = artUrl;
    final image = url == null || url.isEmpty ? null : backdropArtProvider(url);
    if (image == null) {
      return const SizedBox.shrink();
    }

    // Was a live `ImageFiltered(sigma 48)` over a 1.2x full-screen image with
    // an `Opacity` inside it: on Impeller (no raster cache) that full-screen
    // blur re-ran on every frame anything in the shell moved. Now it is
    // blurred once per artwork into a small image and drawn as one quad; the
    // same picture (test/blurred_backdrop_test.dart pins the bake).
    return RepaintBoundary(
      child: Opacity(
        opacity: 0.85,
        child: BlurredBackdrop(
          image: image,
          sigma: 48,
          scale: 1.2,
          fade: MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : Motion.ambient,
        ),
      ),
    );
  }
}
