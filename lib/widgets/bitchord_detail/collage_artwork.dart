import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../utils/app_image_cache.dart';

/// 2x2 Quadrant Collage Artwork widget matching BitChord playlist cover presentation (Screenshot 3).
class CollageArtwork extends StatelessWidget {
  final List<String>? collageUrls;
  final String fallbackUrl;
  final BoxFit fit;

  const CollageArtwork({
    super.key,
    this.collageUrls,
    required this.fallbackUrl,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (collageUrls != null && collageUrls!.length >= 4) {
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: CachedNetworkImage(
                    imageUrl: collageUrls![0],
                    memCacheWidth: AppImageCache.cardMemCache,
                    memCacheHeight: AppImageCache.cardMemCache,
                    fit: fit,
                    errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black26),
                  ),
                ),
                Expanded(
                  child: CachedNetworkImage(
                    imageUrl: collageUrls![1],
                    memCacheWidth: AppImageCache.cardMemCache,
                    memCacheHeight: AppImageCache.cardMemCache,
                    fit: fit,
                    errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black26),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: CachedNetworkImage(
                    imageUrl: collageUrls![2],
                    memCacheWidth: AppImageCache.cardMemCache,
                    memCacheHeight: AppImageCache.cardMemCache,
                    fit: fit,
                    errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black26),
                  ),
                ),
                Expanded(
                  child: CachedNetworkImage(
                    imageUrl: collageUrls![3],
                    memCacheWidth: AppImageCache.cardMemCache,
                    memCacheHeight: AppImageCache.cardMemCache,
                    fit: fit,
                    errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black26),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Single image fallback
    return CachedNetworkImage(
      imageUrl: fallbackUrl,
      memCacheWidth: AppImageCache.cardMemCache,
      memCacheHeight: AppImageCache.cardMemCache,
      fit: fit,
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white38, size: 64),
      ),
    );
  }
}
