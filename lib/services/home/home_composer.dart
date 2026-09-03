import 'package:flutter/foundation.dart';

import 'home_models.dart';
import 'ytm_home_source.dart' show HomeLoadTrace;

/// Composes the final Home feed from a primary (curated) source plus local
/// personalization overlays.
///
/// Rules (v6, spec #10/#11/#42):
/// - preserve native source order and semantics
/// - LOAD ALL valid sections: no section budget. Logged-in feeds run
///   longer than anonymous ones (personalized mixes, library shelves);
///   amputating them at an arbitrary cap is what deleted categories.
///   Per-shelf item budgets + the 2-item floor bound render cost instead.
/// - SECTION-LOCAL dedupe only: the same entity may legitimately appear in
///   multiple native shelves ("Top Picks" and "Trending" may both carry a
///   hit song). Global cross-section dedupe collapsed every later shelf
///   whose content overlapped earlier shelves — the root cause of the
///   1-2-shelf symptom.
/// - validation is identity+title only; missing artwork = PARTIAL item
///   rendered with a placeholder, never rejected (spec #8)
/// - artist diversity cap applies per-section, never erases a shelf
/// - never shuffle; publish one coherent snapshot
class HomeComposer {
  const HomeComposer({
    this.maxItemsPerSection = 12,
    this.maxPerArtist = 3,
  });

  /// Per-shelf item budget (memory/render cost, spec #12 — not a content
  /// filter).
  final int maxItemsPerSection;

  /// Artist over-exposure cap within one shelf (spec #42). Native shelves
  /// rarely exceed this anyway.
  final int maxPerArtist;

  HomeFeed? compose({
    required HomeFeed? primary,
    required HomeFeed? fallback,
  }) {
    final base = primary ?? fallback;
    if (base == null) return null;

    final sections = <HomeSection>[];
    var rejected = 0;
    var sectionLocalDupes = 0;
    var partialRetained = 0;

    for (final section in base.sections) {
      final items = <HomeItem>[];
      final sectionSeen = <String>{};
      final artistCount = <String, int>{};

      for (final item in section.items) {
        // Validation gate (spec #8): ONLY identity + title make an item
        // unsafe to render. Artwork-missing items render with a
        // placeholder — they are PARTIAL, not invalid.
        if (item.id.isEmpty || item.title.isEmpty) {
          rejected++;
          continue;
        }

        // SECTION-LOCAL dedupe (spec #11): repeated entity inside one
        // shelf is a parser/source artifact; cross-section repeats are
        // legitimate editorial behavior.
        if (!sectionSeen.add(item.id)) {
          sectionLocalDupes++;
          continue;
        }

        if (item.supportLevel == SupportLevel.partiallySupported ||
            item.artworkUrl.isEmpty) {
          partialRetained++;
        }

        // Artist diversity per shelf (spec #42).
        final artistKey = _artistKey(item.subtitle);
        if (artistKey != null) {
          final count = artistCount[artistKey] ?? 0;
          if (count >= maxPerArtist) continue;
          artistCount[artistKey] = count + 1;
        }

        items.add(_normalizeSupport(item));
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
          provenance: section.provenance,
        ));
      } else if (section.items.length >= 2 && kDebugMode) {
        debugPrint('HomeComposer: REMOVED "${section.title}" — '
            'only ${items.length} of ${section.items.length} items survived '
            '(section-local dupes=$sectionLocalDupes rejected=$rejected cap)');
        HomeLoadTrace.loss(
          stage: 'composer',
          shelf: section.title,
          reason: 'only ${items.length}/2+ items survived validation',
        );
      }
    }

    if (kDebugMode) {
      final totalItems =
          base.sections.fold<int>(0, (n, s) => n + s.items.length);
      debugPrint(
          'HomeComposer: source=${base.source} sections=${base.sections.length}->${sections.length} '
          'items=$totalItems rejected=$rejected sectionLocalDupes=$sectionLocalDupes '
          'partialRetained=$partialRetained');
      for (final before in base.sections) {
        final after = sections.where((s) => s.id == before.id).toList();
        if (after.isEmpty) {
          debugPrint('HomeComposer: REMOVED "${before.title}" '
              '(${before.items.length} items) — all items failed '
              'validation/local-dedupe or fell under the 2-item floor');
        } else if (after.isNotEmpty &&
            after.first.items.length < before.items.length) {
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
      continuationToken: base.continuationToken,
    );
  }

  /// Support normalization at the composition boundary: an item without
  /// artwork is PARTIAL regardless of what the parser tagged — one truth,
  /// enforced once (UI placeholders key off this).
  static HomeItem _normalizeSupport(HomeItem item) {
    if (item.artworkUrl.isEmpty &&
        item.supportLevel == SupportLevel.fullySupported) {
      return HomeItem(
        id: item.id,
        videoId: item.videoId,
        browseId: item.browseId,
        title: item.title,
        subtitle: item.subtitle,
        artworkUrl: item.artworkUrl,
        contentType: item.contentType,
        artists: item.artists,
        publishedText: item.publishedText,
        playability: item.playability,
        supportLevel: SupportLevel.partiallySupported,
        thumbnails: item.thumbnails,
      );
    }
    return item;
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
