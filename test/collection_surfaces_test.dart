import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/playlist.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/screens/home_screen.dart';
import 'package:music_streaming_app/presentation/home/home_view_mode.dart';
import 'package:music_streaming_app/services/auth_service.dart';
import 'package:music_streaming_app/services/home/home_models.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/collection_play_disc.dart';
import 'package:music_streaming_app/widgets/playlist/playlist_options_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'muzo_enhancements_test.dart' show MockMusicProvider;

/// PLAYLISTS GET THE SAME PLAY BUTTON AND THE SAME SHEET AS ALBUMS, EVERYWHERE.
///
/// Touch-and-hold on one of the listener's own playlists used to offer Rename and
/// Delete (Library) or nothing at all (Home). It now opens a sheet with Play,
/// Shuffle, Play next, Add to queue, Add to a playlist..., Download - and the three
/// things only a playlist of yours has: Pin, Edit details, Delete with Undo.

Track song(String id, String name) => Track(
      id: id,
      trackName: name,
      artistName: 'Tems',
      albumName: 'Mix',
      albumArtUrl: '',
      previewUrl: '',
    );

class _P extends MockMusicProvider {
  _P() : super(loggedIn: true);

  final played = <(String, List<String>, String?)>[];
  final queued = <String>[];

  @override
  Future<void> playTrack(
    Track track, {
    String? playlistId,
    List<Track>? playlistTracks,
    bool setContext = true,
    bool clearQueue = true,
    bool prefetchMetadata = true,
    bool recordHistory = true,
  }) async {
    played.add((track.id, [for (final t in playlistTracks ?? const <Track>[]) t.id], playlistId));
  }

  @override
  void addListToQueue(List<Track> tracks) => queued.addAll(tracks.map((t) => t.id));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _P p;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    p = _P();
  });

  /// Pumps a stand-in for a playlist card that opens the real sheet on long-press.
  Future<void> pumpSheetHost(WidgetTester tester, Playlist pl) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MusicProvider>.value(value: p),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onLongPress: () => showUserPlaylistSheet(context, pl),
                child: const SizedBox(width: 120, height: 120, child: Text('card')),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.longPress(find.text('card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  Future<Playlist> seed(String name, List<Track> tracks) async =>
      (await p.createPlaylistWith(name: name, tracks: tracks))!;

  group('the sheet for one of your own playlists', () {
    testWidgets('has the collection rows and the playlist-only ones, and no Share or Go to artist', (tester) async {
      final pl = await seed('Road trip', [song('aaaaaaaaaa1', 'One'), song('aaaaaaaaaa2', 'Two')]);
      await pumpSheetHost(tester, pl);
      for (final label in [
        'Play',
        'Shuffle',
        'Play next',
        'Add to queue',
        'Add to a playlist...',
        'Download',
        'Pin to top',
        'Edit details',
        'Delete playlist',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Share'), findsNothing, reason: 'a playlist of yours has no public link');
      expect(find.text('Go to artist'), findsNothing);
      expect(find.text('Playlist \u00b7 2 songs'), findsOneWidget);
    });

    testWidgets('Play starts it from the first song, in the playlist\'s order, and records the playlist', (tester) async {
      final pl = await seed('Road trip', [song('aaaaaaaaaa1', 'One'), song('aaaaaaaaaa2', 'Two')]);
      await pumpSheetHost(tester, pl);
      await tester.tap(find.bySemanticsLabel('Play').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(p.played.single.$1, 'aaaaaaaaaa1');
      expect(p.played.single.$2, ['aaaaaaaaaa1', 'aaaaaaaaaa2']);
      expect(p.played.single.$3, pl.id, reason: 'queue provenance is the playlist, not "My Music"');
    });

    testWidgets('Add to queue adds every song', (tester) async {
      final pl = await seed('Road trip', [song('aaaaaaaaaa1', 'One'), song('aaaaaaaaaa2', 'Two')]);
      await pumpSheetHost(tester, pl);
      await tester.tap(find.bySemanticsLabel('Add to queue').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(p.queued, ['aaaaaaaaaa1', 'aaaaaaaaaa2']);
      expect(find.text('Added 2 songs to the queue'), findsOneWidget);
    });

    testWidgets('Pin to top pins it', (tester) async {
      final pl = await seed('Road trip', [song('aaaaaaaaaa1', 'One')]);
      await pumpSheetHost(tester, pl);
      await tester.tap(find.text('Pin to top'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(p.playlistById(pl.id)!.pinned, isTrue);
    });

    testWidgets('Delete removes it and offers Undo, which brings it back', (tester) async {
      final pl = await seed('Road trip', [song('aaaaaaaaaa1', 'One')]);
      await pumpSheetHost(tester, pl);
      await tester.ensureVisible(find.text('Delete playlist'));
      await tester.tap(find.text('Delete playlist'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(p.playlistById(pl.id), isNull);
      expect(find.text('Deleted "Road trip"'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(p.playlistById(pl.id), isNotNull, reason: 'Undo restored it');
    });

    testWidgets('Edit details opens the editor', (tester) async {
      final pl = await seed('Road trip', [song('aaaaaaaaaa1', 'One')]);
      await pumpSheetHost(tester, pl);
      await tester.tap(find.text('Edit details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Save'), findsOneWidget, reason: 'the editor is up');
      expect(find.widgetWithText(TextField, 'Road trip'), findsOneWidget);
    });

    testWidgets('an empty playlist says so instead of failing', (tester) async {
      final pl = await seed('Quiet', const []);
      await pumpSheetHost(tester, pl);
      await tester.tap(find.bySemanticsLabel('Play').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('This playlist is empty. Add songs to it first.'), findsOneWidget);
      expect(p.played, isEmpty);
    });
  });

  group('Home\'s own playlists', () {
    Future<void> pumpHome(WidgetTester tester, List<Playlist> playlists) async {
      p.setTestUserPlaylists(playlists);
      // Home shows its lower sections (where the playlists strip is) once it has a feed.
      p.setTestHomeFeed(HomeFeed(
        sections: [
          HomeSection(
            id: 'quick',
            title: 'Quick picks',
            items: [
              for (var i = 0; i < 4; i++)
                HomeItem(
                  id: 'vid0000000${i}0',
                  videoId: 'vid0000000${i}0',
                  title: 'Feed $i',
                  subtitle: 'Artist',
                  artworkUrl: '',
                  contentType: HomeContentType.song,
                ),
            ],
            presentation: HomePresentation.artworkRail,
          ),
        ],
        fetchedAt: DateTime.now(),
        source: 'ytm_home',
      ));
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<MusicProvider>.value(value: p),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<HomeViewModeStore>.value(value: HomeViewModeStore()),
        ],
        child: MaterialApp(theme: GlassTheme.build(AccentColors.peach), home: const HomeScreen()),
      ));
      await tester.pumpAndSettle();
      // The strip sits below the feed's shelves; build it.
      await tester.scrollUntilVisible(find.text('Your playlists'), 400, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }

    testWidgets('each playlist card has a play disc that plays it', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final pl = await seed('Road trip', [song('aaaaaaaaaa1', 'One'), song('aaaaaaaaaa2', 'Two')]);
        await pumpHome(tester, [pl]);
        expect(find.byType(CollectionPlayDisc), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Play Road trip'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(p.played.single.$3, pl.id);
        expect(p.played.single.$2, ['aaaaaaaaaa1', 'aaaaaaaaaa2']);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('an empty playlist\'s disc says it is empty, and plays nothing', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final pl = await seed('Quiet', const []);
        await pumpHome(tester, [pl]);
        await tester.tap(find.bySemanticsLabel('Play Quiet'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('"Quiet" is empty'), findsOneWidget);
        expect(p.played, isEmpty);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('touch-and-hold opens the playlist sheet', (tester) async {
      final pl = await seed('Road trip', [song('aaaaaaaaaa1', 'One')]);
      await pumpHome(tester, [pl]);
      await tester.longPress(find.text('Road trip').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Pin to top'), findsOneWidget);
      expect(find.text('Delete playlist'), findsOneWidget);
    });
  });
}
