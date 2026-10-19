// lib/presentation/history/history_groups.dart
//
// History grouped by when you played it: Today, Yesterday, This week, Earlier.
// Pure. The list order (newest first) is kept; each song lands in the group its
// last play falls in. A song with no entry in the play log (played before the
// log existed) is "Earlier" - it is never given a date it does not have.

import '../../models/track.dart';

class HistoryGroup {
  const HistoryGroup(this.label, this.tracks);

  final String label;
  final List<Track> tracks;
}

String historyBucket(int? playedAtMs, DateTime now) {
  if (playedAtMs == null) return 'Earlier';
  final at = DateTime.fromMillisecondsSinceEpoch(playedAtMs);
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return 'This week';
  return 'Earlier';
}

/// [tracks] (newest first) split into consecutive groups. Two songs in the same
/// bucket that are not adjacent (an old play replayed recently is moved by the
/// provider to the front, so this does not happen in practice) stay in separate
/// groups rather than being re-ordered.
List<HistoryGroup> groupHistory(List<Track> tracks, Map<String, int> lastPlayed, DateTime now) {
  final groups = <HistoryGroup>[];
  String? label;
  var current = <Track>[];
  for (final t in tracks) {
    final b = historyBucket(lastPlayed[t.id], now);
    if (b != label) {
      if (label != null) groups.add(HistoryGroup(label, current));
      label = b;
      current = <Track>[];
    }
    current.add(t);
  }
  if (label != null) groups.add(HistoryGroup(label, current));
  return groups;
}
