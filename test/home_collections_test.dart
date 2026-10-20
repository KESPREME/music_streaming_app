import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/bitchord_page_models.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/presentation/home/home_collections.dart';
import 'package:music_streaming_app/presentation/home/home_view_mode.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/screens/album_detail_screen.dart';
import 'package:music_streaming_app/screens/home_screen.dart';
import 'package:music_streaming_app/services/auth_service.dart';
import 'package:music_streaming_app/services/home/home_models.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/utils/share_text.dart';
import 'package:provider/provider.dart';

import 'muzo_enhancements_test.dart' show MockMusicProvider;

/// HOME ALBUM AND PLAYLIST CARDS ANSWER.
///
/// "New releases" arrives as album cards (no videoId). The rail used to call the
/// dispatcher and drop its "navigate" answer, and touch-and-hold looked for a
/// song that an album does not have, so the whole shelf was inert: no page, no
/// play, no options. These mount the real Home screen and do what a person does.

Track song(String id, String name) => Track(
      id: id,
      trackName: name,
      artistName: 'Artist A',
      albumName: 'Fresh album',
      albumArtUrl: 'https://example.com/$id.jpg',
      previewUrl: '',
    );

final albumSongs = [song('aaaaaaaaaa1', 'First'), song('aaaaaaaaaa2', 'Second')];

HomeItem album({String id = 'MPREb_fresh1', String title = 'Fresh album'}) => HomeItem(
      id: id,
      browseId: id,
      title: title,
      subtitle: 'Album • Artist A',
      artists: const ['Artist A'],
      artworkUrl: 'https://example.com/$id.jpg',
      contentType: HomeContentType.album,
    );

/// A rail shows from three cards up (_feedSectionRenders), so a shelf is padded
/// with two other albums when a test only cares about one card.
HomeFeed feedOf(List<HomeItem> items, {String title = 'New releases'}) => HomeFeed(
      sections: [
        HomeSection(
          id: 'id_$title',
          title: title,
          items: [
            ...items,
            for (var i = items.length; i < 3; i++) album(id: 'MPREb_pad$i', title: 'Padding $i'),
          ],
          presentation: HomePresentation.artworkRail,
        ),
      ],
      fetchedAt: DateTime.now(),
      source: 'ytm_home',
    );

class AlbumProvider extends MockMusicProvider {
  AlbumProvider({this.albumTracks}) : super(loggedIn: true);

  /// What the album endpoint returns; empty simulates a failed load.
  List<Track>? albumTracks;
  final List<(List<String>, int)> played = [];
  final List<String> queued = [];
  final List<String> nexts = [];
  final List<String> downloaded = [];
  final List<String> fetched = [];

  @override
  Future<AlbumDetailData> fetchAlbumPageData(String browseId) async {
    fetched.add(browseId);
    return AlbumDetailData(
      title: 'Fresh album',
      artistName: 'Artist A',
      coverUrl: '',
      tracks: albumTracks ?? albumSongs,
    );
  }

  @override
  Future<List<Track>> fetchAlbumTracks(String albumBrowseId) async => const [];

  @override
  Future<void> playTrackList(List<Track> tracks, {int initialIndex = 0, String? playlistId}) async {
    played.add(([for (final t in tracks) t.id], initialIndex));
  }

  @override
  void addListToQueue(List<Track> tracks) => queued.addAll(tracks.map((t) => t.id));

  @override
  void playNext(Track track) => nexts.add(track.id);

  @override
  Future<void> downloadTracks(List<Track> tracks, {bool skipDownloaded = true}) async {
    downloaded.addAll(tracks.map((t) => t.id));
  }
}

Future<void> pumpHome(WidgetTester tester, MusicProvider provider) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MusicProvider>.value(value: provider),
        ChangeNotifierProvider<AuthService>.value(value: AuthService()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<HomeViewModeStore>.value(value: HomeViewModeStore()),
      ],
      child: MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A widget test with semantics on BEFORE the first frame (or the labels the tests
/// find by do not exist yet), switched off before the end-of-test check.
void homeTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> hold(WidgetTester tester, String text) async {
  await tester.longPress(find.text(text).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what the helpers say', () {
    test('album, playlist and category ids are told apart', () {
      expect(homeCollectionIdIsAlbum('MPREb_x'), isTrue);
      expect(homeCollectionIdIsAlbum('OLAK5uy_x'), isTrue);
      expect(homeCollectionIdIsAlbum('VLPLx'), isFalse);
      expect(homeCollectionIdHasSongs('VLPLx'), isTrue);
      expect(homeCollectionIdHasSongs('RDCLAK5uy_x'), isTrue);
      expect(homeCollectionIdHasSongs('FEmusic_moods_and_genres_category'), isFalse,
          reason: 'a mood tile opens a category, not a list of songs');
    });

    test('a mood tile gets no play disc and no song menu; an album does', () {
      const mood = HomeItem(
        id: 'FEmusic_moods_and_genres_category_x',
        browseId: 'FEmusic_moods_and_genres_category_x',
        title: 'Chill',
        subtitle: '',
        artworkUrl: '',
        contentType: HomeContentType.playlist,
      );
      expect(homeItemHasSongs(mood), isFalse);
      expect(homeItemHasSongs(album()), isTrue);
    });

    test('share text carries a real link', () {
      expect(songShareText(song('abcdefghijk', 'Hello')),
          'Check out this track: Hello by Artist A\nhttps://music.youtube.com/watch?v=abcdefghijk');
      expect(songShareText(Track(id: '/storage/a.mp3', trackName: 'Local', artistName: 'Me', albumName: '', previewUrl: '/storage/a.mp3', source: 'local')),
          'Check out this track: Local by Me',
          reason: 'a path on this phone is not a link');
      expect(collectionShareText(title: 'Fresh album', artist: 'Artist A', id: 'MPREb_x'),
          'Fresh album by Artist A\nhttps://music.youtube.com/browse/MPREb_x');
      expect(collectionShareLink('VLPLabc'), 'https://music.youtube.com/playlist?list=PLabc');
      expect(collectionShareLink('weird'), isNull);
    });
  });

  group('New releases on the real Home screen', () {
    homeTest('tapping an album opens its page', (tester) async {
      final p = AlbumProvider()..setTestHomeFeed(feedOf([album()]));
      await pumpHome(tester, p);

      await tester.tap(find.text('Fresh album'));
      await tester.pumpAndSettle();

      expect(find.byType(AlbumDetailScreen), findsOneWidget, reason: 'the card used to do nothing');
      expect(p.fetched, contains('MPREb_fresh1'));

      // Leave the page the way a person does, and let its own timers run out.
      Navigator.of(tester.element(find.byType(AlbumDetailScreen))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });

    homeTest('touch-and-hold opens the collection sheet with every option', (tester) async {
      final p = AlbumProvider()..setTestHomeFeed(feedOf([album()]));
      await pumpHome(tester, p);
      await hold(tester, 'Fresh album');

      for (final label in [
        'Play',
        'Shuffle',
        'Play next',
        'Add to queue',
        'Add to a playlist...',
        'Download',
        'Share',
        'Go to artist',
      ]) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
      }
      expect(find.text('Album • Artist A'), findsWidgets);
    });

    homeTest('the sheet\'s Play and Shuffle start the album', (tester) async {
      final p = AlbumProvider()..setTestHomeFeed(feedOf([album()]));
      await pumpHome(tester, p);

      await hold(tester, 'Fresh album');
      await tester.tap(find.bySemanticsLabel('Play').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(p.played.last.$1, ['aaaaaaaaaa1', 'aaaaaaaaaa2']);
      expect(p.played.last.$2, 0);
      expect(find.bySemanticsLabel('Shuffle'), findsNothing, reason: 'the sheet closed');

      await hold(tester, 'Fresh album');
      await tester.tap(find.bySemanticsLabel('Shuffle').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(p.played.last.$1.toSet(), {'aaaaaaaaaa1', 'aaaaaaaaaa2'});
    });

    homeTest('Play next, Add to queue and Download act on the whole album and say so', (tester) async {
      final p = AlbumProvider()..setTestHomeFeed(feedOf([album()]));
      await pumpHome(tester, p);

      await hold(tester, 'Fresh album');
      await tester.tap(find.bySemanticsLabel('Play next').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(p.nexts, ['aaaaaaaaaa2', 'aaaaaaaaaa1'], reason: 'reversed, so the album plays in order');
      expect(find.text('Playing next: 2 songs'), findsOneWidget);

      await hold(tester, 'Fresh album');
      await tester.tap(find.bySemanticsLabel('Add to queue').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(p.queued, ['aaaaaaaaaa1', 'aaaaaaaaaa2']);
      expect(find.text('Added 2 songs to the queue'), findsOneWidget);

      await hold(tester, 'Fresh album');
      await tester.tap(find.bySemanticsLabel('Download').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(p.downloaded, ['aaaaaaaaaa1', 'aaaaaaaaaa2']);
    });

    homeTest('Add to a playlist... > New playlist works from a Home album, after a person\'s pause', (tester) async {
      final p = AlbumProvider()..setTestHomeFeed(feedOf([album()]));
      await pumpHome(tester, p);

      await hold(tester, 'Fresh album');
      await tester.tap(find.bySemanticsLabel('Add to a playlist...').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Add to playlist'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('New playlist'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Starts with 2 songs'), findsOneWidget, reason: 'the editor opened with the album');
    });

    homeTest('the quick-play disc plays the album without opening it', (tester) async {
      final p = AlbumProvider()..setTestHomeFeed(feedOf([album()]));
      await pumpHome(tester, p);

      expect(find.bySemanticsLabel('Play Fresh album'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Play Fresh album'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(p.played.last.$1, ['aaaaaaaaaa1', 'aaaaaaaaaa2']);
      expect(find.byType(AlbumDetailScreen), findsNothing, reason: 'the disc plays; the card opens');
    });

    homeTest('an album that cannot be loaded says so, on the disc and in the sheet', (tester) async {
      final p = AlbumProvider(albumTracks: const [])..setTestHomeFeed(feedOf([album()]));
      await pumpHome(tester, p);

      await tester.tap(find.bySemanticsLabel('Play Fresh album'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(p.played, isEmpty);
      expect(find.text('Couldn\'t load "Fresh album"'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await hold(tester, 'Fresh album');
      await tester.tap(find.bySemanticsLabel('Play').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining("Couldn't load the songs"), findsOneWidget);
      expect(find.bySemanticsLabel('Shuffle'), findsWidgets, reason: 'the sheet stays so it can be retried');
    });

    homeTest('a mood tile is not given a play disc', (tester) async {
      const mood = HomeItem(
        id: 'FEmusic_moods_and_genres_category_x',
        browseId: 'FEmusic_moods_and_genres_category_x',
        title: 'Chill',
        subtitle: '',
        artworkUrl: '',
        contentType: HomeContentType.playlist,
      );
      final p = AlbumProvider()..setTestHomeFeed(feedOf([mood, album()]));
      await pumpHome(tester, p);
      expect(find.bySemanticsLabel('Play Fresh album'), findsOneWidget, reason: 'the album has one');
      expect(find.bySemanticsLabel('Play Chill'), findsNothing, reason: 'a category is not playable');
    });

    homeTest('a card that cannot do anything answers instead of going quiet', (tester) async {
      const dead = HomeItem(
        id: 'mystery',
        title: 'Mystery',
        subtitle: 'Nobody',
        artworkUrl: '',
        contentType: HomeContentType.song, // a song with no videoId is not playable
      );
      final p = AlbumProvider()..setTestHomeFeed(feedOf([dead, album()]));
      await pumpHome(tester, p);
      await tester.tap(find.text('Mystery'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Can\'t open "Mystery" from here'), findsOneWidget);
    });
  });
}
