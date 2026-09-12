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
import 'package:music_streaming_app/widgets/library/library_action_card.dart';
import 'package:music_streaming_app/widgets/library/library_brand_promo_card.dart';

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
  Track? get currentTrack => null;

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
    musicProvider = FakeLibraryMusicProvider();
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
      await tester.binding.setSurfaceSize(const Size(412, 915));
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
      expect(find.textContaining('Your'), findsOneWidget);

      // 3. Filter Bar & Sort Button
      expect(find.byType(LibraryFilterBar), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.bySemanticsLabel('Sort library items'), findsOneWidget);

      // 4. 2-Column Action Grid (6 Cards)
      expect(find.byType(LibraryActionCard), findsNWidgets(6));
      expect(find.text('Liked Songs'), findsOneWidget);
      expect(find.text('Your Playlists'), findsOneWidget);
      expect(find.text('Recently Played'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('Local Files'), findsOneWidget);
      expect(find.text('Import Playlists'), findsOneWidget);

      // 5. Promotional Brand Card
      expect(find.byType(LibraryBrandPromoCard), findsOneWidget);
      expect(find.text('YOUR MUSIC.\nYOUR WORLD.'), findsOneWidget);
      expect(find.text('Listen\nyour way.'), findsOneWidget);
    });

    testWidgets('filter tabs switch smoothly between categories', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
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

      // All 6 action cards are back
      expect(find.byType(LibraryActionCard), findsNWidgets(6));
    });

    testWidgets('sort button opens liquid glass sort options sheet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
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
  });
}
