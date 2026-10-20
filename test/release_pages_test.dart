import 'dart:async';

import 'package:flutter/foundation.dart';
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
  ArtistDetailData? artist;

  @override
  Future<void> playTrackList(List<Track> tracks, {int initialIndex = 0, String? playlistId}) async {
    played.add(([for (final t in tracks) t.id], initialIndex));
  }

  @override
  Future<void> downloadTracks(List<Track> tracks, {bool skipDownloaded = true}) async {
    queuedDownloads.addAll(tracks.map((t) => t.id));
  }

  @override
  Future<ArtistDetailData> fetchArtistPageData(String browseId) async => artist!;
}

Track _t(String id, {int ms = 180000}) => Track(
      id: id,
      trackName: 'Song $id',
      artistName: "K'naan",
      albumName: 'Troubadour',
      previewUrl: '',
      albumArtUrl: '',
      durationMs: ms,
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
    test('the sleeve is 76% of the width, at most half the height', () {
      expect(releaseSleeveSize(const Size(400, 900)), closeTo(304, 0.01));
      expect(releaseSleeveSize(const Size(900, 400)), 200);
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
    });

    Future<void> pump(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(1200, 2700);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
        value: p,
        child: MaterialApp(home: page),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('album: framed sleeve, one honest meta line, play / shuffle / download', (tester) async {
      final tracks = [_t('a1', ms: 240000), _t('a2', ms: 240000), _t('a1', ms: 240000)];
      await pump(
        tester,
        AlbumDetailScreen(
          albumId: 'x',
          albumName: 'Troubadour',
          artistName: "K'naan",
          cachedTracks: tracks,
        ),
      );
      expect(find.byKey(const ValueKey('album_sleeve')), findsOneWidget);
      final sleeve = tester.getSize(find.byKey(const ValueKey('album_sleeve')));
      expect(sleeve.width, closeTo(304, 0.5));
      // No invented year: the page knows the kind, the count and the runtime.
      expect(find.text('Album · 3 tracks · 12 min'), findsOneWidget);
      expect(find.textContaining('2024'), findsNothing);
      // Numbered by position, the repeated track included.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      expect(p.played.single.$1, ['a1', 'a2', 'a1']);
      expect(p.played.single.$2, 0);

      await tester.tap(find.bySemanticsLabel('Download'));
      await tester.pump();
      expect(p.queuedDownloads, ['a1', 'a2', 'a1']);
      expect(find.byType(BitchordActionBar), findsNothing, reason: 'search and more moved to the top bar');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('artist: play disc, latest release, show all, about at the end', (tester) async {
      p.artist = ArtistDetailData(
        name: "K'naan",
        heroImageUrl: '',
        subscriberCountText: '1.9M subscribers',
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
      await pump(
        tester,
        const ArtistDetailScreen(artistId: 'UCknaan', artistName: "K'naan"),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('artist_latest_release')), findsOneWidget);
      expect(find.text('Refugee'), findsWidgets);
      expect(find.text('Single · 2023'), findsOneWidget);
      expect(find.bySemanticsLabel('Share'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      expect(p.played.single.$1, hasLength(25), reason: 'Play takes every top song');

      final grid = tester.widget<TopSongsPagerGrid>(find.byType(TopSongsPagerGrid));
      expect(grid.songs, hasLength(20));

      // Six singles: Show all. Two artists: no.
      await tester.scrollUntilVisible(find.text('Fans might also like'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Show all'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('About the artist'), 300,
          scrollable: find.byType(Scrollable).first);
      final aboutY = tester.getTopLeft(find.text('About the artist')).dy;
      final fansY = tester.getTopLeft(find.text('Fans might also like')).dy;
      expect(aboutY, greaterThan(fansY), reason: 'About comes after the music');
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
