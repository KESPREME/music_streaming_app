import 'package:flutter/material.dart';
import '../theme/material_you_tokens.dart';

/// Material You Elevated Card
/// Card with proper shadow (no blur), solid surface color
/// Configurable elevation levels following Material 3
/// FIX: Using Container instead of Material to avoid automatic surface tint
class MaterialYouElevatedCard extends StatelessWidget {
  final Widget child;
  final double elevation; // 0, 1, 2, 3, 4, or 5
  final double borderRadius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;

  const MaterialYouElevatedCard({
    super.key,
    required this.child,
    this.elevation = 1,
    this.borderRadius = 16,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.backgroundColor,
  });

  BoxShadow _getShadow() {
    switch (elevation.toInt()) {
      case 0:
        return const BoxShadow(color: Colors.transparent);
      case 1:
        return MaterialYouTokens.elevation1;
      case 2:
        return MaterialYouTokens.elevation2;
      case 3:
        return MaterialYouTokens.elevation3;
      case 4:
        return MaterialYouTokens.elevation4;
      case 5:
        return MaterialYouTokens.elevation5;
      default:
        return MaterialYouTokens.elevation1;
    }
  }

  @override
  Widget build(BuildContext context) {
    // FIX: Use pure surface color - NO Material widget to avoid tint
    final bgColor = backgroundColor ?? const Color(0xFF1C1C1E);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: elevation > 0 ? [_getShadow()] : null,
      ),
      child: Material(
        color: Colors.transparent, // Transparent material for ink effects only
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(borderRadius),
          // FIX: Use accent color for splash/highlight with very low opacity
          splashColor: MaterialYouTokens.primaryVibrant.withOpacity(0.08),
          highlightColor: MaterialYouTokens.primaryVibrant.withOpacity(0.03),
          child: Container(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Album/Track card with image and text
class MaterialYouAlbumCard extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double width;
  final double height;
  final bool isCircle;

  const MaterialYouAlbumCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.width = 160,
    this.height = 160,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      width: width,
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Card
          MaterialYouElevatedCard(
            elevation: 2,
            borderRadius: isCircle ? width / 2 : 16,
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              height: height,
              width: width,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(isCircle ? width / 2 : 16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isCircle ? width / 2 : 16),
                child: imageUrl.startsWith('http')
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: colorScheme.surfaceVariant,
                          child: Icon(
                            Icons.music_note_rounded,
                            size: 48,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Container(
                        color: colorScheme.surfaceVariant,
                        child: Icon(
                          Icons.music_note_rounded,
                          size: 48,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Title
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: colorScheme.onSurface,
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          
          // Subtitle
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// List item card (horizontal layout)
class MaterialYouListCard extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool isCircle;

  const MaterialYouListCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return MaterialYouElevatedCard(
      elevation: 1,
      borderRadius: 12,
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(isCircle ? 30 : 8),
            child: imageUrl.startsWith('http')
                ? Image.network(
                    imageUrl,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 60,
                      height: 60,
                      color: colorScheme.surfaceVariant,
                      child: Icon(
                        Icons.music_note_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Container(
                    width: 60,
                    height: 60,
                    color: colorScheme.surfaceVariant,
                    child: Icon(
                      Icons.music_note_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // Trailing
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}
