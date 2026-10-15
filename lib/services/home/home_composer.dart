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
  });

  /// Per-shelf item budget (memory/render cost, spec #12 — not a content
  /// filter).
  final int maxItemsPerSection;

  HomeFeed? compose({
    required HomeFeed? primary,
    required HomeFeed? fallback,
  }) {
    final base = primary ?? fallback;
    if (base == null) return null;

    final sections = <HomeSection>[];
    final seenSectionTitles = <String>{};
    var rejected = 0;
    var sectionLocalDupes = 0;
    var partialRetained = 0;
    var typeFiltered = 0;

    for (final section in base.sections) {
      // Same-title collapse (live bug: native "New releases" + enriched
      // "New releases" rendered twice with different ids). First wins —
      // native order preserved, later duplicates are accounted drops.
      //
      // The key is the NORMALISED title, not lower-case-and-trim: the same shelf
      // arrives as "Listen again" and "Listen again" (non-breaking space),
      // or "What's new" with a curly and a straight apostrophe, and those are
      // one category to a listener and two shelves to a string comparison.
      if (!seenSectionTitles.add(SectionIdentity.normalizedTitle(section.title))) {
        if (kDebugMode) {
          debugPrint(
              'HomeComposer: COLLAPSED duplicate-title section "${section.title}"');
          HomeLoadTrace.loss(
            stage: 'composer',
            shelf: section.title,
            reason: 'duplicate title (first shelf wins)',
          );
        }
        continue;
      }

      // Song-majority shelves must contain songs only (live bug: "Listen
      // again" carried artist cards whose ids are unplayable UC* — they
      // null out of homeItemToTrack and collapse the context playlist to
      // 1 track, killing autoplay). Collection-majority shelves
      // (albums/playlists) keep their type; only stray artist cards are
      // dropped there.
      final songCount = section.items
          .where((i) => i.contentType == HomeContentType.song)
          .length;
      final isSongMajority =
          songCount >= section.items.length / 2 && section.items.isNotEmpty;

      final items = <HomeItem>[];
      final sectionSeen = <String>{};

      for (final item in section.items) {
        // Validation gate (spec #8): ONLY identity + title make an item
        // unsafe to render. Artwork-missing items render with a
        // placeholder — they are PARTIAL, not invalid.
        if (item.id.isEmpty || item.title.isEmpty) {
          rejected++;
          continue;
        }

        // Type coherence (spec #5): songs-only shelves must not carry
        // artists/albums/playlists.
        if (isSongMajority &&
            item.contentType != HomeContentType.song &&
            item.contentType != HomeContentType.video) {
          typeFiltered++;
          if (kDebugMode) {
            debugPrint('HomeComposer: TYPE-DROPPED "${item.title}" '
                '(${item.contentType.name}) from song shelf "${section.title}"');
          }
          continue;
        }
        // Collection shelves: stray artist cards navigate nowhere useful.
        if (!isSongMajority && item.contentType == HomeContentType.artist) {
          typeFiltered++;
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

        // Item budget first (spec #12, memory/render cost only — not a
        // content filter). The artist cap previously ran BEFORE this and
        // re-curated native shelves 10→3 ("Albums for you" = one artist's
        // discography is legitimate editorial). Native order is truth:
        // no artist cap on curated shelves (spec: truth > count).
        if (items.length >= maxItemsPerSection) {
          rejected++;
          continue;
        }

        items.add(_normalizeSupport(item));
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
          'partialRetained=$partialRetained typeFiltered=$typeFiltered');
      for (final before in base.sections) {
        // Collapsed duplicate titles were already accounted (COLLAPSED
        // loss line above) — the seen-set only contains KEPT titles, so
        // skip any section whose title isn't in it (i.e. collapsed ones).
        if (!seenSectionTitles
            .contains(SectionIdentity.normalizedTitle(before.title))) {
          continue;
        }
        final after = sections.where((s) => s.id == before.id).toList();
        if (after.isEmpty) {
          debugPrint('HomeComposer: REMOVED "${before.title}" '
              '(${before.items.length} items) — all items failed '
              'validation/type filter or fell under the 2-item floor');
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
}
