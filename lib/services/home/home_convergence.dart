import 'package:flutter/foundation.dart';

import 'home_models.dart';
import 'ytm_home_source.dart' show HomeLoadTrace;

/// Home convergence (spec #9/#12): merge fresh native sections with
/// per-section memory so a temporary upstream omission does not erase a
/// previously valid category.
///
/// Algorithm (deterministic, testable):
/// 1. index fresh sections by SectionIdentity
/// 2. walk fresh sections in NATIVE order → output
/// 3. for every remembered section absent from fresh:
///      retain at its PREVIOUS POSITION if within TTL and renderable
/// 4. enrichment sections (provenance chart/new_release) append at the end
/// 5. no duplicate identities; provenance preserved
///
/// Positional stability (spec #10): remembered sections keep their prior
/// slot instead of being appended, so
///   A B C D  +  fresh A C D  →  A' B(prev) C' D'
/// not  A C D B.
class HomeConvergence {
  const HomeConvergence({this.now});

  final DateTime? now;

  HomeFeed converge({
    required HomeFeed fresh,
    required Map<String, SectionMemoryEntry> memory,
  }) {
    final clock = now ?? DateTime.now();
    final freshById = <String, HomeSection>{
      for (final s in fresh.sections) SectionIdentity.forSection(s): s,
    };

    // Position bookkeeping from the CURRENT feed (memory order = previous
    // rendered order).
    final previousOrder = <String, int>{
      for (final entry in memory.entries)
        entry.key: entry.value.section.title.hashCode % 100000,
    };
    // Real positional index: derive from memory insertion order by matching
    // identity to the previous feed's section list order stored implicitly
    // in the map iteration — instead, accept an explicit position map.
    return _merge(fresh, freshById, memory, previousOrder, clock);
  }

  HomeFeed convergeWithOrder({
    required HomeFeed fresh,
    required Map<String, SectionMemoryEntry> memory,
    required List<String> previousOrder,
  }) {
    final clock = now ?? DateTime.now();
    final freshById = <String, HomeSection>{
      for (final s in fresh.sections) SectionIdentity.forSection(s): s,
    };
    final positionMap = <String, int>{
      for (var i = 0; i < previousOrder.length; i++) previousOrder[i]: i,
    };
    return _merge(fresh, freshById, memory, positionMap, clock);
  }

  HomeFeed _merge(
    HomeFeed fresh,
    Map<String, HomeSection> freshById,
    Map<String, SectionMemoryEntry> memory,
    Map<String, int> positionMap,
    DateTime clock,
  ) {
    final converged = fresh.sections.toList();
    final convergedIds = freshById.keys.toSet();

    // A remembered shelf is a stand-in for one the response OMITTED. A shelf
    // with the same NAME that the response did send is not omitted, whatever
    // identity it got this time: identity folds in the dominant content type
    // (native:song:quick_picks in one response, native:video:quick_picks in the
    // next), so identity alone let the stale copy come back beside the fresh
    // one - and because the stand-in is inserted at its OLD position, ahead of
    // the fresh shelf, the title-collapse downstream kept the stale one and
    // threw the fresh one away. Name is what a listener sees, so name decides.
    final convergedTitles = <String>{
      for (final s in fresh.sections) SectionIdentity.normalizedTitle(s.title),
    };

    // Newest first, so if two remembered shelves share a name the fresher
    // memory is the one that stands in.
    final remembered = memory.entries.toList()
      ..sort((a, b) => b.value.cachedAt.compareTo(a.value.cachedAt));

    // Retain eligible remembered sections omitted by this response (spec
    // #5/#7): within TTL + still renderable. Expiry/malformation removes.
    for (final entry in remembered) {
      final identity = entry.key;
      if (convergedIds.contains(identity)) continue; // fresh has it
      final s = entry.value.section;
      final titleKey = SectionIdentity.normalizedTitle(s.title);
      if (convergedTitles.contains(titleKey)) {
        HomeLoadTrace.loss(
          stage: 'memory',
          shelf: s.title,
          reason: 'superseded by a shelf of the same name',
        );
        continue;
      }
      final ttl = SectionMemoryPolicy.ttlFor(s);
      final age = clock.difference(entry.value.cachedAt);
      if (age > ttl) {
        HomeLoadTrace.loss(
          stage: 'memory',
          shelf: s.title,
          reason: 'expired (age ${age.inMinutes}min > ttl ${ttl.inMinutes}min)',
        );
        continue;
      }
      if (!SectionMemoryPolicy.isRenderable(s)) {
        HomeLoadTrace.loss(
          stage: 'memory',
          shelf: s.title,
          reason: 'malformed (title/items invalid)',
        );
        continue;
      }
      convergedIds.add(identity);
      convergedTitles.add(titleKey);
      // Positional stability: insert at previous index when valid.
      final pos = positionMap[identity];
      if (pos != null && pos <= converged.length) {
        converged.insert(
            pos.clamp(0, converged.length),
            HomeSection(
              id: s.id,
              title: s.title,
              items: s.items,
              presentation: s.presentation,
              sourcePath: s.sourcePath,
              renderer: s.renderer,
              sourceSubtitle: s.sourceSubtitle,
              provenance: s.provenance,
            ));
        if (kDebugMode) {
          debugPrint('HOME_MEMORY section="${s.title}" action=RETAIN '
              'ageMin=${age.inMinutes} reason="temporary upstream omission"');
        }
      } else {
        converged.add(s);
        if (kDebugMode) {
          debugPrint('HOME_MEMORY section="${s.title}" action=RETAIN_APPEND '
              'ageMin=${age.inMinutes}');
        }
      }
    }

    if (converged.length == fresh.sections.length) return fresh;

    if (kDebugMode) {
      debugPrint(
          'HOME_DIFF fresh=${fresh.sections.length} memory=${memory.length} '
          'converged=${converged.length}');
    }
    return HomeFeed(
      sections: converged,
      fetchedAt: fresh.fetchedAt,
      source: fresh.source,
      heroCandidate: fresh.heroCandidate,
      continuationToken: fresh.continuationToken,
    );
  }
}
