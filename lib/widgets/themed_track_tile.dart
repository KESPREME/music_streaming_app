import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../models/track.dart';
import 'track_tile.dart';
import 'material_you_track_tile.dart';

/// Theme-aware wrapper for Track Tile
/// Switches between TrackTile (Glassmorphism) and MaterialYouTrackTile (Material You)
class ThemedTrackTile extends StatelessWidget {
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

  const ThemedTrackTile({
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    if (themeProvider.isMaterialYou) {
      return MaterialYouTrackTile(
        track: track,
        onTap: onTap,
        onLongPress: onLongPress,
        onOptionsPressed: onOptionsPressed,
        isPlaying: isPlaying,
        playlistId: playlistId,
        dense: dense,
        isInQueueContext: isInQueueContext,
        isRecentlyPlayedContext: isRecentlyPlayedContext,
        backgroundColor: backgroundColor,
      );
    }
    
    return TrackTile(
      track: track,
      onTap: onTap,
      isPlaying: isPlaying,
      playlistId: playlistId,
      dense: dense,
      isInQueueContext: isInQueueContext,
      isRecentlyPlayedContext: isRecentlyPlayedContext,
      backgroundColor: backgroundColor,
    );
  }
}

