import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/social_screen.dart';
import '../screens/material_you_social_screen.dart';

class ThemedSocialScreen extends StatelessWidget {
  const ThemedSocialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouSocialScreen()
        : const SocialScreen();
  }
}
