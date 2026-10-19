import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/presentation/local/local_library.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/local_music_screen.dart';
import 'package:music_streaming_app/services/local_music_service.dart' show SortCriteria;
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LOCAL FILES: the phone's music in four views, played offline in the order
/// shown, with honest scanning / refused / empty states.

Track _t(String id, {String? title, String artist = 'Artist', String album = 'Album', String dir = '/storage/Music'}) =>
    Track(
      id: '$dir/$id.mp3',
      trackName: title ?? 'Song $id',
      artistName: artist,
      albumName: album,
      previewUrl: '$dir/$id.mp3',
      source: 'local',
    );

/// The real provider; only the device-facing parts are replaced.
class _Local extends MusicProvider {
  List<Track> fakeTracks = [];
  bool fakeLoading = false;
  bool fakeDenied = false;
  bool fakeLoadedOnce = true;
  int scans = 0;
  final List<(String, List<String>)> playedOffline = [];

  @override
  List<Track> get localTracks => fakeTracks;
  @override
  bool get isLoadingLocal => fakeLoading;
  @override
  bool get localPermissionDenied => fakeDenied;
  @override
  bool get localLoadedOnce => fakeLoadedOnce;
  @override
  Future<Uint8List?> localArtwork(String path) => Future.value(null);
  @override
  Future<void> loadLocalMusicFiles({bool forceRescan = false}) async => scans++;
  @override
  Future<void> playOfflineTrack(Track track,
      {bool setContext = true, bool clearQueue = true, List<Track>? contextList, bool recordHistory = true}) async {
    playedOffline.add((track.id, [for (final t in contextList ?? const <Track>[]) t.id]));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('grouping', () {
    final songs = [
      _t('a', title: 'Zebra', artist: 'Bea', album: 'Blue', dir: '/storage/Music/Indie'),
      _t('b', title: 'Apple', artist: 'Ann & Bea', album: 'Blue', dir: '/storage/Music/Indie'),
      _t('c', title: 'Mango', artist: '<unknown>', album: '', dir: r'C:\Users\me\Music'),
      _t('d', title: 'Kiwi', artist: 'Ann', album: 'Green', dir: '/storage/Download'),
    ];

    test('albums: by album and its artist, unknown last, songs kept in order', () {
      final g = groupLocal(songs, LocalView.albums);
      expect(g.map((e) => e.label), ['Blue', 'Green', 'Unknown album']);
      expect(g.first.subtitle, 'Bea');
      expect(g.first.tracks.map((t) => t.trackName), ['Zebra', 'Apple'],
          reason: 'the duet stays on its album; the order given, not re-sorted');
    });

    test('albums: same name in two folders stay apart; mixed credits are Various artists', () {
      final g = groupLocal([
        _t('1', artist: 'Queen', album: 'Greatest Hits', dir: '/m/Queen'),
        _t('2', artist: 'ABBA', album: 'Greatest Hits', dir: '/m/ABBA'),
        _t('3', artist: 'X', album: 'Now 99', dir: '/m/Now'),
        _t('4', artist: 'Y', album: 'Now 99', dir: '/m/Now'),
        _t('5', artist: 'Z', album: 'Now 99', dir: '/m/Now'),
        _t('6', artist: 'Unknown Artist', album: 'Unknown Album', dir: '/m/Misc'),
      ], LocalView.albums);
      expect(g.map((e) => '${e.label}/${e.subtitle}'),
          ['Greatest Hits/ABBA', 'Greatest Hits/Queen', 'Now 99/Various artists', 'Unknown album/Unknown artist']);
    });

    test('artists: a duet is filed under both, unknown last', () {
      final g = groupLocal(songs, LocalView.artists);
      expect(g.map((e) => e.label), ['Ann', 'Bea', 'Unknown artist']);
      expect(g[0].tracks.map((t) => t.trackName), ['Apple', 'Kiwi']);
      expect(g[1].tracks.map((t) => t.trackName), ['Zebra', 'Apple']);
    });

    test('folders: the parent directory, either slash', () {
      expect(folderNameOf(songs[0]), 'Indie');
      expect(folderNameOf(songs[2]), 'Music');
      expect(folderPathOf(songs[2]), r'C:\Users\me\Music');
      final g = groupLocal(songs, LocalView.folders);
      expect(g.map((e) => e.label), ['Download', 'Indie', 'Music']);
      expect(g[1].subtitle, '/storage/Music/Indie');
    });

    test('search covers title, artist, album and folder, all words', () {
      expect(searchLocal(songs, 'indie').map((t) => t.trackName), ['Zebra', 'Apple']);
      expect(searchLocal(songs, 'ann green').map((t) => t.trackName), ['Kiwi']);
      expect(searchLocal(songs, '  '), songs);
    });

    test('every sort has words', () {
      final labels = {for (final c in SortCriteria.values) sortLabel(c)};
      expect(labels, hasLength(SortCriteria.values.length));
    });
  });

  group('screen', () {
    late _Local p;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      final ready = Completer<void>();
      final original = debugPrint;
      debugPrint = (msg, {wrapWidth}) {
        if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) ready.complete();
      };
      p = _Local();
      await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      debugPrint = original;
    });

    setUp(() {
      p.fakeTracks = [
        _t('1', title: 'Alpha', artist: 'Ann', album: 'First', dir: '/m/Rock'),
        _t('2', title: 'Bravo', artist: 'Bob', album: 'First', dir: '/m/Rock'),
        _t('3', title: 'Charlie', artist: 'Ann', album: 'Second', dir: '/m/Jazz'),
      ];
      p.fakeLoading = false;
      p.fakeDenied = false;
      p.fakeLoadedOnce = true;
      p.scans = 0;
      p.playedOffline.clear();
    });

    Future<void> pump(WidgetTester tester, {Size size = const Size(412, 1400), double scale = 1}) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
        value: p,
        child: MaterialApp(
          theme: GlassTheme.build(AccentColors.peach),
          builder: (c, child) =>
              MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const LocalMusicScreen())),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a song plays offline, with the list as shown', (tester) async {
      await pump(tester);
      expect(find.text('3 songs · on this device'), findsOneWidget);
      await tester.tap(find.text('Bravo'));
      await tester.pump();
      expect(p.playedOffline.single.$1, '/m/Rock/2.mp3');
      expect(p.playedOffline.single.$2, ['/m/Rock/1.mp3', '/m/Rock/2.mp3', '/m/Jazz/3.mp3']);
      expect(p.scans, 0, reason: 'already has music: no rescan on open');
    });

    testWidgets('search narrows, and Play plays what is shown', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'jazz');
      await settle(tester);
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('1 of 3 songs'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      expect(p.playedOffline.single.$2, ['/m/Jazz/3.mp3']);
    });

    testWidgets('an album opens in place; back closes it, then the screen', (tester) async {
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('Filter: Albums'));
      await settle(tester);
      expect(find.bySemanticsLabel('First, Ann · 2 songs'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('First, Ann · 2 songs'));
      await settle(tester);
      expect(find.text('ALBUMS'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Charlie'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      expect(p.playedOffline.single.$2, ['/m/Rock/1.mp3', '/m/Rock/2.mp3']);

      // System back: closes the album, not the screen.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(LocalMusicScreen), findsOneWidget);
      expect(find.text('ALBUMS'), findsNothing);
      expect(find.bySemanticsLabel('Second, Ann · 1 song'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(LocalMusicScreen), findsNothing);
    });

    testWidgets('artists and folders group the same songs', (tester) async {
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('Filter: Artists'));
      await settle(tester);
      expect(find.bySemanticsLabel('Ann, 2 songs'), findsOneWidget);
      expect(find.bySemanticsLabel('Bob, 1 song'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Filter: Folders'));
      await settle(tester);
      expect(find.bySemanticsLabel('Jazz, 1 song'), findsOneWidget);
      expect(find.bySemanticsLabel('Rock, 2 songs'), findsOneWidget);
    });

    testWidgets('access refused: says why, Allow asks again', (tester) async {
      p.fakeTracks = [];
      p.fakeDenied = true;
      await pump(tester);
      expect(find.text('Allow access to your music'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      final before = p.scans;
      await tester.tap(find.text('Allow access'));
      await tester.pump();
      expect(p.scans, before + 1);
    });

    testWidgets('nothing found after a scan: says so, offers Rescan', (tester) async {
      p.fakeTracks = [];
      await pump(tester);
      expect(find.text('No music on this device'), findsOneWidget);
      expect(find.text('Rescan'), findsOneWidget);
    });

    testWidgets('scanning shows placeholders, not "no music"', (tester) async {
      p.fakeTracks = [];
      p.fakeLoading = true;
      p.fakeLoadedOnce = false;
      await pump(tester);
      expect(find.text('Looking for music on this device…'), findsOneWidget);
      expect(find.text('No music on this device'), findsNothing);
    });

    testWidgets('no layout errors at 360 dp, text x1.3', (tester) async {
      await pump(tester, size: const Size(360, 800), scale: 1.3);
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Filter: Albums'));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
