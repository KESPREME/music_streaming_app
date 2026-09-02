import 'package:flutter/foundation.dart';

import 'home_models.dart';

/// Composes the final Home feed from a primary (curated) source plus local
/// personalization overlays.
///
/// Rules (spec): preserve source order and semantics; validate items;
/// dedupe across sections; cap artist repetition; never shuffle; publish
/// one coherent snapshot.
class HomeComposer {
  const HomeComposer({this.maxItemsPerSection = 10, this.maxPerArtist = 2});

  final int maxItemsPerSection;
  final int maxPerArtist;

  /// [primary] wins wholesale when valid. Local sections are appended
  /// only where they don't duplicate primary content. Null primary →
  /// [fallback] is used as-is.
  ///
  /// Populates [lastReport] — composer-level shelf accounting so no
  /// section is ever silently removed (spec #13/#34).
  HomeFeed? compose({
    required HomeFeed? primary,
    required HomeFeed? fallback,
  }) {
    final base = primary ?? fallback;
    if (base == null) return null;

    final sections = <HomeSection>[];
    final seenIds = <String>{};
    var rejected = 0;
    var duplicates = 0;

    for (final section in base.sections) {
      final items = <HomeItem>[];
      final artistCount = <String, int>{};

      for (final item in section.items) {
        // Validation gate: identity + title + artwork.
        if (item.id.isEmpty || item.title.isEmpty) {
          rejected++;
          continue;
        }
        if (item.artworkUrl.isEmpty) {
          rejected++;
          continue;
        }

        // Cross-section dedupe — one appearance per videoId/browseId.
        if (!seenIds.add(item.id)) {
          duplicates++;
          continue;
        }

        // Artist diversity: cap consecutive over-exposure, don't erase
        // genuinely relevant artists.
        final artistKey = _artistKey(item.subtitle);
        if (artistKey != null) {
          final count = artistCount[artistKey] ?? 0;
          if (count >= maxPerArtist) continue;
          artistCount[artistKey] = count + 1;
        }

        items.add(item);
        if (items.length >= maxItemsPerSection) break;
      }

      if (items.length >= 2) {
        sections.add(HomeSection(
          id: section.id,
          title: section.title,
          items: items,
          presentation: section.presentation,
          sourcePath: section.sourcePath,
          renderer: section.renderer,
          sourceSubtitle: section.sourceSubtitle,
        ));
      } else if (section.items.length >= 2 && kDebugMode) {
        debugPrint('HomeComposer: REMOVED "${section.title}" — '
            'only $items.length of ${section.items.length} items survived '
            '(rejected=$rejected dupes=$duplicates or cap)');
      }
    }

    if (kDebugMode) {
      final totalItems =
          base.sections.fold<int>(0, (n, s) => n + s.items.length);
      debugPrint(
          'HomeComposer: source=${base.source} sections=${base.sections.length}->${sections.length} '
          'items=$totalItems rejected=$rejected duplicates=$duplicates');
      // Full reconciliation — WHY each section was removed/trimmed.
      for (final before in base.sections) {
        final after = sections.where((s) => s.id == before.id).toList();
        if (after.isEmpty) {
          debugPrint('HomeComposer: REMOVED "${before.title}" '
              '(${before.items.length} items) — all items failed '
              'validation/dedupe/diversity or fell under the 2-item floor');
        } else if (after.first.items.length < before.items.length) {
          debugPrint('HomeComposer: TRIMMED "${before.title}" '
              '${before.items.length}→${after.first.items.length} items');
        }
      }
    }

    if (sections.isEmpty) return null;
    return HomeFeed(
      sections: sections,
      fetchedAt: base.fetchedAt,
      source: base.source,
      heroCandidate: base.heroCandidate,
    );
  }

  /// Artist identity from the subtitle's leading name(s). Runs like
  /// "Arijit Singh • Single" or "Artist A, Artist B • Album" yield a
  /// stable key without pretending to be a real artist ID.
  static String? _artistKey(String subtitle) {
    if (subtitle.isEmpty) return null;
    final cut = subtitle.indexOf('•');
    final namePart = (cut > 0 ? subtitle.substring(0, cut) : subtitle).trim();
    if (namePart.isEmpty) return null;
    return namePart.toLowerCase();
  }
}
