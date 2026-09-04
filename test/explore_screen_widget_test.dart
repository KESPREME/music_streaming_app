import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/explore/explore_controller.dart';
import 'package:music_streaming_app/services/explore/explore_engine.dart';
import 'package:music_streaming_app/services/recommendation/candidate.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/presentation/explore/explore_screen.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/services/recommendation/taste_profile.dart';
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
  List<Track>? played,
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
    play: (track, upcoming) async {
      played?.add(track);
    },
    profileProvider: () => _EmptyProfileHolder.profile,
    recordSwipeOutcome: (a, {required wasAccepted}) {},
    isCurrentTrack: (id) => false,
    onAutoplayChanged: (_) {},
    autoplayEnabled: autoplay,
  );
}

class FakeExploreProvider extends MusicProvider {
  Track? fakeCurrent;
  bool fakePlaying = false;
  int pauseCalls = 0;
  int resumeCalls = 0;
  final List<Track> playedTracks = [];
  bool expandCalls = false;

  @override
  Track? get currentTrack => fakeCurrent;
  @override
  bool get isPlaying => fakePlaying;
  @override
  bool get isMiniPlayerVisible => false;
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
  @override
  void setPlayerExpanded(bool expanded) {
    expandCalls = expanded;
  }
}

// TasteProfile with no events — the cold-start baseline.
class _EmptyProfileHolder {
  static final profile = TasteProfile.build(events: const []);
}

void main() {
  final batch5 = [
    _item('aaa11111111'),
    _item('bbb11111111'),
    _item('ccc11111111'),
    _item('ddd11111111'),
    _item('eee11111111'),
  ];

  Widget wrap(ExploreController controller, FakeExploreProvider provider) {
    // Providers ABOVE MaterialApp (production shape) so modal routes
    // (options sheet) resolve them too.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MusicProvider>(create: (_) => provider),
        ChangeNotifierProvider<ExploreController>.value(value: controller),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: const MaterialApp(home: ExploreScreen.forTest()),
    );
  }

  group('ExploreWheel rotary', () {
    testWidgets('rows render with stable keys', (tester) async {
      final controller = _controller(batches: [batch5], autoplay: false);
      await controller.start();
      await tester.pumpWidget(
          wrap(controller, FakeExploreProvider()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('explore_row_aaa11111111')),
          findsOneWidget);
      expect(find.text('Song aaa11111111'), findsWidgets);
    });

    testWidgets('drag settles + debounced autoplay plays snapped track',
        (tester) async {
      final played = <Track>[];
      final controller =
          _controller(batches: [batch5], autoplay: true, played: played);
      await controller.start();
      await tester.pumpWidget(
          wrap(controller, FakeExploreProvider()));
      await tester.pumpAndSettle();
      expect(played.map((t) => t.id), ['aaa11111111']);
      played.clear();

      await tester.drag(find.byType(ListView), const Offset(0, -260));
      // pumpAndSettle flushes the spring; the snap debounce timer needs
      // an explicit clock advance (timers schedule no frames).
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(played, isNotEmpty);
      expect(controller.session!.currentIndex, greaterThan(0));
      expect(played.last.id, controller.session!.active!.track.id);
    });

    testWidgets('neighbor tap jumps to that row', (tester) async {
      final controller = _controller(batches: [batch5], autoplay: false);
      await controller.start();
      await tester.pumpWidget(
          wrap(controller, FakeExploreProvider()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('explore_row_bbb11111111')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(controller.session!.currentIndex, 1);
    });

    testWidgets('playing shows equalizer, paused shows play', (tester) async {
      final controller = _controller(batches: [batch5], autoplay: false);
      await controller.start();
      final provider = FakeExploreProvider()
        ..fakeCurrent = _t('aaa11111111')
        ..fakePlaying = true;
      await tester.pumpWidget(wrap(controller, provider));
      // Bounded pumps: the eq loop + vinyl spin schedule frames forever,
      // so pumpAndSettle would never return while playing.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('eq_bar_0')), findsOneWidget);

      provider.fakePlaying = false;
      provider.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('eq_bar_0')), findsNothing);
      expect(find.bySemanticsLabel('Play'), findsOneWidget);
    });

    testWidgets('vinyl spins only when active+current+playing',
        (tester) async {
      final controller = _controller(batches: [batch5], autoplay: false);
      await controller.start();
      final provider = FakeExploreProvider()
        ..fakeCurrent = _t('aaa11111111')
        ..fakePlaying = true;
      await tester.pumpWidget(wrap(controller, provider));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('vinyl_spin')), findsOneWidget);

      provider.fakePlaying = false;
      provider.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vinyl_spin')), findsNothing);
    });

    testWidgets('title tap expands fullscreen panel', (tester) async {
      final controller = _controller(batches: [batch5], autoplay: false);
      await controller.start();
      final provider = FakeExploreProvider();
      await tester.pumpWidget(wrap(controller, provider));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song aaa11111111'));
      await tester.pumpAndSettle();
      expect(provider.expandCalls, isTrue);
    });
  });

  group('Explore liquid pill', () {
    testWidgets('pill key, title, heart', (tester) async {
      final controller = _controller(batches: [batch5], autoplay: false);
      await controller.start();
      await tester.pumpWidget(
          wrap(controller, FakeExploreProvider()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('explore_pill_aaa11111111')),
          findsOneWidget);
      expect(find.text('Song aaa11111111'), findsWidgets);
      expect(find.bySemanticsLabel('Like'), findsOneWidget);
    });

    testWidgets('long-press pill → sheet Not-interested advances',
        (tester) async {
      final controller = _controller(batches: [batch5], autoplay: false);
      await controller.start();
      await tester.pumpWidget(
          wrap(controller, FakeExploreProvider()));
      await tester.pumpAndSettle();
      expect(controller.session!.currentIndex, 0);
      await tester.longPress(
          find.byKey(const ValueKey('explore_pill_aaa11111111')));
      await tester.pumpAndSettle();
      expect(find.text('Go to Artist'), findsOneWidget);
      expect(find.text('Not interested'), findsOneWidget);
      await tester.tap(find.text('Not interested'));
      await tester.pumpAndSettle();
      expect(controller.session!.currentIndex, 1);
    });

    testWidgets('header bold title, no autoplay toggle', (tester) async {
      final controller = _controller(batches: [batch5], autoplay: false);
      await controller.start();
      await tester.pumpWidget(
          wrap(controller, FakeExploreProvider()));
      await tester.pumpAndSettle();
      expect(find.text('Explore'), findsOneWidget);
      expect(find.bySemanticsLabel('Toggle autoplay'), findsNothing);
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
    });
  });

  group('Explore tab bar', () {
    testWidgets('three tabs, Explore active', (tester) async {
      final controller = _controller(batches: [batch5], autoplay: false);
      await controller.start();
      await tester.pumpWidget(
          wrap(controller, FakeExploreProvider()));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Home tab'), findsOneWidget);
      expect(find.bySemanticsLabel('Explore tab'), findsOneWidget);
      expect(find.bySemanticsLabel('Library tab'), findsOneWidget);
    });

    testWidgets('Library tab requests tab + pops route', (tester) async {
      final controller = _controller(batches: [batch5], autoplay: false);
      await controller.start();
      final provider = FakeExploreProvider();
      await tester.pumpWidget(wrap(controller, provider));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Library tab'));
      await tester.pumpAndSettle();
      expect(provider.requestedTab, 2);
      expect(find.byType(ExploreScreen), findsNothing);
    });

    testWidgets('provider tab request/clear', (tester) async {
      final provider = FakeExploreProvider();
      expect(provider.requestedTab, isNull);
      provider.requestTab(0);
      expect(provider.requestedTab, 0);
      provider.requestTab(0); // idempotent, no crash
      provider.clearRequestedTab();
      expect(provider.requestedTab, isNull);
      provider.clearRequestedTab(); // idempotent, no crash
    });
  });

  group('Explore states', () {
    testWidgets('skeleton before session, empty state when exhausted',
        (tester) async {
      final controller = _controller(batches: [batch5]);
      await tester.pumpWidget(
          wrap(controller, FakeExploreProvider()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.music_note_rounded), findsWidgets);

      final empty = _controller(batches: [const []]);
      await empty.start();
      await tester.pumpWidget(wrap(empty, FakeExploreProvider()));
      await tester.pumpAndSettle();
      expect(find.text('Nothing new right now'), findsOneWidget);
    });
  });
}



