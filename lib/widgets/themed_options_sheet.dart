import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../models/track.dart';
import 'glass_options_sheet.dart';
import 'material_you_options_sheet.dart';
import 'song_sheet_plan.dart';

/// Theme-aware options sheet wrapper
/// Conditionally renders GlassOptionsSheet or MaterialYouOptionsSheet based on theme
class ThemedOptionsSheet extends StatelessWidget {
  final Track track;
  final String? playlistId;
  final bool isInQueueContext;
  final bool isRecentlyPlayedContext;

  /// Where the sheet was opened from; the glass sheet shows only the rows that
  /// make sense there (song_sheet_plan.dart). Material You ignores it.
  final SongSheetOrigin origin;

  const ThemedOptionsSheet({
    super.key,
    required this.track,
    this.playlistId,
    this.isInQueueContext = false,
    this.isRecentlyPlayedContext = false,
    this.origin = SongSheetOrigin.auto,
  });

  /// Helper to show the appropriate options sheet based on the current theme
  /// Hides the mini player during the process
  static Future<void> show(BuildContext context, {
    required Track track,
    String? playlistId,
    bool isInQueueContext = false,
    bool isRecentlyPlayedContext = false,
    VoidCallback? onDislike, // glass sheet only; MY variant frozen
    SongSheetOrigin origin = SongSheetOrigin.auto,
  }) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    if (themeProvider.isGlassmorphism) {
      await GlassOptionsSheet.show(
        context,
        track: track,
        playlistId: playlistId,
        isInQueueContext: isInQueueContext,
        isRecentlyPlayedContext: isRecentlyPlayedContext,
        onDislike: onDislike,
        origin: origin,
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
            origin: origin,
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

