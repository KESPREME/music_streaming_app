import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/glass_tokens.dart';
import 'glass_surface.dart';

class GlassSnackBar extends StatelessWidget {
  final String message;

  const GlassSnackBar({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tier: GlassTier.floating,
      borderRadius: GlassTokens.radiusButton,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            style: GoogleFonts.splineSans(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
