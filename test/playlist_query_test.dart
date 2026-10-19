import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/playlist.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/presentation/playlists/playlist_query.dart';

Track t(String id, String title, [String artist = 'A']) =>
    Track(id: id, trackName: title, artistName: artist, albumName: 'B', previewUrl: '');

Playlist pl(String id, String name,
        {List<Track> tracks = const [], int? updated, bool pinned = false, int? order}) =>
    Playlist(id: id, name: name, imageUrl: '', tracks: tracks, updatedAtMs: updated, pinned: pinned, customOrder: order);

void main() {
  // List order = creation order (oldest first).
  final chill = pl('pl_1', 'Chill', tracks: [t('1', 'Borderline'), t('2', 'Currents')], updated: 300);
  final focus = pl('pl_2', 'Focus', tracks: [t('3', 'Weightless')], updated: 100);
  final gym = pl('pl_3', 'Workout', tracks: [t('4', 'Lose Yourself'), t('5', 'Till I Collapse'), t('6', 'X')], updated: 200);
  final imported = pl('PLabc', 'Road Trip', tracks: [t('7', 'Africa')]);
  final all = [chill, focus, gym, imported];
  List<String> names(List<PlaylistMatch> m) => m.map((e) => e.playlist.name).toList();

  group('sort', () {
    test('recently updated: newest change first; an unknown time sinks, ties keep newest-created first', () {
      expect(sortPlaylists(all, PlaylistSort.recentlyUpdated).map((p) => p.name),
          ['Chill', 'Workout', 'Focus', 'Road Trip']);
    });

    test('pinned always first, in whatever sort', () {
      final pinned = [...all, pl('pl_9', 'Pinned', pinned: true, updated: 1)];
      for (final s in PlaylistSort.values) {
        expect(sortPlaylists(pinned, s).first.name, 'Pinned', reason: s.name);
      }
    });

    test('name ignores case and accents', () {
      final r = sortPlaylists([pl('1', 'zebra'), pl('2', 'Éclair'), pl('3', 'apple')], PlaylistSort.name);
      expect(r.map((p) => p.name), ['apple', 'Éclair', 'zebra']);
    });

    test('most songs, then name', () {
      expect(sortPlaylists(all, PlaylistSort.mostSongs).map((p) => p.name),
          ['Workout', 'Chill', 'Focus', 'Road Trip']);
    });

    test('recently played uses the play map, then falls back to updated', () {
      final r = sortPlaylists(all, PlaylistSort.recentlyPlayed, playedAt: {'pl_2': 9999});
      expect(r.map((p) => p.name), ['Focus', 'Chill', 'Workout', 'Road Trip']);
    });

    test('custom order: placed ones in order, unplaced after', () {
      final r = sortPlaylists(
        [pl('1', 'A'), pl('2', 'B', order: 1), pl('3', 'C', order: 0), pl('4', 'D')],
        PlaylistSort.custom,
      );
      expect(r.map((p) => p.name), ['C', 'B', 'D', 'A']);
    });

    test('a stored sort name round-trips; unknown falls back', () {
      expect(PlaylistSort.fromName('mostSongs'), PlaylistSort.mostSongs);
      expect(PlaylistSort.fromName('???'), PlaylistSort.recentlyUpdated);
    });
  });

  group('filters', () {
    test('created / imported use the id', () {
      expect(names(applyPlaylistQuery(all, const PlaylistQuery(filter: PlaylistFilter.created))),
          ['Chill', 'Workout', 'Focus']);
      expect(names(applyPlaylistQuery(all, const PlaylistQuery(filter: PlaylistFilter.imported))), ['Road Trip']);
    });

    test('downloaded needs every song on the device and at least one song', () {
      final r = applyPlaylistQuery([...all, pl('pl_5', 'Empty')], const PlaylistQuery(filter: PlaylistFilter.downloaded),
          isDownloaded: (id) => {'1', '2', '3'}.contains(id));
      expect(names(r), ['Chill', 'Focus']);
    });
  });

  group('search', () {
    test('matches the name, accents and case aside', () {
      expect(names(applyPlaylistQuery(all, const PlaylistQuery(search: 'CHILL'))), ['Chill']);
      expect(applyPlaylistQuery(all, const PlaylistQuery(search: 'CHILL')).single.containsSong, isNull);
    });

    test('falls back to the songs inside, and says which', () {
      final r = applyPlaylistQuery(all, const PlaylistQuery(search: 'borderline'));
      expect(names(r), ['Chill']);
      expect(r.single.containsSong, 'Borderline');
    });

    test('every word must match one place (name, or one song)', () {
      expect(applyPlaylistQuery(all, const PlaylistQuery(search: 'chill weightless')), isEmpty);
    });

    test('search composes with a filter', () {
      expect(applyPlaylistQuery(all, const PlaylistQuery(search: 'a', filter: PlaylistFilter.imported)).single.playlist.name,
          'Road Trip');
    });

    test('narrowed and signature', () {
      expect(const PlaylistQuery().isNarrowed, isFalse);
      expect(const PlaylistQuery(search: ' ').isNarrowed, isFalse);
      expect(const PlaylistQuery(filter: PlaylistFilter.created).isNarrowed, isTrue);
      expect(const PlaylistQuery(search: 'Café').signature, const PlaylistQuery(search: 'cafe').signature);
    });
  });

  group('wording', () {
    final now = DateTime(2026, 10, 20, 15);
    test('relative day', () {
      String r(DateTime d) => relativeDay(d, now);
      expect(r(DateTime(2026, 10, 20, 1)), 'today');
      expect(r(DateTime(2026, 10, 19, 23, 59)), 'yesterday', reason: 'calendar days, not 24 h');
      expect(r(DateTime(2026, 10, 17)), '3 days ago');
      expect(r(DateTime(2026, 10, 13)), '1 week ago');
      expect(r(DateTime(2026, 10, 1)), '2 weeks ago');
      expect(r(DateTime(2026, 8, 1)), '2 months ago');
      expect(r(DateTime(2025, 1, 1)), 'over a year ago');
      expect(r(DateTime(2026, 10, 21)), 'today', reason: 'a future stamp never prints a negative');
    });

    test('meta line', () {
      expect(playlistMetaLine(pl('pl_1', 'x', tracks: [t('1', 'a')], updated: DateTime(2026, 10, 19).millisecondsSinceEpoch), now),
          '1 song · Updated yesterday');
      expect(playlistMetaLine(pl('pl_2', 'x', updated: DateTime(2026, 10, 20).millisecondsSinceEpoch), now),
          'Empty · Updated today');
      expect(playlistMetaLine(imported, now), '1 song', reason: 'no known time, no invented clause');
    });
  });
}
