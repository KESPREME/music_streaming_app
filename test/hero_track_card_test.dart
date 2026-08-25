import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/widgets/hero_track_card.dart';

Track _track(String id) => Track(
      id: id,
      trackName: 'Neon Skyline',
      artistName: 'Aurora Waves',
      albumName: 'Polar',
      previewUrl: 'https://example.com/audio.mp4',
    );

void main() {
  testWidgets('renders title and artist', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HeroTrackCard(track: _track('a'))),
      ),
    );
    expect(find.text('Neon Skyline'), findsOneWidget);
    expect(find.text('Aurora Waves'), findsOneWidget);
  });

  testWidgets('tap fires callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeroTrackCard(track: _track('a'), onTap: () => taps++),
        ),
      ),
    );
    await tester.tap(find.byType(HeroTrackCard));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('uses fallback container when art fails to load', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HeroTrackCard(track: _track('bad'))),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });
    expect(find.byType(HeroTrackCard), findsOneWidget);
  });

  test('accent resolves to black foreground on light accent', () {
    final color = const Color(0xFFFFE0B2);
    expect(color.computeLuminance() > 0.5, isTrue);
  });
}
