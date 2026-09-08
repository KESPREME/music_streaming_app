import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/core/navigation/root_navigator.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/metadata/track_metadata_enricher.dart';
import 'package:music_streaming_app/utils/artwork_palette_resolver.dart';
import 'package:music_streaming_app/widgets/artist_picker_sheet.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/bitchord_detail.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/bitchord_sliver_app_bar.dart';
import 'package:music_streaming_app/widgets/themed_album_detail_screen.dart';

void main() {
  group('Track isExplicit & Metadata Enrichment Tests', () {
    test('Track models isExplicit property correctly', () {
      final tClean = Track(
        id: '1',
        trackName: 'Wake Me Up',
        artistName: 'The Weeknd',
        albumName: 'Hurry Up Tomorrow',
        previewUrl: '',
        isExplicit: false,
      );
      expect(tClean.isExplicit, isFalse);

      final tExplicit = Track(
        id: '2',
        trackName: 'Cry For Me',
        artistName: 'The Weeknd',
        albumName: 'Hurry Up Tomorrow',
        previewUrl: '',
        isExplicit: true,
      );
      expect(tExplicit.isExplicit, isTrue);

      final json = tExplicit.toJson();
      expect(json['isExplicit'], isTrue);

      final fromJson = Track.fromJson(json);
      expect(fromJson.isExplicit, isTrue);

      final copied = tExplicit.copyWith(isExplicit: false);
      expect(copied.isExplicit, isFalse);
    });

    test('TrackMetadataEnricher extracts explicit markers from track title', () {
      final trackWithTag = Track(
        id: '3',
        trackName: 'São Paulo (Explicit)',
        artistName: 'The Weeknd, Anitta',
        albumName: 'Hurry Up Tomorrow',
        previewUrl: '',
      );

      final sanitized = TrackMetadataEnricher.sanitizeTrack(trackWithTag);
      expect(sanitized.isExplicit, isTrue);
      expect(sanitized.trackName, 'São Paulo');

      final trackWithBracket = Track(
        id: '4',
        trackName: 'I Can\'t Fucking Sing [Explicit]',
        artistName: 'The Weeknd',
        albumName: 'Hurry Up Tomorrow',
        previewUrl: '',
      );

      final sanitized2 = TrackMetadataEnricher.sanitizeTrack(trackWithBracket);
      expect(sanitized2.isExplicit, isTrue);
      expect(sanitized2.trackName, 'I Can\'t Fucking Sing');
    });
  });

  group('BitchordExplicitBadge Widget Tests', () {
    testWidgets('Renders [E] badge with crisp typography and styling', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BitchordExplicitBadge(),
            ),
          ),
        ),
      );

      expect(find.byType(BitchordExplicitBadge), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
    });
  });

  group('TopSongsPagerGrid Parity Tests', () {
    testWidgets('Renders top songs with explicit badge and without swipe interceptor', (tester) async {
      final testSongs = [
        Track(
          id: '1',
          trackName: 'Wake Me Up',
          artistName: 'The Weeknd',
          albumName: 'HUT',
          previewUrl: '',
          isExplicit: false,
        ),
        Track(
          id: '2',
          trackName: 'Cry For Me',
          artistName: 'The Weeknd',
          albumName: 'HUT',
          previewUrl: '',
          isExplicit: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TopSongsPagerGrid(
              songs: testSongs,
              onSongTap: (_, __) {},
              accentColor: Colors.deepOrange,
            ),
          ),
        ),
      );

      // Verify header and songs
      expect(find.text('Top songs'), findsOneWidget);
      expect(find.text('Wake Me Up'), findsOneWidget);
      expect(find.text('Cry For Me'), findsOneWidget);

      // Verify BitchordExplicitBadge renders for explicit song
      expect(find.byType(BitchordExplicitBadge), findsOneWidget);

      // Verify BitchordSwipeableTrackRow is NOT present in TopSongsPagerGrid
      expect(find.byType(BitchordSwipeableTrackRow), findsNothing);
    });
  });

  group('ThemedAlbumDetailScreen Instant Routing Test', () {
    test('Constructs ThemedAlbumDetailScreen with searchByName correctly', () {
      const album = ThemedAlbumDetailScreen(
        albumId: 'album_Hurry Up Tomorrow',
        albumName: 'Hurry Up Tomorrow',
        artistName: 'The Weeknd',
        searchByName: true,
      );

      expect(album.albumId, 'album_Hurry Up Tomorrow');
      expect(album.albumName, 'Hurry Up Tomorrow');
      expect(album.artistName, 'The Weeknd');
      expect(album.searchByName, isTrue);
    });
  });

  group('mainNavigatorKey Registration Test', () {
    test('mainNavigatorKey is exported and initialized', () {
      expect(mainNavigatorKey, isNotNull);
      expect(rootNavigatorKey, isNotNull);
    });
  });

  group('PrimaryArtist Resolution Tests (BitChord parity)', () {
    test('Extracts primary artist accurately from multi-artist credits', () {
      expect(ArtistPickerSheet.getPrimaryArtist('The Weeknd, Anitta'), 'The Weeknd');
      expect(ArtistPickerSheet.getPrimaryArtist('Anitta & Shakira'), 'Anitta');
      expect(ArtistPickerSheet.getPrimaryArtist('Post Malone feat. Morgan Wallen'), 'Post Malone');
      expect(ArtistPickerSheet.getPrimaryArtist('Drake ft. 21 Savage'), 'Drake');
      expect(ArtistPickerSheet.getPrimaryArtist('AC/DC'), 'AC/DC');
      expect(ArtistPickerSheet.getPrimaryArtist('Florence and the Machine'), 'Florence and the Machine');
      expect(ArtistPickerSheet.getPrimaryArtist('Coldplay'), 'Coldplay');
      expect(ArtistPickerSheet.getPrimaryArtist(''), '');
    });
  });

  group('BitChord Authentic ArtworkPalette Tests', () {
    test('Produces authentic BitChord background with lightness 0.13', () {
      final palette = ArtworkPaletteResolver.fromColors(
        const Color(0xFF524335), // The previous muddy olive/khaki swatch
        vibrantColor: const Color(0xFFD32F2F),
        edgeColor: const Color(0xFF3E2723),
        dark: true,
      );

      final bgHsl = HSLColor.fromColor(palette.background);
      expect(bgHsl.lightness, closeTo(0.13, 0.01));

      final defaultHsl = HSLColor.fromColor(ArtworkPalette.defaultDark.background);
      expect(defaultHsl.lightness, lessThanOrEqualTo(0.07));
    });
  });

  group('BitchordSliverAppBar Transparency Tests', () {
    testWidgets('Renders crystal-clear with 0 blur when scrollOffset is 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                BitchordSliverAppBar(
                  title: 'Hurry Up Tomorrow',
                  scrollOffset: 0.0,
                  artHeight: 380,
                  backgroundColor: const Color(0xFF0A080C),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 1000)),
              ],
            ),
          ),
        ),
      );

      // At rest (offset = 0), fadeProgress <= 0.001, so BackdropFilter is bypassed completely
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Hurry Up Tomorrow'), findsOneWidget);

      // Title opacity is 0.0 at rest
      final opacityWidget = tester.widget<Opacity>(
        find.ancestor(
          of: find.text('Hurry Up Tomorrow'),
          matching: find.byType(Opacity),
        ).first,
      );
      expect(opacityWidget.opacity, equals(0.0));
    });

    testWidgets('Renders transparent frosted blur without solid colored background when scrolled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                BitchordSliverAppBar(
                  title: 'Hurry Up Tomorrow',
                  scrollOffset: 500.0,
                  artHeight: 380,
                  backgroundColor: const Color(0xFF524335),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 1000)),
              ],
            ),
          ),
        ),
      );

      // Scrolled past threshold: BackdropFilter is active
      expect(find.byType(BackdropFilter), findsOneWidget);
      
      // SliverAppBar has forceMaterialTransparency = true
      final sliverAppBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
      expect(sliverAppBar.forceMaterialTransparency, isTrue);
      expect(sliverAppBar.backgroundColor, equals(Colors.transparent));

      // Container has top gradient scrim, NOT solid backgroundColor
      final containers = tester.widgetList<Container>(find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.byType(Container),
      ));
      expect(containers.isNotEmpty, isTrue);
      final boxDeco = containers.first.decoration as BoxDecoration?;
      expect(boxDeco?.color, isNull); // No solid color!
      expect(boxDeco?.border, isNull); // No divider border!
    });
  });
}

