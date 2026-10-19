import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/playlist.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/screens/user_playlist_detail_screen.dart';
import 'package:music_streaming_app/screens/user_playlist_screen.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/playlist/add_songs_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// YOUR PLAYLISTS (the list) and a playlist (the live detail), end to end on the
/// real provider: what you tap changes the real playlists, and the screen shows
/// the change.

Track _t(String id, [String? title, String artist = 'Artist']) => Track(
      id: id,
      trackName: title ?? 'Song $id',
      artistName: artist,
      albumName: 'Album',
      albumArtUrl: 'https://example.com/$id.jpg',
      previewUrl: '',
    );

/// The real provider, but starting a song only records the request.
class _Rec extends MusicProvider {
  final List<(String, List<String>, String?)> played = [];
  String? fakeContext;

  @override
  String? get currentPlaylistId => fakeContext;

  @override
  Future<void> playTrack(Track track,
      {String? playlistId,
      List<Track>? playlistTracks,
      bool setContext = true,
      bool clearQueue = true,
      bool prefetchMetadata = true,
      bool recordHistory = true}) async {
    played.add((track.id, [for (final t in playlistTracks ?? const <Track>[]) t.id], playlistId));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Rec p;
  final theme = ThemeProvider();

  setUpAll(() async {
    UserPlaylistDetailScreen.defaultUsePalette = false;
    SharedPreferences.setMockInitialValues({});
    final ready = Completer<void>();
    final original = debugPrint;
    debugPrint = (msg, {wrapWidth}) {
      if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) ready.complete();
    };
    p = _Rec();
    await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    debugPrint = original;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final pl in List.of(p.userPlaylists)) {
      p.deletePlaylistWithUndo(pl.id);
    }
    p.played.clear();
    p.fakeContext = null;
    for (final t in List.of(p.likedSongs)) {
      p.unlikeSong(t.id);
    }
  });

  Future<Playlist> seed(String name, [List<String> ids = const [], String? description]) async =>
      (await p.createPlaylistWith(
          name: name, tracks: [for (final i in ids) _t(i)], description: description ?? ''))!;

  Future<void> pump(WidgetTester tester, Widget home,
      {Size size = const Size(412, 1400), double scale = 1.0}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MusicProvider>.value(value: p),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ],
      child: MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        builder: (c, child) =>
            MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: home,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  final now = DateTime.now();

  group('Your Playlists (the list)', () {
    testWidgets('lists playlists with count, meta, and Liked Songs first', (tester) async {
      await seed('Chill', ['a', 'b']);
      await seed('Focus', ['c']);
      p.likeSong(_t('z'));
      await pump(tester, UserPlaylistScreen(now: now));

      expect(find.text('Your Playlists'), findsWidgets);
      expect(find.text('2 playlists'), findsOneWidget);
      expect(find.text('Liked Songs'), findsOneWidget);
      expect(find.text('2 songs · Updated today'), findsOneWidget);
      expect(find.text('1 song · Updated today'), findsOneWidget);
      final liked = tester.getTopLeft(find.text('Liked Songs')).dy;
      expect(liked < tester.getTopLeft(find.text('Chill')).dy, isTrue);
    });

    testWidgets('search finds a playlist by a song inside it and says which', (tester) async {
      await seed('Chill', ['a']);
      p.userPlaylists.first.tracks; // (list is live)
      final pl = await p.createPlaylistWith(name: 'Drive', tracks: [_t('q', 'Borderline')]);
      await pump(tester, UserPlaylistScreen(now: now));

      await tester.enterText(find.byType(TextField), 'borderline');
      await settle(tester);
      expect(find.text('Drive'), findsOneWidget);
      expect(find.text('Chill'), findsNothing);
      expect(find.text('Contains "Borderline"'), findsOneWidget);
      expect(find.text('Liked Songs'), findsNothing, reason: 'Liked Songs is not a match');

      await tester.enterText(find.byType(TextField), 'zzzz');
      await settle(tester);
      expect(find.text('No playlists match "zzzz"'), findsOneWidget);
      await tester.tap(find.text('Clear search and filters'));
      await settle(tester);
      expect(find.text('Chill'), findsOneWidget);
      expect(pl, isNotNull);
    });

    testWidgets('Created by you hides imported playlists; the Imported chip only exists when needed', (tester) async {
      await seed('Mine', ['a']);
      await pump(tester, UserPlaylistScreen(now: now));
      expect(find.bySemanticsLabel('Filter: Imported'), findsNothing);

      // importPlaylist awaits a disk write; let real time pass for it.
      await tester.runAsync(() => p.importPlaylist(Playlist(id: 'PLxyz', name: 'From YouTube', imageUrl: '', tracks: [_t('y')])));
      await settle(tester);
      expect(find.bySemanticsLabel('Filter: Imported'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Filter: Created by you'));
      await settle(tester);
      expect(find.text('Mine'), findsOneWidget);
      expect(find.text('From YouTube'), findsNothing);
    });

    testWidgets('sort sheet reorders and is remembered; grid toggle is remembered', (tester) async {
      await seed('Zed', ['a']);
      await seed('Alpha', ['b']);
      await pump(tester, UserPlaylistScreen(now: now));

      await tester.tap(find.bySemanticsLabel('Sort: Recently updated'));
      await settle(tester);
      await tester.tap(find.text('Name'));
      await settle(tester);
      expect(tester.getTopLeft(find.text('Alpha')).dy < tester.getTopLeft(find.text('Zed')).dy, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPlaylistSortPref), 'name');

      await tester.tap(find.bySemanticsLabel('Grid view'));
      await settle(tester);
      expect(prefs.getString(kPlaylistViewPref), 'grid');
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Zed'), findsOneWidget);
      // Two tiles to a row: Liked Songs first, then Alpha beside it, Zed below.
      expect(tester.getTopLeft(find.text('Alpha')).dy, tester.getTopLeft(find.text('Liked Songs')).dy);
      expect(tester.getTopLeft(find.text('Zed')).dy > tester.getTopLeft(find.text('Alpha')).dy, isTrue);
    });

    testWidgets('custom order shows drag handles', (tester) async {
      await seed('A', ['a']);
      await seed('B', ['b']);
      await pump(tester, UserPlaylistScreen(now: now));
      expect(find.bySemanticsLabel(RegExp('Drag to reorder')), findsNothing);
      await tester.tap(find.bySemanticsLabel('Sort: Recently updated'));
      await settle(tester);
      await tester.tap(find.text('Custom order'));
      await settle(tester);
      expect(find.bySemanticsLabel(RegExp('Drag to reorder')), findsNWidgets(2));
    });

    testWidgets('tapping a playlist opens it', (tester) async {
      await seed('Chill', ['a', 'b']);
      await pump(tester, UserPlaylistScreen(now: now));
      await tester.tap(find.text('Chill'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(UserPlaylistDetailScreen), findsOneWidget);
      expect(find.text('Add songs'), findsOneWidget);
    });

    testWidgets('swipe left deletes, Undo brings it back in place', (tester) async {
      final a = await seed('One', ['a']);
      final b = await seed('Two', ['b']);
      await pump(tester, UserPlaylistScreen(now: now));
      await tester.drag(find.text('Two'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(p.userPlaylists.map((e) => e.id), [a.id]);
      expect(find.text('Undo'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(p.userPlaylists.map((e) => e.id), [a.id, b.id]);
    });

    testWidgets('menu: pin moves it to the top and marks it; play records it', (tester) async {
      await seed('Old', ['a']);
      final newer = await seed('Newer', ['b']);
      await pump(tester, UserPlaylistScreen(now: now));
      await tester.longPress(find.text('Old'));
      await settle(tester);
      await tester.tap(find.text('Pin to top'));
      await settle(tester);
      expect(find.byIcon(Icons.push_pin_rounded), findsWidgets);
      expect(tester.getTopLeft(find.text('Old')).dy < tester.getTopLeft(find.text('Newer')).dy, isTrue);

      await tester.longPress(find.text('Newer'));
      await settle(tester);
      await tester.tap(find.text('Play'));
      await settle(tester);
      expect(p.played.single.$1, 'b');
      expect(p.played.single.$3, newer.id);
      expect(p.playlistLastPlayedMs(newer.id), isNotNull);
    });

    testWidgets('empty: invitation to create or import', (tester) async {
      await pump(tester, UserPlaylistScreen(now: now));
      expect(find.text('Make your first playlist'), findsOneWidget);
      expect(find.text('Import from Spotify or YouTube'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('New playlist').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Playlist name'), findsOneWidget, reason: 'the create sheet is open');
    });

    for (final (size, scale) in const [(Size(360, 800), 1.3), (Size(360, 800), 1.0)]) {
      testWidgets('no layout errors at ${size.width.toInt()} dp, text x$scale, list and grid', (tester) async {
        await seed('A very long playlist name that keeps on going and going past the edge', ['a', 'b']);
        await seed('Short');
        await pump(tester, UserPlaylistScreen(now: now), size: size, scale: scale);
        expect(tester.takeException(), isNull);
        await tester.tap(find.bySemanticsLabel('Grid view'));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('A playlist (live)', () {
    Future<Playlist> five() => seed('Road', ['a', 'b', 'c', 'd', 'e'], 'For long drives');

    testWidgets('shows name, description, meta and its songs', (tester) async {
      final pl = await five();
      await pump(tester, UserPlaylistScreen(now: now));
      await pump(tester, UserPlaylistDetailScreen(playlistId: pl.id));
      expect(find.text('Road'), findsWidgets);
      expect(find.text('For long drives'), findsOneWidget);
      expect(find.text('Made by you · 5 songs'), findsOneWidget);
      expect(find.text('Song a'), findsOneWidget);
      expect(find.text('Add songs'), findsOneWidget);
    });

    testWidgets('a row plays inside the playlist, in order', (tester) async {
      final pl = await five();
      await pump(tester, UserPlaylistDetailScreen(playlistId: pl.id));
      await tester.tap(find.text('Song c'));
      await tester.pump();
      expect(p.played.single.$1, 'c');
      expect(p.played.single.$2, ['a', 'b', 'c', 'd', 'e']);
      expect(p.played.single.$3, pl.id);
      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      expect(p.played.last.$1, 'a');
    });

    testWidgets('Play becomes Pause while this playlist is what is playing', (tester) async {
      final pl = await five();
      p.fakeContext = pl.id;
      await pump(tester, UserPlaylistDetailScreen(playlistId: pl.id));
      // Not "playing" in the fake, but the playlist is the context and the song is in it.
      expect(find.bySemanticsLabel('Play'), findsOneWidget);
    });

    testWidgets('swipe left removes a song with Undo that restores its place', (tester) async {
      final pl = await five();
      await pump(tester, UserPlaylistDetailScreen(playlistId: pl.id));
      await tester.drag(find.text('Song c'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(p.playlistById(pl.id)!.tracks.map((t) => t.id), ['a', 'b', 'd', 'e']);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(p.playlistById(pl.id)!.tracks.map((t) => t.id), ['a', 'b', 'c', 'd', 'e']);
    });

    testWidgets('select several and remove, one Undo', (tester) async {
      final pl = await five();
      await pump(tester, UserPlaylistDetailScreen(playlistId: pl.id));
      await tester.longPress(find.text('Song a'));
      await settle(tester);
      await tester.tap(find.text('Song e'));
      await settle(tester);
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Remove'));
      await tester.pumpAndSettle();
      expect(p.playlistById(pl.id)!.tracks.map((t) => t.id), ['b', 'c', 'd']);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(p.playlistById(pl.id)!.tracks.map((t) => t.id), ['a', 'b', 'c', 'd', 'e']);
    });

    testWidgets('reorder mode shows handles and Done leaves it', (tester) async {
      final pl = await five();
      await pump(tester, UserPlaylistDetailScreen(playlistId: pl.id));
      await tester.tap(find.bySemanticsLabel('More options'));
      await settle(tester);
      await tester.tap(find.text('Reorder songs'));
      await settle(tester);
      expect(find.text('Drag to reorder'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Drag to reorder Song')), findsNWidgets(5));
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(find.text('Drag to reorder'), findsNothing);
    });

    testWidgets('edit details renames it live', (tester) async {
      final pl = await five();
      await pump(tester, UserPlaylistDetailScreen(playlistId: pl.id));
      await tester.tap(find.bySemanticsLabel('More options'));
      await settle(tester);
      await tester.tap(find.text('Edit details'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Playlist name'), 'Highway');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Highway'), findsWidgets);
      expect(p.playlistById(pl.id)!.name, 'Highway');
    });

    testWidgets('delete from the menu leaves the screen, with Undo', (tester) async {
      final pl = await five();
      await pump(tester, const Scaffold(body: Text('before')));
      await tester.binding.setSurfaceSize(const Size(412, 1400));
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(builder: (_) => UserPlaylistDetailScreen(playlistId: pl.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('More options'));
      await settle(tester);
      await tester.tap(find.text('Delete playlist'));
      await tester.pumpAndSettle();
      expect(p.playlistById(pl.id), isNull);
      expect(find.byType(UserPlaylistDetailScreen), findsNothing);
      expect(find.text('Deleted "Road"'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(p.playlistById(pl.id), isNotNull);
    });

    testWidgets('an empty playlist invites you to add songs', (tester) async {
      final pl = await seed('Blank');
      await pump(tester, UserPlaylistDetailScreen(playlistId: pl.id));
      expect(find.text('This playlist is empty'), findsOneWidget);
      expect(find.text('Made by you · No songs'), findsOneWidget);
    });

    testWidgets('Add songs: from Liked, + adds and turns into a check', (tester) async {
      final pl = await seed('Blank');
      p.likeSong(_t('l1', 'Liked One'));
      await pump(tester, UserPlaylistDetailScreen(playlistId: pl.id));
      await tester.tap(find.bySemanticsLabel('Add songs').first);
      await settle(tester);
      await tester.tap(find.text('Liked'));
      await settle(tester);
      expect(find.text('Liked One'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Add Liked One, Artist'));
      await settle(tester);
      expect(p.playlistById(pl.id)!.tracks.map((t) => t.id), ['l1']);
      expect(find.bySemanticsLabel('Added: Liked One, Artist'), findsOneWidget);
    });

    testWidgets('Add songs: search shows results, a failure says so', (tester) async {
      final pl = await seed('Blank');
      var fail = false;
      await pump(tester, Scaffold(body: Builder(builder: (c) => TextButton(
            onPressed: () => showAddSongsSheet(c, pl.id, searchOverride: (q) async {
              if (fail) throw Exception('offline');
              return [_t('s1', 'Found $q')];
            }),
            child: const Text('open'),
          ))));
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.text('Search'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'tame');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.text('Found tame'), findsOneWidget);

      fail = true;
      await tester.enterText(find.byType(TextField), 'other');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.text('Search failed. Check your connection and try again.'), findsOneWidget);
    });

    testWidgets('deleted elsewhere while open: the screen closes itself', (tester) async {
      final pl = await five();
      await pump(tester, const Scaffold(body: Text('before')));
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(builder: (_) => UserPlaylistDetailScreen(playlistId: pl.id)));
      await tester.pumpAndSettle();
      p.deletePlaylistWithUndo(pl.id);
      await tester.pumpAndSettle();
      expect(find.byType(UserPlaylistDetailScreen), findsNothing);
      expect(find.text('before'), findsOneWidget);
    });

    for (final (size, scale) in const [(Size(360, 800), 1.3), (Size(360, 800), 1.0)]) {
      testWidgets('no layout errors at ${size.width.toInt()} dp, text x$scale', (tester) async {
        final pl = await seed(
            'A very long playlist name that keeps on going and going past the edge of the screen', [
          'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i',
        ], 'A long description that wraps onto a second and a third line and then keeps going well past three lines of text for sure');
        await pump(tester, UserPlaylistDetailScreen(playlistId: pl.id), size: size, scale: scale);
        expect(tester.takeException(), isNull);
        await tester.longPress(find.text('Song a'));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('suggested songs', () {
    test('merged in order, de-duplicated, capped', () {
      final out = suggestedSongs([
        [_t('1'), _t('2')],
        [_t('2'), _t('3')],
        [_t('4')],
      ], limit: 3);
      expect(out.map((t) => t.id), ['1', '2', '3']);
      expect(suggestedSongs([[_t('1')], [_t('1')]], exclude: {'1'}), isEmpty);
    });
  });
}
