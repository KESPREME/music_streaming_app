import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/replay_screen.dart';
import 'package:music_streaming_app/screens/replay_story_screen.dart';
import 'package:music_streaming_app/services/listening_stats.dart';
import 'package:music_streaming_app/services/replay/replay_summary.dart';
import 'package:music_streaming_app/widgets/replay/replay_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// REPLAY. The play log attributes time to the right track; the summary ranks,
/// filters and counts by the rules in replay_summary.dart; the screens show what
/// the summary says and nothing else.

class _Clock {
  _Clock(this.now);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

Track _t(String id, {String artist = 'Tame Impala', String album = 'Deadbeat', String? genre}) =>
    Track(
      id: id,
      trackName: 'Song $id',
      artistName: artist,
      albumName: album,
      albumArtUrl: 'https://example.com/$id.jpg',
      previewUrl: '',
      genre: genre,
    );

/// Plays [track] for [d] on [s], then stops.
void _play(ListeningStats s, _Clock c, Track track, Duration d) {
  s.onTrackChanged(track);
  s.onPlayingChanged(true);
  c.advance(d);
  s.onPlayingChanged(false);
}

class _FakeProvider extends ChangeNotifier implements MusicProvider {
  _FakeProvider(this.listeningStats);

  @override
  final ListeningStats listeningStats;

  final List<String> played = [];

  @override
  Future<void> playTrackList(List<Track> tracks, {int initialIndex = 0, String? playlistId}) async {
    played.add(tracks[initialIndex].id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the play log', () {
    test('time goes to the track that was playing, across a track change', () async {
      final c = _Clock(DateTime(2026, 10, 15, 20));
      final s = ListeningStats(clock: c.call);
      await s.load();
      s.onTrackChanged(_t('a'));
      s.onPlayingChanged(true);
      c.advance(const Duration(minutes: 3));
      s.onTrackChanged(_t('b')); // auto-advance: still playing
      c.advance(const Duration(minutes: 2));
      s.onPlayingChanged(false);

      expect(s.records.map((r) => (r.trackId, r.ms ~/ 60000)).toList(),
          [('a', 3), ('b', 2)]);
    });

    test('a replay of the same track (repeat one) is a new play', () async {
      final c = _Clock(DateTime(2026, 10, 15, 20));
      final s = ListeningStats(clock: c.call);
      await s.load();
      s.onTrackChanged(_t('a'));
      s.onPlayingChanged(true);
      c.advance(const Duration(minutes: 3));
      s.onTrackChanged(null); // what MusicProvider does before replaying
      s.onTrackChanged(_t('a'));
      c.advance(const Duration(minutes: 3));
      s.onPlayingChanged(false);
      expect(s.records.map((r) => r.trackId), ['a', 'a']);
    });

    test('pause and resume on one track is one play, not two', () async {
      final c = _Clock(DateTime(2026, 10, 15, 20));
      final s = ListeningStats(clock: c.call);
      await s.load();
      s.onTrackChanged(_t('a'));
      s.onPlayingChanged(true);
      c.advance(const Duration(minutes: 1));
      s.onPlayingChanged(false);
      c.advance(const Duration(minutes: 10));
      s.onPlayingChanged(true);
      c.advance(const Duration(minutes: 1));
      s.onPlayingChanged(false);
      expect(s.records, hasLength(1));
      expect(s.records.single.ms, 2 * 60000);
    });

    test('the log and its tracks survive a restart', () async {
      final c = _Clock(DateTime(2026, 10, 15, 20));
      final a = ListeningStats(clock: c.call);
      await a.load();
      _play(a, c, _t('a', genre: 'Electronic'), const Duration(minutes: 4));
      await Future<void>.delayed(Duration.zero);

      final b = ListeningStats(clock: c.call);
      await b.load();
      expect(b.records.single.trackId, 'a');
      expect(b.tracks['a']!.title, 'Song a');
      expect(b.tracks['a']!.genre, 'Electronic');
    });

    test('a play recorded before the stored log is read does not overwrite it',
        () async {
      final c = _Clock(DateTime(2026, 10, 15, 20));
      final first = ListeningStats(clock: c.call);
      await first.load();
      _play(first, c, _t('old'), const Duration(minutes: 30));
      await Future<void>.delayed(Duration.zero);

      // Next launch: music starts before the log has loaded.
      final next = ListeningStats(clock: c.call);
      _play(next, c, _t('new'), const Duration(minutes: 5));
      await next.load();
      expect(next.records.map((r) => r.trackId), ['old', 'new']);
      await Future<void>.delayed(Duration.zero);

      final again = ListeningStats(clock: c.call);
      await again.load();
      expect(again.records.map((r) => r.trackId), ['old', 'new'],
          reason: 'both survived, neither twice');
    });

    test('clear forgets everything', () async {
      final c = _Clock(DateTime(2026, 10, 15, 20));
      final s = ListeningStats(clock: c.call);
      await s.load();
      _play(s, c, _t('a'), const Duration(minutes: 4));
      await s.clear();
      expect(s.records, isEmpty);
      expect(s.msThisYear, 0);
    });
  });

  group('the summary', () {
    late _Clock c;
    late ListeningStats s;
    setUp(() async {
      c = _Clock(DateTime(2026, 9, 28, 19, 30));
      s = ListeningStats(clock: c.call);
      await s.load();
    });

    test('ranks songs by plays, then minutes', () {
      // Interleaved: the same track twice in a row is one play (pause/resume).
      for (final (id, m) in const [
        ('a', 3), ('b', 3), ('c', 10), ('a', 3), ('b', 3), ('c', 10), ('a', 3),
      ]) {
        _play(s, c, _t(id), Duration(minutes: m));
      }
      final r = ReplaySummary.of(s, ReplayPeriod.year, now: c.now);
      expect(r.topSongs.map((e) => e.key), ['a', 'c', 'b']);
      expect(r.topSongs.first.plays, 3);
      expect(r.plays, 7);
    });

    test('a skip adds minutes but is not a play', () {
      _play(s, c, _t('a'), const Duration(seconds: 12));
      _play(s, c, _t('b'), const Duration(minutes: 2));
      final r = ReplaySummary.of(s, ReplayPeriod.year, now: c.now);
      expect(r.plays, 1);
      expect(r.topSongs.map((e) => e.key), ['b']);
      expect(r.totalMs, 12000 + 120000);
    });

    test('a duet credits both artists', () {
      _play(s, c, _t('a', artist: 'Justice & Tame Impala'), const Duration(minutes: 3));
      _play(s, c, _t('b', artist: 'Tame Impala'), const Duration(minutes: 3));
      final r = ReplaySummary.of(s, ReplayPeriod.year, now: c.now);
      expect(r.topArtists.first.title, 'Tame Impala');
      expect(r.topArtists.first.plays, 2);
      expect(r.topArtists.map((e) => e.title), contains('Justice'));
      expect(ReplaySummary.splitArtists('Gym Class Heroes feat. Adam Levine'),
          ['Gym Class Heroes', 'Adam Levine']);
    });

    test('singles are not albums', () {
      _play(s, c, Track(id: 's', trackName: 'Loser', artistName: 'X', albumName: 'Loser', previewUrl: ''),
          const Duration(minutes: 3));
      _play(s, c, _t('a', album: 'Currents'), const Duration(minutes: 3));
      final r = ReplaySummary.of(s, ReplayPeriod.year, now: c.now);
      expect(r.topAlbums.map((e) => e.title), ['Currents']);
    });

    test('genres only when the source gave one', () {
      _play(s, c, _t('a'), const Duration(minutes: 3));
      expect(ReplaySummary.of(s, ReplayPeriod.year, now: c.now).topGenres, isEmpty);
      _play(s, c, _t('b', genre: 'Electronic'), const Duration(minutes: 3));
      expect(ReplaySummary.of(s, ReplayPeriod.year, now: c.now).topGenres.single.title,
          'Electronic');
    });

    test('periods filter by when the play started', () {
      _play(s, c, _t('sept'), const Duration(minutes: 3)); // Sept 2026
      c.now = DateTime(2025, 12, 1, 10);
      _play(s, c, _t('lastyear'), const Duration(minutes: 3));
      c.now = DateTime(2026, 10, 2, 10);
      _play(s, c, _t('oct'), const Duration(minutes: 3));

      Set<String> keys(ReplayPeriod p) =>
          ReplaySummary.of(s, p, now: c.now).topSongs.map((e) => e.key).toSet();
      expect(keys(ReplayPeriod.month), {'oct'});
      expect(keys(ReplayPeriod.year), {'oct', 'sept'});
      expect(keys(ReplayPeriod.allTime), {'oct', 'sept', 'lastyear'});
      expect(ReplaySummary.of(s, ReplayPeriod.month, now: c.now).memberSince!.year, 2025,
          reason: 'member since is the first play ever');
    });

    test('peak hour and biggest day', () {
      _play(s, c, _t('a'), const Duration(minutes: 20)); // 19:30 on the 28th
      c.now = DateTime(2026, 9, 29, 8);
      _play(s, c, _t('b'), const Duration(minutes: 5));
      final r = ReplaySummary.of(s, ReplayPeriod.year, now: c.now);
      expect(r.peakHour, 19);
      expect(r.biggestDay, DateTime(2026, 9, 28));
      expect(r.biggestDayMs, 20 * 60000);
      expect(r.distinctSongs, 2);
    });

    test('the session still playing is shown live', () {
      s.onTrackChanged(_t('a'));
      s.onPlayingChanged(true);
      c.advance(const Duration(minutes: 4));
      final r = ReplaySummary.of(s, ReplayPeriod.year, now: c.now);
      expect(r.minutes, 4);
      expect(r.topSongs.single.key, 'a');
    });

    test('formatting', () {
      expect(formatListenTime(167 * 60000), '2h 47m');
      expect(formatListenTime(48 * 60000), '48 min');
      expect(formatListenTime(120 * 60000), '2h');
      expect(formatListenTime(1000), '<1 min');
      expect(formatHour(20), '8 PM');
      expect(formatHour(0), 'midnight');
      expect(memberSinceLabel(DateTime(2026, 9, 3)), '09/26');
    });
  });

  group('faces and pages say only what is true', () {
    test('a new listener gets the minutes face alone, and a short story', () {
      final r = ReplaySummary.compute(
          records: const [], tracks: const {}, period: ReplayPeriod.year, now: DateTime(2026));
      expect(r.isEmpty, isTrue);
      expect(ReplayFace.of(r).map((f) => f.label), ['MINUTES LISTENED']);
      expect(ReplayStoryScreen.pagesFor(r), ['intro', 'minutes', 'outro']);
    });

    test('a full year has all four faces', () async {
      final c = _Clock(DateTime(2026, 9, 28, 20));
      final s = ListeningStats(clock: c.call);
      await s.load();
      _play(s, c, _t('a', genre: 'Pop'), const Duration(minutes: 3));
      final r = ReplaySummary.of(s, ReplayPeriod.year, now: c.now);
      expect(ReplayFace.of(r).map((f) => f.label),
          ['MINUTES LISTENED', 'TOP SONG', 'TOP ARTIST', 'TOP ALBUM']);
      expect(ReplayStoryScreen.pagesFor(r),
          ['intro', 'minutes', 'song', 'artists', 'albums', 'genres', 'pattern', 'outro']);
      expect(replayShareText(r), contains('Top song: Song a - Tame Impala'));
    });
  });

  group('the Replay screen', () {
    Future<_FakeProvider> pump(WidgetTester tester,
        {bool withPlays = true, Size size = const Size(412, 2600)}) async {
      final c = _Clock(DateTime(2026, 9, 28, 20));
      final s = ListeningStats(clock: c.call);
      await tester.runAsync(s.load);
      if (withPlays) {
        _play(s, c, _t('a'), const Duration(minutes: 30));
        _play(s, c, _t('b', artist: 'Bruno Mars', album: 'Unorthodox Jukebox'),
            const Duration(minutes: 10));
      }
      final p = _FakeProvider(s);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
        value: p,
        child: MaterialApp(home: ReplayScreen(now: c.now)),
      ));
      await tester.pump(const Duration(seconds: 2));
      return p;
    }

    testWidgets('shows the sections the summary has', (tester) async {
      await pump(tester);
      expect(find.text('Replay'), findsOneWidget);
      expect(find.text('Play your Replay'), findsOneWidget);
      expect(find.text('Top songs'), findsOneWidget);
      expect(find.text('Top artists'), findsOneWidget);
      expect(find.text('Top albums'), findsOneWidget);
      expect(find.text('Top genres'), findsNothing, reason: 'no genre tags');
      expect(find.text('Your listening pattern'), findsOneWidget);
      expect(find.text('You listen most around 8 PM.'), findsOneWidget);
      expect(find.text('Share my Replay'), findsOneWidget);
    });

    testWidgets('lays out on a small phone without overflow', (tester) async {
      await pump(tester, size: const Size(360, 2600));
      expect(tester.takeException(), isNull);
      // Swipe the card wallet to the top-song face.
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      expect(find.text('TOP SONG'), findsOneWidget);
    });

    testWidgets('Play plays the top songs in order', (tester) async {
      final p = await pump(tester);
      await tester.tap(find.bySemanticsLabel('Play top songs'));
      await tester.pump();
      expect(p.played, ['a']);
    });

    testWidgets('switching period re-summarises', (tester) async {
      await pump(tester);
      await tester.tap(find.text('All time'));
      await tester.pump(); // the switch starts on this frame
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('All time'), findsWidgets);
      expect(find.text('Top songs'), findsOneWidget);
    });

    testWidgets('nothing played: an honest empty state, no empty sections', (tester) async {
      await pump(tester, withPlays: false);
      expect(find.text('Your Replay starts here'), findsOneWidget);
      expect(find.text('Top songs'), findsNothing);
      expect(find.text('Play your Replay'), findsNothing);
    });
  });

  group('the story', () {
    Future<ReplaySummary> summary() async {
      final c = _Clock(DateTime(2026, 9, 28, 20));
      final s = ListeningStats(clock: c.call);
      await s.load();
      _play(s, c, _t('a'), const Duration(minutes: 30));
      return ReplaySummary.of(s, ReplayPeriod.year, now: c.now);
    }

    testWidgets('advances on its own, on tap, and back', (tester) async {
      final s = await tester.runAsync(summary);
      await tester.pumpWidget(MaterialApp(
        home: ReplayStoryScreen(summary: s!, pageDuration: const Duration(seconds: 1)),
      ));
      expect(find.text('Page 1 of 7'), findsNothing); // label is semantic only
      expect(find.textContaining('is ready'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('MINUTES'), findsOneWidget, reason: 'auto-advanced');

      // Tap the right side: next.
      await tester.tapAt(const Offset(700, 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Song a'), findsOneWidget);

      // Tap the left side: back.
      await tester.tapAt(const Offset(20, 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('MINUTES'), findsOneWidget);

      // Leave before the timers matter.
      await tester.pumpWidget(const SizedBox());
    });

    for (final size in const [Size(360, 640), Size(412, 915), Size(800, 500)]) {
      testWidgets('every page fits at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        final r = await tester.runAsync(() async {
          final c = _Clock(DateTime(2026, 9, 28, 20));
          final s = ListeningStats(clock: c.call);
          await s.load();
          for (var i = 0; i < 6; i++) {
            _play(s, c, _t('t$i', artist: 'Artist with a fairly long name $i',
                album: 'An album title that goes on and on $i', genre: 'Genre $i'),
                Duration(minutes: 10 - i));
          }
          return ReplaySummary.of(s, ReplayPeriod.year, now: c.now);
        });
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(
          home: ReplayStoryScreen(summary: r!, pageDuration: const Duration(seconds: 30)),
        ));
        final pages = ReplayStoryScreen.pagesFor(r);
        expect(pages, hasLength(8));
        for (var i = 0; i < pages.length - 1; i++) {
          await tester.pump(const Duration(milliseconds: 900));
          expect(tester.takeException(), isNull, reason: 'page ${pages[i]}');
          await tester.tapAt(Offset(size.width - 20, size.height / 2));
        }
        await tester.pump(const Duration(milliseconds: 900));
        expect(tester.takeException(), isNull, reason: 'outro');
        expect(find.textContaining('your '), findsWidgets);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('holding pauses it', (tester) async {
      final s = await tester.runAsync(summary);
      await tester.pumpWidget(MaterialApp(
        home: ReplayStoryScreen(summary: s!, pageDuration: const Duration(seconds: 1)),
      ));
      final g = await tester.startGesture(const Offset(400, 400));
      await tester.pump(const Duration(milliseconds: 600)); // long press begins
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('is ready'), findsOneWidget, reason: 'paused');
      await g.up();
      await tester.pumpWidget(const SizedBox());
    });
  });
}