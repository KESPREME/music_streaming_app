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
  final bool isRecentlyPlayedContext;

  const ThemedOptionsSheet({
    super.key,
    required this.track,
    this.isRecentlyPlayedContext = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        if (themeProvider.isGlassmorphism) {
          return GlassOptionsSheet(
            track: track,
            isRecentlyPlayedContext: isRecentlyPlayedContext,
          );
        } else {
          return MaterialYouOptionsSheet(
            track: track,
            isRecentlyPlayedContext: isRecentlyPlayedContext,
          );
        }
      },
    );
  }
}
