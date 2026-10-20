import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/bitchord_page_models.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/album_detail_screen.dart';
import 'package:music_streaming_app/screens/artist_detail_screen.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/bitchord_detail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _P extends MusicProvider {
  final played = <(List<String>, int)>[];
  final queuedDownloads = <String>[];
  final queued = <String>[];
  final nexts = <String>[];
  ArtistDetailData? artist;
  AlbumDetailData? albumData;

  @override
  Future<void> playTrackList(List<Track> tracks, {int initialIndex = 0, String? playlistId}) async {
    played.add(([for (final t in tracks) t.id], initialIndex));
  }

  @override
  Future<void> downloadTracks(List<Track> tracks, {bool skipDownloaded = true}) async {
    queuedDownloads.addAll(tracks.map((t) => t.id));
  }

  @override
  void addListToQueue(List<Track> tracks) => queued.addAll(tracks.map((t) => t.id));

  @override
  void playNext(Track track) => nexts.add(track.id);

  @override
  Future<ArtistDetailData> fetchArtistPageData(String browseId) async => artist!;

  @override
  Future<AlbumDetailData> fetchAlbumPageData(String browseId) async => albumData!;
}

Track _t(String id, {int ms = 180000, String? name}) => Track(
      id: id,
      trackName: name ?? 'Song $id',
      artistName: "K'naan",
      albumName: 'Troubadour',
      previewUrl: '',
      albumArtUrl: '',
      duration: Duration(milliseconds: ms),
    );

void main() {
  group('release meta line', () {
    test('kind · year · tracks · runtime', () {
      expect(
        releaseMetaLine(kind: 'Album', year: '2008', trackCount: 14, totalSeconds: 59 * 60),
        'Album · 2008 · 14 tracks · 59 min',
      );
    });
    test('unknown parts are left out, never invented', () {
      expect(releaseMetaLine(kind: 'Album', trackCount: 3), 'Album · 3 tracks');
      expect(releaseMetaLine(trackCount: 1), '1 track');
      expect(releaseMetaLine(trackCount: 0), '');
    });
    test('hours read as hours', () {
      expect(releaseDurationText(72 * 60), '1 hr 12 min');
      expect(releaseDurationText(120 * 60), '2 hr');
      expect(releaseDurationText(20), '1 min');
    });
    test('kind from the header subtitle', () {
      expect(releaseKindFrom('Album'), 'Album');
      expect(releaseKindFrom(' EP '), 'EP');
      expect(releaseKindFrom('single'), 'Single');
      expect(releaseKindFrom(' • '), isNull);
      expect(releaseKindFrom(null), isNull);
    });
  });

  group('pages', () {
    late _P p;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final ready = Completer<void>();
      final original = debugPrint;
      debugPrint = (msg, {wrapWidth}) {
        if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) {
          ready.complete();
        }
      };
      p = _P();
      await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      debugPrint = original;
    });

    setUp(() {
      p.played.clear();
      p.queuedDownloads.clear();
      p.queued.clear();
      p.nexts.clear();
    });

    Future<void> pump(WidgetTester tester, Widget page) async {
      // 400x900 logical at 3x. (setSurfaceSize does not apply in this Flutter.)
      tester.view.physicalSize = const Size(1200, 2700);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
        value: p,
        child: MaterialApp(home: page),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
    }

    List<Track> album() => [
          _t('a1', ms: 240000, name: 'Zulu'),
          _t('a2', ms: 180000, name: 'Alpha'),
          _t('a3', ms: 300000, name: 'Mike'),
        ];

    AlbumDetailScreen albumPage() => AlbumDetailScreen(
          albumId: 'x',
          albumName: 'Troubadour',
          artistName: "K'naan",
          cachedTracks: album(),
        );

    testWidgets('album: FULL BLEED, one surface, no framed sleeve and no band layer', (tester) async {
      await pump(tester, albumPage());
      final header = find.byType(ImmersiveHeader);
      expect(header, findsOneWidget);
      final size = tester.getSize(header);
      expect(size.width, 400, reason: 'edge to edge');
      expect(size.height, closeTo(400 / 0.92, 1));
      expect(tester.getTopLeft(header), Offset.zero, reason: 'behind the status bar');
      // The layers that made the dark band are not on the page.
      expect(find.byType(MergeBand), findsNothing);
      expect(find.byType(ArtworkFootFade), findsNothing);
      expect(find.byKey(const ValueKey('album_sleeve')), findsNothing);
      expect(find.byType(BitchordActionBar), findsNothing);
    });

    testWidgets('album: one honest meta line, durations, original track numbers', (tester) async {
      await pump(tester, albumPage());
      expect(find.text('Album · 3 tracks · 12 min'), findsOneWidget);
      expect(find.textContaining('2024'), findsNothing);
      expect(find.byKey(const ValueKey('duration_a1')), findsOneWidget);
      expect(find.text('4:00'), findsOneWidget);
      expect(find.text('3:00'), findsOneWidget);
      expect(find.text('5:00'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('album: glass pills play, shuffle and download', (tester) async {
      await pump(tester, albumPage());
      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      expect(p.played.last.$1, ['a1', 'a2', 'a3']);
      expect(p.played.last.$2, 0);

      await tester.tap(find.bySemanticsLabel('Shuffle'));
      await tester.pump();
      expect(p.played.last.$1.toSet(), {'a1', 'a2', 'a3'});

      await tester.tap(find.bySemanticsLabel('Download'));
      await tester.pump();
      expect(p.queuedDownloads, ['a1', 'a2', 'a3']);
    });

    testWidgets('album: Sort reorders the list and Play + row taps follow it', (tester) async {
      await pump(tester, albumPage());
      await tester.tap(find.bySemanticsLabel('Sort'));
      await tester.pumpAndSettle();
      expect(find.text('Album order'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Longest first'), findsOneWidget);
      await tester.tap(find.text('Title'));
      await tester.pumpAndSettle();

      // Rows now read Alpha, Mike, Zulu - each keeps its ALBUM number.
      final alpha = tester.getTopLeft(find.text('Alpha')).dy;
      final mike = tester.getTopLeft(find.text('Mike')).dy;
      final zulu = tester.getTopLeft(find.text('Zulu')).dy;
      expect(alpha, lessThan(mike));
      expect(mike, lessThan(zulu));
      expect(find.text('2'), findsOneWidget, reason: 'Alpha is track 2 on the album');

      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      expect(p.played.last.$1, ['a2', 'a3', 'a1'], reason: 'Play follows the order shown');

      await tester.tap(find.text('Mike'));
      await tester.pump();
      expect(p.played.last.$1, ['a2', 'a3', 'a1']);
      expect(p.played.last.$2, 1, reason: 'the queue starts at the row you tapped');
    });

    testWidgets('album: Sort by length puts the longest first', (tester) async {
      await pump(tester, albumPage());
      await tester.tap(find.bySemanticsLabel('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Longest first'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      expect(p.played.last.$1, ['a3', 'a1', 'a2']);
    });

    testWidgets('album: search filters, and closing it restores the list', (tester) async {
      await pump(tester, albumPage());
      await tester.tap(find.bySemanticsLabel('Search in album'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'mik');
      await tester.pump();
      expect(find.text('Mike'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Close search'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('album: the More menu queues the album in order', (tester) async {
      await pump(tester, albumPage());
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      for (final t in ['Play next', 'Add to queue', 'Save as playlist', 'Download album', 'Share', 'Go to artist']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      expect(p.queued, ['a1', 'a2', 'a3']);

      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play next'));
      await tester.pumpAndSettle();
      expect(p.nexts, ['a3', 'a2', 'a1'], reason: 'reversed, so the album plays in order');
    });

    testWidgets('album: the page\'s own title and kind win, and More by the artist shows under the list',
        (tester) async {
      p.albumData = AlbumDetailData(
        title: 'Troubadour (Deluxe)',
        artistName: "K'naan",
        year: '2009',
        kind: 'EP',
        coverUrl: '',
        description: 'The second studio album.',
        tracks: album(),
        shelves: [
          DetailShelf(title: "More by K'naan", items: [
            for (var i = 0; i < 3; i++)
              DetailShelfItem(title: 'Other $i', subtitle: 'Album', browseId: 'MPREb_o$i', imageUrl: ''),
          ]),
        ],
      );
      await pump(
        tester,
        const AlbumDetailScreen(albumId: 'MPREb_x', albumName: 'Troubadour', artistName: "K'naan"),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Troubadour (Deluxe)'), findsWidgets);
      expect(find.text('EP · 2009 · 3 tracks · 12 min'), findsOneWidget);

      await tester.scrollUntilVisible(find.text("More by K'naan"), 300, scrollable: find.byType(Scrollable).first);
      expect(find.byType(ShelfCarousel), findsOneWidget);
      expect(find.text('Other 0'), findsOneWidget);
      // After the tracks, never before them.
      final lastTrack = tester.getTopLeft(find.text('Mike')).dy;
      expect(tester.getTopLeft(find.text("More by K'naan")).dy, greaterThan(lastTrack));
    });

    ArtistDetailData artistData() => ArtistDetailData(
          name: "K'naan",
          heroImageUrl: '',
          subscriberCountText: '1.9M subscribers',
          monthlyListenerCount: '239M monthly audience',
          description: 'Somali-Canadian rapper.',
          topSongs: [for (var i = 0; i < 25; i++) _t('s$i')],
          shelves: [
            DetailShelf(title: 'Singles & EPs', items: [
              for (var i = 0; i < 6; i++)
                DetailShelfItem(
                  title: i == 0 ? 'Refugee' : 'Single $i',
                  subtitle: i == 0 ? 'Single • 2023' : '2020',
                  browseId: 'MPREb_$i',
                  imageUrl: '',
                  type: 'single',
                ),
            ]),
            const DetailShelf(title: 'Fans might also like', items: [
              DetailShelfItem(title: 'A', subtitle: '', browseId: 'UC1', imageUrl: '', type: 'artist'),
              DetailShelfItem(title: 'B', subtitle: '', browseId: 'UC2', imageUrl: '', type: 'artist'),
            ]),
          ],
        );

    Future<void> pumpArtist(WidgetTester tester) async {
      p.artist = artistData();
      await pump(tester, const ArtistDetailScreen(artistId: 'UCknaan', artistName: "K'naan"));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('artist: FULL BLEED, one surface, no band layer', (tester) async {
      await pumpArtist(tester);
      final header = find.byType(ImmersiveHeader);
      expect(header, findsOneWidget);
      expect(tester.getSize(header).width, 400);
      expect(tester.getTopLeft(header), Offset.zero);
      expect(find.byType(MergeBand), findsNothing);
      expect(find.byType(ArtworkFootFade), findsNothing);
    });

    testWidgets('artist: name, listeners caption, glass Play disc and latest release', (tester) async {
      await pumpArtist(tester);
      expect(find.byKey(const ValueKey('artist_name')), findsOneWidget);
      expect(find.byKey(const ValueKey('artist_listeners')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('artist_listeners'))).data,
        '239M monthly listeners',
      );
      expect(find.byKey(const ValueKey('artist_latest_release')), findsOneWidget);
      expect(find.text('Single · 2023'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      expect(p.played.last.$1, hasLength(25), reason: 'Play takes every top song');
      await tester.tap(find.bySemanticsLabel('Download'));
      await tester.pump();
      expect(p.queuedDownloads, hasLength(20), reason: 'the 20 shown');
    });

    testWidgets('artist: the top-right capsule DOES things (share, more menu, account)', (tester) async {
      await pumpArtist(tester);
      expect(find.bySemanticsLabel('Share'), findsOneWidget);
      expect(find.bySemanticsLabel('More'), findsOneWidget);
      expect(find.bySemanticsLabel('Sign in'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      for (final t in ['Play next', 'Add to queue', 'Save top songs as playlist', 'Download top songs', 'Share']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      expect(p.queued, hasLength(20));
      expect(p.queued.first, 's0');

      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download top songs'));
      await tester.pumpAndSettle();
      expect(p.queuedDownloads, hasLength(20));
    });

    testWidgets('artist: top songs capped at 20, Show all, About after the music', (tester) async {
      await pumpArtist(tester);
      final grid = tester.widget<TopSongsPagerGrid>(find.byType(TopSongsPagerGrid));
      expect(grid.songs, hasLength(20));

      await tester.scrollUntilVisible(find.text('Fans might also like'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Show all'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('About the artist'), 300,
          scrollable: find.byType(Scrollable).first);
      final aboutY = tester.getTopLeft(find.text('About the artist')).dy;
      final fansY = tester.getTopLeft(find.text('Fans might also like')).dy;
      expect(aboutY, greaterThan(fansY), reason: 'About comes after the music');
    });
  });

  group('album sort', () {
    final a = _t('a', ms: 100, name: 'Beta');
    final b = _t('b', ms: 300, name: 'alpha');
    final c = _t('c', ms: 300, name: 'Gamma');
    test('album order is the input, untouched', () {
      final input = [a, b, c];
      expect(sortAlbumTracks(input, AlbumSort.albumOrder), same(input));
    });
    test('title ignores case and keeps album order for ties', () {
      expect(sortAlbumTracks([a, b, c], AlbumSort.title).map((t) => t.id), ['b', 'a', 'c']);
    });
    test('longest first is stable for equal lengths', () {
      expect(sortAlbumTracks([a, b, c], AlbumSort.duration).map((t) => t.id), ['b', 'c', 'a']);
    });
    test('never mutates its input', () {
      final input = [a, b, c];
      sortAlbumTracks(input, AlbumSort.title);
      expect(input.map((t) => t.id), ['a', 'b', 'c']);
    });
  });
}