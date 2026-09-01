import 'package:flutter/foundation.dart';

import 'home_models.dart';
import 'ytm_home_source.dart';

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
    debugPrint('HomeDiagnostics.diff: +$added items / -$removed items | '
        'sections changed: ${!listEquals(prevTitles, nextTitles)}');
  }

  /// Source-tier provenance per final section (spec #14/#15).
  static void logProvenance(HomeFeed feed) {
    if (!kDebugMode) return;
    for (final section in feed.sections) {
      debugPrint('HomeDiagnostics.provenance "${section.title}" '
          'source=${feed.source} sectionId=${section.id} '
          'order=${feed.sections.indexOf(section)} '
          'presentation=${section.presentation.name}');
    }
  }

  /// Quality score — development-only (spec #91). Not user-facing.
  static double computeQualityScore(HomeFeed feed) {
    if (feed.sections.isEmpty) return 0;
    final items = feed.sections.expand((s) => s.items).toList();
    if (items.isEmpty) return 0;

    final withIdentity =
        items.where((i) => i.id.isNotEmpty).length / items.length;
    final withArtwork =
        items.where((i) => i.artworkUrl.isNotEmpty).length / items.length;
    final withSubtitle =
        items.where((i) => i.subtitle.isNotEmpty).length / items.length;
    final knownTypes =
        items.where((i) => i.contentType != HomeContentType.unknown).length /
            items.length;
    final sourceTrust = feed.source == 'ytm_home' ? 1.0 : 0.75;

    // Weighted: identity and type accuracy matter most.
    final score = sourceTrust * 0.25 +
        withIdentity * 0.25 +
        knownTypes * 0.2 +
        withArtwork * 0.15 +
        withSubtitle * 0.15;
    return double.parse(score.toStringAsFixed(3));
  }
}
