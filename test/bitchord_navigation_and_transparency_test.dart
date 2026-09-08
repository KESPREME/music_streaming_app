import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/core/navigation/root_navigator.dart';
import 'package:music_streaming_app/widgets/glass_options_sheet.dart';
import 'package:music_streaming_app/widgets/artist_picker_sheet.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/bitchord_sliver_app_bar.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/merge_band.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/utils/artwork_palette_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BitChord Navigation Target Tests', () {
    testWidgets('Go to album from options pushes onto mainNavigatorKey and collapses player', (tester) async {
      final musicProvider = MusicProvider();
      final track = Track(
        id: 'test_track_1',
        trackName: 'São Paulo',
        artistName: 'The Weeknd, Anitta',
        albumName: 'Hurry Up Tomorrow',
        albumArtUrl: 'https://example.com/art.jpg',
        previewUrl: 'https://example.com/audio.mp3',
      );

      musicProvider.setPlayerExpanded(true);
      expect(musicProvider.isPlayerExpanded, isTrue);

      ArtworkPaletteResolver.putCached(track.albumArtUrl, ArtworkPalette.defaultDark);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MusicProvider>.value(value: musicProvider),
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ],
          child: MaterialApp(
            navigatorKey: mainNavigatorKey,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      GlassOptionsSheet.show(
                        ctx,
                        track: track,
                      );
                    },
                    child: const Text('Open Options'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Open sheet
      await tester.tap(find.text('Open Options'));
      await tester.pumpAndSettle();

      // Find "Go to album"
      final goToAlbumOption = find.text('Go to album');
      expect(goToAlbumOption, findsOneWidget);

      // Tap "Go to album"
      await tester.tap(goToAlbumOption, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      // Player should be collapsed
      expect(musicProvider.isPlayerExpanded, isFalse);
      expect(musicProvider.hideMiniPlayer, isFalse);

      // Detail screen should be pushed onto mainNavigatorKey
      expect(mainNavigatorKey.currentState?.canPop(), isTrue);

      musicProvider.dispose();
    });

    testWidgets('ArtistPickerSheet parseArtists and getPrimaryArtist behaves correctly', (tester) async {
      expect(ArtistPickerSheet.getPrimaryArtist('The Weeknd, Anitta'), equals('The Weeknd'));
      expect(ArtistPickerSheet.getPrimaryArtist('AC/DC'), equals('AC/DC'));
      expect(ArtistPickerSheet.hasMultipleArtists('The Weeknd, Anitta'), isTrue);
      expect(ArtistPickerSheet.hasMultipleArtists('The Weeknd'), isFalse);
    });
  });

  group('BitChord MergeBand & Transparent Top Bar Tests', () {
    testWidgets('MergeBand renders without error and blends join with backdrop filter', (tester) async {
      final controller = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                MergeBand(
                  scrollController: controller,
                  artHeight: 380,
                  washColor: const Color(0xFF131018),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(MergeBand), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('BitchordSliverAppBar has forceMaterialTransparency and transparent background', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                BitchordSliverAppBar(
                  title: 'Starboy',
                  scrollOffset: 100.0,
                  artHeight: 380,
                  backgroundColor: const Color(0xFF131018),
                ),
              ],
            ),
          ),
        ),
      );

      final sliverAppBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
      expect(sliverAppBar.forceMaterialTransparency, isTrue);
      expect(sliverAppBar.backgroundColor, equals(Colors.transparent));
    });
  });
}
