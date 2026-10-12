import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/now_playing_screen.dart';
import 'package:music_streaming_app/presentation/home/home_view_mode.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/glass_options_sheet.dart';
import 'package:music_streaming_app/screens/lyrics_screen.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_line.dart';
import 'package:music_streaming_app/screens/home_screen.dart';
import 'package:music_streaming_app/services/auth_service.dart';
import 'package:music_streaming_app/services/home/home_models.dart';
import 'package:music_streaming_app/models/playlist.dart';
import 'package:music_streaming_app/services/recommendation/quick_picks_engine.dart';
import 'package:music_streaming_app/services/recommendation/candidate.dart';
import 'package:music_streaming_app/widgets/home_sections.dart';

class MockMusicProvider extends MusicProvider {
  MockMusicProvider({this.initialTrack, bool playing = false, bool loggedIn = false})
      : _playing = playing,
        _loggedIn = loggedIn;

  Track? initialTrack;
  final bool _playing;
  final bool _loggedIn;
  bool _canvasActive = false;
  Duration _pos = const Duration(seconds: 15);
  final Duration _dur = const Duration(minutes: 3);
  final List<Track> _testQueue = [];
  List<LyricsEntry>? _testLyrics;
  HomeFeed? _testHomeFeed;
  List<Track> _testRecents = [];
  List<Track> _testQuickPicks = [];
  List<QuickPickCandidate> _testCandidates = [];
  List<Track> _testRecs = [];
  List<Track> _testTrending = [];
  List<Playlist> _testPlaylists = [];

  @override
  Track? get currentTrack => initialTrack;

  @override
  bool get isPlaying => _playing;

  @override
  Duration get duration => _dur;

  @override
  Duration get position => _pos;

  void setTestPosition(Duration p) {
    _pos = p;
    notifyListeners();
  }

  @override
  bool get isLoggedIn => _loggedIn;

  @override
  bool get isCanvasActive => _canvasActive;

  @override
  void toggleCanvas() {
    _canvasActive = !_canvasActive;
    notifyListeners();
  }

  @override
  List<Track> get queue => List.unmodifiable(_testQueue);

  @override
  List<LyricsEntry>? get currentLyrics => _testLyrics;

  void setTestLyrics(List<LyricsEntry> l) {
    _testLyrics = l;
    notifyListeners();
  }

  @override
  HomeFeed? get homeFeed => _testHomeFeed;

  void setTestHomeFeed(HomeFeed? f) {
    _testHomeFeed = f;
    notifyListeners();
  }

  @override
  List<Track> get recentlyPlayed => _testRecents;

  void setTestRecentlyPlayed(List<Track> r) {
    _testRecents = r;
    notifyListeners();
  }

  @override
  List<Track> get quickPicks => _testQuickPicks;

  @override
  List<QuickPickCandidate> get quickPickCandidates => _testCandidates;

  void setTestQuickPicks(List<Track> qp, [List<QuickPickCandidate>? candidates]) {
    _testQuickPicks = qp;
    _testCandidates = candidates ??
        qp
            .map((t) => QuickPickCandidate(
                  track: t,
                  reason: CandidateReason.globalTrending,
                  score: 1.0,
                ))
            .toList();
    notifyListeners();
  }

  @override
  List<Track> get recommendedTracks => _testRecs;

  void setTestRecommendedTracks(List<Track> recs) {
    _testRecs = recs;
    notifyListeners();
  }

  @override
  List<Track> get trendingTracks => _testTrending;

  void setTestTrendingTracks(List<Track> tr) {
    _testTrending = tr;
    notifyListeners();
  }

  @override
  List<Playlist> get userPlaylists => _testPlaylists;

  void setTestUserPlaylists(List<Playlist> pl) {
    _testPlaylists = pl;
    notifyListeners();
  }
}

Track sampleTrack({String id = 'dQw4w9WgXcQ', String title = 'Borderline', String artist = 'Tame Impala', String source = 'youtube'}) {
  return Track(
    id: id,
    trackName: title,
    artistName: artist,
    albumArtUrl: 'https://example.com/art.jpg',
    albumName: 'The Slow Rush',
    previewUrl: 'https://example.com/audio.mp3',
    source: source,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Muzo / Liquid Glass Requirements Test Suite', () {
    testWidgets('Lyrics: multi-line lyric covering line 1 first before line 2', (tester) async {
      final provider = MockMusicProvider(
        initialTrack: sampleTrack(),
        playing: true,
      );

      final multilineLyrics = [
        // Word timings on the first line so the wipe is genuinely exercised.
        // Without them the line is line-synced only, renders as plain text, and
        // there is nothing to clip - which is correct behaviour but tests
        // nothing about the highlight.
        LyricsEntry(
          timeMs: 0,
          endMs: 10000,
          text: 'Gone a little far this time\nwith something',
          words: const [
            WordTiming(timeMs: 0, durationMs: 400, text: 'Gone'),
            WordTiming(timeMs: 400, durationMs: 400, text: 'a'),
            WordTiming(timeMs: 800, durationMs: 400, text: 'little'),
            WordTiming(timeMs: 1200, durationMs: 400, text: 'far'),
          ],
        ),
        LyricsEntry(
          timeMs: 10000,
          endMs: 20000,
          text: 'How was I to know this high came rushing',
          words: const [
            WordTiming(timeMs: 10000, durationMs: 400, text: 'How'),
            WordTiming(timeMs: 10400, durationMs: 400, text: 'was'),
            WordTiming(timeMs: 10800, durationMs: 400, text: 'I'),
          ],
        ),
      ];
      provider.setTestLyrics(multilineLyrics);

      final theme = GlassTheme.build(AccentColors.peach);
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider<MusicProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: LyricsScreen(isEmbedded: true),
            ),
          ),
        ),
      );
      await tester.pump();

      // At position 2s (20% of line 1), line 1 words are highlighting, line 2 words remain inactive
      // Drive the clock to the middle of line 1's words (they run 0-1600ms), and let
      // the correction timer land. At 2s the line is already fully sung and
      // correctly renders as plain text with nothing to clip.
      provider.setTestPosition(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(LyricsScreen), findsOneWidget);

      // The only ShaderMask is the dissolve at the top and bottom 28dp of the list
      // (BitChord `fadingEdges`). The sweep itself is NOT a mask: it is a clip per
      // visual row over a brighter copy of the same text, drawn by one render
      // object.
      expect(find.byType(ShaderMask), findsOneWidget);

      // Exactly one line is the active one, and it is the one carrying the soft
      // leading edge.
      expect(find.byType(LyricLine), findsWidgets);
      final active = tester
          .widgetList<LyricLine>(find.byType(LyricLine))
          .where((l) => l.feather)
          .toList();
      expect(active.length, 1);
      expect(active.single.entry.isWordSynced, isTrue,
          reason: 'the word-by-word wipe is a clip over a brighter copy');

      // At position 9.9s (99% of line 1), the screen must still be intact and
      // the first line must not have dropped out.
      provider.setTestPosition(const Duration(milliseconds: 9900));
      await tester.pump();
      expect(find.byType(LyricsScreen), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) =>
            w is LyricLine &&
            w.entry.text == 'Gone a little far this time\nwith something'),
        findsWidgets,
      );
    });
    testWidgets('NowPlaying: Wave tab only toggles lofi and does not switch page; tapping active tab toggles back to album', (tester) async {
      final provider = MockMusicProvider(
        initialTrack: sampleTrack(),
        playing: true,
      );

      final theme = GlassTheme.build(AccentColors.peach);
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider<MusicProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: theme,
            home: NowPlayingScreen(track: sampleTrack()),
          ),
        ),
      );
      await tester.pump();

      // Initial page is Album Art (Page 1)
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      expect(find.bySemanticsLabel('Lyrics tab'), findsOneWidget);

      // Navigate to Lyrics tab (Tab 0)
      await tester.tap(find.bySemanticsLabel('Lyrics tab'));
      await tester.pumpAndSettle();
      expect(find.byType(LyricsScreen), findsOneWidget);

      // Tap Wave tab (Tab 2)
      await tester.tap(find.bySemanticsLabel('Canvas tab'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should have toggled lofi and canvas
      expect(provider.isCanvasActive, isTrue);

      // PageView should NOT have switched to album art, still on Lyrics page
      expect(find.byType(LyricsScreen), findsOneWidget);

      // Tapping the currently active Lyrics tab (Tab 0) toggles back to album art (Page 1)
      await tester.tap(find.bySemanticsLabel('Lyrics tab'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      // Now on Album Art page: large artwork and transport controls are visible
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    });

    testWidgets('Options Sheet: displays Mine Music Code and liquid glass tokens', (tester) async {
      final provider = MockMusicProvider(initialTrack: sampleTrack(), playing: true);
      final theme = GlassTheme.build(AccentColors.peach);

      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider<MusicProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: GlassOptionsSheet(track: sampleTrack()),
            ),
          ),
        ),
      );
      await tester.pump();

      // Visible Mine Music Code label
      expect(find.text('Mine Music Code'), findsOneWidget);
      // Muzo Code fallback exists for backward compatibility
      expect(find.text('Muzo Code'), findsOneWidget);

      // Verify option order: Add to playlist -> Mine Music Code -> Go to album
      // -> Go to artist -> Download -> Share -> Song Info -> Sleep Timer.
      // "Force Canvas" was removed from the sheet; no longer asserted.
      expect(find.text('Add to a playlist...'), findsOneWidget);
      expect(find.text('Go to album'), findsOneWidget);
      expect(find.text('Go to artist'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Song Info'), findsOneWidget);
      expect(find.text('Sleep Timer'), findsOneWidget);
    });

    testWidgets('Home: Guest mode renders all shelves/sections in feed including quick picks', (tester) async {
      final provider = MockMusicProvider(
        initialTrack: sampleTrack(),
        loggedIn: false, // Guest / anonymous mode
      );

      final feed = HomeFeed(
        source: 'ytm',
        fetchedAt: DateTime.now(),
        sections: const [
          HomeSection(
            id: 'sec_new_rel',
            title: 'New releases',
            presentation: HomePresentation.artworkRail,
            provenance: 'new_release',
            items: [
              HomeItem(
                id: 'nr1',
                videoId: 'nr1',
                title: 'New Song 1',
                subtitle: 'Artist 1',
                artworkUrl: 'https://example.com/1.jpg',
                contentType: HomeContentType.song,
              ),
              HomeItem(
                id: 'nr2',
                videoId: 'nr2',
                title: 'New Song 2',
                subtitle: 'Artist 2',
                artworkUrl: 'https://example.com/2.jpg',
                contentType: HomeContentType.song,
              ),
              HomeItem(
                id: 'nr3',
                videoId: 'nr3',
                title: 'New Song 3',
                subtitle: 'Artist 3',
                artworkUrl: 'https://example.com/3.jpg',
                contentType: HomeContentType.song,
              ),
            ],
          ),
          HomeSection(
            id: 'sec_trending',
            title: 'Charts & Trending',
            presentation: HomePresentation.compactTracks,
            provenance: 'charts',
            items: [
              HomeItem(
                id: 'tr1',
                videoId: 'tr1',
                title: 'Trending 1',
                subtitle: 'Artist A',
                artworkUrl: 'https://example.com/a.jpg',
                contentType: HomeContentType.song,
              ),
              HomeItem(
                id: 'tr2',
                videoId: 'tr2',
                title: 'Trending 2',
                subtitle: 'Artist B',
                artworkUrl: 'https://example.com/b.jpg',
                contentType: HomeContentType.song,
              ),
              HomeItem(
                id: 'tr3',
                videoId: 'tr3',
                title: 'Trending 3',
                subtitle: 'Artist C',
                artworkUrl: 'https://example.com/c.jpg',
                contentType: HomeContentType.song,
              ),
            ],
          ),
          HomeSection(
            id: 'sec_quick_picks',
            title: 'Quick picks',
            presentation: HomePresentation.artworkRail,
            provenance: 'quick_picks',
            items: [
              HomeItem(
                id: 'qp1',
                title: 'Quick 1',
                subtitle: 'Artist D',
                artworkUrl: 'https://example.com/d.jpg',
                contentType: HomeContentType.song,
              ),
              HomeItem(
                id: 'qp2',
                title: 'Quick 2',
                subtitle: 'Artist E',
                artworkUrl: 'https://example.com/e.jpg',
                contentType: HomeContentType.song,
              ),
              HomeItem(
                id: 'qp3',
                title: 'Quick 3',
                subtitle: 'Artist F',
                artworkUrl: 'https://example.com/f.jpg',
                contentType: HomeContentType.song,
              ),
            ],
          ),
        ],
      );
      provider.setTestHomeFeed(feed);

      final theme = GlassTheme.build(AccentColors.peach);
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider<MusicProvider>.value(
          value: provider,
          // HomeScreen reads auth state for its header avatar and the
          // signed-out prompt, so the mount has to provide it.
          child: ChangeNotifierProvider<AuthService>.value(
            value: AuthService(),
            child: MaterialApp(
              theme: theme,
              // Section headers read the persisted rows-vs-cards choice from this store.
              home: ChangeNotifierProvider<HomeViewModeStore>(
                create: (_) => HomeViewModeStore(),
                child: const HomeScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // All feed shelves (New releases, Charts & Trending, Quick picks) are present in guest mode
      expect(find.text('New releases'), findsOneWidget);
      expect(find.text('Charts & Trending'), findsOneWidget);
      expect(find.text('Quick picks'), findsOneWidget);
    });

    testWidgets('Home: Guest mode renders personalized sections (Jump Back In, Quick Picks, Playlists) when available', (tester) async {
      final provider = MockMusicProvider(
        initialTrack: sampleTrack(id: 'current_playing'),
        loggedIn: false, // Guest / anonymous mode
      );

      final recentTrack = sampleTrack(id: 'recent_1', title: 'Recent Track');
      final quickPickTrack = sampleTrack(id: 'qp_track_1', title: 'Pick Track');
      provider.setTestRecentlyPlayed([recentTrack]);
      provider.setTestQuickPicks(
        [quickPickTrack],
        [
          QuickPickCandidate(
            track: quickPickTrack,
            reason: CandidateReason.globalTrending,
            score: 1.0,
          )
        ],
      );
      provider.setTestUserPlaylists([
        Playlist(id: 'p1', name: 'Guest Playlist', imageUrl: '', tracks: [recentTrack]),
      ]);

      final theme = GlassTheme.build(AccentColors.peach);
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider<MusicProvider>.value(
          value: provider,
          // HomeScreen reads auth state for its header avatar and the
          // signed-out prompt, so the mount has to provide it.
          child: ChangeNotifierProvider<AuthService>.value(
            value: AuthService(),
            child: MaterialApp(
              theme: theme,
              // Section headers read the persisted rows-vs-cards choice from this store.
              home: ChangeNotifierProvider<HomeViewModeStore>(
                create: (_) => HomeViewModeStore(),
                child: const HomeScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jump back in'), findsOneWidget);
      expect(find.text('Quick picks'), findsOneWidget);
      expect(find.text('Your playlists'), findsOneWidget);
    });

    testWidgets('Home: Guest mode renders fallback sections (Made for you, Artists) when feed is null', (tester) async {
      final provider = MockMusicProvider(
        initialTrack: sampleTrack(),
        loggedIn: false, // Guest / anonymous mode
      );

      final track1 = sampleTrack(id: 'rec_1', title: 'Rec Track', artist: 'Daft Punk');
      provider.setTestRecommendedTracks([track1]);
      provider.setTestTrendingTracks([track1]);

      final theme = GlassTheme.build(AccentColors.peach);
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider<MusicProvider>.value(
          value: provider,
          // HomeScreen reads auth state for its header avatar and the
          // signed-out prompt, so the mount has to provide it.
          child: ChangeNotifierProvider<AuthService>.value(
            value: AuthService(),
            child: MaterialApp(
              theme: theme,
              // Section headers read the persisted rows-vs-cards choice from this store.
              home: ChangeNotifierProvider<HomeViewModeStore>(
                create: (_) => HomeViewModeStore(),
                child: const HomeScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only "Made for you" and "Artists" are legacy fallbacks. There is no
      // "Top picks for you" header in home_screen.dart, so it is not asserted.
      expect(find.widgetWithText(HomeSectionHeader, 'Made for you'), findsOneWidget);
      expect(find.widgetWithText(HomeSectionHeader, 'Artists'), findsOneWidget);
    });

    testWidgets('Home: Guest mode renders promoted hero shelf and lower shelves without dropping sections', (tester) async {
      final provider = MockMusicProvider(
        initialTrack: sampleTrack(),
        loggedIn: false, // Guest / anonymous mode
      );

      final feed = HomeFeed(
        source: 'ytm',
        fetchedAt: DateTime.now(),
        sections: const [
          HomeSection(
            id: 'sec_hero_songs',
            title: 'Featured Tracks',
            presentation: HomePresentation.compactTracks,
            provenance: 'editorial',
            items: [
              HomeItem(
                id: '12345678901',
                videoId: '12345678901',
                title: 'Hero Song 1',
                subtitle: 'Artist 1',
                artworkUrl: 'https://example.com/1.jpg',
                contentType: HomeContentType.song,
              ),
              HomeItem(
                id: '12345678902',
                videoId: '12345678902',
                title: 'Hero Song 2',
                subtitle: 'Artist 2',
                artworkUrl: 'https://example.com/2.jpg',
                contentType: HomeContentType.song,
              ),
              HomeItem(
                id: '12345678903',
                videoId: '12345678903',
                title: 'Hero Song 3',
                subtitle: 'Artist 3',
                artworkUrl: 'https://example.com/3.jpg',
                contentType: HomeContentType.song,
              ),
            ],
          ),
          HomeSection(
            id: 'sec_new_albums',
            title: 'Fresh Albums',
            presentation: HomePresentation.artworkRail,
            provenance: 'new_release',
            items: [
              HomeItem(
                id: 'album_1',
                browseId: 'MPREb_album1',
                title: 'Album 1',
                subtitle: 'Artist A',
                artworkUrl: 'https://example.com/a.jpg',
                contentType: HomeContentType.album,
              ),
              HomeItem(
                id: 'album_2',
                browseId: 'MPREb_album2',
                title: 'Album 2',
                subtitle: 'Artist B',
                artworkUrl: 'https://example.com/b.jpg',
                contentType: HomeContentType.album,
              ),
              HomeItem(
                id: 'album_3',
                browseId: 'MPREb_album3',
                title: 'Album 3',
                subtitle: 'Artist C',
                artworkUrl: 'https://example.com/c.jpg',
                contentType: HomeContentType.album,
              ),
            ],
          ),
        ],
      );
      provider.setTestHomeFeed(feed);

      final theme = GlassTheme.build(AccentColors.peach);
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider<MusicProvider>.value(
          value: provider,
          // HomeScreen reads auth state for its header avatar and the
          // signed-out prompt, so the mount has to provide it.
          child: ChangeNotifierProvider<AuthService>.value(
            value: AuthService(),
            child: MaterialApp(
              theme: theme,
              // Section headers read the persisted rows-vs-cards choice from this store.
              home: ChangeNotifierProvider<HomeViewModeStore>(
                create: (_) => HomeViewModeStore(),
                child: const HomeScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Featured Tracks is promoted to hero and Fresh Albums is in lower sections
      expect(find.widgetWithText(HomeSectionHeader, 'Featured Tracks'), findsOneWidget);
      expect(find.widgetWithText(HomeSectionHeader, 'Fresh Albums'), findsOneWidget);
    });
  });
}
