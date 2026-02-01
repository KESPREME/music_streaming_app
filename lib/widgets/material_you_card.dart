import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Material You card component (parallel to LiquidCard)
/// Flat design with NO gradients - solid colors with elevation
class MaterialYouCard extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double width;
  final double height;
  final bool isCircle;

  const MaterialYouCard({
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
  State<MaterialYouCard> createState() => _MaterialYouCardState();
}

class _MaterialYouCardState extends State<MaterialYouCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      onLongPress: widget.onLongPress != null ? () {
        HapticFeedback.mediumImpact();
        setState(() => _isPressed = false);
        widget.onLongPress!();
      } : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        child: Container(
          width: widget.width,
          margin: const EdgeInsets.only(right: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Container
              Material(
                elevation: _isPressed ? 1 : 2,
                surfaceTintColor: colorScheme.surfaceTint,
                color: colorScheme.surfaceContainerHighest ?? colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(
                  widget.isCircle ? widget.width / 2 : 16,
                ),
                child: Container(
                  height: widget.height,
                  width: widget.width,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      widget.isCircle ? widget.width / 2 : 16,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      widget.isCircle ? widget.width / 2 : 16,
                    ),
                    child: widget.imageUrl.startsWith('http')
                        ? Image.network(
                            widget.imageUrl,
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
                widget.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: colorScheme.onSurface,
                  letterSpacing: 0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              
              // Subtitle
              if (widget.subtitle.isNotEmpty)
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
