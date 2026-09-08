import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// An explicit badge [E] matching BitChord 1:1 design.
///
/// Renders a crisp, subtle rounded rectangular border enclosing the letter 'E',
/// aligned alongside the track title on album, playlist, and artist detail pages.
class BitchordExplicitBadge extends StatelessWidget {
  final double size;
  final Color? color;

  const BitchordExplicitBadge({
    super.key,
    this.size = 15.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = color ?? Colors.white.withValues(alpha: 0.55);
    final textColor = color ?? Colors.white.withValues(alpha: 0.90);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          color: borderColor,
          width: 0.9,
        ),
        borderRadius: BorderRadius.circular(2.5),
      ),
      child: Text(
        'E',
        style: GoogleFonts.plusJakartaSans(
          fontSize: size * 0.64,
          fontWeight: FontWeight.w800,
          color: textColor,
          height: 1.0,
        ),
      ),
    );
  }
}
