import 'package:flutter/foundation.dart';

import 'search_followup_store.dart';

/// Search → play transition graph (spec #7/#8).
///
/// Models "what the user actually chose after searching X". Weighted
/// transitions with recency decay and confidence gating (spec #9: one
/// accidental search must not dominate).
class SearchFollowupGraph {
  SearchFollowupGraph({this.store});

  final SearchFollowupStore? store;

  /// query (normalized) → targetItemId → weight
  final Map<String, Map<String, double>> _edges = {};

  /// Recency decay: weight multiplier per day since the transition.
  static const double _dailyDecay = 0.97;

  /// Spec #9: minimum evidence before a transition is "confident".
  static const int _minConfidenceObservations = 1;
  static const double _confidenceBoostThreshold = 3;

  DateTime? _lastLoaded;

  /// Record: user searched [query], then played [trackId] by [artistName].
  Future<void> recordTransition(
      String query, String trackId, String artistName) async {
    final normalized = _normalizeQuery(query);
    if (normalized.isEmpty || trackId.isEmpty) return;
    final edges = _edges.putIfAbsent(normalized, () => {});
    edges[trackId] = (edges[trackId] ?? 0) + 1;
    await store?.saveTransition(normalized, trackId, artistName);
  }

  /// Affinity of [trackId] for a search context. 0 when no evidence.
  /// Higher with repeated evidence; decays with age.
  double affinityFor(String trackId, {String? activeQuery}) {
    if (activeQuery != null && activeQuery.isNotEmpty) {
      final edges = _edges[_normalizeQuery(activeQuery)];
      final w = edges?[trackId];
      if (w != null) return (w / (w + 2)).clamp(0.0, 1.0);
    }
    // Without an active query: does this track appear in any recent
    // search-follow-up? Use the max edge weight, softly discounted.
    double best = 0;
    for (final edges in _edges.values) {
      final w = edges[trackId];
      if (w != null && w > best) best = w;
    }
    if (best < _minConfidenceObservations) return 0;
    return (best / (best + 4)).clamp(0.0, 0.5); // weaker without context
  }

  /// Top follow-up track ids for a query, ordered by weight.
  List<String> topFollowups(String query, {int limit = 10}) {
    final edges = _edges[_normalizeQuery(query)];
    if (edges == null) return const [];
    final sorted = edges.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }

  /// Rebuild from persisted store on startup.
  Future<void> loadFromStore() async {
    if (store == null || _lastLoaded != null) return;
    try {
      final transitions = await store!.loadTransitions();
      for (final t in transitions) {
        final edges =
            _edges.putIfAbsent(_normalizeQuery(t.queryNormalized), () => {});
        edges[t.trackId] = (edges[t.trackId] ?? 0) + 1;
      }
      _lastLoaded = DateTime.now();
      if (kDebugMode && transitions.isNotEmpty) {
        debugPrint(
            'SearchFollowupGraph: loaded ${transitions.length} transitions');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('SearchFollowupGraph: load failed: $e');
    }
  }

  /// Apply daily decay to all edges (call after load / periodically).
  void applyDecay({required int daysSinceLastUse}) {
    if (daysSinceLastUse <= 0) return;
    final factor = _dailyDecayPow(daysSinceLastUse);
    for (final edges in _edges.values) {
      for (final key in edges.keys.toList()) {
        final v = edges[key]! * factor;
        if (v < 0.1) {
          edges.remove(key);
        } else {
          edges[key] = v;
        }
      }
    }
  }

  static double _dailyDecayPow(int days) {
    var f = 1.0;
    for (var i = 0; i < days && f > 0.3; i++) {
      f *= _dailyDecay;
    }
    return f;
  }

  static String _normalizeQuery(String q) =>
      q.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  int get edgeCount => _edges.values.fold(0, (n, e) => n + e.length);
}
