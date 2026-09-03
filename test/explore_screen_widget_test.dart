import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/explore/explore_controller.dart';
import 'package:music_streaming_app/services/explore/explore_engine.dart';
import 'package:music_streaming_app/services/explore/explore_policy.dart';
import 'package:music_streaming_app/services/explore/explore_session.dart';
import 'package:music_streaming_app/services/recommendation/candidate.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/presentation/explore/explore_screen.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/services/recommendation/taste_profile.dart';
import 'package:music_streaming_app/widgets/liquid_play_button.dart';
import 'package:provider/provider.dart';

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

ExploreController _controller({
  List<List<ExploreItem>> batches = const [],
  bool autoplay = true,
}) {
  var call = 0;
  return ExploreController(
    engine: ExploreEngine(),
    fetchSources: (anchor) async {
      final b = batches[call.clamp(0, batches.length - 1)];
      call++;
      return ExploreSources(
          regionalChart: b.map((i) => i.track).toList());
    },
    play: (track, upcoming) async {},
    profileProvider: () => _EmptyProfileHolder.profile,
    recordSwipeOutcome: (a, {required wasAccepted}) {},
    isCurrentTrack: (id) => false,
    onAutoplayChanged: (_) {},
    autoplayEnabled: autoplay,
  );
}

class FakeExploreProvider extends MusicProvider {
  @override
  Track? get currentTrack => null;
  @override
  bool get isPlaying => false;
  @override
  bool get isMiniPlayerVisible => false;
  @override
  bool isSongLiked(String trackId) => false;
  @override
  Future<void> playTrack(Track track,
      {String? playlistId,
      List<Track>? playlistTracks,
      bool setContext = true,
      bool clearQueue = true}) async {}
  @override
  void toggleLike(Track track) {}
  @override
  void addListToQueue(List<Track> tracks) {}
}

// TasteProfile with no events — the cold-start baseline.
class _EmptyProfileHolder {
  static final profile = TasteProfile.build(events: const []);
}

void main() {
  final batch1 = [
    _item('aaa11111111'),
    _item('bbb11111111'),
    _item('ccc11111111'),
  ];

  Widget wrap(ExploreController controller) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MusicProvider>(
            create: (_) => FakeExploreProvider()),
        ChangeNotifierProvider<ExploreController>.value(value: controller),
      ],
      child: const ExploreScreen.forTest(),
    );
  }

  group('ExploreScreen states', () {
    testWidgets('loading spinner before session', (tester) async {
      final controller = _controller(batches: [batch1]);
      // Do not start() — screen shows loading.
      await tester.pumpWidget(MaterialApp(home: wrap(controller)));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders pages with stable keys + reason chip + controls',
        (tester) async {
      final controller = _controller(batches: [batch1]);
      controller.autoplayEnabled = false;
      await controller.start();
      await tester.pumpWidget(MaterialApp(home: wrap(controller)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('explore_page_aaa11111111')),
          findsOneWidget);
      expect(find.text('Song aaa11111111'), findsOneWidget);
      expect(find.text(ExplorePolicy.reasonLabel(
          CandidateReason.regionalTrending)), findsOneWidget);
      expect(find.bySemanticsLabel('Like'), findsOneWidget);
      expect(find.byType(LiquidPlayButton), findsOneWidget);
      expect(find.bySemanticsLabel('Add to queue'), findsOneWidget);
      expect(find.bySemanticsLabel('More options'), findsOneWidget);
    });

    testWidgets('autoplay-off chip visible when disabled', (tester) async {
      final controller = _controller(batches: [batch1], autoplay: false);
      await controller.start();
      await tester.pumpWidget(MaterialApp(home: wrap(controller)));
      await tester.pumpAndSettle();
      expect(find.text('Autoplay off'), findsOneWidget);
    });

    testWidgets('empty state shows nothing-new + retry', (tester) async {
      final controller = _controller(batches: [const []]);
      await controller.start();
      await tester.pumpWidget(MaterialApp(home: wrap(controller)));
      await tester.pumpAndSettle();
      expect(find.text('Nothing new right now'), findsOneWidget);
      expect(find.bySemanticsLabel('Retry'), findsOneWidget);
    });

    testWidgets('trailing loading stub while not exhausted', (tester) async {
      final controller = _controller(batches: [batch1]);
      controller.autoplayEnabled = false;
      await controller.start();
      await tester.pumpWidget(MaterialApp(home: wrap(controller)));
      await tester.pumpAndSettle();
      expect(controller.exhausted, isFalse);
      // itemCount = items + loading stub.
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      expect(find.text('1 · 2 left'), findsOneWidget);
    });
  });
}
