import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/equalizer_screen.dart';
import '../screens/material_you_equalizer_screen.dart';

class ThemedEqualizerScreen extends StatelessWidget {
  const ThemedEqualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouEqualizerScreen()
        : const EqualizerScreen();
  }
}
