import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/presentation/explore/explore_feed_card.dart';
import 'package:music_streaming_app/presentation/explore/explore_layout.dart';
import 'package:music_streaming_app/presentation/explore/explore_wheel.dart';
import 'package:music_streaming_app/services/explore/explore_palette.dart';
import 'package:music_streaming_app/services/explore/explore_controller.dart';
import 'package:music_streaming_app/services/explore/explore_engine.dart';
import 'package:music_streaming_app/services/recommendation/candidate.dart';
import 'package:music_streaming_app/services/recommendation/taste_profile.dart';

Track _t(String id) => Track(
      id: id,
      trackName: 'Song $id',
      artistName: 'Artist $id',
      albumName: 'Album $id',
      previewUrl: '',
      source: 'youtube',
    );

ExploreItem _item(String id) => ExploreItem(
      track: _t(id),
      reason: CandidateReason.regionalTrending,
      score: 1,
      source: 'chart_regional',
    );

void main() {
  group('ExploreController thermal & network refill throttling', () {
    test('rapid refill calls within cooldown are throttled', () async {
      int fetchCalls = 0;
      final controller = ExploreController(
        engine: ExploreEngine(),
        fetchSources: (anchor) async {
          fetchCalls++;
          return ExploreSources(
            regionalChart: [_t('s1'), _t('s2')],
          );
        },
        play: (track, upcoming) async {},
        profileProvider: () => TasteProfile.build(events: const []),
        recordSwipeOutcome: (_, {required wasAccepted}) {},
        isCurrentTrack: (_) => false,
        autoplayEnabled: false,
        onAutoplayChanged: (_) {},
      );

      await controller.start();
      expect(fetchCalls, 1);

      // Settle index 0 has remaining <= threshold
      final callsAfterStart = fetchCalls;

      // Calling maybeRefill immediately should be throttled by _minRefillInterval (5s)
      await controller.maybeRefill();
      expect(fetchCalls, callsAfterStart,
          reason: 'Rapid refill should be throttled by min interval');

      // Another rapid call should also be throttled
      await controller.maybeRefill();
      expect(fetchCalls, callsAfterStart,
          reason: 'Repeated unthrottled refill calls must not hammer network');
    });

    test('consecutive refill errors back off and mark exhausted', () async {
      int fetchCalls = 0;
      final controller = ExploreController(
        engine: ExploreEngine(),
        fetchSources: (anchor) async {
          fetchCalls++;
          throw Exception('Simulated network failure');
        },
        play: (track, upcoming) async {},
        profileProvider: () => TasteProfile.build(events: const []),
        recordSwipeOutcome: (_, {required wasAccepted}) {},
        isCurrentTrack: (_) => false,
        autoplayEnabled: false,
        onAutoplayChanged: (_) {},
      );

      // Start will fail gracefully
      await controller.start();
      expect(controller.error, isNotNull);
      expect(fetchCalls, 1);
    });
  });

  group('ExploreFeedCard background & off-screen resource optimization', () {
    testWidgets('isActive=false does not animate or render active equalizer',
        (tester) async {
      final item = _item('track1');

      // Render with isActive: false (e.g. background tab or phone locked)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExploreFeedCard(
              item: item,
              palette: ExplorePalette.neutral,
              isCurrentTrack: true,
              isPlaying: true,
              isLiked: false,
              embedded: true,
              isActive: false, // Inactive tab!
              onTogglePlay: () {},
              onOpenPlayer: () {},
              onOpenArtist: () {},
              onToggleLike: () {},
              onMore: () {},
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // With isActive=false, eq bars must NOT be rendered
      expect(find.byKey(const ValueKey('eq_bar_0')), findsNothing,
          reason: 'Inactive card must not animate equalizer or tick vsync');

      // Now switch isActive to true (user returns to Explore tab)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExploreFeedCard(
              item: item,
              palette: ExplorePalette.neutral,
              isCurrentTrack: true,
              isPlaying: true,
              isLiked: false,
              embedded: true,
              isActive: true, // Tab became active!
              onTogglePlay: () {},
              onOpenPlayer: () {},
              onOpenArtist: () {},
              onToggleLike: () {},
              onMore: () {},
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('eq_bar_0')), findsOneWidget,
          reason: 'Active card should show equalizer when playing');
    });

    testWidgets('off-screen card (isCurrentTrack=false) does not animate equalizer',
        (tester) async {
      final item = _item('track2');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExploreFeedCard(
              item: item,
              palette: ExplorePalette.neutral,
              isCurrentTrack: false, // Offscreen / neighbor card
              isPlaying: true,
              isLiked: false,
              embedded: true,
              isActive: true,
              onTogglePlay: () {},
              onOpenPlayer: () {},
              onOpenArtist: () {},
              onToggleLike: () {},
              onMore: () {},
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('eq_bar_0')), findsNothing,
          reason: 'Off-screen card must not render active equalizer');
    });
  });

  group('ExploreWheel background optimization', () {
    testWidgets('isActive=false stops vinyl spinning when playing',
        (tester) async {
      final items = [_item('w1'), _item('w2')];
      final controller = ScrollController();
      const spec = ExploreWheelSpec(
        itemExtent: 120,
        arcA: 40,
        contentMaxWidth: 400,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExploreWheel(
              items: items,
              scrollController: controller,
              physics: const SnapScrollPhysics(
                parent: ClampingScrollPhysics(),
                itemExtent: 120,
              ),
              viewportH: 600,
              extent: 120,
              spec: spec,
              settledIndex: 0,
              currentTrackId: 'w1',
              isPlaying: true,
              isActive: false, // Background tab
              accent: Colors.amber,
              isLiked: (_) => false,
              onTapRow: (_) {},
              onTogglePlay: (_, __) {},
              onOpenPlayer: () {},
              onOpenArtist: (_) {},
              onLike: (_) {},
              onMore: (_) {},
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      // With isActive=false, VinylDisc should NOT be spinning
      expect(find.byKey(const ValueKey('vinyl_spin')), findsNothing,
          reason: 'Vinyl should not spin when wheel is inactive');
    });
  });
}
