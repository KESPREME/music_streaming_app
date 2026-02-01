import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import 'glass_playback_bar.dart';
import 'material_you_playback_bar.dart';

/// Theme-aware playback bar wrapper
/// Conditionally renders GlassPlaybackBar or MaterialYouPlaybackBar based on theme
class ThemedPlaybackBar extends StatelessWidget {
  final Track track;
  final MusicProvider provider;
  final Color accentColor;

  const ThemedPlaybackBar({
    super.key,
    required this.track,
    required this.provider,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        if (themeProvider.isGlassmorphism) {
          return GlassPlaybackBar(
            track: track,
            provider: provider,
            accentColor: accentColor,
          );
        } else {
          return MaterialYouPlaybackBar(
            track: track,
            provider: provider,
            accentColor: accentColor,
          );
        }
      },
    );
  }
}
