// lib/presentation/liked/liked_songs_query.dart
//
// What the Liked Songs list shows, given what the listener asked for.
//
// Pure: tracks + a query in, the visible list out. Play and Shuffle act on that
// visible list, so "search 'tame', press Play" plays exactly what is on screen.
//
// Rules:
//   * Recently added is the stored order: likeSong inserts at the front and an
//     undo puts a song back at its old position, so list order IS added order.
//   * Text sorts compare a folded form (case and common accents removed) and
//     fall back to stored order, so ties are stable.
//   * Most played reads the local play log; unplayed songs keep stored order
//     after the played ones.
//   * Search matches every word against title, artist and album (folded).
//   * Filters are single-select: Downloaded, one artist (duets count for both
//     artists), or one genre (only offered when the source tagged genres).

import '../../models/track.dart';
import '../../services/replay/replay_summary.dart' show ReplaySummary;

enum LikedSort {
  recentlyAdded('Recently added'),
  title('Title'),
  artist('Artist'),
  album('Album'),
  mostPlayed('Most played');

  const LikedSort(this.label);
  final String label;

  static LikedSort fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => recentlyAdded);
}

enum LikedFilterKind { downloaded, artist, genre }

/// One filter chip. [value] is the artist or genre for those kinds.
class LikedFilter {
  const LikedFilter.downloaded()
      : kind = LikedFilterKind.downloaded,
        value = '';
  const LikedFilter.artist(this.value) : kind = LikedFilterKind.artist;
  const LikedFilter.genre(this.value) : kind = LikedFilterKind.genre;

  final LikedFilterKind kind;
  final String value;

  String get label => kind == LikedFilterKind.downloaded ? 'Downloaded' : value;

  @override
  bool operator ==(Object other) =>
      other is LikedFilter &&
      other.kind == kind &&
      normalizeForSearch(other.value) == normalizeForSearch(value);

  @override
  int get hashCode => Object.hash(kind, normalizeForSearch(value));
}

class LikedQuery {
  const LikedQuery({
    this.sort = LikedSort.recentlyAdded,
    this.filter,
    this.search = '',
  });

  final LikedSort sort;
  final LikedFilter? filter;
  final String search;

  bool get isNarrowed => filter != null || search.trim().isNotEmpty;

  LikedQuery copyWith({
    LikedSort? sort,
    LikedFilter? filter,
    bool clearFilter = false,
    String? search,
  }) =>
      LikedQuery(
        sort: sort ?? this.sort,
        filter: clearFilter ? null : (filter ?? this.filter),
        search: search ?? this.search,
      );

  /// Identity of what is shown, for keyed transitions.
  String get signature =>
      '${sort.name}|${filter?.kind.name}:${filter?.value}|${normalizeForSearch(search)}';
}

const Map<String, String> _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
  'ç': 'c', 'ć': 'c', 'č': 'c',
  'ď': 'd', 'đ': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
  'ğ': 'g',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ı': 'i',
  'ł': 'l', 'ľ': 'l',
  'ñ': 'n', 'ń': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o',
  'ř': 'r',
  'ś': 's', 'š': 's', 'ş': 's', 'ß': 'ss',
  'ť': 't', 'ţ': 't',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u',
  'ý': 'y', 'ÿ': 'y',
  'ź': 'z', 'ż': 'z', 'ž': 'z',
  '’': "'", '‘': "'",
};

/// Lower-cased, common accents folded, whitespace collapsed. Non-Latin scripts
/// are kept as they are, so searching in them still works.
String normalizeForSearch(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_fold[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _matches(Track t, List<String> words) {
  if (words.isEmpty) return true;
  final hay = normalizeForSearch('${t.trackName} ${t.artistName} ${t.albumName}');
  return words.every(hay.contains);
}

bool _passes(Track t, LikedFilter? f, bool Function(String id) isDownloaded) {
  if (f == null) return true;
  switch (f.kind) {
    case LikedFilterKind.downloaded:
      return t.source == 'local' || isDownloaded(t.id);
    case LikedFilterKind.artist:
      final want = normalizeForSearch(f.value);
      return ReplaySummary.splitArtists(t.artistName)
          .any((a) => normalizeForSearch(a) == want);
    case LikedFilterKind.genre:
      return normalizeForSearch(t.genre ?? '') == normalizeForSearch(f.value);
  }
}

/// The visible list for [query] over [tracks] (stored, newest-first order).
List<Track> applyLikedQuery(
  List<Track> tracks,
  LikedQuery query, {
  Map<String, int> playCounts = const {},
  bool Function(String id)? isDownloaded,
}) {
  final downloaded = isDownloaded ?? (_) => false;
  final words = normalizeForSearch(query.search)
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList(growable: false);

  // Index pairs keep stored order as the tie-break for every sort.
  final rows = <(int, Track)>[
    for (var i = 0; i < tracks.length; i++)
      if (_passes(tracks[i], query.filter, downloaded) && _matches(tracks[i], words))
        (i, tracks[i]),
  ];

  int byText(String a, String b) =>
      normalizeForSearch(a).compareTo(normalizeForSearch(b));

  switch (query.sort) {
    case LikedSort.recentlyAdded:
      break;
    case LikedSort.title:
      rows.sort((a, b) {
        final c = byText(a.$2.trackName, b.$2.trackName);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    case LikedSort.artist:
      rows.sort((a, b) {
        var c = byText(a.$2.artistName, b.$2.artistName);
        if (c == 0) c = byText(a.$2.albumName, b.$2.albumName);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    case LikedSort.album:
      rows.sort((a, b) {
        var c = byText(a.$2.albumName, b.$2.albumName);
        if (c == 0) c = byText(a.$2.artistName, b.$2.artistName);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    case LikedSort.mostPlayed:
      rows.sort((a, b) {
        final c = (playCounts[b.$2.id] ?? 0).compareTo(playCounts[a.$2.id] ?? 0);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
  }
  return [for (final r in rows) r.$2];
}

/// The chips worth offering for [tracks]: Downloaded when anything is, artists
/// with at least two songs (most first, up to [maxArtists]), genres likewise
/// when tagged. Fewer than two options of a kind is not a filter.
List<LikedFilter> likedFilterChips(
  List<Track> tracks, {
  bool Function(String id)? isDownloaded,
  int maxArtists = 8,
}) {
  final downloaded = isDownloaded ?? (_) => false;
  final chips = <LikedFilter>[];
  if (tracks.any((t) => t.source == 'local' || downloaded(t.id))) {
    chips.add(const LikedFilter.downloaded());
  }

  List<String> top(Iterable<String> names, int max) {
    final counts = <String, int>{};
    final display = <String, String>{};
    for (final n in names) {
      final key = normalizeForSearch(n);
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      display.putIfAbsent(key, () => n.trim());
    }
    final keys = counts.keys.where((k) => counts[k]! >= 2).toList()
      ..sort((a, b) {
        final c = counts[b]!.compareTo(counts[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    return [for (final k in keys.take(max)) display[k]!];
  }

  chips.addAll(top(
    tracks.expand((t) => ReplaySummary.splitArtists(t.artistName)),
    maxArtists,
  ).map(LikedFilter.artist));
  chips.addAll(top(
    tracks.map((t) => t.genre ?? ''),
    6,
  ).map(LikedFilter.genre));
  return chips;
}

/// "7 hr 12 min" / "48 min" for a list, or null when too few durations are
/// known (under 80%) for the total to mean anything.
String? formatCollectionDuration(List<Track> tracks) {
  if (tracks.isEmpty) return null;
  var known = 0;
  var ms = 0;
  for (final t in tracks) {
    final d = t.durationMs;
    if (d != null && d > 0) {
      known++;
      ms += d;
    }
  }
  if (known < tracks.length * 0.8) return null;
  final minutes = (ms / Duration.millisecondsPerMinute).round();
  if (minutes < 1) return null;
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h hr' : '$h hr $m min';
}
