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

      // The Apple syllable mirrors lead, in the order the reference uses, and
      // Genius is last because it cannot synchronise at all. The reasoning is
      // recorded on [LyricsService.defaultProviderOrder]; this pins the shape
      // rather than restating the whole list twice.
      expect(service.providerOrder, equals(LyricsService.defaultProviderOrder));
      expect(
        service.providerOrder.first,
        LyricsProvider.lrcRed,
        reason: 'the Apple mirrors lead, lrc.red first',
      );
      expect(
        service.providerOrder.last,
        LyricsProvider.genius,
        reason: 'plain text is a fallback, never a lead',
      );

      // Every provider in the declared order is enabled out of the box.
      expect(service.enabledProviders, equals(service.providerOrder.toSet()));
    });

    test('the unsynchronised providers are last', () {
      final order = LyricsService.defaultProviderOrder;
      // Nothing that can only produce whole lines may be asked before something
      // that can synchronise, or the wipe silently degrades for a whole song.
      for (final unsynced in [
        LyricsProvider.genius,
        LyricsProvider.youtubeTranscript,
      ]) {
        for (final synced in order.where((p) => p.canWordSync)) {
          expect(
            order.indexOf(synced),
            lessThan(order.indexOf(unsynced)),
            reason: '$synced must be tried before $unsynced',
          );
        }
      }
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

      // Leave exactly one enabled, whichever it is. Driven off the declared
      // order rather than a copied list, so adding a provider does not quietly
      // make this test assert the wrong thing.
      final order = service.providerOrder;
      final survivor = order.last;
      for (final provider in order.where((p) => p != survivor)) {
        await service.setProviderEnabled(provider, false);
      }

      expect(service.enabledProviders.length, equals(1));
      expect(service.enabledProviders.first, equals(survivor));

      // Attempting to disable the last one should not remove it. A lyrics
      // screen with no source configured cannot fetch anything at all.
      await service.setProviderEnabled(survivor, false);
      expect(service.isProviderEnabled(survivor), isTrue);
      expect(service.enabledProviders.length, equals(1));
    });

    test('resetProvidersToDefault restores the declared order and enables all',
        () async {
      final service = LyricsService();
      await service.updateProviderOrder([LyricsProvider.lrclib, LyricsProvider.betterLyrics]);
      await service.setProviderEnabled(LyricsProvider.betterLyrics, false);

      await service.resetProvidersToDefault();
      expect(
        service.providerOrder,
        equals(LyricsService.defaultProviderOrder),
      );
      expect(
        service.enabledProviders.length,
        equals(LyricsService.defaultProviderOrder.length),
      );
      expect(service.isProviderEnabled(LyricsProvider.betterLyrics), isTrue);
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
