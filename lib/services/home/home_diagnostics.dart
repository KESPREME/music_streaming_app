import 'package:flutter/foundation.dart';

import 'home_models.dart';

/// Development-only Home diagnostics. Everything is no-op in release.
///
/// Answers: "why is this item under this section?" — source provenance,
/// request context, quality report, cached-vs-fresh diff.
class HomeDiagnostics {
  HomeDiagnostics._();

  /// Records the last refresh summary (debug console + inspector).
  static Map<String, dynamic> lastReport = {};
  static DateTime? lastReportAt;

  static void logRequestContext({
    required String source,
    required String clientName,
    required String clientVersion,
    required String hl,
    required bool hasVisitorId,
    required bool hasSignatureTimestamp,
  }) {
    if (!kDebugMode) return;
    lastReport.addAll({
      'requestSource': source,
      'clientName': clientName,
      'clientVersion': clientVersion,
      'hl': hl,
      'gl': '(inferred by YouTube from IP — intentionally not overridden)',
      'visitorIdPresent': hasVisitorId,
      'signatureTimestampPresent': hasSignatureTimestamp,
    });
    debugPrint('HomeDiagnostics.context: $lastReport');
  }

  static void logFeedReport({
    required HomeFeed? feed,
    required bool cacheHit,
    required int requestMs,
    required bool fallbackActive,
    int rejectedItems = 0,
    int duplicateItems = 0,
  }) {
    if (!kDebugMode) return;
    lastReport.addAll({
      'feedSource': feed?.source,
      'sectionCount': feed?.sections.length ?? 0,
      'itemCount': feed?.sections.fold<int>(0, (n, s) => n + s.items.length),
      'rejected': rejectedItems,
      'duplicates': duplicateItems,
      'cacheHit': cacheHit,
      'requestMs': requestMs,
      'fallbackActive': fallbackActive,
      'schemaVersion': feed == null ? null : kHomeFeedSchemaVersion,
      'reportedAt': DateTime.now().toIso8601String(),
    });
    lastReportAt = DateTime.now();
    debugPrint('HomeDiagnostics.report: $lastReport');

    // Per-shelf breakdown — the shelf-level truth the UI renders.
    if (feed != null) {
      for (final section in feed.sections) {
        debugPrint('HomeDiagnostics.shelf "${section.title}" '
            '[${section.presentation.name}] items=${section.items.length} '
            'types=${section.items.map((i) => i.contentType.name).toSet().join('|')} '
            'first=${section.items.take(3).map((i) => i.title).join(' / ')}');
      }
    }
  }

  /// Pull-to-refresh path — compare fresh vs what was on screen.
  static void logRefreshDiff({
    required HomeFeed? previous,
    required HomeFeed? next,
  }) {
    if (!kDebugMode) return;
    if (previous == null || next == null) return;
    final prevIds =
        previous.sections.expand((s) => s.items.map((i) => i.id)).toSet();
    final nextIds =
        next.sections.expand((s) => s.items.map((i) => i.id)).toSet();
    final added = nextIds.difference(prevIds).length;
    final removed = prevIds.difference(nextIds).length;
    final prevTitles = previous.sections.map((s) => s.title).toList();
    final nextTitles = next.sections.map((s) => s.title).toList();

    // Section-level diff (spec #87): added/removed shelves, not just items.
    final addedSections =
        nextTitles.where((t) => !prevTitles.contains(t)).toList();
    final removedSections =
        prevTitles.where((t) => !nextTitles.contains(t)).toList();
    debugPrint('HomeDiagnostics.diff: +$added items / -$removed items | '
        'sections +${addedSections.length}/-${removedSections.length}'
        '${addedSections.isNotEmpty ? ' (+${addedSections.take(3).join(", ")})' : ''}'
        '${removedSections.isNotEmpty ? ' (-${removedSections.take(3).join(", ")})' : ''}');
  }

  /// Source-tier provenance per final section (spec #14/#15).
  static void logProvenance(HomeFeed feed) {
    if (!kDebugMode) return;
    for (final section in feed.sections) {
      debugPrint('HomeDiagnostics.provenance "${section.title}" '
          'source=${feed.source} sectionId=${section.id} '
          'order=${feed.sections.indexOf(section)} '
          'renderer=${section.renderer ?? '?'} '
          'presentation=${section.presentation.name}');
    }
  }

  /// Source trust tiers (spec #35/#55) — prevent low-trust fallback from
  /// silently dominating Home. Values documented, not magic.
  static const double trustNativeHome = 1.0;
  static const double trustFallback = 0.75;

  /// Feed-health regression detection (spec #19): compare fresh vs previous
  /// good feed. A fresh feed with dramatically fewer sections/items is
  /// DEGRADED — do not let it overwrite a rich cache and lock the UI into
  /// a thin Home for 45 minutes.
  static bool isDegraded({
    required HomeFeed? previous,
    required HomeFeed next,
  }) {
    if (previous == null) return false;
    final prevSections = previous.sections.length;
    final nextSections = next.sections.length;
    final prevItems =
        previous.sections.fold<int>(0, (n, s) => n + s.items.length);
    final nextItems = next.sections.fold<int>(0, (n, s) => n + s.items.length);
    const minSectionsForComparison = 4;
    if (prevSections < minSectionsForComparison) return false;

    // Degraded: loses over half of sections AND more than half of items.
    final degraded =
        nextSections < prevSections / 2 && nextItems < prevItems / 2;
    if (degraded && kDebugMode) {
      debugPrint(
          'HomeDiagnostics: DEGRADED_FEED — sections $prevSections→$nextSections, '
          'items $prevItems→$nextItems (keeping previous good feed)');
    }
    return degraded;
  }

  /// Multi-dimensional quality report (spec #58/#80): NO single opaque
  /// number — each dimension is observable so a failure in one axis can't
  /// hide behind a healthy overall score.
  static Map<String, double> qualityDimensions(HomeFeed feed) {
    final items = feed.sections.expand((s) => s.items).toList();
    if (items.isEmpty) {
      return {
        'structural': 0,
        'semantic': 0,
        'playability': 0,
        'diversity': 0,
        'sourceTrust': 0,
        'freshness': 0,
      };
    }

    // Structural: identity + artwork + non-empty title coverage.
    final structural = (items
                    .where((i) => i.id.isNotEmpty && i.artworkUrl.isNotEmpty)
                    .length /
                items.length) *
            0.5 +
        (items.where((i) => i.title.isNotEmpty).length / items.length) * 0.5;

    // Semantic: types resolved + structured metadata present.
    final knownTypes =
        items.where((i) => i.contentType != HomeContentType.unknown).length /
            items.length;
    final withMeta = items.where((i) => i.artists.isNotEmpty).length;
    final semantic = knownTypes * 0.6 + (withMeta / items.length) * 0.4;

    // Playability: playable or valid navigation (album/playlist).
    final playable = items.where((i) => i.isPlayable).length / items.length;

    // Diversity: unique-artist ratio across the feed (1.0 = no repetition).
    final artistKeys = items
        .map((i) => i.artists.isNotEmpty ? i.artists.first.toLowerCase() : null)
        .whereType<String>()
        .toList();
    final diversity = artistKeys.isEmpty
        ? 1.0
        : artistKeys.toSet().length / artistKeys.length;

    final sourceTrust =
        feed.source == 'ytm_home' ? trustNativeHome : trustFallback;

    // Freshness: 1.0 under 2h, decaying to 0 at 48h.
    final ageHours = DateTime.now().difference(feed.fetchedAt).inHours;
    final freshness = (1.0 - ageHours / 48).clamp(0.0, 1.0);

    return {
      'structural': double.parse(structural.toStringAsFixed(3)),
      'semantic': double.parse(semantic.toStringAsFixed(3)),
      'playability': double.parse(playable.toStringAsFixed(3)),
      'diversity': double.parse(diversity.toStringAsFixed(3)),
      'sourceTrust': sourceTrust,
      'freshness': double.parse(freshness.toStringAsFixed(3)),
    };
  }
}
