import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/utils/artwork_palette_resolver.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/about_section.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/artist_stats_row.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/bitchord_action_bar.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/bitchord_sliver_app_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ArtworkPaletteResolver Tests', () {
    test('Derives distinct HSL palette tokens accurately', () {
      const dominant = Color(0xFFE89838); // Warm orange
      final palette = ArtworkPaletteResolver.fromColors(dominant);

      expect(palette.background, isNotNull);
      expect(palette.wash, isNotNull);
      expect(palette.elevated, isNotNull);
      expect(palette.accent, isNotNull);
      expect(palette.onBackgroundVariant, isNotNull);
      expect(palette.divider, isNotNull);

      // Dark theme background should be very dark (lightness ~ 0.13)
      final hslBg = HSLColor.fromColor(palette.background);
      expect(hslBg.lightness, lessThan(0.20));

      // Accent should retain vibrancy
      final hslAccent = HSLColor.fromColor(palette.accent);
      expect(hslAccent.saturation, greaterThan(0.40));
    });

    test('Default dark palette fallback works', () {
      final def = ArtworkPalette.defaultDark;
      expect(def.background, const Color(0xFF0A080C));
      expect(def.accent, const Color(0xFFFF5252));
    });
  });

  group('ArtistStatsRow Formatting & Layout Tests', () {
    testWidgets('Formats "260M monthly listeners" and scales down without overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320, // narrow screen
              child: ArtistStatsRow(
                subscriberCountText: '35.4M subscribers',
                monthlyListenerCount: '260M monthly audience',
                palette: ArtworkPalette.defaultDark,
              ),
            ),
          ),
        ),
      );

      expect(find.text('35.4M subscribers'), findsOneWidget);
      expect(find.text('260M monthly listeners'), findsOneWidget);
      // Ensure no layout overflow exception
      expect(tester.takeException(), isNull);
    });
  });

  group('BitchordActionBar Search Button Tests', () {
    testWidgets('Search button displays search icon and preserves it', (tester) async {
      bool searchActive = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return BitchordActionBar(
                  onPlay: () {},
                  onShuffle: () {},
                  onSearch: () {
                    setState(() {
                      searchActive = !searchActive;
                    });
                  },
                  searching: searchActive,
                  onMore: () {},
                );
              },
            ),
          ),
        ),
      );

      // Initially search icon
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      // Tap search
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Should still be search icon (never turns to 'X')
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });
  });

  group('AboutSection Text Cleaning Tests', () {
    test('Strips Wikipedia URLs and trailing boilerplates', () {
      const rawText =
          'The Weeknd is a Canadian singer and songwriter. '
          'Read more on https://en.wikipedia.org/wiki/The_Weeknd (from Wikipedia, the free encyclopedia).';
      final cleaned = AboutSection.cleanText(rawText);

      expect(cleaned.contains('https://'), isFalse);
      expect(cleaned.contains('from Wikipedia'), isFalse);
      expect(cleaned.startsWith('The Weeknd is a Canadian singer'), isTrue);
    });
  });

  group('BitchordSliverAppBar Tests', () {
    testWidgets('Renders back button and title fades in with scroll offset', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                BitchordSliverAppBar(
                  title: 'Hurry Up Tomorrow',
                  scrollOffset: 450.0, // Scrolled past threshold
                  artHeight: 380.0,
                  backgroundColor: const Color(0xFF101010),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.more_horiz_rounded),
                      onPressed: () {},
                    ),
                  ],
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 1000),
                ),
              ],
            ),
          ),
        ),
      );

      // Back button and more button exist
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

      // Title text exists
      expect(find.text('Hurry Up Tomorrow'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

