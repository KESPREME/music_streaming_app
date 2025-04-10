// lib/widgets/player_controls.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';

class PlayerControls extends StatelessWidget {
  final bool showLabels;
  final bool compact;

  const PlayerControls({
    Key? key,
    this.showLabels = false,
    this.compact = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final isPlaying = musicProvider.isPlaying;
    final shuffleEnabled = musicProvider.shuffleEnabled;
    final repeatMode = musicProvider.repeatMode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildShuffleButton(context, shuffleEnabled),
              _buildRepeatButton(context, repeatMode),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!compact) _buildPreviousButton(context),
            const SizedBox(width: 16),
            _buildPlayPauseButton(context, isPlaying),
            const SizedBox(width: 16),
            if (!compact) _buildNextButton(context),
          ],
        ),
      ],
    );
  }

  Widget _buildShuffleButton(BuildContext context, bool shuffleEnabled) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.shuffle,
            color: shuffleEnabled ? Colors.deepPurple : Colors.white70,
            size: 24,
          ),
          onPressed: () {
            final musicProvider = Provider.of<MusicProvider>(context, listen: false);
            musicProvider.toggleShuffle();
          },
        ),
        if (showLabels)
          Text(
            'Shuffle',
            style: TextStyle(
              color: shuffleEnabled ? Colors.deepPurple : Colors.white70,
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  Widget _buildRepeatButton(BuildContext context, RepeatMode repeatMode) {
    IconData icon;
    String label;
    Color color;

    switch (repeatMode) {
      case RepeatMode.off:
        icon = Icons.repeat;
        label = 'Repeat Off';
        color = Colors.white70;
        break;
      case RepeatMode.all:
        icon = Icons.repeat;
        label = 'Repeat All';
        color = Colors.deepPurple;
        break;
      case RepeatMode.one:
        icon = Icons.repeat_one;
        label = 'Repeat One';
        color = Colors.deepPurple;
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            icon,
            color: color,
            size: 24,
          ),
          onPressed: () {
            final musicProvider = Provider.of<MusicProvider>(context, listen: false);
            musicProvider.cycleRepeatMode();
          },
        ),
        if (showLabels)
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  Widget _buildPreviousButton(BuildContext context) {
    return IconButton(
      icon: const Icon(
        Icons.skip_previous,
        color: Colors.white,
        size: 36,
      ),
      onPressed: () {
        final musicProvider = Provider.of<MusicProvider>(context, listen: false);
        musicProvider.skipToPrevious();
      },
    );
  }

  Widget _buildPlayPauseButton(BuildContext context, bool isPlaying) {
    return Container(
      width: compact ? 48 : 64,
      height: compact ? 48 : 64,
      decoration: BoxDecoration(
        color: Colors.deepPurple,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(
          isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
          size: compact ? 24 : 36,
        ),
        onPressed: () {
          final musicProvider = Provider.of<MusicProvider>(context, listen: false);
          if (isPlaying) {
            musicProvider.pauseTrack();
          } else {
            if (musicProvider.currentTrack != null) {
              musicProvider.resumeTrack();
            }
          }
        },
      ),
    );
  }

  Widget _buildNextButton(BuildContext context) {
    return IconButton(
      icon: const Icon(
        Icons.skip_next,
        color: Colors.white,
        size: 36,
      ),
      onPressed: () {
        final musicProvider = Provider.of<MusicProvider>(context, listen: false);
        musicProvider.skipToNext();
      },
    );
  }
}
