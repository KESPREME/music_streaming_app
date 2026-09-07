import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/bitchord_page_models.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/bitchord_detail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BitChord Models Test', () {
    test('DetailShelfItem and DetailShelf instantiation and defaults', () {
      const item = DetailShelfItem(
        title: 'Born in the Wild',
        subtitle: '2024 • Album',
        browseId: 'MPREb_album1',
        imageUrl: 'https://example.com/art.jpg',
        type: 'album',
      );

      expect(item.title, 'Born in the Wild');
      expect(item.subtitle, '2024 • Album');
      expect(item.browseId, 'MPREb_album1');
      expect(item.type, 'album');

      const shelf = DetailShelf(
        title: 'Albums',
        items: [item],
      );

      expect(shelf.title, 'Albums');
      expect(shelf.items.length, 1);
      expect(shelf.items.first.title, 'Born in the Wild');
    });

    test('ArtistDetailData structure and properties', () {
      final artistData = ArtistDetailData(
        name: 'Tems',
        heroImageUrl: 'https://example.com/hero.jpg',
        subscriberCountText: '1.72M subscribers',
        monthlyListenerCount: '67.3M monthly listeners',
        description: 'Temilade Openiyi is a Nigerian singer and songwriter.',
        topSongs: [
          Track(
            id: 'song_1',
            trackName: 'Me & U',
            artistName: 'Tems',
            albumName: 'Born in the Wild',
            previewUrl: '',
            albumArtUrl: 'https://example.com/art1.jpg',
            duration: const Duration(seconds: 192),
          ),
        ],
        shelves: const [
          DetailShelf(
            title: 'Albums',
            items: [
              DetailShelfItem(
                title: 'Born in the Wild',
                subtitle: '2024',
                browseId: 'MPREb_album',
                imageUrl: 'https://example.com/art.jpg',
              ),
            ],
          ),
        ],
      );

      expect(artistData.name, 'Tems');
      expect(artistData.subscriberCountText, '1.72M subscribers');
      expect(artistData.monthlyListenerCount, '67.3M monthly listeners');
      expect(artistData.topSongs.length, 1);
      expect(artistData.topSongs.first.title, 'Me & U');
      expect(artistData.shelves.length, 1);
      expect(artistData.shelves.first.title, 'Albums');
    });

    test('AlbumDetailData structure and properties', () {
      final albumData = AlbumDetailData(
        title: 'Born in the Wild',
        artistName: 'Tems',
        artistBrowseId: 'UC_tems',
        year: '2024',
        trackCount: 18,
        coverUrl: 'https://example.com/album.jpg',
        description: 'Debut studio album by Tems.',
        tracks: [
          Track(
            id: 't_1',
            trackName: 'Born in the Wild',
            artistName: 'Tems',
            albumName: 'Born in the Wild',
            previewUrl: '',
            duration: const Duration(seconds: 144),
          ),
        ],
      );

      expect(albumData.title, 'Born in the Wild');
      expect(albumData.artistName, 'Tems');
      expect(albumData.year, '2024');
      expect(albumData.trackCount, 18);
      expect(albumData.tracks.length, 1);
      expect(albumData.tracks.first.durationText, '2:24');
    });

    test('PlaylistDetailData structure and properties', () {
      final playlistData = PlaylistDetailData(
        title: 'Born In the Wild',
        curatorName: 'Tems',
        viewsText: '78K views',
        trackCount: 5,
        coverUrl: 'https://example.com/playlist.jpg',
        collageThumbnails: const [
          'https://example.com/1.jpg',
          'https://example.com/2.jpg',
          'https://example.com/3.jpg',
          'https://example.com/4.jpg',
        ],
        description: 'Complete playlist collection.',
        tracks: [
          Track(
            id: 'p_1',
            trackName: 'Love Me JeJe',
            artistName: 'Tems',
            albumName: 'Born in the Wild',
            previewUrl: '',
            duration: const Duration(seconds: 178),
          ),
        ],
      );

      expect(playlistData.title, 'Born In the Wild');
      expect(playlistData.curatorName, 'Tems');
      expect(playlistData.viewsText, '78K views');
      expect(playlistData.collageThumbnails?.length, 4);
    });
  });

  group('BitChord Detail Widgets Test', () {
    testWidgets('ArtistStatsRow renders subscribers and monthly listeners',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArtistStatsRow(
              subscriberCountText: '1.72M subscribers',
              monthlyListenerCount: '67.3M monthly listeners',
            ),
          ),
        ),
      );

      expect(find.text('1.72M subscribers'), findsOneWidget);
      expect(find.text('67.3M monthly listeners'), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    });

    testWidgets('BitchordActionBar renders all 4 action buttons and handles taps',
        (tester) async {
      bool playTapped = false;
      bool shuffleTapped = false;
      bool searchTapped = false;
      bool moreTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BitchordActionBar(
              accentColor: Colors.deepOrange,
              onPlay: () => playTapped = true,
              onShuffle: () => shuffleTapped = true,
              onSearch: () => searchTapped = true,
              onMore: () => moreTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Play'), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(playTapped, true);

      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await tester.pumpAndSettle();
      expect(shuffleTapped, true);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(searchTapped, true);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(moreTapped, true);
    });

    testWidgets('AboutSection expands and collapses', (tester) async {
      const longBio =
          'This is a long description of the artist or album that spans many sentences. '
          'It tells the story of how the project came together and the inspiration behind every track. '
          'There are many layers of instrumentation and emotional vocal delivery throughout.';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AboutSection(
              title: 'About the artist',
              text: longBio,
              accentColor: Colors.deepOrange,
            ),
          ),
        ),
      );

      expect(find.text('About the artist'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Less'), findsOneWidget);

      await tester.tap(find.text('Less'));
      await tester.pumpAndSettle();
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('DetailSearchField filters input and invokes clear',
        (tester) async {
      final controller = TextEditingController();
      String currentQuery = '';
      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailSearchField(
              controller: controller,
              hintText: 'Search in playlist',
              accentColor: Colors.teal,
              onChanged: (q) => currentQuery = q,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Wild');
      expect(currentQuery, 'Wild');

      // First tap clears text
      await tester.pump();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(controller.text, '');
      expect(currentQuery, '');

      // Second tap when empty invokes onClose
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(closed, true);
    });

    testWidgets('TopSongsPagerGrid arranges tracks into 4-row columns',
        (tester) async {
      final testTracks = List.generate(
        10,
        (i) => Track(
          id: 'song_$i',
          trackName: 'Track Title $i',
          artistName: 'Artist $i',
          albumName: 'Album $i',
          previewUrl: '',
          duration: const Duration(minutes: 3, seconds: 20),
        ),
      );

      int tappedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TopSongsPagerGrid(
              songs: testTracks,
              accentColor: Colors.deepPurple,
              onSongTap: (queue, index) => tappedIndex = index,
            ),
          ),
        ),
      );

      expect(find.text('Top songs'), findsOneWidget);
      // The first column displays 4 tracks
      expect(find.text('Track Title 0'), findsOneWidget);
      expect(find.text('Track Title 1'), findsOneWidget);
      expect(find.text('Track Title 2'), findsOneWidget);
      expect(find.text('Track Title 3'), findsOneWidget);

      await tester.tap(find.text('Track Title 0'));
      await tester.pump();
      expect(tappedIndex, 0);
    });

    testWidgets('CollageArtwork renders 2x2 quadrant container', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: CollageArtwork(
                collageUrls: [
                  'https://example.com/1.jpg',
                  'https://example.com/2.jpg',
                  'https://example.com/3.jpg',
                  'https://example.com/4.jpg',
                ],
                fallbackUrl: 'https://example.com/fallback.jpg',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CollageArtwork), findsOneWidget);
    });
  });
}
