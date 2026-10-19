import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/playlist.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track _t(String id) => Track(id: id, trackName: 'Song $id', artistName: 'A', albumName: 'B', previewUrl: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MusicProvider p;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // The provider loads its saved playlists during initialisation and replaces
    // the list when it finishes; wait for that, or a late load races the tests.
    final ready = Completer<void>();
    final original = debugPrint;
    debugPrint = (msg, {wrapWidth}) {
      if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) {
        ready.complete();
      }
    };
    // The real provider: MockMusicProvider overrides userPlaylists.
    p = MusicProvider();
    await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    debugPrint = original;
  });

  setUp(() async {
    for (final pl in List.of(p.userPlaylists)) {
      p.deletePlaylistWithUndo(pl.id);
    }
  });

  Future<Playlist> make(String name, [List<String> ids = const []]) async {
    final pl = await p.createPlaylistWith(name: name, tracks: [for (final i in ids) _t(i)]);
    return pl!;
  }

  List<String> ids(String plId) => p.playlistById(plId)!.tracks.map((t) => t.id).toList();

  group('model', () {
    test('old saves load, new fields are written only when set', () {
      final old = Playlist.fromJson({'id': 'pl_1700000000000', 'name': 'Old', 'imageUrl': '', 'tracks': []});
      expect(old.description, '');
      expect(old.pinned, isFalse);
      expect(old.created, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(old.updated, old.created, reason: 'no stamp: reports creation, invents nothing');
      expect(old.isUserCreated, isTrue);
      expect(old.toJson().keys, {'id', 'name', 'imageUrl', 'tracks'});

      final imported = Playlist.fromJson({'id': 'PLabc', 'name': 'I', 'imageUrl': '', 'tracks': []});
      expect(imported.isUserCreated, isFalse);
      expect(imported.created, isNull);
    });

    test('new fields round-trip', () {
      final pl = Playlist(
          id: 'pl_1', name: 'N', imageUrl: '', tracks: const [], description: 'd', createdAtMs: 5, updatedAtMs: 9, pinned: true, customOrder: 2);
      final back = Playlist.fromJson(pl.toJson());
      expect((back.description, back.createdAtMs, back.updatedAtMs, back.pinned, back.customOrder), ('d', 5, 9, true, 2));
    });
  });

  group('create / edit', () {
    test('creating stamps times and drops duplicate songs', () async {
      final pl = await p.createPlaylistWith(name: '  Mix  ', tracks: [_t('a'), _t('a'), _t('b')], description: ' hi ');
      expect(pl!.name, 'Mix');
      expect(pl.description, 'hi');
      expect(pl.tracks.map((t) => t.id), ['a', 'b']);
      expect(pl.createdAtMs, isNotNull);
      expect(pl.updatedAtMs, pl.createdAtMs);
    });

    test('an empty name makes nothing', () async {
      expect(await p.createPlaylistWith(name: '   '), isNull);
      expect(p.userPlaylists, isEmpty);
    });

    test('updatePlaylist changes only what it is given and stamps the time', () async {
      final pl = await make('One', ['a']);
      await Future<void>.delayed(const Duration(milliseconds: 3)); // a later stamp
      await p.updatePlaylist(pl.id, description: 'new words');
      final u = p.playlistById(pl.id)!;
      expect((u.name, u.description), ('One', 'new words'));
      expect(u.updatedAtMs! > pl.updatedAtMs!, isTrue);
      await p.updatePlaylist(pl.id, name: '   ');
      expect(p.playlistById(pl.id)!.name, 'One', reason: 'a blank name is ignored');
    });
  });

  group('songs', () {
    test('adding skips songs already there and reports how many were new', () async {
      final pl = await make('P', ['a', 'b']);
      expect(await p.addTracksToPlaylist(pl.id, [_t('b'), _t('c'), _t('c'), _t('d')]), 2);
      expect(ids(pl.id), ['a', 'b', 'c', 'd']);
      expect(await p.addTracksToPlaylist(pl.id, [_t('a')]), 0);
      expect(await p.addTracksToPlaylist('nope', [_t('a')]), 0);
    });

    test('batch remove and undo restore every position, once', () async {
      final pl = await make('P', ['a', 'b', 'c', 'd']);
      final removed = p.removeTracksFromPlaylist(pl.id, ['b', 'd']);
      expect(ids(pl.id), ['a', 'c']);
      expect(removed.map((r) => r.index), [1, 3]);
      p.restorePlaylistTracks(pl.id, removed);
      expect(ids(pl.id), ['a', 'b', 'c', 'd']);
      p.restorePlaylistTracks(pl.id, removed);
      expect(ids(pl.id), ['a', 'b', 'c', 'd'], reason: 'a second undo adds nothing');
    });

    test('unknown ids remove nothing and do not notify', () async {
      final pl = await make('P', ['a']);
      var n = 0;
      void l() => n++;
      p.addListener(l);
      expect(p.removeTracksFromPlaylist(pl.id, ['zzz']), isEmpty);
      expect(n, 0);
      p.removeListener(l);
    });

    test('reorder follows ReorderableListView semantics', () async {
      final pl = await make('P', ['a', 'b', 'c', 'd']);
      p.reorderPlaylistTrack(pl.id, 0, 3); // a to just before d
      expect(ids(pl.id), ['b', 'c', 'a', 'd']);
      p.reorderPlaylistTrack(pl.id, 3, 0); // d to the top
      expect(ids(pl.id), ['d', 'b', 'c', 'a']);
      p.reorderPlaylistTrack(pl.id, 1, 2); // no-op: already there
      expect(ids(pl.id), ['d', 'b', 'c', 'a']);
      p.reorderPlaylistTrack(pl.id, 9, 0);
      expect(ids(pl.id), ['d', 'b', 'c', 'a'], reason: 'out of range is ignored');
    });

    test('playlistsContaining finds every playlist with the song', () async {
      final a = await make('A', ['x', 'y']);
      final b = await make('B', ['y']);
      await make('C', ['z']);
      expect(p.playlistsContaining('y').map((e) => e.id), [a.id, b.id]);
      expect(p.playlistsContaining('none'), isEmpty);
    });
  });

  group('arranging', () {
    test('pinning does not change "recently updated"', () async {
      final pl = await make('P');
      p.setPlaylistPinned(pl.id, true);
      final u = p.playlistById(pl.id)!;
      expect(u.pinned, isTrue);
      expect(u.updatedAtMs, pl.updatedAtMs);
    });

    test('custom order is stored per playlist', () async {
      final a = await make('A');
      final b = await make('B');
      p.setPlaylistOrder([b.id, a.id]);
      expect((p.playlistById(b.id)!.customOrder, p.playlistById(a.id)!.customOrder), (0, 1));
    });

    test('delete with undo puts the playlist back where it was, with its songs', () async {
      final a = await make('A', ['1']);
      final b = await make('B', ['2', '3']);
      final c = await make('C');
      final removed = p.deletePlaylistWithUndo(b.id)!;
      expect(p.userPlaylists.map((e) => e.id), [a.id, c.id]);
      p.restorePlaylist(removed);
      expect(p.userPlaylists.map((e) => e.id), [a.id, b.id, c.id]);
      expect(ids(b.id), ['2', '3']);
      p.restorePlaylist(removed);
      expect(p.userPlaylists, hasLength(3), reason: 'no duplicate on a second undo');
    });

    test('marking played is remembered', () async {
      final a = await make('A');
      expect(p.playlistLastPlayedMs(a.id), isNull);
      p.markPlaylistPlayed(a.id);
      expect(p.playlistLastPlayedMs(a.id), isNotNull);
      p.markPlaylistPlayed('nope');
      expect(p.playlistLastPlayedMs('nope'), isNull);
    });
  });
}
