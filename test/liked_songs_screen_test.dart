import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/liked_songs_screen.dart';
import 'package:music_streaming_app/services/listening_stats.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LIKED SONGS, on the screen: one live list, and every action on it does what
/// it says - on the songs that are visible.

Track _t(String id, String title, String artist) => Track(
      id: id,
      trackName: title,
      artistName: artist,
      albumName: 'Album $id',
      previewUrl: '',
    );

class _Fake extends ChangeNotifier implements MusicProvider {
  _Fake(List<Track> liked) : _liked = List.of(liked);

  final List<Track> _liked;
  final List<(String, List<String>, String?)> played = [];
  final List<String> queued = [];
  final List<int> tabs = [];
  Track? current;
  bool playingNow = false;
  String? contextId;

  @override
  List<Track> get likedSongs => List.unmodifiable(_liked);
  @override
  Track? get currentTrack => current;
  @override
  bool get isPlaying => playingNow;
  @override
  String? get currentPlaylistId => contextId;
  @override
  bool isTrackDownloadedSync(String trackId) => false;
  @override
  bool isSongLiked(String trackId) => _liked.any((t) => t.id == trackId);
  @override
  final ListeningStats listeningStats = ListeningStats();
  @override
  bool get isPlayerExpanded => false;
  @override
  final GlobalKey<NavigatorState> playerNavigatorKey = GlobalKey<NavigatorState>();
  @override
  void setPlayerExpanded(bool value) {}
  @override
  void requestTab(int index) => tabs.add(index);

  @override
  Future<void> playTrack(Track track,
      {String? playlistId,
      List<Track>? playlistTracks,
      bool setContext = true,
      bool clearQueue = true,
      bool prefetchMetadata = true,
      bool recordHistory = true}) async {
    played.add((track.id, [for (final t in playlistTracks ?? const <Track>[]) t.id], playlistId));
  }

  @override
  void addToQueue(Track track) => queued.add(track.id);

  @override
  List<RemovedLike> unlikeSongs(Iterable<String> trackIds) {
    final ids = trackIds.toSet();
    final removed = <RemovedLike>[
      for (var i = 0; i < _liked.length; i++)
        if (ids.contains(_liked[i].id)) RemovedLike(index: i, track: _liked[i]),
    ];
    _liked.removeWhere((t) => ids.contains(t.id));
    notifyListeners();
    return removed;
  }

  @override
  void restoreLikedSongs(List<RemovedLike> removed) {
    for (final r in [...removed]..sort((a, b) => a.index.compareTo(b.index))) {
      _liked.insert(r.index, r.track);
    }
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _songs = [
  _t('a', 'oh yeah?', 'Steve Lacy'),
  _t('b', 'Blinding Lights', 'The Weeknd'),
  _t('c', 'Get Lucky', 'Daft Punk'),
  _t('d', 'Save Your Tears', 'The Weeknd'),
];

Future<_Fake> _pump(WidgetTester tester,
    {List<Track>? liked, Size size = const Size(412, 1400), double textScale = 1.0}) async {
  final fake = _Fake(liked ?? _songs);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
    value: fake,
    child: MaterialApp(
      theme: GlassTheme.build(AccentColors.peach),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const LikedSongsScreen(),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
  return fake;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hero and rows show the live list', (tester) async {
    await _pump(tester);
    expect(find.text('Liked Songs'), findsWidgets);
    expect(find.text('4 songs'), findsOneWidget);
    for (final t in _songs) {
      expect(find.text(t.trackName), findsOneWidget);
    }
  });

  testWidgets('a row plays inside the visible list, in the liked context', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.text('Get Lucky'));
    await tester.pump();
    expect(fake.played.single.$1, 'c');
    expect(fake.played.single.$2, ['a', 'b', 'c', 'd']);
    expect(fake.played.single.$3, kLikedContextId);
  });

  testWidgets('Play plays from the top; Shuffle plays everything once', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    expect(fake.played.last.$1, 'a');
    await tester.tap(find.bySemanticsLabel('Shuffle'));
    await tester.pump();
    expect(fake.played.last.$2.toSet(), {'a', 'b', 'c', 'd'});
  });

  testWidgets('while this collection plays, Play becomes Pause', (tester) async {
    final fake = _Fake(_songs)
      ..current = _songs[1]
      ..playingNow = true
      ..contextId = kLikedContextId;
    await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
      value: fake,
      child: const MaterialApp(home: LikedSongsScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Blinding Lights.*now playing')), findsOneWidget);
  });

  testWidgets('search narrows what Play plays, and says when nothing matches', (tester) async {
    final fake = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'weeknd');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('oh yeah?'), findsNothing);
    expect(find.text('2 of 4 songs'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    expect(fake.played.last.$2, ['b', 'd']);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No songs match "zzz"'), findsOneWidget);
    await tester.tap(find.text('Clear search and filters'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('oh yeah?'), findsOneWidget);
  });

  testWidgets('sort sheet reorders and the choice is remembered', (tester) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Sort: Recently added'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    final y = {for (final t in _songs) t.trackName: tester.getTopLeft(find.text(t.trackName)).dy};
    expect(y['Blinding Lights']! < y['Get Lucky']!, isTrue);
    expect(y['Get Lucky']! < y['oh yeah?']!, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kLikedSortPref), 'title');
  });

  testWidgets('artist chip filters', (tester) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Show filters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsLabel('Filter: The Weeknd'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Get Lucky'), findsNothing);
    expect(find.text('Blinding Lights'), findsOneWidget);
  });

  testWidgets('swipe right queues and keeps the row', (tester) async {
    final fake = await _pump(tester);
    await tester.drag(find.text('Get Lucky'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(fake.queued, ['c']);
    expect(find.text('Get Lucky'), findsOneWidget);
  });

  testWidgets('swipe left removes with Undo, and Undo puts it back in place', (tester) async {
    final fake = await _pump(tester);
    await tester.drag(find.text('Get Lucky'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(fake.likedSongs.map((t) => t.id), ['a', 'b', 'd']);
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(fake.likedSongs.map((t) => t.id), ['a', 'b', 'c', 'd']);
    expect(find.text('Get Lucky'), findsOneWidget);
  });

  testWidgets('long-press selects; batch remove has one Undo', (tester) async {
    final fake = await _pump(tester);
    await tester.longPress(find.text('oh yeah?'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Save Your Tears'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Remove'));
    await tester.pumpAndSettle();
    expect(fake.likedSongs.map((t) => t.id), ['b', 'c']);
    expect(find.text('Removed 2 songs from Liked Songs'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(fake.likedSongs.map((t) => t.id), ['a', 'b', 'c', 'd']);
  });

  testWidgets('selection: Select all, then back leaves selection, not the screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
      value: _Fake(_songs),
      child: const MaterialApp(home: Scaffold(body: Text('root'))),
    ));
    tester.state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => const LikedSongsScreen()));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('oh yeah?'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Select all'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('4 selected'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('4 selected'), findsNothing);
    expect(find.byType(LikedSongsScreen), findsOneWidget);
  });

  testWidgets('empty: an invitation that goes to Explore', (tester) async {
    final fake = await _pump(tester, liked: const []);
    expect(find.text('Songs you like live here'), findsOneWidget);
    expect(find.bySemanticsLabel('Play'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Find music'));
    await tester.pump();
    expect(fake.tabs, [1]);
  });

  for (final (size, scale) in const [(Size(360, 900), 1.0), (Size(360, 900), 1.3), (Size(430, 900), 1.0)]) {
    testWidgets('no layout errors at ${size.width.toInt()} dp, text x$scale', (tester) async {
      final long = [
        ..._songs,
        _t('e', 'Stereo Hearts (feat. Adam Levine) - Extended Radio Mix Version', 'Gym Class Heroes & Adam Levine'),
      ];
      await _pump(tester, liked: long, size: size, textScale: scale);
      expect(tester.takeException(), isNull);
      await tester.longPress(find.text('oh yeah?'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  }
}
