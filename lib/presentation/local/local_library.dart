// lib/presentation/local/local_library.dart
//
// The Local Files screen's data, pure: search, the four views (songs, albums,
// artists, folders), and the words for the sort options.
//
// Folder is the file's parent directory, read from the path string (no disk
// access), so this works on any platform and in tests.

import '../../models/track.dart';
import '../../services/local_music_service.dart' show SortCriteria;
import '../../services/replay/replay_summary.dart' show ReplaySummary;
import '../liked/liked_songs_query.dart' show normalizeForSearch;

enum LocalView {
  songs('Songs'),
  albums('Albums'),
  artists('Artists'),
  folders('Folders');

  const LocalView(this.label);
  final String label;
}

class LocalGroup {
  const LocalGroup({required this.key, required this.label, required this.tracks, this.subtitle = ''});

  final String key;
  final String label;

  /// Albums: the album's artist (or "Various artists"). Folders: the folder's path.
  final String subtitle;
  final List<Track> tracks;
}

/// The directory a local file is in ("/storage/emulated/0/Music/Indie").
String folderPathOf(Track t) {
  final p = t.previewUrl.isNotEmpty ? t.previewUrl : t.id;
  final i = p.lastIndexOf(RegExp(r'[\\/]'));
  return i <= 0 ? '' : p.substring(0, i);
}

/// The last segment of [folderPathOf] ("Indie").
String folderNameOf(Track t) {
  final dir = folderPathOf(t);
  final i = dir.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? dir : dir.substring(i + 1);
}

/// Empty, MediaStore's `<unknown>`, or the scanner's "Unknown Artist/Album".
bool isUnknownTag(String s) {
  final v = s.trim().toLowerCase();
  return v.isEmpty || v == '<unknown>' || v == 'unknown artist' || v == 'unknown album' || v == 'unknown';
}

/// The album's artist: the lead artist most of its songs credit, or
/// "Various artists" when no one leads at least half of them.
String _albumArtist(List<Track> songs) {
  final counts = <String, ({String name, int n})>{};
  for (final t in songs) {
    final lead = ReplaySummary.splitArtists(t.artistName).firstOrNull ?? t.artistName;
    if (isUnknownTag(lead)) continue;
    final k = normalizeForSearch(lead);
    counts[k] = (name: counts[k]?.name ?? lead.trim(), n: (counts[k]?.n ?? 0) + 1);
  }
  if (counts.isEmpty) return 'Unknown artist';
  final top = counts.values.reduce((a, b) => b.n > a.n ? b : a);
  return top.n * 2 >= songs.length ? top.name : 'Various artists';
}

List<Track> searchLocal(List<Track> tracks, String query) {
  final words = normalizeForSearch(query).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return tracks;
  return tracks.where((t) {
    final hay = normalizeForSearch('${t.trackName} ${t.artistName} ${t.albumName} ${folderNameOf(t)}');
    return words.every(hay.contains);
  }).toList();
}

/// [tracks] grouped for [view] (not [LocalView.songs]), groups sorted by name,
/// songs inside a group kept in the order given. An artist credit naming
/// several artists files the song under each of them.
List<LocalGroup> groupLocal(List<Track> tracks, LocalView view) {
  final groups = <String, ({String label, String subtitle, List<Track> tracks})>{};
  void add(String key, String label, String subtitle, Track t) {
    final g = groups.putIfAbsent(key, () => (label: label, subtitle: subtitle, tracks: <Track>[]));
    g.tracks.add(t);
  }

  for (final t in tracks) {
    switch (view) {
      case LocalView.songs:
        break;
      case LocalView.albums:
        // An album is its name in its folder: a duet or a guest verse stays on
        // its album, and two "Greatest Hits" in different folders stay apart.
        if (isUnknownTag(t.albumName)) {
          add('unknown album', 'Unknown album', '', t);
        } else {
          add('${normalizeForSearch(t.albumName)}|${folderPathOf(t)}', t.albumName.trim(), '', t);
        }
      case LocalView.artists:
        final names = ReplaySummary.splitArtists(t.artistName).where((a) => !isUnknownTag(a)).toList();
        if (names.isEmpty) {
          add('unknown artist', 'Unknown artist', '', t);
        } else {
          for (final a in names) {
            add(normalizeForSearch(a), a.trim(), '', t);
          }
        }
      case LocalView.folders:
        final dir = folderPathOf(t);
        final name = folderNameOf(t);
        add(dir, name.isEmpty ? 'Device' : name, dir, t);
    }
  }
  final out = [
    for (final e in groups.entries)
      LocalGroup(
        key: e.key,
        label: e.value.label,
        subtitle: view == LocalView.albums ? _albumArtist(e.value.tracks) : e.value.subtitle,
        tracks: e.value.tracks,
      ),
  ]..sort((a, b) {
      // "Unknown …" sinks to the end; the rest alphabetically.
      final ua = a.label.startsWith('Unknown'), ub = b.label.startsWith('Unknown');
      if (ua != ub) return ua ? 1 : -1;
      final byName = normalizeForSearch(a.label).compareTo(normalizeForSearch(b.label));
      return byName != 0 ? byName : normalizeForSearch(a.subtitle).compareTo(normalizeForSearch(b.subtitle));
    });
  return out;
}

String sortLabel(SortCriteria c) => switch (c) {
      SortCriteria.nameAsc => 'Title (A-Z)',
      SortCriteria.nameDesc => 'Title (Z-A)',
      SortCriteria.artistAsc => 'Artist (A-Z)',
      SortCriteria.artistDesc => 'Artist (Z-A)',
      SortCriteria.albumAsc => 'Album (A-Z)',
      SortCriteria.albumDesc => 'Album (Z-A)',
      SortCriteria.durationAsc => 'Shortest first',
      SortCriteria.durationDesc => 'Longest first',
      SortCriteria.folderAsc => 'Folder (A-Z)',
      SortCriteria.folderDesc => 'Folder (Z-A)',
      SortCriteria.dateAddedAsc => 'Oldest files first',
      SortCriteria.dateAddedDesc => 'Newest files first',
    };
