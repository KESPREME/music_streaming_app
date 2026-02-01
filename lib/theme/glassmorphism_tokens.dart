import 'package:flutter/material.dart';

/// Glassmorphism design tokens (reference only - existing widgets use these)
/// DO NOT modify existing glass widgets - this is for reference and comparison
class GlassmorphismTokens {
  static const Map<String, dynamic> tokens = {
    // Colors (Translucent surfaces)
    'surface': {
      'primary': Color(0x1AFFFFFF), // 10% white
      'secondary': Color(0x0DFFFFFF), // 5% white
      'tertiary': Color(0x05FFFFFF), // 2% white
    },
    'border': {
      'primary': Color(0x33FFFFFF), // 20% white
      'secondary': Color(0x1AFFFFFF), // 10% white
    },
    'backdrop': {
      'blur': 20.0,
      'tint': Color(0x0DFFFFFF),
    },
    
    // Shapes
    'borderRadius': {
      'small': 8.0,
      'medium': 16.0,
      'large': 24.0,
      'extraLarge': 32.0,
    },
    
    // Shadows
    'shadows': {
      'small': BoxShadow(
        color: Color(0x1A000000),
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
      'medium': BoxShadow(
        color: Color(0x26000000),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
      'large': BoxShadow(
        color: Color(0x33000000),
        blurRadius: 30,
        offset: Offset(0, 10),
      ),
    },
    
    // Motion
    'durations': {
      'fast': Duration(milliseconds: 150),
      'medium': Duration(milliseconds: 300),
      'slow': Duration(milliseconds: 500),
    },
    'curves': {
      'standard': Curves.easeInOut,
      'emphasized': Curves.easeOutCubic,
    },
    
    // Spacing
    'spacing': {
      'xs': 4.0,
      'sm': 8.0,
      'md': 16.0,
      'lg': 24.0,
      'xl': 32.0,
      'xxl': 48.0,
    },
  };
}
