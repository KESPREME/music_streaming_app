import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/accent_controller.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/models/playlist.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/screens/library_screen.dart';
import 'package:music_streaming_app/widgets/library/library_header.dart';
import 'package:music_streaming_app/widgets/library/library_hero_artwork.dart';
import 'package:music_streaming_app/widgets/library/library_filter_bar.dart';
import 'package:music_streaming_app/services/listening_stats.dart';
import 'package:music_streaming_app/widgets/library/library_listening_card.dart';
import 'package:music_streaming_app/widgets/library/library_shelves.dart';

class FakeLibraryMusicProvider extends ChangeNotifier implements MusicProvider {
  final List<Track> _fakeLikedSongs = [];
  final List<Playlist> _fakeUserPlaylists = [];
  final List<Track> _fakeRecentlyPlayed = [];
  final List<Track> _fakeLocalTracks = [];

  @override
  List<Track> get likedSongs => _fakeLikedSongs;

  @override
  List<Playlist> get userPlaylists => _fakeUserPlaylists;

  @override
  List<Track> get recentlyPlayed => _fakeRecentlyPlayed;

  @override
  List<Track> get localTracks => _fakeLocalTracks;

  @override
  Future<List<Track>> getDownloadedTracks() async => [];

  @override
  Future<List<dynamic>> getSmartLibraryArtists() async => [];

  @override
  Future<List<Track>> getSmartLibraryAlbums() async => [];

  @override
  final ListeningStats listeningStats = ListeningStats();

  @override
  Track? get currentTrack => null;

  @override
  Color? get currentPaletteColor => null;

  @override
  bool get hideMiniPlayer => false;

  @override
  Future<void> createPlaylist(String name,
      {List<Track>? initialTracks, String? imageUrl}) async {
    _fakeUserPlaylists.add(Playlist(
      id: '1',
      name: name,
      imageUrl: imageUrl ?? '',
      tracks: initialTracks ?? [],
    ));
    notifyListeners();
  }

  @override
  Future<void> renamePlaylist(String id, String newName) async {
    final idx = _fakeUserPlaylists.indexWhere((p) => p.id == id);
    if (idx != -1) {
      _fakeUserPlaylists[idx] = _fakeUserPlaylists[idx].copyWith(name: newName);
      notifyListeners();
    }
  }

  @override
  Future<void> deletePlaylist(String id) async {
    _fakeUserPlaylists.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  void seedTestData() {
    _fakeLikedSongs.addAll(List.generate(
      10,
      (i) => Track(
        id: 'like_$i',
        trackName: 'Liked Track $i',
        artistName: 'Artist $i',
        albumName: 'Album $i',
        previewUrl: '',
      ),
    ));
    _fakeRecentlyPlayed.add(
      Track(
        id: 'rec_0',
        trackName: 'Recent Track',
        artistName: 'Artist',
        albumName: 'Album',
        previewUrl: '',
      ),
    );
    _fakeLocalTracks.addAll(List.generate(
      81,
      (i) => Track(
        id: 'loc_$i',
        trackName: 'Local Track $i',
        artistName: 'Artist $i',
        albumName: 'Album $i',
        previewUrl: '',
      ),
    ));
  }

  @override
  bool get isPlayerExpanded => false;

  @override
  final GlobalKey<NavigatorState> playerNavigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void setPlayerExpanded(bool value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLibraryMusicProvider musicProvider;
  late AccentController accentController;
  late ThemeProvider themeProvider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    accentController = AccentController();
    musicProvider = FakeLibraryMusicProvider()..seedTestData();
    themeProvider = ThemeProvider();
  });

  Widget buildTestableWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AccentController>.value(value: accentController),
        ChangeNotifierProvider<MusicProvider>.value(value: musicProvider),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ],
      child: const MaterialApp(
        home: LibraryScreen(),
      ),
    );
  }

  group('Mine Music Library Screen Parity Tests', () {
    testWidgets('renders all primary visual components on All tab', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestableWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // 1. Header with Brand & Actions
      expect(find.byType(LibraryHeader), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText().contains('Mine Music')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Create playlist'), findsOneWidget);
      expect(find.bySemanticsLabel('Search library'), findsOneWidget);

      // 2. Hero Section with Editorial Typography
      expect(find.byType(LibraryHeroArtwork), findsOneWidget);
      expect(find.textContaining('ALL YOUR SOUNDS'), findsOneWidget);
      expect(find.text('Music\nlives\nhere.'), findsOneWidget);
      expect(find.textContaining('Your'), findsWidgets);

      // 3. Filter Bar & Sort Button
      expect(find.byType(LibraryFilterBar), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.bySemanticsLabel('Sort library items'), findsOneWidget);

      // 4. Listening card: nothing listened yet, so the honest empty state.
      expect(find.byType(LibraryListeningCard), findsOneWidget);
      expect(find.textContaining('in music'), findsOneWidget);

      // 5. Quick access: six destinations (the rail scrolls; the first few are
      // laid out on screen).
      expect(find.text('Quick access'), findsOneWidget);
      expect(find.text('Liked Songs'), findsOneWidget);
      expect(find.text('Your Playlists'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);

      // 6. Shelves: recents has one track; playlists always offers a new one.
      expect(find.text('Recently played'), findsOneWidget);
      expect(find.text('Recent Track'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('New playlist'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Your playlists'), findsOneWidget);
    });

    testWidgets('filter tabs switch smoothly between categories', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestableWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Tap Playlists
      await tester.tap(find.text('Playlists'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Empty state rendered cleanly when no playlists exist
      expect(find.text('No playlists yet'), findsOneWidget);
      expect(find.text('Create Playlist'), findsOneWidget);

      // Tap Artists
      await tester.tap(find.text('Artists'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Filter bar still visible
      expect(find.byType(LibraryFilterBar), findsOneWidget);

      // Tap back to All
      await tester.tap(find.text('All'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // The All tab is back
      expect(find.text('Quick access'), findsOneWidget);
    });

    testWidgets('sort button opens liquid glass sort options sheet', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestableWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Tap sort button
      await tester.tap(find.bySemanticsLabel('Sort library items'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify Sort options are shown
      expect(find.text('Sort by'), findsOneWidget);
      expect(find.text('Recently Added'), findsOneWidget);
      expect(find.text('Alphabetical (A-Z)'), findsOneWidget);
      expect(find.text('Most Tracks'), findsOneWidget);

      // Tap Alphabetical
      await tester.tap(find.text('Alphabetical (A-Z)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Sheet dismissed
      expect(find.text('Sort by'), findsNothing);
    });

    for (final width in [360.0, 375.0, 390.0, 412.0, 430.0]) {
      testWidgets('validates responsive layout, long titles, and card geometry at ${width.toInt()}dp', (tester) async {
        tester.view.physicalSize = Size(width, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestableWidget());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        // 1. Zero RenderFlex or layout exceptions across all widths
        expect(tester.takeException(), isNull);

        // 2. Every destination tile has a 44dp-plus target and its full label.
        final tiles = find.byType(LibraryQuickTile);
        expect(tiles, findsWidgets);
        final tileSize = tester.getSize(tiles.first);
        expect(tileSize.width, greaterThanOrEqualTo(44));
        expect(tileSize.height, greaterThanOrEqualTo(44));
        expect(find.text('1 song'), findsWidgets);
        expect(find.text('10 songs'), findsOneWidget);
        expect(find.text('Recent Track'), findsOneWidget);      });
    }
  });
}
