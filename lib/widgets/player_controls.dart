import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';

class PlayerControls extends StatelessWidget {
  final bool showLabels; // Keep for potential future use, but modern designs often hide them
  final bool compact;    // To differentiate between full player and mini player controls if needed
  final double iconSize;
  final double mainIconSize;

  const PlayerControls({
    super.key,
    this.showLabels = false,
    this.compact = false,
    this.iconSize = 28.0,       // Default icon size
    this.mainIconSize = 40.0, // Default for play/pause
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context); // Listen to changes for UI updates
    final theme = Theme.of(context);

    final Color activeColor = theme.colorScheme.primary;
    final Color inactiveColor = theme.iconTheme.color?.withOpacity(0.7) ?? theme.colorScheme.onSurface.withOpacity(0.7);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 16.0, vertical: compact ? 8.0 : 12.0),
      child: Row(
        mainAxisAlignment: compact ? MainAxisAlignment.end : MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!compact)
            _buildIconButton(
              context: context,
              theme: theme,
              icon: Icons.shuffle_rounded,
              label: 'Shuffle',
              isActive: musicProvider.shuffleEnabled,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              onPressed: musicProvider.toggleShuffle,
              iconSize: iconSize * 0.85, // Slightly smaller for shuffle/repeat
            ),

          if (!compact) Spacer(flex: 1),

          _buildIconButton(
            context: context,
            theme: theme,
            icon: Icons.skip_previous_rounded,
            label: 'Previous',
            onPressed: musicProvider.skipToPrevious,
            iconSize: iconSize,
            inactiveColor: inactiveColor,
          ),

          Padding( // Add padding around the main play/pause button
            padding: EdgeInsets.symmetric(horizontal: compact ? 8.0 : 16.0),
            child: _buildPlayPauseButton(context, musicProvider, theme, activeColor),
          ),

          _buildIconButton(
            context: context,
            theme: theme,
            icon: Icons.skip_next_rounded,
            label: 'Next',
            onPressed: musicProvider.skipToNext,
            iconSize: iconSize,
            inactiveColor: inactiveColor,
          ),

          if (!compact) Spacer(flex: 1),

          if (!compact)
            _buildIconButton(
              context: context,
              theme: theme,
              icon: musicProvider.repeatMode == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
              label: 'Repeat',
              isActive: musicProvider.repeatMode != RepeatMode.off,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              onPressed: musicProvider.cycleRepeatMode,
              iconSize: iconSize * 0.85, // Slightly smaller for shuffle/repeat
            ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String label,
    bool isActive = false, // For icons like shuffle/repeat that have an active state
    Color? activeColor,
    Color? inactiveColor,
    required VoidCallback onPressed,
    double? iconSize,
  }) {
    final color = isActive ? (activeColor ?? theme.colorScheme.primary) : (inactiveColor ?? theme.iconTheme.color);

    if (showLabels) { // If labels are ever needed
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(icon, size: iconSize ?? this.iconSize),
            color: color,
            onPressed: onPressed,
            tooltip: label,
            padding: EdgeInsets.all(compact ? 8.0 : 12.0),
            splashRadius: (iconSize ?? this.iconSize) + 8,
          ),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ],
      );
    }

    return IconButton(
      icon: Icon(icon, size: iconSize ?? this.iconSize),
      color: color,
      onPressed: onPressed,
      tooltip: label,
      padding: EdgeInsets.all(compact ? 8.0 : 12.0), // Adjust padding for touch target
      splashRadius: (iconSize ?? this.iconSize) + 4, // Control splash radius
    );
  }

  Widget _buildPlayPauseButton(BuildContext context, MusicProvider musicProvider, ThemeData theme, Color activeColor) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary, // Use primary color for background for emphasis
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: Offset(0, 2),
          )
        ]
      ),
      child: IconButton(
        icon: Icon(
          musicProvider.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: mainIconSize,
        ),
        color: theme.colorScheme.onPrimary, // Ensure contrast with primary background
        onPressed: () {
          if (musicProvider.isPlaying) {
            musicProvider.pauseTrack();
          } else {
            if (musicProvider.currentTrack != null) {
              musicProvider.resumeTrack();
            }
            // Optionally, if currentTrack is null, could try to play the first from queue or a default list
          }
        },
        tooltip: musicProvider.isPlaying ? 'Pause' : 'Play',
        padding: EdgeInsets.all(compact ? 10.0 : 16.0), // Generous padding for main button
        splashRadius: mainIconSize + 8,
      ),
    );
  }
}
