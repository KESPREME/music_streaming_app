import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/now_playing_screen.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/queue_screen.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/glass_surface.dart';
import 'package:music_streaming_app/widgets/mini_player.dart';

class FakeMusicProvider extends MusicProvider {
  FakeMusicProvider({this.track, bool playing = false}) : _playing = playing;

  Track? track;
  bool _playing;
  int resumeCalls = 0;
  int pauseCalls = 0;
  final List<Track> queueTracks = [];
  Track? lastPlayed;
  bool? lastClearQueue;
  bool failQueuePlay = false;

  @override
  Track? get currentTrack => track;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isMiniPlayerVisible => true;

  @override
  Duration get duration => const Duration(minutes: 3);

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Future<void> resumeTrack() async {
    resumeCalls++;
    _playing = true;
  }

  @override
  Future<void> pauseTrack() async {
    pauseCalls++;
    _playing = false;
  }

  @override
  Future<void> skipToPrevious() async {}

  @override
  Future<void> skipToNext() async {}

  @override
  List<Track> get queue => List.unmodifiable(queueTracks);

  @override
  Future<void> playTrack(
    Track track, {
    String? playlistId,
    List<Track>? playlistTracks,
    bool setContext = true,
    bool clearQueue = true,
  }) async {
    if (failQueuePlay) throw StateError('Queue playback failed');
    lastPlayed = track;
    lastClearQueue = clearQueue;
  }

  @override
  void removeFromQueue(dynamic item) => queueTracks.remove(item);

  @override
  void reorderQueueItem(int oldIndex, int newIndex) {}

  @override
  void clearQueue() => queueTracks.clear();
}

Track buildTrack() => Track(
      id: 'track-1',
      trackName: 'Glass track',
      artistName: 'Glass artist',
      albumName: 'Glass album',
      previewUrl: '',
    );

Future<void> pumpMiniPlayer(
  WidgetTester tester,
  FakeMusicProvider provider,
) async {
  final theme = GlassTheme.build(AccentColors.peach).copyWith(
    splashFactory: NoSplash.splashFactory,
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<MusicProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: theme,
        home: const Scaffold(body: MiniPlayer()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('renders no player content without a track', (tester) async {
    final provider = FakeMusicProvider();

    await pumpMiniPlayer(tester, provider);

    expect(find.byType(GlassSurface), findsNothing);
  });

  testWidgets('renders track title and artist', (tester) async {
    final provider = FakeMusicProvider(track: buildTrack());

    await pumpMiniPlayer(tester, provider);

    expect(find.text('Glass track'), findsOneWidget);
    expect(find.text('Glass artist'), findsOneWidget);
  });

  testWidgets('play control calls resumeTrack', (tester) async {
    final provider = FakeMusicProvider(track: buildTrack());

    await pumpMiniPlayer(tester, provider);

    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();

    expect(provider.resumeCalls, 1);
  });

  testWidgets('renders Now Playing content and labeled player controls',
      (tester) async {
    final provider = FakeMusicProvider(track: buildTrack());
    final theme = GlassTheme.build(AccentColors.peach).copyWith(
      splashFactory: NoSplash.splashFactory,
    );
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: theme,
          home: NowPlayingScreen(track: buildTrack()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Glass track'), findsOneWidget);
    expect(find.text('Glass artist'), findsOneWidget);
    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    expect(find.bySemanticsLabel('Previous track'), findsOneWidget);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);
    expect(find.bySemanticsLabel('Shuffle'), findsOneWidget);
    expect(find.bySemanticsLabel('Repeat'), findsOneWidget);
  });

  testWidgets('queue row plays track without clearing queue', (tester) async {
    final provider = FakeMusicProvider();
    final track = buildTrack();
    provider.queueTracks.add(track);
    final theme = GlassTheme.build(AccentColors.peach).copyWith(
      splashFactory: NoSplash.splashFactory,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: theme,
          home: const QueueScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Glass track'));
    await tester.pump();

    expect(provider.lastPlayed, same(track));
    expect(provider.lastClearQueue, isFalse);
  });

  testWidgets('queue row shows failure snackbar and keeps track',
      (tester) async {
    final provider = FakeMusicProvider()..failQueuePlay = true;
    final track = buildTrack();
    provider.queueTracks.add(track);
    final theme = GlassTheme.build(AccentColors.peach).copyWith(
      splashFactory: NoSplash.splashFactory,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: theme,
          home: const QueueScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Glass track'));
    await tester.pump();

    expect(provider.queue, hasLength(1));
    expect(provider.queue.single, same(track));
    expect(find.text('Could not play Glass track'), findsOneWidget);
  });

  test('queue-row validation failure rethrows without consuming queue',
      () async {
    final provider = MusicProvider();
    final queuedTrack = buildTrack();
    final invalidTrack = queuedTrack.copyWith(id: 'PL_test');
    provider.addToQueue(queuedTrack);

    try {
      await expectLater(
        provider.playTrack(
          invalidTrack,
          setContext: false,
          clearQueue: false,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        provider.errorMessage,
        'Cannot play Glass track - it is a playlist/album, not a song.',
      );
      expect(provider.queue, hasLength(1));
      expect(provider.queue.single, same(queuedTrack));
    } finally {
      provider.dispose();
    }
  });
}
