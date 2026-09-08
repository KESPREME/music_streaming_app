import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../utils/image_quality_utils.dart';

/// Ambient backdrop matching NowPlayingScreen and BitChord ArtworkMeshBackdrop.
///
/// When [imageUrl] is provided, renders the full-bleed scaled blurred cover art base
/// (sigma 55), dual radiant radial color mesh layers driven by [accentColor], and a
/// smooth dark gradient settling into [backgroundColor].
///
/// Falls back to the vertical gradient wash when [imageUrl] is null or empty.
class ArtworkWash extends StatelessWidget {
  final Color backgroundColor;
  final Color washColor;
  final Color accentColor;
  final Color elevatedColor;
  final double washFraction;
  final String? imageUrl;

  const ArtworkWash({
    super.key,
    required this.backgroundColor,
    required this.washColor,
    required this.accentColor,
    required this.elevatedColor,
    this.washFraction = 0.62,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      final highQualityUrl = ImageQualityUtils.getHighQualityUrl(imageUrl!.trim());
      return Stack(
        fit: StackFit.expand,
        children: [
          // 0. Base solid dark foundation
          ColoredBox(color: backgroundColor),

          // 1. Blurred Cover Artwork Base (matching NowPlayingScreen lines 275-298)
          RepaintBoundary(
            child: ClipRect(
              child: Transform.scale(
                scale: 1.6,
                alignment: Alignment.topCenter,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 55,
                    sigmaY: 55,
                  ),
                  child: SizedBox.expand(
                    child: CachedNetworkImage(
                      imageUrl: highQualityUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black45),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 2. Dual Radiant Color Mesh Layers (matching BitChord ArtworkWash and NowPlayingScreen)
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.0, -0.25),
                radius: 1.25,
                colors: [
                  accentColor.withValues(alpha: 0.46),
                  accentColor.withValues(alpha: 0.18),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.52, 1.0],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.45, 0.65),
                radius: 1.15,
                colors: [
                  elevatedColor.withValues(alpha: 0.32),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),

          // 3. Gentle ambient vertical gradient settling smoothly into backgroundColor
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.04),
                  Colors.black.withValues(alpha: 0.14),
                  backgroundColor.withValues(alpha: 0.55),
                  backgroundColor.withValues(alpha: 0.92),
                ],
                stops: const [0.0, 0.40, 0.75, 1.0],
              ),
            ),
          ),
        ],
      );
    }

    return CustomPaint(
      size: Size.infinite,
      painter: _ArtworkWashPainter(
        backgroundColor: backgroundColor,
        washColor: washColor,
        accentColor: accentColor,
        elevatedColor: elevatedColor,
        washFraction: washFraction,
      ),
    );
  }
}

class _ArtworkWashPainter extends CustomPainter {
  final Color backgroundColor;
  final Color washColor;
  final Color accentColor;
  final Color elevatedColor;
  final double washFraction;

  _ArtworkWashPainter({
    required this.backgroundColor,
    required this.washColor,
    required this.accentColor,
    required this.elevatedColor,
    required this.washFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Vertical base gradient: wash -> background
    final stop1 = washFraction.clamp(0.0, 1.0);
    final stop2 = ui.lerpDouble(stop1, 1.0, 0.35)!;
    final stop3 = ui.lerpDouble(stop1, 1.0, 0.70)!;

    final baseGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0.0, stop1, stop2, stop3, 1.0],
      colors: [
        washColor,
        washColor,
        Color.lerp(washColor, backgroundColor, 0.12)!,
        Color.lerp(washColor, backgroundColor, 0.55)!,
        backgroundColor,
      ],
    );

    final basePaint = Paint()..shader = baseGradient.createShader(rect);
    canvas.drawRect(rect, basePaint);

    // 2. Mesh Blob 1: Left accent blob under artwork foot
    _drawBlob(
      canvas: canvas,
      size: size,
      color: accentColor.withValues(alpha: 0.13),
      at: Offset(0.12, washFraction + 0.08),
      radiusFraction: 0.80,
    );

    // 3. Mesh Blob 2: Right elevated blob further down
    _drawBlob(
      canvas: canvas,
      size: size,
      color: elevatedColor.withValues(alpha: 0.30),
      at: Offset(0.96, washFraction + 0.30),
      radiusFraction: 0.95,
    );
  }

  void _drawBlob({
    required Canvas canvas,
    required Size size,
    required Color color,
    required Offset at,
    required double radiusFraction,
  }) {
    final center = Offset(at.dx * size.width, at.dy * size.height);
    final radius = size.width * radiusFraction;

    final blobGradient = RadialGradient(
      colors: [
        color,
        color.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 1.0],
    );

    final blobPaint = Paint()
      ..shader = blobGradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );

    canvas.drawCircle(center, radius, blobPaint);
  }

  @override
  bool shouldRepaint(covariant _ArtworkWashPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.washColor != washColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.elevatedColor != elevatedColor ||
        oldDelegate.washFraction != washFraction;
  }
}
