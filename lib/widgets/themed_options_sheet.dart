import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../models/track.dart';
import 'glass_options_sheet.dart';
import 'material_you_options_sheet.dart';

/// Theme-aware options sheet wrapper
/// Conditionally renders GlassOptionsSheet or MaterialYouOptionsSheet based on theme
class ThemedOptionsSheet extends StatelessWidget {
  final Track track;
  final String? playlistId;
  final bool isInQueueContext;
  final bool isRecentlyPlayedContext;

  const ThemedOptionsSheet({
    super.key,
    required this.track,
    this.playlistId,
    this.isInQueueContext = false,
    this.isRecentlyPlayedContext = false,
  });

  /// Helper to show the appropriate options sheet based on the current theme
  /// Hides the mini player during the process
  static Future<void> show(BuildContext context, {
    required Track track,
    String? playlistId,
    bool isInQueueContext = false,
    bool isRecentlyPlayedContext = false,
  }) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    if (themeProvider.isGlassmorphism) {
      await GlassOptionsSheet.show(
        context,
        track: track,
        playlistId: playlistId,
        isInQueueContext: isInQueueContext,
        isRecentlyPlayedContext: isRecentlyPlayedContext,
      );
    } else {
      await MaterialYouOptionsSheet.show(
        context,
        track: track,
        playlistId: playlistId,
        isInQueueContext: isInQueueContext,
        isRecentlyPlayedContext: isRecentlyPlayedContext,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        if (themeProvider.isGlassmorphism) {
          return GlassOptionsSheet(
            track: track,
            playlistId: playlistId,
            isInQueueContext: isInQueueContext,
            isRecentlyPlayedContext: isRecentlyPlayedContext,
          );
        } else {
          return MaterialYouOptionsSheet(
            track: track,
            playlistId: playlistId,
            isInQueueContext: isInQueueContext,
            isRecentlyPlayedContext: isRecentlyPlayedContext,
          );
        }
      },
    );
  }
}

