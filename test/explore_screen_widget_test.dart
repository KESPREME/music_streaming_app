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

ExploreItem _item(String id, {double confidence = 0}) => ExploreItem(
      track: _t(id),
      reason: CandidateReason.regionalTrending,
      score: 1,
      source: 'chart_regional',
      confidence: confidence,
    );

ExploreController _controller({
  List<List<ExploreItem>> batches = const [],
  bool autoplay = true,
  ExploreSession? existingSession,
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
    existingSession: existingSession,
  );
}

class FakeExploreProvider extends MusicProvider {
  Track? fakeCurrent;
  bool fakePlaying = false;
  int pauseCalls = 0;
  int resumeCalls = 0;
  final List<Track> playedTracks = [];

  @override
  Track? get currentTrack => fakeCurrent;
  @override
  bool get isPlaying => fakePlaying;
  @override
  bool get isMiniPlayerVisible => false;
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();
  @override
  bool isSongLiked(String trackId) => false;
  @override
  Future<void> playTrack(Track track,
      {String? playlistId,
      List<Track>? playlistTracks,
      bool setContext = true,
      bool clearQueue = true}) async {
    playedTracks.add(track);
  }

  @override
  Future<void> pauseTrack() async {
    pauseCalls++;
    fakePlaying = false;
  }

  @override
  Future<void> resumeTrack() async {
    resumeCalls++;
    fakePlaying = true;
  }

  @override
  void toggleLike(Track track) {}
  @override
  void addListToQueue(List<Track> tracks) {}
  @override
  Future<void> navigateToArtist(String artistName) async {}
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

  Widget wrap(ExploreController controller, FakeExploreProvider provider) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MusicProvider>(create: (_) => provider),
        ChangeNotifierProvider<ExploreController>.value(value: controller),
      ],
      child: const ExploreScreen.forTest(),
    );
  }

  group('ExploreScreen deck', () {
    testWidgets('skeleton before session (no spinner)', (tester) async {
      final controller = _controller(batches: [batch1]);
      await tester.pumpWidget(
          MaterialApp(home: wrap(controller, FakeExploreProvider())));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.music_note_rounded), findsWidgets);
    });

    testWidgets('deck page: stable key, title, slim rail, no giant panel',
        (tester) async {
      final controller = _controller(batches: [batch1]);
      controller.autoplayEnabled = false;
      await controller.start();
      await tester.pumpWidget(
          MaterialApp(home: wrap(controller, FakeExploreProvider())));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('explore_page_aaa11111111')),
          findsOneWidget);
      expect(find.text('Song aaa11111111'), findsOneWidget);
      // Low confidence (0.0) → reason line hidden (album-only line stays).
      expect(find.textContaining(ExplorePolicy.reasonLabel(
          CandidateReason.regionalTrending)), findsNothing);
      expect(find.textContaining('Album aaa11111111'), findsOneWidget);
      expect(find.bySemanticsLabel('Like'), findsOneWidget);
      expect(find.byType(LiquidPlayButton), findsOneWidget);
      expect(find.bySemanticsLabel('Add to queue'), findsOneWidget);
      expect(find.bySemanticsLabel('More options'), findsOneWidget);
      expect(find.text('Not interested'), findsOneWidget);
    });

    testWidgets('high-confidence item shows reason context', (tester) async {
      // Engine recomputes confidence — inject the ranked item directly.
      final session =
          ExploreSession(sessionId: 7, startedAt: DateTime.now());
      session.appendBatch(
          [_item('aaa11111111', confidence: 0.8), _item('bbb11111111')]);
      session.advanceTo(0);
      final controller =
          _controller(autoplay: false, existingSession: session);
      await controller.start(); // restores, no refetch
      await tester.pumpWidget(
          MaterialApp(home: wrap(controller, FakeExploreProvider())));
      await tester.pumpAndSettle();
      expect(find.textContaining(ExplorePolicy.reasonLabel(
          CandidateReason.regionalTrending)), findsOneWidget);
    });

    testWidgets('next peek visible on first page, prev peek hidden',
        (tester) async {
      final controller = _controller(batches: [batch1]);
      controller.autoplayEnabled = false;
      await controller.start();
      await tester.pumpWidget(
          MaterialApp(home: wrap(controller, FakeExploreProvider())));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Play next'), findsOneWidget);
      expect(find.text('Song bbb11111111'), findsWidgets);
    });

    testWidgets('header: back + title + toggle, thin progress, no counter',
        (tester) async {
      final controller = _controller(batches: [batch1], autoplay: false);
      await controller.start();
      await tester.pumpWidget(
          MaterialApp(home: wrap(controller, FakeExploreProvider())));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.bySemanticsLabel('Toggle autoplay'), findsOneWidget);
      expect(find.byIcon(Icons.play_disabled_rounded), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('left'), findsNothing);
    });

    testWidgets('artwork tap plays non-current track', (tester) async {
      final controller = _controller(batches: [batch1]);
      controller.autoplayEnabled = false;
      await controller.start();
      final provider = FakeExploreProvider();
      await tester.pumpWidget(MaterialApp(home: wrap(controller, provider)));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(
          'Toggle playback for Song aaa11111111'));
      await tester.pumpAndSettle();
      expect(provider.playedTracks.map((t) => t.id), ['aaa11111111']);
    });

    testWidgets('not-interested advances the session', (tester) async {
      final controller = _controller(batches: [batch1]);
      controller.autoplayEnabled = false;
      await controller.start();
      await tester.pumpWidget(
          MaterialApp(home: wrap(controller, FakeExploreProvider())));
      await tester.pumpAndSettle();
      expect(controller.session!.currentIndex, 0);
      await tester.tap(find.text('Not interested'));
      await tester.pumpAndSettle();
      expect(controller.session!.currentIndex, 1);
    });

    testWidgets('empty state shows nothing-new + retry', (tester) async {
      final controller = _controller(batches: [const []]);
      await controller.start();
      await tester.pumpWidget(
          MaterialApp(home: wrap(controller, FakeExploreProvider())));
      await tester.pumpAndSettle();
      expect(find.text('Nothing new right now'), findsOneWidget);
      expect(find.bySemanticsLabel('Retry'), findsOneWidget);
    });
  });
}
