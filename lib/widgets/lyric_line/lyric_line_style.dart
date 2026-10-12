// lib/widgets/lyric_line/lyric_line_style.dart
// The falloff ladders: how a lyric row looks at a given distance from the one
// being sung. Numbers are BitChord's (`PlayerLyrics.kt`), read, not approximated.

import 'package:flutter/animation.dart';

/// The visual falloff for lyric rows, kept beside the widget that renders it so
/// the ladder cannot drift from its consumer.
class LyricLineStyle {
  const LyricLineStyle._();

  /// ONE easing and ONE duration for every lyric dimension.
  ///
  /// Blur, alpha, scale and scroll all move on the same cubic, so a handover
  /// reads as one movement rather than four things settling at slightly
  /// different rates. It is monotonic with almost no initial acceleration, which
  /// keeps a line from snapping into place and then creeping - an overshooting
  /// curve here makes the motion finish before the animation does, which reads
  /// as the page jumping early.
  ///
  /// BitChord's `LYRIC_EASING` / `LYRIC_SETTLE_MS` (`PlayerLyrics.kt:367-368`).
  static const Curve lyricEase = Cubic(0.41, 0.0, 0.12, 0.99);
  static const Duration lyricSettle = Duration(milliseconds: 400);

  /// Scale of a line that is not the active one. Tweened on the same spec as the
  /// blur so a line recedes and returns as one movement. BitChord
  /// `INACTIVE_SCALE` (`PlayerLyrics.kt:337`).
  static const double inactiveScale = 0.98;

  /// Alpha by distance from the active line, symmetric in both directions.
  ///
  /// The floor of 0.46 is the important part: a line never fades to invisible,
  /// so the whole lyric stays readable without scrolling.
  static const List<double> alphaLadder = [1.0, 0.8, 0.7, 0.58, 0.46];

  /// Blur by distance, in dp (a radius, as Compose's `Modifier.blur` takes it).
  /// Capped at 2.4: past that every line outside the centre is a smear.
  static const List<double> blurLadder = [0.0, 1.0, 1.0, 1.7, 2.4];

  /// Uniform alpha while the reader is scrolling by hand. Browsing is not a
  /// state to be dimmed through: the reader is trying to read the words.
  static const double browsingAlpha = 0.8;

  /// Alpha for a line whose source had no timings at all.
  static const double unsyncedAlpha = 0.95;

  static double alphaForDistance(int distance) {
    if (distance <= 0) return alphaLadder.first;
    final i = distance < alphaLadder.length ? distance : alphaLadder.length - 1;
    return alphaLadder[i];
  }

  static double blurForDistance(int distance) {
    if (distance <= 0) return blurLadder.first;
    final i = distance < blurLadder.length ? distance : blurLadder.length - 1;
    return blurLadder[i];
  }

  /// The blur radius, in dp, a row [distance] from the active one sits at. Zero
  /// while browsing so the whole lyric can be read.
  static double blurFor({required int distance, required bool isBrowsing}) =>
      isBrowsing ? 0.0 : blurForDistance(distance.abs());

  /// The alpha a row [distance] from the active one sits at.
  static double alphaFor({
    required int distance,
    required bool isBrowsing,
    required bool isSynced,
  }) =>
      isBrowsing
          ? browsingAlpha
          : (isSynced ? alphaForDistance(distance) : unsyncedAlpha);

  /// The scale a row [distance] from the active one sits at.
  static double scaleFor({required int distance}) =>
      distance == 0 ? 1.0 : inactiveScale;

  /// The Gaussian sigma, in LOGICAL px, that a ladder radius of [radiusDp]
  /// produces on a device with [devicePixelRatio].
  ///
  /// Compose's `Modifier.blur(r.dp)` hands Android a RenderEffect radius of
  /// `r * dpr` pixels, and HWUI converts a radius to a Skia sigma as
  /// `0.57735 * radius + 0.5` (`Blur::convertRadiusToSigma`). In logical pixels
  /// that is `0.57735 * r + 0.5 / dpr`. Feeding the ladder straight into
  /// Flutter's sigma (as this used to) over-blurs every row by up to 1.6x.
  static double sigmaFor(double radiusDp, double devicePixelRatio) {
    if (radiusDp <= 0) return 0.0;
    final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    return 0.57735 * radiusDp + 0.5 / dpr;
  }
}
