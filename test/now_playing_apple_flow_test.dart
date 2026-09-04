import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/now_playing_screen.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/glass_options_sheet.dart';
import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/widgets/apple_player_icons.dart';

class TestMusicProvider extends MusicProvider {
  TestMusicProvider({this.initialTrack, bool playing = false}) : _playing = playing;

  Track? initialTrack;
  bool _playing;
  double _testVolume = 0.8;
  bool _testAutoplay = true;
  bool _testCanvas = false;
  RepeatMode _testRepeatMode = RepeatMode.off;
  bool _testShuffle = false;
  final List<Track> _testQueue = [];
  Track? _lastPlayedTrack;
  Track? get lastPlayedTrack => _lastPlayedTrack;
  Duration _testPosition = const Duration(seconds: 15);
  final Duration _testDuration = const Duration(minutes: 3);

  @override
  Track? get currentTrack => initialTrack;

  @override
  bool get isPlaying => _playing;

  @override
  Duration get duration => _testDuration;

  @override
  Duration get position => _testPosition;

  @override
  double get volume => _testVolume;

  @override
  Future<void> setVolume(double value) async {
    _testVolume = value;
    notifyListeners();
  }

  @override
  bool get autoplayEnabled => _testAutoplay;

  @override
  void toggleAutoplay() {
    _testAutoplay = !_testAutoplay;
    notifyListeners();
  }

  @override
  bool get isCanvasActive => _testCanvas;

  @override
  void toggleCanvas() {
    _testCanvas = !_testCanvas;
    notifyListeners();
  }

  @override
  RepeatMode get repeatMode => _testRepeatMode;

  @override
  void cycleRepeatMode() {
    _testRepeatMode = _testRepeatMode == RepeatMode.off
        ? RepeatMode.all
        : (_testRepeatMode == RepeatMode.all ? RepeatMode.one : RepeatMode.off);
    notifyListeners();
  }

  @override
  void setRepeatMode(RepeatMode mode) {
    _testRepeatMode = mode;
    notifyListeners();
  }

  @override
  bool get shuffleEnabled => _testShuffle;

  @override
  void toggleShuffle() {
    _testShuffle = !_testShuffle;
    notifyListeners();
  }

  @override
  List<Track> get queue => List.unmodifiable(_testQueue);

  @override
  bool get canClearQueue => _testQueue.isNotEmpty;

  @override
  void clearQueue() {
    _testQueue.clear();
    notifyListeners();
  }

  @override
  Future<void> playTrack(
    Track track, {
    String? playlistId,
    List<Track>? playlistTracks,
    bool setContext = true,
    bool clearQueue = true,
  }) async {
    _lastPlayedTrack = track;
    initialTrack = track;
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> resumeTrack() async {
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> pauseTrack() async {
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> seekTo(Duration position) async {
    _testPosition = position;
    notifyListeners();
  }

  @override
  List<LyricsEntry>? get currentLyrics => const [
        LyricsEntry(timeMs: 0, text: 'You live in my dream state'),
        LyricsEntry(timeMs: 15000, text: 'You exist behind my eyelids, my eyelids'),
        LyricsEntry(timeMs: 30000, text: 'Now I do not wanna wake up'),
      ];

  @override
  bool get hasSyncedLyrics => true;
}

Track testTrack() => Track(
      id: 'track_123',
      trackName: 'See You Again',
      artistName: 'Tyler, The Creator',
      albumName: 'Flower Boy',
      previewUrl: 'https://example.com/audio.mp3',
    );

void main() {
  testWidgets('renders Apple Music 3-page Now Playing layout with bottom tab bar',
      (tester) async {
    final provider = TestMusicProvider(initialTrack: testTrack(), playing: true);
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
          home: NowPlayingScreen(track: testTrack()),
        ),
      ),
    );
    await tester.pump();

    // Verify main player content
    expect(find.text('See You Again'), findsWidgets);
    expect(find.text('Tyler, The Creator'), findsWidgets);
    expect(find.bySemanticsLabel('Play'), findsNothing); // Playing, so Pause is shown
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.bySemanticsLabel('Previous track'), findsOneWidget);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);
    expect(find.bySemanticsLabel('Favorite'), findsOneWidget);
    expect(find.bySemanticsLabel('Options'), findsOneWidget);

    // Verify custom Apple icons and bottom tab bar semantics
    expect(find.byType(AppleLyricsIcon), findsOneWidget);
    expect(find.byType(AppleCanvasIcon), findsOneWidget);
    expect(find.byIcon(Icons.format_list_bulleted_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Lyrics tab'), findsOneWidget);
    expect(find.bySemanticsLabel('Canvas tab'), findsOneWidget);
    expect(find.bySemanticsLabel('Queue tab'), findsOneWidget);

    // Tap Canvas icon while on page 1 toggles visualizer canvas
    await tester.tap(find.bySemanticsLabel('Canvas tab'));
    await tester.pump();
    expect(provider.isCanvasActive, isTrue);
  });

  testWidgets('switches to Lyrics tab and renders kinetic lyrics and mini player',
      (tester) async {
    final provider = TestMusicProvider(initialTrack: testTrack(), playing: true);
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
          home: NowPlayingScreen(track: testTrack()),
        ),
      ),
    );
    await tester.pump();

    // Tap Lyrics bottom tab
    await tester.tap(find.bySemanticsLabel('Lyrics tab'));
    await tester.pumpAndSettle();

    // Verify top mini track header in Lyrics page
    expect(find.bySemanticsLabel('Pronunciation'), findsOneWidget);
    expect(find.text('aあ'), findsOneWidget);

    // Verify kinetic lyrics
    expect(find.text('You exist behind my eyelids, my eyelids'), findsOneWidget);
    expect(find.text('You live in my dream state'), findsOneWidget);

    // Tap a lyric line to seek
    await tester.tap(find.text('Now I do not wanna wake up'));
    await tester.pump();
    expect(provider.position.inMilliseconds, 30000);
  });

  testWidgets('switches to Queue tab and displays pill buttons and Playing Next',
      (tester) async {
    final provider = TestMusicProvider(initialTrack: testTrack(), playing: true);
    final upcomingTrack = Track(
      id: 'track_456',
      trackName: 'Moonlight',
      artistName: 'Kali Uchis',
      albumName: 'Red Moon in Venus',
      previewUrl: '',
    );
    provider._testQueue.add(upcomingTrack);

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
          home: NowPlayingScreen(track: testTrack()),
        ),
      ),
    );
    await tester.pump();

    // Tap Queue bottom tab
    await tester.tap(find.bySemanticsLabel('Queue tab'));
    await tester.pumpAndSettle();

    // Verify Queue view elements
    expect(find.text('Playing Next'), findsOneWidget);
    expect(find.text('From Muzo'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Moonlight'), findsOneWidget);

    // Verify pill buttons
    expect(find.bySemanticsLabel('Autoplay'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Autoplay'));
    await tester.pump();
    expect(provider.autoplayEnabled, isFalse);
  });

  testWidgets('options sheet shows Apple / Muzo options matching Image 3',
      (tester) async {
    final provider = TestMusicProvider(initialTrack: testTrack(), playing: true);
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
          home: Scaffold(
            body: GlassOptionsSheet(track: testTrack()),
          ),
        ),
      ),
    );
    await tester.pump();

    // Check actions from Image 3
    expect(find.text('Add to a playlist...'), findsOneWidget);
    expect(find.text('Muzo Code'), findsOneWidget);
    expect(find.text('Go to artist'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Song Info'), findsOneWidget);
    expect(find.text('Force Canvas'), findsOneWidget);
    expect(find.text('Sleep Timer'), findsOneWidget);
  });
}
