import 'package:flutter/material.dart';
import '../providers/music_provider.dart';

/// Material You progress bar for audio playback
/// Flat design with NO wavy effects - simple linear progress
class MaterialYouProgressBar extends StatelessWidget {
  final MusicProvider provider;
  final Color accentColor;
  final bool isMini; // Add isMini flag
  final bool showThumb;
  final bool showTimeLabels;
  final VoidCallback? onSeekStart; // Optional callback for seek start
  final VoidCallback? onSeekEnd; // Optional callback for seek end

  const MaterialYouProgressBar({
    super.key,
    required this.provider,
    required this.accentColor,
    this.showThumb = true,
    this.showTimeLabels = true,
    this.isMini = false, // Default to false (standard slider)
    this.onSeekStart,
    this.onSeekEnd,
  });

  @override
  Widget build(BuildContext context) {
    // If it's the mini player, render a lightweight LinearProgressIndicator with touch seek
    if (isMini) {
      return _buildMiniProgressBar(context);
    }

    // Otherwise, render the standard Slider
    return _buildStandardProgressBar(context);
  }

  Widget _buildMiniProgressBar(BuildContext context) {
    final duration = provider.duration;
    final position = provider.position;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            _seekToRelativePosition(details.localPosition.dx, constraints.maxWidth, duration);
          },
          onHorizontalDragUpdate: (details) {
             _seekToRelativePosition(details.localPosition.dx, constraints.maxWidth, duration);
          },
          child: SizedBox(
            height: 12, // Sufficient touch target height
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: accentColor.withOpacity(0.12),
                  color: accentColor,
                  minHeight: 2, // Very thin line
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _seekToRelativePosition(double dx, double width, Duration duration) {
    if (width <= 0) return;
    final double relative = (dx / width).clamp(0.0, 1.0);
    final newPosition = Duration(milliseconds: (relative * duration.inMilliseconds).round());
    provider.seekTo(newPosition);
  }

  Widget _buildStandardProgressBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final position = provider.position;
    final duration = provider.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: showTimeLabels ? 48 : 24,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: showThumb ? 4 : 3,
              thumbShape: showThumb
                  ? const RoundSliderThumbShape(enabledThumbRadius: 6)
                  : const RoundSliderThumbShape(enabledThumbRadius: 0),
              overlayShape: showThumb
                  ? const RoundSliderOverlayShape(overlayRadius: 16)
                  : const RoundSliderOverlayShape(overlayRadius: 0),
              activeTrackColor: accentColor,
              inactiveTrackColor: colorScheme.surfaceContainerHighest ?? colorScheme.surfaceVariant,
              thumbColor: accentColor,
              overlayColor: accentColor.withOpacity(0.12),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: showThumb
                  ? (value) {
                      final newPosition = Duration(
                        milliseconds: (value * duration.inMilliseconds).round(),
                      );
                      provider.seekTo(newPosition);
                    }
                  : null,
            ),
          ),
        ),
        
        if (showTimeLabels)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
