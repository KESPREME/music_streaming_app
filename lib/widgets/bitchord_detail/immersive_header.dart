// lib/widgets/bitchord_detail/immersive_header.dart
//
// A full-bleed photo that dissolves into the page colour as ONE surface.
//
// Why this exists (measured on the old screenshots, see
// docs/PLAN-glass-detail-pages.md): the old header was three layers that did not
// agree. The photo's foot fade stopped at 88% opacity, so its last row was still
// 12% photo and the row under it 0%: a hard edge on any bright picture. A veil
// (MergeBand) then painted a flat opaque stripe over that edge, which is the
// dark band you saw, and the photo moved as a separate translated layer, so a
// fractional offset left an anti-aliased hairline.
//
// Here:
//   * the photo is a normal child of the scroll view, so it scrolls natively
//     with the content (nothing to fall out of step);
//   * the fade is a single smootherstep gradient that ends at alpha EXACTLY 1.0
//     on the header's last row, in the same colour the page behind it is
//     painted with, so there is no edge to hide and no band layer;
//   * the header height is snapped to the physical pixel grid;
//   * the fade does not take part in the parallax or it would slide off the
//     bottom edge; it only stretches, anchored there.
//
// Gradient-only: no ShaderMask, no BackdropFilter (those caused a worse seam and
// a stutter on the old page).

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Smootherstep: zero slope at both ends, so the photo leaves the screen without
/// a visible start and the fade lands on the wash without a kink.
double immersiveSmootherstep(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
}

/// How many stops sample the fade. Enough that 8-bit steps never band across a
/// 250dp ramp on a dark colour.
const int kImmersiveFadeSamples = 18;

/// Where along the fade (0..1) it reaches full opacity. The rest is a flat,
/// fully opaque tail: the photo's own last rows are then buried under opaque
/// wash, whatever sub-pixel position the header is drawn at.
const double kImmersiveFadeLandsAt = 0.96;

/// The fade's opacity at [u] (0 = where the photo is untouched, 1 = the last
/// row of the header).
double immersiveFadeAlpha(double u) => immersiveSmootherstep(u / kImmersiveFadeLandsAt);

/// The wash-coloured fade, transparent at the top and exactly opaque at the
/// bottom.
LinearGradient immersiveFadeGradient(Color wash) {
  final stops = <double>[];
  final colors = <Color>[];
  for (var i = 0; i < kImmersiveFadeSamples; i++) {
    final u = i / (kImmersiveFadeSamples - 1);
    stops.add(u);
    // Last stop is built from alpha 1.0 directly, never from a float that
    // rounds to 254/255.
    colors.add(i == kImmersiveFadeSamples - 1 ? wash.withValues(alpha: 1.0) : wash.withValues(alpha: immersiveFadeAlpha(u)));
  }
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: stops,
    colors: colors,
  );
}

/// A soft dark bump through the middle of the fade so white text stays legible
/// on a bright cover. Zero at both ends, so it can never form an edge.
LinearGradient immersiveScrimGradient(double strength) {
  const n = 9;
  final stops = <double>[];
  final colors = <Color>[];
  for (var i = 0; i < n; i++) {
    final u = i / (n - 1);
    stops.add(u);
    final bump = math.pow(math.sin(math.pi * u), 1.6).toDouble();
    colors.add(Colors.black.withValues(alpha: strength * bump));
  }
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: stops,
    colors: colors,
  );
}

/// How far the fade layer reaches past the photo's last row, in logical px.
///
/// THE HAIRLINE: at a fractional scroll offset (the join at row 322.63) the
/// photo layer and the fade layer each anti-alias their own bottom edge at 63%
/// coverage. The fade's unpainted 37% of that pixel lets the photo's partial
/// pixel show through: one stray row, bright on a bright cover and dark on a
/// dark one. Reaching the fade below the photo means the photo's edge pixel is
/// always completely covered by opaque wash; the fade's own edge pixel then
/// lies over page wash of the same colour and cannot be seen.
const double kImmersiveFootBleed = 3.0;

class ImmersiveHeader extends StatelessWidget {
  const ImmersiveHeader({
    super.key,
    required this.height,
    required this.washColor,
    required this.photo,
    this.scrollController,
    this.overlay,
    this.child,
    this.fadeFraction = 0.55,
    this.parallax = 0.3,
    this.topShade = 0.5,
    this.titleScrim = 0.2,
  });

  /// Header height in logical px (snapped to the pixel grid when laid out).
  final double height;

  /// The page colour the photo dissolves into. MUST be the colour the page
  /// behind the header is painted with at the header's bottom edge.
  final Color washColor;

  /// The photo (already sized with BoxFit.cover by the caller).
  final Widget photo;

  /// Drives parallax and the pull-down stretch. Null: a still header.
  final ScrollController? scrollController;

  /// Drawn over the photo, under the fade (a looping motion cover).
  final Widget? overlay;

  /// Title block, aligned to the bottom, over the fade. Not stretched.
  final Widget? child;

  /// How much of the height the fade covers, from the bottom.
  final double fadeFraction;

  /// Share of the scroll offset the photo trails behind the content (0 = none).
  final double parallax;

  /// Darkness at the very top, under the status bar and the back button.
  final double topShade;

  /// Darkness of the title scrim bump.
  final double titleScrim;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final h = height <= 0 ? 0.0 : (height * dpr).round() / dpr;
    final still = MediaQuery.disableAnimationsOf(context);
    final controller = scrollController;

    final photoStack = RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(child: photo),
          if (overlay != null) overlay!,
        ],
      ),
    );

    final fadeH = h * fadeFraction;
    // One layer: the top shade, the title scrim and the fade. It is
    // [kImmersiveFootBleed] taller than the photo (see there).
    final fadeStack = RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: math.min(h * 0.3, 170.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: topShade),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: kImmersiveFootBleed,
            height: fadeH,
            child: DecoratedBox(decoration: BoxDecoration(gradient: immersiveScrimGradient(titleScrim))),
          ),
          // ONE gradient, whose flat opaque tail runs on past the photo's last
          // row. Not a gradient plus a separate "foot" box: two abutting
          // anti-aliased edges at the same fractional position cover only
          // 1 - (1-.63)(1-.37) = 77% of that pixel, which let 23% of the photo
          // through (measured: a stray row of 112 between rows of 29).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: fadeH + kImmersiveFootBleed,
            child: DecoratedBox(decoration: BoxDecoration(gradient: immersiveFadeGradient(washColor))),
          ),
        ],
      ),
    );

    Widget layers(double offset) {
      // Pull-down: the layers grow from their bottom edge by exactly the pull,
      // so their top stays glued to the top of the screen and nothing opens
      // up above the photo.
      final stretch = offset < 0 ? (h - offset) / h : 1.0;
      final shift = (offset > 0 && !still) ? math.min(offset, h) * parallax : 0.0;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          // Open at the top (the stretch grows upward), shut at the bottom (the
          // parallax would otherwise paint over the content below).
          Positioned.fill(
            child: ClipRect(
              clipper: const _OpenTopClipper(),
              child: Transform.translate(
                offset: Offset(0, shift),
                child: Transform.scale(scale: stretch, alignment: Alignment.bottomCenter, child: photoStack),
              ),
            ),
          ),
          // No parallax: the fade is anchored to the last row, and reaches
          // below it. Not clipped: past the last row it is wash on wash.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: -kImmersiveFootBleed,
            child: Transform.scale(scale: stretch, alignment: Alignment.bottomCenter, child: fadeStack),
          ),
        ],
      );
    }

    final body = controller == null
        ? layers(0)
        : AnimatedBuilder(
            animation: controller,
            builder: (context, _) => layers(controller.hasClients && controller.position.hasPixels ? controller.offset : 0.0),
          );

    return SizedBox(
      width: double.infinity,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: body),
          if (child != null) Align(alignment: Alignment.bottomCenter, child: child),
        ],
      ),
    );
  }
}

class _OpenTopClipper extends CustomClipper<Rect> {
  const _OpenTopClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, -4000, size.width, size.height);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
