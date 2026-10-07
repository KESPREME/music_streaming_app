import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/services/lyrics/lyrics_service.dart';

/// PROVIDER REACHABILITY.
///
/// Three providers were declared in [LyricsProvider] and rendered by the settings
/// sheet - and were never consulted by a single lookup. `defaultProviderOrder`
/// seeded `_providerOrder`, the race read `_providerOrder`, and the sheet listed
/// `_providerOrder`, so anything missing from that one list was simultaneously
/// invisible to the race and visible to the user, who could reorder it and watch
/// nothing change.
///
/// That is worse than not offering a provider: it looks like the provider is
/// broken rather than unreachable.
///
/// These read the REAL constants. A test that restated the enum would have passed
/// while all three stayed broken.

void main() {
  group('every provider can be reached', () {
    test('every enum member is either in the default order or hidden', () {
      final unreachable = <LyricsProvider>[];
      for (final provider in LyricsProvider.values) {
        if (!provider.isOffered) continue;
        if (!LyricsService.defaultProviderOrder.contains(provider)) {
          unreachable.add(provider);
        }
      }
      expect(
        unreachable,
        isEmpty,
        reason: 'declared, shown in the sheet, and never asked. Either add it to '
            'defaultProviderOrder or mark it not offered.',
      );
    });

    test('the default order has no duplicates and is not empty', () {
      final order = LyricsService.defaultProviderOrder;
      expect(order.toSet().length, order.length,
          reason: 'a duplicated entry in the order asks the same provider twice');
      expect(order, isNotEmpty);
    });

    test('a repaired order contains nothing this build has retired', () {
      // `reconcileOrder` filters the saved list, so it must filter the re-seeded
      // list too. It did not: the loop that adds providers missing from a saved
      // order had no `isOffered` check and put straight back everything the
      // filter above had just removed.
      final repaired = LyricsService.reconcileOrder(
        LyricsService.defaultProviderOrder,
      );
      final retired = repaired.where((p) => !p.isOffered).toList();
      expect(retired, isEmpty);
    });

    test('the word-sync capable providers are not all last', () {
      // A sanity check on the ORDER, not just its contents: every word-synced
      // source below every line-only source would mean no word-synced provider
      // could ever answer, however the user reordered nothing.
      final firstLineOnly = LyricsService.defaultProviderOrder
          .indexWhere((p) => !p.canWordSync);
      expect(
        firstLineOnly,
        greaterThan(0),
        reason: 'the order leads with line-only fallbacks, so the sources that '
            'can actually synchronise never get asked first',
      );
    });
  });

  group('a retired provider stays retired', () {
    test('megalobiz and simpMusic are not offered', () {
      // Both are HTML scrapes / video-id-keyed hosts the reference hides
      // (LyricsSource.kt:87, 108). Ours hid only one, so a returning user kept
      // paying for a scrape the sheet could not even show them.
      expect(LyricsProvider.megalobiz.isOffered, isFalse);
      expect(LyricsProvider.simpMusic.isOffered, isFalse);
    });

    test('a saved order is repaired, not trusted', () {
      final repaired = LyricsService.reconcileOrder([
        LyricsProvider.lrclib,
        LyricsProvider.genius,
        LyricsProvider.megalobiz,
      ]);

      // Dropped: no longer offered.
      expect(repaired.contains(LyricsProvider.megalobiz), isFalse);
      // Restored: in the default order, missing from the saved one.
      expect(repaired.contains(LyricsProvider.lrcRed), isTrue);
      // The user's ordering survives where it can.
      expect(
        repaired.indexOf(LyricsProvider.lrclib),
        lessThan(repaired.indexOf(LyricsProvider.genius)),
        reason: 'reconcileOrder repairs what it must and leaves the rest alone',
      );
    });

    test('a provider added since the order was saved lands after its '
        'declared predecessor, not at the end', () {
      // Without this a new provider is appended below every line-only fallback,
      // where the race's priority order means it never gets to answer.
      final repaired = LyricsService.reconcileOrder([
        LyricsProvider.lrcRed,
        LyricsProvider.genius,
      ]);
      expect(
        repaired.indexOf(LyricsProvider.betterLyrics),
        lessThan(repaired.indexOf(LyricsProvider.genius)),
        reason: 'a new word-synced provider must not be appended below every '
            'line-only fallback',
      );
    });

    test('reconcileOrder is idempotent', () {
      final once = LyricsService.reconcileOrder([
        LyricsProvider.genius,
        LyricsProvider.lrclib,
      ]);
      final twice = LyricsService.reconcileOrder(once);
      expect(twice, once);
    });

    test('an empty saved order falls back to the default', () {
      // The default MINUS what this build has retired: the fallback is every
      // provider this build can actually ask, which is not quite the declaration
      // order any more now that two of them are hidden.
      final offered = LyricsService.defaultProviderOrder
          .where((p) => p.isOffered)
          .toList();
      expect(LyricsService.reconcileOrder(const []), offered);
    });
  });

  group('the word-sync preference defaults off', () {
    test('holding a line-synced answer is opt-in', () {
      // Holding costs a round trip on every remaining provider for every track.
      // Shipping it on meant every cold start paid for lookups nobody asked for;
      // the reference's own note says it is worth it "to some, not to others"
      // (AppSettings.kt:500-507).
      //
      // Read off the constant the service, the provider and the preference load
      // all use, rather than a literal beside the assertion - a test that wrote
      // `expect(false, isFalse)` would keep passing after somebody flipped it.
      expect(LyricsService.prioritizeSyllableDefault, isFalse);
    });
  });
}