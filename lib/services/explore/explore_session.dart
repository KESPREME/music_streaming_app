import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/explore/explore_engine.dart';
import 'package:music_streaming_app/services/explore/explore_policy.dart';

/// One Explore listening session: the served stream, session-level
/// dedupe, artist-run diversity and navigation position.
///
/// Cross-session repeats are allowed (cooldown is implicit through
/// source freshness); within a session an item is never served twice.
class ExploreSession {
  ExploreSession({
    required this.sessionId,
    required this.startedAt,
    this.seed,
  });

  final int sessionId;
  final DateTime startedAt;
  final Track? seed;

  final List<ExploreItem> items = [];
  final Set<String> shownItemIds = {};
  final Set<String> shownKeys = {}; // normalized title+artist identity
  final Set<String> playedItemIds = {};
  final List<ExploreItem> _deferred = [];

  int currentIndex = -1;
  int generation = 0;

  /// Max consecutive pages sharing a primary artist (soft cap).
  static const int maxArtistRun = ExplorePolicy.maxArtistRun;

  ExploreItem? get active =>
      (currentIndex >= 0 && currentIndex < items.length)
          ? items[currentIndex]
          : null;

  List<ExploreItem> get remaining =>
      currentIndex + 1 >= items.length
          ? const []
          : items.sublist(currentIndex + 1);

  bool get needsRefill => remaining.length <= ExplorePolicy.refillThreshold;

  String _artistKey(Track t) {
    final raw = t.artistName.split(',').first.trim().toLowerCase();
    return raw;
  }

  String _identityKey(Track t) =>
      '${t.trackName.trim().toLowerCase()}|${_artistKey(t)}';

  bool _wouldBreakArtistRun(Track t) {
    final key = _artistKey(t);
    if (key.isEmpty) return false;
    var run = 0;
    for (var i = items.length - 1; i >= 0; i--) {
      if (_artistKey(items[i].track) == key) {
        run++;
      } else {
        break;
      }
    }
    // Also count trailing deferred same-artist items queued ahead.
    return run >= maxArtistRun;
  }

  /// Append a ranked batch. Dedupes against shown ids and song identity;
  /// enforces the artist-run cap by deferring (never dropping) offenders.
  /// The cap is SOFT: blocked leftovers force through at the end of the
  /// pass so a one-artist pool can never starve the stream.
  void appendBatch(List<ExploreItem> batch) {
    generation++;
    final incoming = [..._deferred, ...batch];
    _deferred.clear();

    final placed = <ExploreItem>[];
    final leftovers = <ExploreItem>[];

    void place(ExploreItem item) {
      shownItemIds.add(item.track.id);
      shownKeys.add(_identityKey(item.track));
      items.add(item);
      placed.add(item);
    }

    for (final item in incoming) {
      final track = item.track;
      if (shownItemIds.contains(track.id)) continue;
      if (shownKeys.contains(_identityKey(track))) continue;
      if (_wouldBreakArtistRun(track)) {
        leftovers.add(item);
        continue;
      }
      place(item);
    }

    // Soft-cap yield: recheck in order; force the first blocked item if
    // nothing fits, so progress is always made.
    while (leftovers.isNotEmpty) {
      ExploreItem? forced;
      for (var i = 0; i < leftovers.length; i++) {
        final item = leftovers[i];
        if (shownItemIds.contains(item.track.id)) {
          leftovers.removeAt(i--);
          continue;
        }
        if (!_wouldBreakArtistRun(item.track)) {
          forced = leftovers.removeAt(i);
          place(item);
          break;
        }
      }
      if (forced == null && leftovers.isNotEmpty) {
        final item = leftovers.removeAt(0);
        if (!shownItemIds.contains(item.track.id)) place(item);
      }
    }
  }

  /// Move to [index] (clamped), marking the item played.
  void advanceTo(int index) {
    if (index < 0) index = 0;
    if (index > items.length - 1) index = items.length - 1;
    if (items.isEmpty) return;
    currentIndex = index;
    playedItemIds.add(items[index].track.id);
  }

  /// Items pushed into the stream but not yet reached (for prefetch).
  List<ExploreItem> upcoming({int count = ExplorePolicy.prefetchAhead}) {
    final start = currentIndex + 1;
    if (start >= items.length) return const [];
    return items.sublist(start, (start + count).clamp(start, items.length));
  }
}
