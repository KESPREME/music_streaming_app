import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../models/track.dart';
import '../now_playing_screen.dart';
import 'material_you_now_playing_screen.dart';

/// Theme-aware Now Playing Screen wrapper
/// Conditionally renders NowPlayingScreen or MaterialYouNowPlayingScreen based on theme
class ThemedNowPlayingScreen extends StatelessWidget {
  final Track track;
  final VoidCallback? onMinimize;

  const ThemedNowPlayingScreen({
    super.key,
    required this.track,
    this.onMinimize,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        if (themeProvider.isGlassmorphism) {
          return NowPlayingScreen(
            track: track,
            onMinimize: onMinimize,
          );
        } else {
          return MaterialYouNowPlayingScreen(
            track: track,
            onMinimize: onMinimize,
          );
        }
      },
    );
  }
}
