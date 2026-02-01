import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../screens/queue_screen.dart';
import '../screens/material_you_queue_screen.dart';

class ThemedQueueScreen extends StatelessWidget {
  const ThemedQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return themeProvider.isMaterialYou
        ? const MaterialYouQueueScreen()
        : const QueueScreen();
  }
}
