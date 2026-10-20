import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/presentation/home/home_view_mode.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/home_screen.dart';
import 'package:music_streaming_app/services/auth_service.dart';
import 'package:music_streaming_app/services/home/home_models.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:provider/provider.dart';

import 'muzo_enhancements_test.dart' show MockMusicProvider;

/// HOME, END TO END: ONE SHELF PER JOB, AND EVERY LIST ROW PLAYS.
///
/// The planner is pinned in `home_shelf_plan_test.dart` and the row in
/// `track_list_row_test.dart`. These mount the real `HomeScreen` and check what
/// a person would see and do: the page the bug report described (a feed that
/// sends its own "Quick picks" and "Listen again") draws each once, and in list
/// mode a tap on a song starts it.

String vid(int n) => 'vid${n.toString().padLeft(8, '0')}'; // 11 chars

Track track(int n, {String source = 'youtube', String? id}) => Track(
      id: id ?? vid(n),
      trackName: 'Title $n',
      artistName: 'Artist $n',
      albumName: 'Album',
      albumArtUrl: 'https://example.com/$n.jpg',
      previewUrl: '',
      source: source,
    );

HomeItem item(int n) => HomeItem(
      id: vid(n),
      videoId: vid(n),
      title: 'Feed $n',
      subtitle: 'Feed Artist $n',
      artworkUrl: 'https://example.com/feed$n.jpg',
      contentType: HomeContentType.song,
    );

HomeSection shelf(String title, List<int> ns) => HomeSection(
      id: 'id_$title',
      title: title,
      items: [for (final n in ns) item(n)],
      presentation: HomePresentation.artworkRail,
    );

HomeFeed feedOf(List<HomeSection> s) =>
    HomeFeed(sections: s, fetchedAt: DateTime.now(), source: 'ytm_home');

/// Records what Home asks the player to start.
class RecordingProvider extends MockMusicProvider {
  RecordingProvider() : super(loggedIn: true);

  final List<String> played = [];
  List<Track>? lastContext;

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
    played.add(track.id);
    lastContext = playlistTracks;
  }
}

Future<void> pumpHome(
  WidgetTester tester,
  MusicProvider provider, {
  HomeViewModeStore? modes,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<MusicProvider>.value(
      value: provider,
      child: ChangeNotifierProvider<AuthService>.value(
        value: AuthService(),
        child: MaterialApp(
          theme: GlassTheme.build(AccentColors.peach),
          home: ChangeNotifierProvider<HomeViewModeStore>.value(
            value: modes ?? HomeViewModeStore(),
            child: const HomeScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('one shelf per job, on the real screen', () {
    testWidgets(
        'a feed that sends its own Quick picks and Listen again: each appears once',
        (tester) async {
      final p = RecordingProvider()
        ..setTestHomeFeed(feedOf([
          shelf('Listen again', [1, 2, 3]),
          shelf('Quick picks', [4, 5, 6]),
          shelf('New releases', [7, 8, 9]),
        ]))
        // The app's own shelves, which used to be drawn as well.
        ..setTestRecommendedTracks([track(30)])
        ..setTestQuickPicks([track(20), track(21), track(22)])
        ..setTestRecentlyPlayed([track(10), track(11)]);
      await pumpHome(tester, p);

      expect(find.text('Quick picks'), findsOneWidget);
      expect(find.text('Listen again'), findsOneWidget);
      expect(find.text('Jump back in'), findsNothing,
          reason: 'the plays made here live in Listen again, not a 2nd shelf');
      expect(find.text('New releases'), findsOneWidget);

      // The feed's Quick picks is the one on screen, not the app's.
      expect(find.text('Feed 4'), findsOneWidget);
      expect(find.text('Title 20'), findsNothing);
      // What was played here is in Listen again, ahead of the native items.
      expect(find.text('Title 10'), findsOneWidget);
      expect(find.text('Feed 1'), findsOneWidget);
    });

    testWidgets('the shelves keep the feed\'s own order', (tester) async {
      final p = RecordingProvider()
        ..setTestHomeFeed(feedOf([
          shelf('New releases', [7, 8, 9]),
          shelf('Quick picks', [4, 5, 6]),
          shelf('Listen again', [1, 2, 3]),
        ]))
        ..setTestRecommendedTracks([track(30)]);
      await pumpHome(tester, p);

      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('New releases'), lessThan(y('Quick picks')));
      expect(y('Quick picks'), lessThan(y('Listen again')));
    });

    testWidgets('a feed without them: the app\'s own fill both jobs, once each',
        (tester) async {
      final p = RecordingProvider()
        ..setTestHomeFeed(feedOf([
          shelf('New releases', [7, 8, 9]),
          shelf('Trending', [1, 2, 3]),
        ]))
        ..setTestRecommendedTracks([track(30)])
        ..setTestQuickPicks([track(20), track(21), track(22)])
        ..setTestRecentlyPlayed([track(10), track(11)]);
      await pumpHome(tester, p);

      expect(find.text('Quick picks'), findsOneWidget);
      expect(find.text('Jump back in'), findsOneWidget);
      expect(find.text('Title 20'), findsOneWidget);
      expect(find.text('Title 10'), findsOneWidget);
    });

    testWidgets('local-file plays do not bring the hidden Jump back in back',
        (tester) async {
      final p = RecordingProvider()
        ..setTestHomeFeed(feedOf([
          shelf('Listen again', [1, 2, 3]),
          shelf('New releases', [7, 8, 9]),
        ]))
        ..setTestRecommendedTracks([track(30)])
        ..setTestRecentlyPlayed([
          track(10),
          track(0, source: 'local', id: '/storage/emulated/0/Music/a.mp3'),
        ]);
      await pumpHome(tester, p);

      expect(find.text('Listen again'), findsOneWidget);
      expect(find.text('Jump back in'), findsNothing,
          reason: 'a local file must not resurrect the hidden shelf');
      expect(find.text('Title 10'), findsOneWidget,
          reason: 'the streamable play is in Listen again');
    });

    testWidgets('the hero carousel\'s tracks are not served again as Quick picks',
        (tester) async {
      final same = [for (var i = 1; i <= 4; i++) track(i)];
      final p = RecordingProvider()
        ..setTestRecommendedTracks(same)
        ..setTestQuickPicks(same);
      await pumpHome(tester, p);

      expect(find.text('For you'), findsWidgets);
      expect(find.text('Quick picks'), findsNothing,
          reason: 'it would be the same four tracks twice');
    });

    testWidgets('picks the hero does not show still make a Quick picks shelf',
        (tester) async {
      final p = RecordingProvider()
        ..setTestRecommendedTracks([track(1), track(2)])
        ..setTestQuickPicks([for (var i = 1; i <= 8; i++) track(i)]);
      await pumpHome(tester, p);

      expect(find.text('For you'), findsWidgets);
      expect(find.text('Quick picks'), findsOneWidget);
    });
  });

  group('list mode plays on tap', () {
    testWidgets('Quick picks rows', (tester) async {
      final modes = HomeViewModeStore()
        ..debugSet(HomeViewSection.quickPicks, HomeSectionViewMode.list);
      final p = RecordingProvider()
        ..setTestRecommendedTracks([track(30)])
        ..setTestQuickPicks([track(20), track(21), track(22)]);
      await pumpHome(tester, p, modes: modes);

      await tester.tap(find.text('Title 21'));
      await tester.pump();

      expect(p.played, [vid(21)]);
      expect(p.lastContext?.map((t) => t.id), contains(vid(22)),
          reason: 'it starts inside the shelf as its queue, not alone');
    });

    testWidgets('Jump back in rows', (tester) async {
      final modes = HomeViewModeStore()
        ..debugSet(HomeViewSection.jumpBackIn, HomeSectionViewMode.list);
      final p = RecordingProvider()
        ..setTestRecommendedTracks([track(30)])
        ..setTestRecentlyPlayed([track(10), track(11)]);
      await pumpHome(tester, p, modes: modes);

      await tester.tap(find.text('Title 11'));
      await tester.pump();

      expect(p.played, [vid(11)]);
    });

    testWidgets('a locally merged play in the feed\'s Listen again, in list mode',
        (tester) async {
      final modes = HomeViewModeStore()
        ..debugSet(HomeViewSection.listenAgain, HomeSectionViewMode.list);
      final p = RecordingProvider()
        ..setTestHomeFeed(feedOf([
          shelf('Listen again', [1, 2, 3]),
          shelf('New releases', [7, 8, 9]),
        ]))
        ..setTestRecommendedTracks([track(30)])
        ..setTestRecentlyPlayed([track(10)]);
      await pumpHome(tester, p, modes: modes);

      await tester.tap(find.text('Feed 2'));
      await tester.pump();
      expect(p.played, [vid(2)]);

      await tester.tap(find.text('Title 10'));
      await tester.pump();
      expect(p.played, [vid(2), vid(10)]);
    });
  });
}
