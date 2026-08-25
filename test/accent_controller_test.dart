import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/providers/accent_controller.dart';
import 'package:music_streaming_app/theme/glass_theme.dart' show AccentColors;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AccentController', () {
    test('default accent is peach', () {
      final controller = AccentController();
      expect(controller.accent, AccentController.peach);
      expect(controller.preset, AccentPreset.peach);
      expect(controller.isAlbumAdaptive, isFalse);
    });

    test('setPreset changes accent and persists', () async {
      final controller = AccentController();
      await controller.setPreset(AccentPreset.ice);

      expect(controller.accent, AccentColors.ice);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('accent_preset'), AccentPreset.ice.name);
    });

    test('custom hex color is accepted and persisted', () async {
      final controller = AccentController();
      await controller.setCustomColor(const Color(0xFF123456));

      expect(controller.preset, AccentPreset.custom);
      expect(controller.accent, const Color(0xFF123456));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('accent_custom_hex'), 'FF123456');
    });

    test('invalid hex string is rejected', () {
      expect(AccentController.tryParseHex('not-hex'), isNull);
      expect(AccentController.tryParseHex('#FF00AA'), isNotNull,
          reason: '#RRGGBB with # prefix must parse');
    });

    test('album-adaptive uses album accent when available', () async {
      final controller = AccentController();
      await controller.setAlbumAdaptive(true);
      controller.setAlbumAccent(const Color(0xFFABCDEF));

      expect(controller.isAlbumAdaptive, isTrue);
      expect(controller.accent, const Color(0xFFABCDEF));
    });

    test('album-adaptive falls back to preset when album accent is null',
        () async {
      final controller = AccentController();
      await controller.setAlbumAdaptive(true);
      controller.setAlbumAccent(null);

      expect(controller.accent, AccentController.peach);
    });

    test('album-adaptive off ignores album accent', () async {
      final controller = AccentController();
      controller.setAlbumAccent(const Color(0xFFABCDEF));
      expect(controller.accent, AccentController.peach,
          reason: 'adaptive off must ignore album accent');
    });

    test('initialize restores persisted state', () async {
      SharedPreferences.setMockInitialValues({
        'accent_preset': AccentPreset.custom.name,
        'accent_custom_hex': 'FF778899',
        'accent_album_adaptive': true,
      });

      final controller = AccentController();
      await controller.initialize();

      expect(controller.preset, AccentPreset.custom);
      expect(controller.accent, const Color(0xFF778899));
      expect(controller.isAlbumAdaptive, isTrue);
    });

    test('presets expose at least six colors', () {
      expect(AccentPreset.values.length, greaterThanOrEqualTo(6));
    });
  });
}
