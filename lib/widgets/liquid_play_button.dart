import 'dart:ui';
import 'package:flutter/material.dart';

class LiquidPlayButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isPlaying;

  const LiquidPlayButton({
    super.key,
    required this.onPressed,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30), // Pill/Circle shape
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Water-like gradient: Clear to slightly white/red tint
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.2),
                Colors.white.withOpacity(0.05),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1), // Much softer shadow
                blurRadius: 10,
                spreadRadius: 0, 
                offset: const Offset(0, 4),
              ),
              // Inner glow hack using BoxShadow (inset not supported easily without custom painter, 
              // but we can simulate gloss with the gradient)
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(30),
              splashColor: Colors.white.withOpacity(0.3),
              highlightColor: Colors.white.withOpacity(0.1),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white.withOpacity(0.9), // Slightly translucent icon
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
