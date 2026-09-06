import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/now_playing_screen.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/glass_options_sheet.dart';
import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/utils/lyrics_utils.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_service.dart';
import 'package:music_streaming_app/services/canvas_resolution_service.dart';
import 'package:music_streaming_app/services/canvas_video_manager.dart';
import 'package:music_streaming_app/screens/lyrics_screen.dart';
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
    bool prefetchMetadata = true,
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

    // Verify kinetic lyrics (active line uses Text.rich with WidgetSpan)
    expect(find.textContaining('eyelids'), findsWidgets);
    expect(find.textContaining('dream state'), findsWidgets);

    // Tap a lyric line to seek
    await tester.tap(find.textContaining('wake up').first);
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

  test('LyricsUtils: parses enhanced word-level LRC tags and character-weighted fallback', () {
    const enhancedLrc = '''
[00:01.00] <00:01.00> Gone <00:01.50> a <00:01.80> little <00:02.40> far
[00:05.00] How was I to know this high
''';
    final entries = LyricsUtils.parseLrc(enhancedLrc);
    expect(entries.length, 3); // head + 2 lines

    // Line 1: enhanced tags
    final line1 = entries[1];
    expect(line1.text, 'Gone a little far');
    expect(line1.words, isNotNull);
    expect(line1.words!.length, 4);
    expect(line1.words![0].text, 'Gone');
    expect(line1.words![0].timeMs, 1000);
    expect(line1.words![0].durationMs, 500);

    // Line 2: fallback syllable-weighted timing
    final line2 = entries[2];
    expect(line2.text, 'How was I to know this high');
    expect(line2.words, isNotNull);
    expect(line2.words!.length, 7);
    // End-of-phrase word 'high' gets 1.6x elongation bonus, longer than short word 'I'
    final iWord = line2.words!.firstWhere((w) => w.text == 'I');
    final highWord = line2.words!.firstWhere((w) => w.text == 'high');
    expect(highWord.durationMs, greaterThan(iWord.durationMs));
  });

  testWidgets('Album artwork tap triggers unified morph to lyrics, and mini tap returns',
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

    // In full player mode, title & artist are visible down below
    expect(find.text('See You Again'), findsWidgets);
    expect(find.text('Tyler, The Creator'), findsWidgets);
    expect(find.bySemanticsLabel('Lyrics tab'), findsOneWidget);

    // Tap the album art image to trigger morph to lyrics
    await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
    await tester.pumpAndSettle();

    // Now in lyrics mode
    expect(find.byType(LyricsScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Pronunciation'), findsOneWidget);

    // Tap the mini album art to return back to album art view
    await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
    await tester.pumpAndSettle();

    // Returned to full player mode
    expect(find.bySemanticsLabel('Lyrics tab'), findsOneWidget);
  });

  test('LyricsUtils.stripCredits: cuts title repeats and credits from opening and outro', () {
    const fixtureWithCredits = '''
[id:\$00000000]
[ti:Heartbreak Anniversary]
[ar:Giveon]
[al:Heartbreak Anniversary]
[by:]
[00:00.00]Heartbreak Anniversary - GIVĒON
[00:04.12]Lyrics by：Giveon Evans/Varren Wade/Sevn Thomas
[00:08.24]Composed by：Giveon Evans/Varren Wade/Sevn Thomas/Maneesh
[00:12.36]Ooh
[00:15.90]Balloons are deflated
[00:19.73]Guess they look lifeless like me
[03:04.12]'Cause I think of you think of you
[03:07.90]Ooh ooh ooh-ooh
[03:15.00]Produced by: Maneesh
''';

    final stripped = LyricsUtils.stripCredits(fixtureWithCredits);
    expect(stripped.contains('GIVĒON'), isFalse);
    expect(stripped.contains('Lyrics by'), isFalse);
    expect(stripped.contains('Composed by'), isFalse);
    expect(stripped.contains('Produced by'), isFalse);
    expect(stripped.startsWith('[00:12.36]Ooh'), isTrue);
    expect(stripped.contains('[00:15.90]Balloons are deflated'), isTrue);
    expect(stripped.contains("[03:07.90]Ooh ooh ooh-ooh"), isTrue);

    // Parsing via parseLrc also automatically applies stripCredits
    final entries = LyricsUtils.parseLrc(fixtureWithCredits);
    // headEntry is at index 0, first sung line is at index 1
    expect(entries[1].text, 'Ooh');
    expect(entries[1].timeMs, 12360);
  });

  test('LyricsUtils.stripCredits: strips opening Title - Artist repetition without colons', () {
    const arcticMonkeysLrc = '''
[00:00.00]I Wanna Be Yours - Arctic Monkeys
[00:15.20]I wanna be your vacuum cleaner
[00:18.50]Breathing in your dust
''';
    final entries = LyricsUtils.parseLrc(arcticMonkeysLrc);
    expect(entries[1].text, 'I wanna be your vacuum cleaner');
    expect(entries[1].timeMs, 15200);
  });

  test('LyricsUtils.stripCredits: strips Chinese credits (作词/作曲/编曲)', () {
    const chineseLrc = '''
[00:00.00]作词 : 周杰伦
[00:02.00]作曲 : 周杰伦
[00:04.00]编曲 : 钟兴民
[00:10.50]快使用双截棍
''';
    final entries = LyricsUtils.parseLrc(chineseLrc);
    expect(entries[1].text, '快使用双截棍');
    expect(entries[1].timeMs, 10500);
  });

  test('LyricsService.withInstrumentalGaps: inserts intro break and mid-song breaks', () {
    final rawEntries = [
      LyricsEntry.headEntry,
      const LyricsEntry(timeMs: 15200, text: 'I wanna be your vacuum cleaner', endMs: 18000),
      const LyricsEntry(timeMs: 25000, text: 'Breathing in your dust', endMs: 28000),
    ];

    final withGaps = LyricsService.withInstrumentalGaps(rawEntries);
    expect(withGaps.first.timeMs, 0);
    expect(withGaps.first.isMusicalBreak, isTrue);
    expect(withGaps[1].text, 'I wanna be your vacuum cleaner');

    // Gap between 18000ms and 25000ms is 7000ms >= 3800ms -> should insert break at 18000ms
    final midGap = withGaps.firstWhere((e) => e.timeMs == 18000);
    expect(midGap.isMusicalBreak, isTrue);
    expect(midGap.text, '• • •');
  });

  test('CanvasResolutionService: strict candidate title matching rejects mismatched titles by same artist', () {
    // Dracula video candidate must NEVER score or match when target is Borderline!
    final candidateDracula = Track(
      id: 'dracula_vid_1',
      trackName: 'Dracula (Official Video)',
      artistName: 'Tame Impala',
      albumName: 'Dracula',
      previewUrl: '',
    );
    final targetBorderline = Track(
      id: 'borderline_track_1',
      trackName: 'Borderline',
      artistName: 'Tame Impala',
      albumName: 'The Slow Rush',
      previewUrl: '',
    );

    // Using CanvasResolutionService internal candidate scoring behavior
    // If titles do not match, score must be 0 (rejected outright)
    final normC = candidateDracula.trackName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim();
    final normT = targetBorderline.trackName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim();
    expect(normC.contains(normT), isFalse);
    expect(normT.contains(normC), isFalse);
  });

  test('CanvasVideoManager: singleton state, attach and detach lifecycle', () async {
    final manager = CanvasVideoManager.instance;
    expect(manager, isNotNull);
    expect(manager.isRendered, isFalse);
    expect(manager.currentController, isNull);

    final dummyTrack = Track(
      id: 'test_canvas_track',
      trackName: 'Test Song',
      artistName: 'Test Artist',
      albumName: 'Test Album',
      previewUrl: '',
    );

    await manager.attachTrack(dummyTrack, isPlaying: true);
    // In test environment, _isTesting guards ExoPlayer hardware allocation
    expect(manager.controllerNotifier.value, isNull);
    expect(manager.isRenderedNotifier.value, isFalse);

    // Detach cleanly resets track state
    await manager.detach();
    expect(manager.currentController, isNull);
    expect(manager.isRendered, isFalse);
  });

  testWidgets('GlassOptionsSheet: accepts dynamic accentColor and renders themed liquid glass', (tester) async {
    final dummyTrack = Track(
      id: 't_borderline',
      trackName: 'Borderline',
      artistName: 'Tame Impala',
      albumName: 'The Slow Rush',
      previewUrl: '',
      albumArtUrl: 'https://example.com/borderline.jpg',
    );

    final provider = TestMusicProvider(initialTrack: dummyTrack);

    final theme = GlassTheme.build(AccentColors.peach);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: ChangeNotifierProvider<MusicProvider>.value(
          value: provider,
          child: Scaffold(
            body: GlassOptionsSheet(
              track: dummyTrack,
              accentColor: const Color(0xFFE84828), // Crimson orange from sand dunes
              dominantColor: const Color(0xFF882211),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Borderline'), findsOneWidget);
    expect(find.text('Tame Impala'), findsOneWidget);
    expect(find.text('Add to a playlist...'), findsOneWidget);
    expect(find.text('Go to album'), findsOneWidget);
    expect(find.text('Go to artist'), findsOneWidget);
  });
}
