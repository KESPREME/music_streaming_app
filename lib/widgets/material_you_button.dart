import 'package:flutter/material.dart';

/// Material You button variants
/// Flat design with NO gradients - solid colors with state layers

enum MaterialYouButtonType {
  filled,
  tonal,
  outlined,
  text,
}

class MaterialYouButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final MaterialYouButtonType type;
  final bool isLoading;

  const MaterialYouButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.type = MaterialYouButtonType.filled,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (isLoading) {
      return _buildLoadingButton(context);
    }

    switch (type) {
      case MaterialYouButtonType.filled:
        return _buildFilledButton(context, colorScheme);
      case MaterialYouButtonType.tonal:
        return _buildTonalButton(context, colorScheme);
      case MaterialYouButtonType.outlined:
        return _buildOutlinedButton(context, colorScheme);
      case MaterialYouButtonType.text:
        return _buildTextButton(context, colorScheme);
    }
  }

  Widget _buildFilledButton(BuildContext context, ColorScheme colorScheme) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: icon != null ? Icon(icon) : const SizedBox.shrink(),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildTonalButton(BuildContext context, ColorScheme colorScheme) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: icon != null ? Icon(icon) : const SizedBox.shrink(),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.onSecondaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildOutlinedButton(BuildContext context, ColorScheme colorScheme) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon != null ? Icon(icon) : const SizedBox.shrink(),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildTextButton(BuildContext context, ColorScheme colorScheme) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: icon != null ? Icon(icon) : const SizedBox.shrink(),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildLoadingButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return FilledButton(
      onPressed: null,
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary.withOpacity(0.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
        ),
      ),
    );
  }
}
