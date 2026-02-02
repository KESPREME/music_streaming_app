import 'package:flutter/material.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouSnackBar extends StatelessWidget {
  final String message;
  final bool isError;

  const MaterialYouSnackBar({
    super.key, 
    required this.message,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: isError ? colorScheme.errorContainer : MaterialYouTokens.primaryVibrant,
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeLarge), // Pill shape
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              message,
              style: MaterialYouTypography.labelLarge(
                isError ? colorScheme.onErrorContainer : Colors.black, // High contrast
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

void showMaterialYouSnackBar(BuildContext context, String message, {bool isError = false, Duration duration = const Duration(seconds: 2)}) {
  // Clear existing snackbars to avoid stacking delay
  ScaffoldMessenger.of(context).clearSnackBars();
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      padding: EdgeInsets.zero,
      content: Center(
        child: MaterialYouSnackBar(message: message, isError: isError),
      ),
      duration: duration,
    ),
  );
}
