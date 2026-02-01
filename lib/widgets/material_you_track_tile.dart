import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/track.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

/// Material You Track Tile - Clean, flat design with NO blur
/// Features:
/// - Light blue accent for playing track
/// - Proper elevation (1-2)
/// - Material 3 ripple effects
/// - Integrated options menu (3-dot)
/// - Long-press support for options
class MaterialYouTrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onOptionsPressed;
  final bool isPlaying;
  final String? playlistId;
  final bool dense;
  final bool isInQueueContext;
  final bool isRecentlyPlayedContext;
  final Color? backgroundColor;

  const MaterialYouTrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.onLongPress,
    this.onOptionsPressed,
    this.isPlaying = false,
    this.playlistId,
    this.dense = false,
    this.isInQueueContext = false,
    this.isRecentlyPlayedContext = false,
    this.backgroundColor,
  });

  Widget _buildArtworkWidget(BuildContext context, ColorScheme colorScheme) {
    final artworkSize = dense ? 40.0 : 56.0;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (artworkSize * pixelRatio).round();

    if (track.albumArtUrl.isNotEmpty) {
      return Material(
        elevation: isPlaying ? 2 : 1,
        surfaceTintColor: isPlaying ? MaterialYouTokens.primaryVibrant : colorScheme.surfaceTint,
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
          child: Image.network(
            track.albumArtUrl,
            width: artworkSize,
            height: artworkSize,
            cacheWidth: cacheSize,
            cacheHeight: cacheSize,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: artworkSize,
              height: artworkSize,
              color: colorScheme.surfaceVariant,
              child: Icon(
                Icons.broken_image_rounded,
                size: artworkSize * 0.5,
                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: artworkSize,
                height: artworkSize,
                color: colorScheme.surfaceVariant,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2.0,
                      color: MaterialYouTokens.primaryVibrant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else {
      return Material(
        elevation: 1,
        surfaceTintColor: colorScheme.surfaceTint,
        color: colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
        child: Container(
          width: artworkSize,
          height: artworkSize,
          alignment: Alignment.center,
          child: Icon(
            Icons.music_note_rounded,
            size: artworkSize * 0.5,
            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveBackgroundColor = backgroundColor ??
        (isPlaying
            ? MaterialYouTokens.primaryVibrant.withOpacity(0.08)
            : Colors.transparent);

    return Material(
      color: effectiveBackgroundColor,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress ?? onOptionsPressed,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 12.0 : 16.0,
            vertical: dense ? 8.0 : 12.0,
          ),
          child: Row(
            children: [
              // Album Art
              _buildArtworkWidget(context, colorScheme),
              
              SizedBox(width: dense ? 12 : 16),
              
              // Track Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Track Name
                    Text(
                      track.trackName,
                      style: (dense
                              ? MaterialYouTypography.bodyLarge(colorScheme.onSurface)
                              : MaterialYouTypography.titleMedium(colorScheme.onSurface))
                          .copyWith(
                        color: isPlaying
                            ? MaterialYouTokens.primaryVibrant
                            : colorScheme.onSurface,
                        fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w600,
                      ),
                      maxLines: dense ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    // Artist Name
                    if (track.artistName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        track.artistName,
                        style: (dense
                                ? MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant)
                                : MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant))
                            .copyWith(
                          color: isPlaying
                              ? MaterialYouTokens.primaryVibrant.withOpacity(0.8)
                              : colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              
              SizedBox(width: dense ? 8 : 12),
              
              // Playing Indicator or Options Button
              if (isPlaying)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: MaterialYouTokens.primaryVibrant.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: MaterialYouTokens.primaryVibrant,
                    size: 20,
                  ),
                )
              else
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    onPressed: onOptionsPressed,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

