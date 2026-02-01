import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'liquid_card.dart';
import 'material_you_card.dart';

/// Theme-aware card wrapper
/// Conditionally renders LiquidCard or MaterialYouCard based on theme
class ThemedCard extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double width;
  final double height;
  final bool isCircle;

  const ThemedCard({
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
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        if (themeProvider.isGlassmorphism) {
          return LiquidCard(
            imageUrl: imageUrl,
            title: title,
            subtitle: subtitle,
            onTap: onTap,
            onLongPress: onLongPress,
            width: width,
            height: height,
            isCircle: isCircle,
          );
        } else {
          return MaterialYouCard(
            imageUrl: imageUrl,
            title: title,
            subtitle: subtitle,
            onTap: onTap,
            onLongPress: onLongPress,
            width: width,
            height: height,
            isCircle: isCircle,
          );
        }
      },
    );
  }
}
