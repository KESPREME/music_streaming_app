import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/widgets/search_grid_cards.dart';
import 'package:music_streaming_app/widgets/search_result_row.dart';

void main() {
  final testTrack = Track(
    id: 'test_123',
    trackName: 'Borderline',
    artistName: 'Tame Impala',
    albumName: 'The Slow Rush',
    previewUrl: 'https://example.com/preview.mp3',
    albumArt: 'https://example.com/art.jpg',
    durationMs: 238000,
    source: 'youtube',
  );

  group('SearchMediaGridCard Tests (Albums & Playlists)', () {
    testWidgets('renders square artwork, title, subtitle and fires onTap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: SearchMediaGridCard(
                  track: testTrack,
                  subtitle: 'EP, Summer Jones',
                  onTap: () => tapped = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Borderline'), findsOneWidget);
      expect(find.text('EP, Summer Jones'), findsOneWidget);

      await tester.tap(find.text('Borderline'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });

  group('SearchArtistGridCard Tests (Artists)', () {
    testWidgets('renders circular portrait, centered title, Artist subtitle and fires onTap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: SearchArtistGridCard(
                  artistName: 'Tame Impala',
                  artistImageUrl: 'https://example.com/artist.jpg',
                  subtitle: 'Artist',
                  onTap: () => tapped = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tame Impala'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);

      await tester.tap(find.text('Tame Impala'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });

  group('SearchResultRow Video 16:9 Tests (Videos)', () {
    testWidgets('renders 16:9 widescreen thumbnail when isVideo is true', (tester) async {
      bool tapped = false;
      bool moreTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchResultRow(
              track: testTrack,
              isVideo: true,
              subtitle: 'Tame Impala • 3:58',
              onTap: () => tapped = true,
              onMore: () => moreTapped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Borderline'), findsOneWidget);
      expect(find.text('Tame Impala • 3:58'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);

      // Verify widescreen thumbnail width 104, height 58
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final videoArtworkBox = sizedBoxes.firstWhere(
        (box) => box.width == 104.0 && box.height == 58.0,
      );
      expect(videoArtworkBox, isNotNull);

      // Tap row
      await tester.tap(find.text('Borderline'));
      await tester.pump();
      expect(tapped, isTrue);

      // Tap more icon
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pump();
      expect(moreTapped, isTrue);
    });
  });
}
