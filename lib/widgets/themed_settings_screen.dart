import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/settings_screen.dart';
import '../screens/material_you_settings_screen.dart';

/// Themed Settings Screen Wrapper
/// Switches between Glass and Material You versions based on theme
class ThemedSettingsScreen extends StatelessWidget {
  const ThemedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouSettingsScreen()
        : const SettingsScreen();
  }
}
