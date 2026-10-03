import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_service.dart';
import 'package:music_streaming_app/widgets/library/library_hero_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsService Customizable Providers Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final service = LyricsService();
      await service.resetProvidersToDefault();
    });

    test('default providers list has correct order and all are enabled', () {
      final service = LyricsService();
      expect(service.providerOrder, equals([
        LyricsProvider.betterLyrics,
        LyricsProvider.simpMusic,
        LyricsProvider.kugou,
        LyricsProvider.lrclib,
        LyricsProvider.youtubeTranscript,
      ]));
      expect(service.enabledProviders, containsAll([
        LyricsProvider.betterLyrics,
        LyricsProvider.simpMusic,
        LyricsProvider.kugou,
        LyricsProvider.lrclib,
        LyricsProvider.youtubeTranscript,
      ]));
    });

    test('updateProviderOrder updates and persists custom priority', () async {
      final service = LyricsService();
      final newOrder = [
        LyricsProvider.lrclib,
        LyricsProvider.betterLyrics,
        LyricsProvider.kugou,
        LyricsProvider.simpMusic,
        LyricsProvider.youtubeTranscript,
      ];

      await service.updateProviderOrder(newOrder);
      expect(service.providerOrder, equals(newOrder));

      // Verify persistent in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('lyrics_providers_order'), equals(newOrder.map((e) => e.name).toList()));
    });

    test('setProviderEnabled disables and enables a provider', () async {
      final service = LyricsService();
      
      await service.setProviderEnabled(LyricsProvider.kugou, false);
      expect(service.isProviderEnabled(LyricsProvider.kugou), isFalse);
      expect(service.enabledProviders.contains(LyricsProvider.kugou), isFalse);

      await service.setProviderEnabled(LyricsProvider.kugou, true);
      expect(service.isProviderEnabled(LyricsProvider.kugou), isTrue);
      expect(service.enabledProviders.contains(LyricsProvider.kugou), isTrue);
    });

    test('setProviderEnabled rejects disabling the last remaining provider', () async {
      final service = LyricsService();
      
      // Disable 4 out of 5
      await service.setProviderEnabled(LyricsProvider.betterLyrics, false);
      await service.setProviderEnabled(LyricsProvider.simpMusic, false);
      await service.setProviderEnabled(LyricsProvider.kugou, false);
      await service.setProviderEnabled(LyricsProvider.lrclib, false);
      
      expect(service.enabledProviders.length, equals(1));
      expect(service.enabledProviders.first, equals(LyricsProvider.youtubeTranscript));

      // Attempting to disable the last one should not remove it
      await service.setProviderEnabled(LyricsProvider.youtubeTranscript, false);
      expect(service.isProviderEnabled(LyricsProvider.youtubeTranscript), isTrue);
      expect(service.enabledProviders.length, equals(1));
    });

    test('resetProvidersToDefault restores all 5 in default order and enabled', () async {
      final service = LyricsService();
      await service.updateProviderOrder([LyricsProvider.lrclib, LyricsProvider.betterLyrics]);
      await service.setProviderEnabled(LyricsProvider.betterLyrics, false);

      await service.resetProvidersToDefault();
      expect(service.providerOrder, equals([
        LyricsProvider.betterLyrics,
        LyricsProvider.simpMusic,
        LyricsProvider.kugou,
        LyricsProvider.lrclib,
        LyricsProvider.youtubeTranscript,
      ]));
      expect(service.enabledProviders.length, equals(5));
    });
  });

  group('Liquid Orb Dynamic Palette Tint Tests', () {
    testWidgets('LiquidOrb widget accepts dynamicColor parameter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: LiquidOrb(
                size: Size(200, 200),
                dynamicColor: Color(0xFFFF5722),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(LiquidOrb), findsOneWidget);
    });

    testWidgets('LiquidOrb widget works with default null dynamicColor (pure blue drop)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: LiquidOrb(
                size: Size(200, 200),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(LiquidOrb), findsOneWidget);
    });
  });
}
