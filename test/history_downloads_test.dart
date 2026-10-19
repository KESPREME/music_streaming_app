import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/presentation/history/history_groups.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/downloaded_songs_screen.dart';
import 'package:music_streaming_app/screens/recently_played_screen.dart';
import 'package:music_streaming_app/services/listening_stats.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HISTORY and DOWNLOADED on the shared kit: live lists whose actions do what
/// they say, with Undo where an undo is possible and a confirmation where it
/// is not.

Track _t(String id, [String? title, String artist = 'Artist']) => Track(
      id: id,
      trackName: title ?? 'Song $id',
      artistName: artist,
      albumName: 'Album',
      albumArtUrl: 'https://example.com/$id.jpg',
      previewUrl: '',
    );

class _Rec extends MusicProvider {
  final List<(String, List<String>, String?)> played = [];
  final List<(String, List<String>)> playedOffline = [];
  List<Track> fakeDownloads = [];
  List<Track> fakeActive = [];
  Map<String, double> fakeProgress = {};
  final List<String> cancelled = [];

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
  Future<void> playOfflineTrack(Track track,
      {bool setContext = true, bool clearQueue = true, List<Track>? contextList, bool recordHistory = true}) async {
    playedOffline.add((track.id, [for (final t in contextList ?? const <Track>[]) t.id]));
  }

  @override
  Future<List<Track>> getDownloadedTracks() async => List.of(fakeDownloads);

  @override
  Future<void> deleteDownloadedTrack(String trackId) async =>
      fakeDownloads.removeWhere((t) => t.id == trackId);

  @override
  List<Track> get currentlyDownloadingTracks => fakeActive;

  @override
  Map<String, double> get downloadProgress => fakeProgress;

  @override
  void cancelDownload(String trackId) => cancelled.add(trackId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Rec p;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final ready = Completer<void>();
    final original = debugPrint;
    debugPrint = (msg, {wrapWidth}) {
      if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) ready.complete();
    };
    p = _Rec();
    await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    debugPrint = original;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    p.debugSetRecentlyPlayed(const []);
    p.played.clear();
    p.playedOffline.clear();
    p.fakeDownloads = [];
    p.fakeActive = [];
    p.fakeProgress = {};
    p.cancelled.clear();
  });

  Future<void> pump(WidgetTester tester, Widget home, {Size size = const Size(412, 1400), double scale = 1.0}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
      value: p,
      child: MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        builder: (c, child) =>
            MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: home,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('history groups', () {
    final now = DateTime(2026, 10, 20, 15);
    int ms(DateTime d) => d.millisecondsSinceEpoch;

    test('buckets by calendar day', () {
      expect(historyBucket(ms(DateTime(2026, 10, 20, 1)), now), 'Today');
      expect(historyBucket(ms(DateTime(2026, 10, 19, 23, 59)), now), 'Yesterday');
      expect(historyBucket(ms(DateTime(2026, 10, 15)), now), 'This week');
      expect(historyBucket(ms(DateTime(2026, 10, 13)), now), 'Earlier');
      expect(historyBucket(null, now), 'Earlier', reason: 'a song with no logged play is never given a date');
    });

    test('keeps order and splits consecutive groups', () {
      final g = groupHistory(
        [_t('a'), _t('b'), _t('c'), _t('d')],
        {'a': ms(DateTime(2026, 10, 20)), 'b': ms(DateTime(2026, 10, 20, 9)), 'c': ms(DateTime(2026, 10, 19))},
        now,
      );
      expect(g.map((e) => e.label), ['Today', 'Yesterday', 'Earlier']);
      expect(g.map((e) => e.tracks.map((t) => t.id).toList()), [
        ['a', 'b'],
        ['c'],
        ['d']
      ]);
      expect(groupHistory(const [], const {}, now), isEmpty);
    });

    test('lastPlayedAt reads the newest play of each track', () async {
      final s = ListeningStats();
      await s.load();
      s.onTrackChanged(_t('a'));
      s.onPlayingChanged(true);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      s.onPlayingChanged(false);
      expect(s.lastPlayedAt().keys, ['a']);
      expect(s.lastPlayedAt()['a']! > 0, isTrue);
    });
  });

  group('History screen', () {
    testWidgets('empty: an invitation', (tester) async {
      await pump(tester, const RecentlyPlayedScreen());
      expect(find.text('Nothing played yet'), findsOneWidget);
      expect(find.text('Find music'), findsOneWidget);
    });

    testWidgets('lists songs under a group header; tap plays inside the list', (tester) async {
      p.debugSetRecentlyPlayed([_t('a'), _t('b'), _t('c')]);
      await pump(tester, const RecentlyPlayedScreen());
      expect(find.text('History'), findsWidgets);
      expect(find.text('3 songs'), findsOneWidget);
      expect(find.text('Earlier'), findsOneWidget);
      await tester.tap(find.text('Song b'));
      await tester.pump();
      expect(p.played.single.$1, 'b');
      expect(p.played.single.$2, ['a', 'b', 'c']);
      expect(p.played.single.$3, kHistoryContextId);
    });

    testWidgets('search narrows what plays', (tester) async {
      p.debugSetRecentlyPlayed([_t('a', 'Borderline'), _t('b', 'Currents'), _t('c', 'Borderline Live')]);
      await pump(tester, const RecentlyPlayedScreen());
      await tester.enterText(find.byType(TextField), 'borderline');
      await settle(tester);
      expect(find.text('Currents'), findsNothing);
      expect(find.text('2 of 3 songs'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      expect(p.played.last.$2, ['a', 'c']);
    });

    testWidgets('swipe left removes with Undo that restores the place', (tester) async {
      p.debugSetRecentlyPlayed([_t('a'), _t('b'), _t('c')]);
      await pump(tester, const RecentlyPlayedScreen());
      await tester.drag(find.text('Song b'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(p.recentlyPlayed.map((t) => t.id), ['a', 'c']);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(p.recentlyPlayed.map((t) => t.id), ['a', 'b', 'c']);
    });

    testWidgets('Clear history empties it, and Undo brings it all back', (tester) async {
      p.debugSetRecentlyPlayed([_t('a'), _t('b')]);
      await pump(tester, const RecentlyPlayedScreen());
      await tester.tap(find.bySemanticsLabel('More options'));
      await settle(tester);
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      expect(p.recentlyPlayed, isEmpty);
      expect(find.text('History cleared'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(p.recentlyPlayed.map((t) => t.id), ['a', 'b']);
    });

    testWidgets('select and remove', (tester) async {
      p.debugSetRecentlyPlayed([_t('a'), _t('b'), _t('c')]);
      await pump(tester, const RecentlyPlayedScreen());
      await tester.longPress(find.text('Song a'));
      await settle(tester);
      await tester.tap(find.text('Song c'));
      await settle(tester);
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Remove'));
      await tester.pumpAndSettle();
      expect(p.recentlyPlayed.map((t) => t.id), ['b']);
    });

    testWidgets('no layout errors at 360 dp, text x1.3', (tester) async {
      p.debugSetRecentlyPlayed([
        _t('a', 'An extremely long song title that goes on and on and on and on', 'A very long artist name too'),
        _t('b'),
      ]);
      await pump(tester, const RecentlyPlayedScreen(), size: const Size(360, 800), scale: 1.3);
      expect(tester.takeException(), isNull);
      await tester.longPress(find.text('Song b'));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Downloaded screen', () {
    test('sortDownloads: recent keeps order, title and artist ignore case and accents', () {
      final l = [_t('1', 'zebra', 'B'), _t('2', 'Éclair', 'C'), _t('3', 'apple', 'A')];
      expect(sortDownloads(l, DownloadSort.recent).map((t) => t.id), ['1', '2', '3']);
      expect(sortDownloads(l, DownloadSort.title).map((t) => t.id), ['3', '2', '1']);
      expect(sortDownloads(l, DownloadSort.artist).map((t) => t.id), ['3', '1', '2']);
    });

    testWidgets('empty: an invitation', (tester) async {
      await pump(tester, const DownloadedSongsScreen());
      expect(find.text('Nothing downloaded yet'), findsOneWidget);
    });

    testWidgets('lists what is on the device and plays it offline, in order', (tester) async {
      p.fakeDownloads = [_t('a'), _t('b'), _t('c')];
      await pump(tester, const DownloadedSongsScreen());
      expect(find.text('3 songs · available offline'), findsOneWidget);
      await tester.tap(find.text('Song b'));
      await tester.pump();
      expect(p.playedOffline.single.$1, 'b');
      expect(p.playedOffline.single.$2, ['a', 'b', 'c']);
    });

    testWidgets('swipe left does NOT delete a download', (tester) async {
      p.fakeDownloads = [_t('a'), _t('b')];
      await pump(tester, const DownloadedSongsScreen());
      await tester.drag(find.text('Song a'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(p.fakeDownloads.map((t) => t.id), ['a', 'b']);
      expect(find.text('Song a'), findsOneWidget);
    });

    testWidgets('selecting and removing asks first; Cancel keeps them, Remove deletes', (tester) async {
      p.fakeDownloads = [_t('a'), _t('b'), _t('c')];
      await pump(tester, const DownloadedSongsScreen());
      await tester.longPress(find.text('Song a'));
      await settle(tester);
      await tester.tap(find.text('Song b'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove 2 downloads?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(p.fakeDownloads, hasLength(3));

      await tester.tap(find.bySemanticsLabel('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(p.fakeDownloads.map((t) => t.id), ['c']);
      expect(find.text('2 downloads removed'), findsOneWidget);
    });

    testWidgets('in-progress downloads show a bar and can be cancelled', (tester) async {
      p.fakeDownloads = [_t('a')];
      p.fakeActive = [_t('x', 'Coming down')];
      p.fakeProgress = {'x': 0.4};
      await pump(tester, const DownloadedSongsScreen());
      expect(find.text('Downloading'), findsOneWidget);
      expect(find.text('40% · Artist'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel download of Coming down'));
      expect(p.cancelled, ['x']);
    });

    testWidgets('no layout errors at 360 dp, text x1.3', (tester) async {
      p.fakeDownloads = [_t('a', 'An extremely long song title that goes on and on and on and on'), _t('b')];
      p.fakeActive = [_t('x', 'Another very long title that is still on its way down to the device')];
      await pump(tester, const DownloadedSongsScreen(), size: const Size(360, 800), scale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });
}
