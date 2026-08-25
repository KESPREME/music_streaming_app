import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/theme/glass_theme.dart';

void main() {
  group('GlassTheme', () {
    test('scaffold background is pure black (AMOLED)', () {
      final theme = GlassTheme.build(AccentColors.peach);
      expect(theme.scaffoldBackgroundColor, Colors.black);
    });

    test('colorScheme primary is the given accent', () {
      final theme = GlassTheme.build(AccentColors.peach);
      expect(theme.colorScheme.primary, AccentColors.peach);
    });

    test('onPrimary contrasts with light accent (black on peach)', () {
      final theme = GlassTheme.build(AccentColors.peach);
      expect(theme.colorScheme.onPrimary, Colors.black);
    });

    test('onPrimary flips to white for dark accents', () {
      const darkAccent = Color(0xFF1A237E); // deep indigo
      final theme = GlassTheme.build(darkAccent);
      expect(theme.colorScheme.onPrimary, Colors.white);
    });

    test('surface stays near-black for glass contrast', () {
      final theme = GlassTheme.build(AccentColors.peach);
      expect(theme.colorScheme.surface, Colors.black);
    });

    test('brightness is dark', () {
      final theme = GlassTheme.build(AccentColors.peach);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });
  });
}
