// lib/presentation/playlists/playlist_query.dart
//
// What the Your Playlists list shows, given what the listener asked for.
// Pure: playlists + a query in, the visible rows out.
//
//   * Pinned playlists always sort first.
//   * Sorts break ties by creation order (the later one first, like a feed), so
//     the list never shuffles between rebuilds.
//   * Search matches the playlist's name, and falls back to the songs inside:
//     "which playlist has Borderline?" answers with the playlist and the song.
//   * "Downloaded" means every song is on the device (an empty playlist is not).

import '../../models/playlist.dart';
import '../liked/liked_songs_query.dart' show normalizeForSearch;

String normalizeName(String s) => normalizeForSearch(s);

enum PlaylistSort {
  recentlyUpdated('Recently updated'),
  recentlyPlayed('Recently played'),
  name('Name'),
  mostSongs('Most songs'),
  custom('Custom order');

  const PlaylistSort(this.label);
  final String label;

  static PlaylistSort fromName(String? n) =>
      values.firstWhere((s) => s.name == n, orElse: () => recentlyUpdated);
}

enum PlaylistFilter {
  all('All'),
  downloaded('Downloaded'),
  created('Created by you'),
  imported('Imported');

  const PlaylistFilter(this.label);
  final String label;
}

class PlaylistQuery {
  const PlaylistQuery({
    this.sort = PlaylistSort.recentlyUpdated,
    this.filter = PlaylistFilter.all,
    this.search = '',
  });

  final PlaylistSort sort;
  final PlaylistFilter filter;
  final String search;

  bool get isNarrowed => filter != PlaylistFilter.all || search.trim().isNotEmpty;

  PlaylistQuery copyWith({PlaylistSort? sort, PlaylistFilter? filter, String? search}) =>
      PlaylistQuery(
        sort: sort ?? this.sort,
        filter: filter ?? this.filter,
        search: search ?? this.search,
      );

  String get signature => '${sort.name}|${filter.name}|${normalizeName(search)}';
}

/// A playlist that matched, and the song that made it match when the name did
/// not.
class PlaylistMatch {
  const PlaylistMatch(this.playlist, {this.containsSong});

  final Playlist playlist;
  final String? containsSong;
}

int _updatedMs(Playlist p) => p.updated?.millisecondsSinceEpoch ?? 0;

/// [playlists] ordered by [sort], pinned first. [playedAt] is playlist id ->
/// epoch ms of the last time it was played.
List<Playlist> sortPlaylists(
  List<Playlist> playlists,
  PlaylistSort sort, {
  Map<String, int> playedAt = const {},
}) {
  final rows = <(int, Playlist)>[for (var i = 0; i < playlists.length; i++) (i, playlists[i])];

  int tie(int a, int b) => b.compareTo(a); // later in the list first
  int byKey(int Function(Playlist) key, (int, Playlist) a, (int, Playlist) b) {
    final c = key(b.$2).compareTo(key(a.$2));
    return c != 0 ? c : tie(a.$1, b.$1);
  }

  rows.sort((a, b) {
    if (a.$2.pinned != b.$2.pinned) return a.$2.pinned ? -1 : 1;
    switch (sort) {
      case PlaylistSort.recentlyUpdated:
        return byKey(_updatedMs, a, b);
      case PlaylistSort.recentlyPlayed:
        final c = (playedAt[b.$2.id] ?? 0).compareTo(playedAt[a.$2.id] ?? 0);
        return c != 0 ? c : byKey(_updatedMs, a, b);
      case PlaylistSort.name:
        final c = normalizeName(a.$2.name).compareTo(normalizeName(b.$2.name));
        return c != 0 ? c : tie(a.$1, b.$1);
      case PlaylistSort.mostSongs:
        final c = b.$2.tracks.length.compareTo(a.$2.tracks.length);
        if (c != 0) return c;
        final n = normalizeName(a.$2.name).compareTo(normalizeName(b.$2.name));
        return n != 0 ? n : tie(a.$1, b.$1);
      case PlaylistSort.custom:
        final oa = a.$2.customOrder, ob = b.$2.customOrder;
        if (oa != null && ob != null) return oa.compareTo(ob);
        if (oa != null) return -1; // placed ones before unplaced
        if (ob != null) return 1;
        return tie(a.$1, b.$1);
    }
  });
  return [for (final r in rows) r.$2];
}

/// The visible rows for [query].
List<PlaylistMatch> applyPlaylistQuery(
  List<Playlist> playlists,
  PlaylistQuery query, {
  Map<String, int> playedAt = const {},
  bool Function(String trackId)? isDownloaded,
}) {
  final downloaded = isDownloaded ?? (_) => false;
  final words = normalizeName(query.search).split(' ').where((w) => w.isNotEmpty).toList();

  bool passes(Playlist p) => switch (query.filter) {
        PlaylistFilter.all => true,
        PlaylistFilter.downloaded => p.tracks.isNotEmpty && p.tracks.every((t) => downloaded(t.id)),
        PlaylistFilter.created => p.isUserCreated,
        PlaylistFilter.imported => !p.isUserCreated,
      };

  final out = <PlaylistMatch>[];
  for (final p in sortPlaylists(playlists, query.sort, playedAt: playedAt)) {
    if (!passes(p)) continue;
    if (words.isEmpty) {
      out.add(PlaylistMatch(p));
      continue;
    }
    final name = normalizeName(p.name);
    if (words.every(name.contains)) {
      out.add(PlaylistMatch(p));
      continue;
    }
    for (final t in p.tracks) {
      final hay = normalizeName('${t.trackName} ${t.artistName}');
      if (words.every(hay.contains)) {
        out.add(PlaylistMatch(p, containsSong: t.trackName));
        break;
      }
    }
  }
  return out;
}

/// "today", "yesterday", "3 days ago", "2 weeks ago", "4 months ago",
/// "over a year ago".
String relativeDay(DateTime when, DateTime now) {
  final d = DateTime(now.year, now.month, now.day)
      .difference(DateTime(when.year, when.month, when.day))
      .inDays;
  if (d <= 0) return 'today';
  if (d == 1) return 'yesterday';
  if (d < 7) return '$d days ago';
  if (d < 30) {
    final w = d ~/ 7;
    return w == 1 ? '1 week ago' : '$w weeks ago';
  }
  if (d < 365) {
    final m = d ~/ 30;
    return m == 1 ? '1 month ago' : '$m months ago';
  }
  return 'over a year ago';
}

/// "32 songs · Updated yesterday". The update clause is left out when it is not
/// known (an imported playlist saved before updates were stamped).
String playlistMetaLine(Playlist p, DateTime now) {
  final n = p.tracks.length;
  final songs = n == 0 ? 'Empty' : (n == 1 ? '1 song' : '$n songs');
  final u = p.updated;
  return u == null ? songs : '$songs · Updated ${relativeDay(u, now)}';
}
