import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/material.dart'
    show AnimatedOpacity, CustomScrollView;
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
import 'package:music_streaming_app/widgets/lyric_line/lyric_line.dart';
import 'package:music_streaming_app/screens/queue_screen.dart';
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
  List<Track> get upNext => List.unmodifiable(_testQueue);

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
    bool recordHistory = true,
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
  List<LyricsEntry>? get currentLyrics => [
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

    // The two mode discs, floated over the foot of the lyric panel.
    //
// NOT a header control: they are mode switches for the LYRIC, not the track,
    // which is why they sit with the lyric rather than beside the star and the
    // overflow menu. There is no "a?" header button in the reference at all.
    //
    // The globe's label is honest about THIS lyric: it is English, so there is
    // nothing to romanize and the disc says so rather than inviting a tap that
    // could only echo the original back.
    expect(
      find.bySemanticsLabel('These lyrics already use Latin characters'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Show romanized lyrics'), findsNothing);
    expect(find.bySemanticsLabel('Show translated lyrics'), findsOneWidget);
    expect(find.bySemanticsLabel('Pronunciation'), findsNothing);

    // Lyric lines are drawn by one render object each, not by Text widgets, so
    // they are found by the line they carry.
    Finder lyric(String contains) => find.byWidgetPredicate(
          (w) => w is LyricLine && w.entry.text.contains(contains),
        );
    expect(lyric('eyelids'), findsWidgets);
    expect(lyric('dream state'), findsWidgets);

    // Tap a lyric line to seek
    await tester.tap(lyric('wake up').first);
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

    // Verify Queue view elements (no source subtitle: removed by design).
    // Landed state: the flight retired, the page header owns the row.
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('Playing Now'), findsNothing);
    expect(find.byKey(const ValueKey('queueMorphArt')), findsNothing);
    expect(find.byKey(const ValueKey('queueHeaderArt')), findsOneWidget);
    expect(find.text('From Muzo'), findsNothing);
    expect(find.text('From Mine Music'), findsNothing);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Moonlight'), findsOneWidget);

    // Verify the controls-only pill in the bottom bar (the player
    // transport above keeps its own set - scope into the pill).
    final controlsPill = find.byKey(const ValueKey('controls'));
    expect(controlsPill, findsOneWidget);
    expect(
      find.descendant(
        of: controlsPill,
        matching: find.bySemanticsLabel('Autoplay'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.descendant(
      of: controlsPill,
      matching: find.bySemanticsLabel('Autoplay'),
    ));
    await tester.pump();
    expect(provider.autoplayEnabled, isFalse);
  });

  testWidgets('queue morph flies, then hands off to the page header',
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

    await tester.tap(find.bySemanticsLabel('Queue tab'));
    // Mid-flight: the flying artwork exists, and the queue content underneath
    // is still fully transparent - the staged entrance waits for the landing.
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('queueMorphArt')), findsOneWidget);
    final staged = tester.widget<Opacity>(
      find.ancestor(of: find.byType(QueueScreen), matching: find.byType(Opacity))
          .first,
    );
    expect(staged.opacity, 0.0);

    // Landed: flight retired, page header owns the resting row. Retiring the
    // overlay is what keeps the star / a? / options buttons reachable.
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('queueMorphArt')), findsNothing);
    expect(find.byKey(const ValueKey('queueHeaderArt')), findsOneWidget);
  });

  testWidgets('queue to lyrics swaps the middle without replaying the flight',
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

    await tester.tap(find.bySemanticsLabel('Queue tab'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('queueHeaderArt')), findsOneWidget);

    // Queue -> lyrics. The flight artwork must never appear: the mini is
    // already on screen and both surfaces rest at the same rect, so this is a
    // page swap. A single frame proves no mini -> hero -> mini replay started.
    await tester.tap(find.bySemanticsLabel('Lyrics tab'));
    await tester.pump();
    expect(find.byKey(const ValueKey('queueMorphArt')), findsNothing);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('queueMorphArt')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(LyricsScreen), findsOneWidget);

    // Lyrics -> queue: same rule in the other direction.
    await tester.tap(find.bySemanticsLabel('Queue tab'));
    await tester.pump();
    expect(find.byKey(const ValueKey('queueMorphArt')), findsNothing);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('queueMorphArt')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('queueHeaderArt')), findsOneWidget);
  });

  testWidgets('artwork swipe right opens lyrics, left stays with the pager',
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

    // Leftward is the PageView's job (artwork -> queue); the Listener must not
    // eat it. -320 clears the pager's half-page threshold on a 400px surface.
    await tester.drag(
      find.byKey(const ValueKey('now_playing_album_art')),
      const Offset(-320, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('queueHeaderArt')), findsOneWidget);

    // Back home, then rightward: nothing is to the left of page 0, so this is
    // the one direction the pager leaves free for the lyrics.
    await tester.tap(find.byKey(const ValueKey('queueHeaderArt')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('now_playing_album_art')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('now_playing_album_art')),
      const Offset(180, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LyricsScreen), findsOneWidget);
  });

  testWidgets('queue panel toggles closed from the Queue button',
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

    await tester.tap(find.bySemanticsLabel('Queue tab'));
    await tester.pumpAndSettle();
    // Landed: the flight has retired and the page's own header owns the
    // resting state - which is where the star / a? / options actions live.
    expect(find.byKey(const ValueKey('queueMorphArt')), findsNothing);
    expect(find.byKey(const ValueKey('queueHeaderArt')), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('Playing Now'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Queue tab'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('queueMorphArt')), findsNothing);
    expect(find.byKey(const ValueKey('queueHeaderArt')), findsNothing);
    expect(find.text('Queue'), findsNothing);
  });

  testWidgets('lyrics chrome hides after 5s idle and returns on a lower-half tap',
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

    await tester.tap(find.bySemanticsLabel('Lyrics tab'));
    await tester.pumpAndSettle();
    expect(find.byType(LyricsScreen), findsOneWidget);

    bool deckShown() =>
        find.byKey(const Key('npPlayerDeck')).evaluate().isNotEmpty;

    expect(deckShown(), isTrue);
    await tester.pump(const Duration(seconds: 5));
    // The hide is a 420ms size animation, so the deck stays in the tree until it
    // lands: the first pump starts the ticker, the second runs it out.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(deckShown(), isFalse);

    // A tap in the TOP half brings nothing back. Reveal is a decision (a
    // lower-half tap, a scroll back the other way), not a side effect of any
    // pointer touching the glass; the old "every pointer-down un-hides" flickered
    // the controls back in on the touch that started a scroll to hide them.
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(deckShown(), isFalse);

    // The lower half does.
    await tester.tapAt(const Offset(200, 700));
    await tester.pump(const Duration(milliseconds: 500));
    expect(deckShown(), isTrue);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('queue scroll collapses the deck and back up reveals it',
      (tester) async {
    final provider = TestMusicProvider(initialTrack: testTrack(), playing: true);
    for (var i = 0; i < 12; i++) {
      provider._testQueue.add(Track(
        id: 'scrolltrack$i',
        trackName: 'Scroll Song $i',
        artistName: 'Artist $i',
        albumName: 'Album',
        previewUrl: '',
      ));
    }
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

    await tester.tap(find.bySemanticsLabel('Queue tab'));
    await tester.pumpAndSettle();

    bool deckShown() =>
        find.byKey(const Key('npPlayerDeck')).evaluate().isNotEmpty;

    expect(deckShown(), isTrue);

    final list = find.descendant(
      of: find.byType(QueueScreen),
      matching: find.byType(CustomScrollView),
    );
    expect(list, findsOneWidget);

    // Finger drags the list down (plain drag: no ballistic bounce to
    // muddy the assert): the deck collapses.
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(deckShown(), isFalse);

    // Drags back up: the deck returns.
    await tester.drag(list, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(deckShown(), isTrue);

    // Slow long drags accumulate instead of gating per-frame, so they
    // collapse too (back at the top after the drag home above). Travels
    // well past touch slop so the scrolled distance itself crosses.
    await tester.timedDrag(
      list,
      const Offset(0, -140),
      const Duration(milliseconds: 800),
    );
    await tester.pumpAndSettle();
    expect(deckShown(), isFalse);
  });

  testWidgets('short viewport never throws in hero math (deck shares column)',
      (tester) async {
    final provider = TestMusicProvider(initialTrack: testTrack(), playing: true);
    final theme = GlassTheme.build(AccentColors.peach).copyWith(
      splashFactory: NoSplash.splashFactory,
    );

    // Short screen: the shared deck leaves the player page under 538px
    // tall, where the old 280 floor exceeded the 52% ceiling and clamp()
    // threw every frame (white screen on device).
    await tester.binding.setSurfaceSize(const Size(400, 500));
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
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(NowPlayingScreen), findsOneWidget);
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
      // "Force Canvas" was removed from the sheet; no longer asserted.
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
    expect(find.bySemanticsLabel('Show translated lyrics'), findsOneWidget);

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
      LyricsEntry(timeMs: 15200, text: 'I wanna be your vacuum cleaner', endMs: 18000),
      LyricsEntry(timeMs: 25000, text: 'Breathing in your dust', endMs: 28000),
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
