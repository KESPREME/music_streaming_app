import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/glass_tokens.dart';
import 'glass_surface.dart';

class GlassSnackBar extends StatelessWidget {
  final String message;

  const GlassSnackBar({super.key, required this.message});

  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(milliseconds: 2000),
  }) {
    showGlassSnackBar(context, message, duration: duration);
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    return GlassSurface(
      tier: GlassTier.floating,
      borderRadius: GlassTokens.radiusButton,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenW > 120 ? screenW - 96 : 280,
        ),
        child: Text(
          message,
          style: GoogleFonts.plusJakartaSans(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

void showGlassSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 2000),
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating, // Pill style float
      margin: const EdgeInsets.symmetric(
        horizontal: 40,
        vertical: 20,
      ), // Center-ish float but standard is bottom
      padding: EdgeInsets.zero,
      content: Center(
        // Center content to make it look like a pill rather than full width
        child: GlassSnackBar(message: message),
      ),
      duration: duration,
    ),
  );
}
