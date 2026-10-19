import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/playlist.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/playlist/add_to_playlist_sheet.dart';
import 'package:music_streaming_app/widgets/playlist/playlist_cover.dart';
import 'package:music_streaming_app/widgets/playlist/playlist_edit_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ADD TO PLAYLIST and CREATE / EDIT, on the screen.

Track _t(String id, [String? title]) => Track(
      id: id,
      trackName: title ?? 'Song $id',
      artistName: 'Artist',
      albumName: 'Album',
      albumArtUrl: 'https://example.com/$id.jpg',
      previewUrl: '',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MusicProvider p;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final ready = Completer<void>();
    final original = debugPrint;
    debugPrint = (msg, {wrapWidth}) {
      if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) ready.complete();
    };
    p = MusicProvider();
    await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    debugPrint = original;
  });

  setUp(() {
    for (final pl in List.of(p.userPlaylists)) {
      p.deletePlaylistWithUndo(pl.id);
    }
  });

  Future<Playlist> seed(String name, [List<String> ids = const []]) async {
    return (await p.createPlaylistWith(name: name, tracks: [for (final i in ids) _t(i)]))!;
  }

  late Future<void> Function(BuildContext) opener;
  Future<void> pumpApp(WidgetTester tester, {double scale = 1.0, Size size = const Size(412, 900)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
      value: p,
      child: MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(onPressed: () => opener(context), child: const Text('open')),
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('Add to playlist', () {
    testWidgets('New playlist first, then yours; tick two and add', (tester) async {
      final a = await seed('Chill');
      final b = await seed('Focus');
      opener = (c) => showAddToPlaylistSheet(c, [_t('x', 'Borderline')]);
      await pumpApp(tester);
      await open(tester);

      expect(find.text('Add to playlist'), findsOneWidget);
      expect(find.text('Borderline'), findsOneWidget);
      final newY = tester.getTopLeft(find.text('New playlist')).dy;
      expect(newY < tester.getTopLeft(find.text('Chill')).dy, isTrue);

      await tester.tap(find.text('Chill'));
      await tester.pump();
      await tester.tap(find.text('Focus'));
      await tester.pump();
      await tester.tap(find.text('Add to 2 playlists'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(p.playlistById(a.id)!.tracks.map((t) => t.id), ['x']);
      expect(p.playlistById(b.id)!.tracks.map((t) => t.id), ['x']);
      expect(find.text('Added to 2 playlists'), findsOneWidget);
    });

    testWidgets('a playlist that already has the song says so and cannot be ticked', (tester) async {
      await seed('Has it', ['x']);
      final other = await seed('Not yet');
      opener = (c) => showAddToPlaylistSheet(c, [_t('x')]);
      await pumpApp(tester);
      await open(tester);

      expect(find.text('Already in this playlist'), findsOneWidget);
      await tester.tap(find.text('Has it'));
      await tester.pump();
      expect(find.text('Choose playlists'), findsOneWidget, reason: 'nothing got ticked');

      await tester.tap(find.text('Not yet'));
      await tester.pump();
      expect(find.text('Add to Not yet'), findsOneWidget);
      await tester.tap(find.text('Add to Not yet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(p.playlistById(other.id)!.tracks, hasLength(1));
    });

    testWidgets('several songs: partial overlap is counted, duplicates skipped', (tester) async {
      final pl = await seed('Mix', ['a']);
      opener = (c) => showAddToPlaylistSheet(c, [_t('a'), _t('b'), _t('c')]);
      await pumpApp(tester);
      await open(tester);

      expect(find.text('3 songs'), findsOneWidget);
      expect(find.text('1 already in · 1 song'), findsOneWidget);
      await tester.tap(find.text('Mix'));
      await tester.pump();
      await tester.tap(find.text('Add to Mix'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(p.playlistById(pl.id)!.tracks.map((t) => t.id), ['a', 'b', 'c']);
    });

    testWidgets('New playlist from the sheet makes one with the songs', (tester) async {
      opener = (c) => showAddToPlaylistSheet(c, [_t('x', 'Borderline'), _t('y')]);
      await pumpApp(tester);
      await open(tester);

      expect(find.text('You have no playlists yet. Make the first one.'), findsOneWidget);
      await tester.tap(find.text('New playlist'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Starts with 2 songs'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Late drive');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(p.userPlaylists.single.name, 'Late drive');
      expect(p.userPlaylists.single.tracks.map((t) => t.id), ['x', 'y']);
      expect(find.text('Created "Late drive" with 2 songs'), findsOneWidget);
    });

    testWidgets('search appears with many playlists', (tester) async {
      for (var i = 0; i < 7; i++) {
        await seed('List $i');
      }
      opener = (c) => showAddToPlaylistSheet(c, [_t('x')]);
      await pumpApp(tester, size: const Size(412, 1100));
      await open(tester);
      await tester.enterText(find.byType(TextField), 'list 3');
      await tester.pump();
      expect(find.text('List 3'), findsOneWidget);
      expect(find.text('List 4'), findsNothing);
    });

    for (final (size, scale) in const [(Size(360, 640), 1.3), (Size(360, 900), 1.0)]) {
      testWidgets('no layout errors at ${size.width.toInt()}x${size.height.toInt()}, text x$scale', (tester) async {
        await seed('A very long playlist name that keeps on going and going past the edge of the row');
        opener = (c) => showAddToPlaylistSheet(c, [_t('x', 'An equally long song title that also keeps going')]);
        await pumpApp(tester, size: size, scale: scale);
        await open(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Create / edit', () {
    testWidgets('Save needs a name; saving creates the playlist with its description', (tester) async {
      Playlist? result;
      opener = (c) async => result = await showPlaylistEditSheet(c);
      await pumpApp(tester);
      await open(tester);

      expect(find.text('New playlist'), findsOneWidget);
      Future<void> trySave() async {
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      await trySave();
      expect(p.userPlaylists, isEmpty, reason: 'no name, no playlist');

      await tester.enterText(find.widgetWithText(TextField, 'Playlist name'), '  Road  ');
      await tester.enterText(find.widgetWithText(TextField, 'Description'), 'For long drives');
      await tester.pump();
      await trySave();
      expect(result?.name, 'Road');
      expect(p.userPlaylists.single.description, 'For long drives');
    });

    testWidgets('editing changes name, description and the chosen cover only', (tester) async {
      final pl = await seed('Old name', ['a', 'b']);
      opener = (c) => showPlaylistEditSheet(c, existing: p.playlistById(pl.id), coverPicker: () async => '/tmp/cover.png');
      await pumpApp(tester);
      await open(tester);

      expect(find.text('Edit playlist'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Playlist name'), 'New name');
      await tester.tap(find.bySemanticsLabel('Change image'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Choose from device'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final u = p.playlistById(pl.id)!;
      expect((u.name, u.imageUrl), ('New name', '/tmp/cover.png'));
      expect(u.tracks.map((t) => t.id), ['a', 'b'], reason: 'songs untouched');
    });

    testWidgets('cancel changes nothing', (tester) async {
      final pl = await seed('Keep', ['a']);
      opener = (c) => showPlaylistEditSheet(c, existing: p.playlistById(pl.id));
      await pumpApp(tester);
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Playlist name'), 'Changed');
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(p.playlistById(pl.id)!.name, 'Keep');
    });
  });

  group('cover', () {
    test('local paths are recognised, web urls are not', () {
      expect(isLocalImagePath('/data/user/0/app/cover.jpg'), isTrue);
      expect(isLocalImagePath('file:///sdcard/a.png'), isTrue);
      expect(isLocalImagePath(r'C:\Users\me\a.png'), isTrue);
      expect(isLocalImagePath('https://example.com/a.jpg'), isFalse);
      expect(isLocalImagePath(''), isFalse);
    });

    test('collage needs four distinct covers; hue is stable per name', () {
      Playlist holding(List<Track> ts) => Playlist(id: 'p', name: 'n', imageUrl: '', tracks: ts);
      expect(playlistCollageCovers(holding([_t('1'), _t('2'), _t('3')])), hasLength(3));
      expect(playlistCollageCovers(holding([for (var i = 0; i < 9; i++) _t('$i')])), hasLength(4));
      expect(playlistHue('Chill'), playlistHue('chill'));
      expect(playlistHue('Chill'), isNot(playlistHue('Focus')));
    });
  });
}
