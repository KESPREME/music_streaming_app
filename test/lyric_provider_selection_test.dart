import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_service.dart';

import 'support/fake_lyrics_world.dart';

const _ms = Duration(milliseconds: 1);

Track track(String title, {int? durationMs = 237000}) => Track(
      id: 'vid_$title',
      trackName: title,
      artistName: 'Tame Impala',
      albumName: 'Currents',
      previewUrl: '',
      durationMs: durationMs,
    );

/// The text of the first sung line, which is what "which lyrics" means here.
String? firstLine(MusicProvider p) {
  final lines = p.currentLyrics;
  if (lines == null) return null;
  for (final l in lines) {
    if (!l.isMusicalBreak) return l.text;
  }
  return null;
}

Future<void> settle([int ms = 60]) => Future<void>.delayed(_ms * ms);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLyricsWorld world;
  late MusicProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    world = FakeLyricsWorld();
    // Short enough that a test never waits on the real 4s / 10s.
    world.service.raceGrace = _ms * 30;
    provider = MusicProvider(lyricsService: world.service);
    provider.debugSetCurrentTrack(track('Borderline'));
  });

  tearDown(() {
    try {
      provider.dispose();
    } catch (_) {
      // Tearing down audio plumbing that never started is not interesting.
    }
  });

  group('what the lookup leaves behind', () {
    test('the winner is shown, and its row is checked', () async {
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('winner'));

      await provider.fetchLyrics();

      expect(firstLine(provider), 'winner');
      expect(provider.lyricsSourceProvider, LyricsProvider.lrcRed);
      expect(provider.lyricsStateOf(LyricsProvider.lrcRed), ProviderState.found);
    });

    test('every provider\'s answer is kept, not just the winner\'s', () async {
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('winner'));
      world[LyricsProvider.kugou].reply(lineSyncedLines('other'), delay: _ms * 20);

      await provider.fetchLyrics();
      await settle();

      expect(provider.lyricsStateOf(LyricsProvider.kugou), ProviderState.found);
      // Misses are recorded as misses.
      expect(provider.lyricsStateOf(LyricsProvider.unison), ProviderState.notFound);
      // And what was never asked stays "not searched".
      expect(provider.lyricsStateOf(LyricsProvider.genius), ProviderState.notFetched);
    });

    test('nothing found: says so, and does not claim a source', () async {
      await provider.fetchLyrics();
      await settle();

      expect(provider.currentLyrics, isEmpty);
      expect(provider.lyricsError, 'No lyrics found');
      expect(provider.lyricsSourceProvider, isNull);
      expect(provider.isLoadingLyrics, isFalse);
    });

    test('a cache hit still checks its row', () async {
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('cached'));
      await provider.fetchLyrics();

      final again = MusicProvider(lyricsService: world.service)
        ..debugSetCurrentTrack(track('Borderline'));
      addTearDown(() {
        try {
          again.dispose();
        } catch (_) {}
      });
      await again.fetchLyrics();

      expect(again.lyricsSourceProvider, LyricsProvider.lrcRed);
      expect(again.lyricsStateOf(LyricsProvider.lrcRed), ProviderState.found);
    });
  });

  group('choosing a provider', () {
    test('FOUND: switches at once, and the lyrics are never null on the way',
        () async {
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('first'));
      world[LyricsProvider.kugou].reply(lineSyncedLines('second'), delay: _ms * 20);
      await provider.fetchLyrics();
      await settle();

      final seen = <String?>[];
      provider.addListener(() => seen.add(firstLine(provider)));

      await provider.selectLyricsProvider(LyricsProvider.kugou);

      expect(firstLine(provider), 'second');
      expect(provider.lyricsSourceProvider, LyricsProvider.kugou);
      expect(provider.selectedLyricsProvider, LyricsProvider.kugou);
      expect(seen, isNotEmpty);
      // The old switch nulled the lyrics and refetched: the panel went to its
      // skeleton and cross-faded two copies of every line.
      expect(seen.contains(null), isFalse);
      expect(provider.isLoadingLyrics, isFalse);
    });

    test('FETCHING: the choice is remembered and applied the moment it lands',
        () async {
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('first'));
      world[LyricsProvider.unison]
          .reply(wordSyncedLines('slow'), delay: _ms * 120);
      await provider.fetchLyrics();
      expect(provider.lyricsStateOf(LyricsProvider.unison), ProviderState.fetching);

      await provider.selectLyricsProvider(LyricsProvider.unison);
      expect(firstLine(provider), 'first', reason: 'nothing changes until it lands');
      expect(provider.selectedLyricsProvider, LyricsProvider.unison);

      await settle(200);
      expect(firstLine(provider), 'slow');
      expect(provider.lyricsSourceProvider, LyricsProvider.unison);
    });

    test('NOT FETCHED: it is asked on its own, and shown when it answers',
        () async {
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('first'));
      world[LyricsProvider.genius].reply(plainLines('from genius'));
      await provider.fetchLyrics();
      await settle();
      // Lazy, and something answered: Genius was never asked.
      expect(provider.lyricsStateOf(LyricsProvider.genius), ProviderState.notFetched);
      expect(world[LyricsProvider.genius].calls, 0);

      await provider.selectLyricsProvider(LyricsProvider.genius);
      await settle();

      expect(world[LyricsProvider.genius].calls, 1);
      expect(firstLine(provider), 'from genius');
      expect(provider.lyricsSourceProvider, LyricsProvider.genius);
      expect(provider.lyricsStateOf(LyricsProvider.genius), ProviderState.found);
    });

    test('NOT FOUND: choosing it does nothing', () async {
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('first'));
      await provider.fetchLyrics();
      await settle();
      final callsBefore = world[LyricsProvider.unison].calls;

      await provider.selectLyricsProvider(LyricsProvider.unison);
      await settle();

      expect(firstLine(provider), 'first');
      expect(provider.selectedLyricsProvider, isNull);
      expect(world[LyricsProvider.unison].calls, callsBefore);
    });

    test('a chosen source that has nothing hands the screen back to the race',
        () async {
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('first'));
      await provider.fetchLyrics();
      await settle();
      // Not found by the race, but a dedicated fetch will find nothing either.
      world[LyricsProvider.genius].reply(null);

      await provider.selectLyricsProvider(LyricsProvider.genius);
      await settle();

      expect(provider.lyricsStateOf(LyricsProvider.genius), ProviderState.notFound);
      expect(provider.selectedLyricsProvider, isNull);
      expect(firstLine(provider), 'first');
    });

    test('the choice becomes the cached lyric for the next play', () async {
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('first'));
      world[LyricsProvider.kugou].reply(lineSyncedLines('second'), delay: _ms * 20);
      await provider.fetchLyrics();
      await settle();

      await provider.selectLyricsProvider(LyricsProvider.kugou);
      await settle();

      final next = await world.service.lookup(
        title: 'Borderline',
        artist: 'Tame Impala',
        videoId: 'vid_Borderline',
        durationMs: 237000,
      );
      expect(next.provider, LyricsProvider.kugou);
    });
  });

  group('a source the race gave up on', () {
    test('goes back to "not searched", and a choice made meanwhile is fetched '
        'on its own', () async {
      world.service.raceDeadline = _ms * 100;
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('first'));
      var unisonCalls = 0;
      world[LyricsProvider.unison].answer = (_) async {
        unisonCalls++;
        // The first ask hangs past the deadline; the dedicated one is quick.
        if (unisonCalls == 1) await Future<void>.delayed(_ms * 500);
        return wordSyncedLines('rescued');
      };

      await provider.fetchLyrics();
      await provider.selectLyricsProvider(LyricsProvider.unison); // still fetching
      expect(provider.lyricsStateOf(LyricsProvider.unison), ProviderState.fetching);

      await settle(400);

      expect(unisonCalls, 2, reason: 'asked again, alone, after being cut off');
      expect(firstLine(provider), 'rescued');
      expect(provider.lyricsSourceProvider, LyricsProvider.unison);
    });

    test('with no choice made it simply goes back to "not searched"', () async {
      world.service.raceDeadline = _ms * 80;
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('first'));
      world[LyricsProvider.unison].reply(null, delay: _ms * 400);

      await provider.fetchLyrics();
      expect(provider.lyricsStateOf(LyricsProvider.unison), ProviderState.fetching);
      await settle(200);

      expect(provider.lyricsStateOf(LyricsProvider.unison), ProviderState.notFetched);
    });
  });

  group('a track change', () {
    test('discards a stale lookup\'s reports', () async {
      world[LyricsProvider.kugou].answer = (args) async {
        if (args['title'] == 'Old') {
          await Future<void>.delayed(_ms * 120);
          return lineSyncedLines('old song');
        }
        return null;
      };

      provider.debugSetCurrentTrack(track('Old'));
      final oldLookup = provider.fetchLyrics();
      await settle(10);

      provider.debugSetCurrentTrack(track('New'));
      await provider.fetchLyrics();
      await oldLookup;
      await settle(200);

      // The old song's late answer did not land on the new song.
      expect(provider.lyricsStateOf(LyricsProvider.kugou), ProviderState.notFound);
      expect(provider.currentLyrics?.any((e) => e.text.contains('old song')) ?? false,
          isFalse);
    });

    test('is the one thing that clears the lyrics and the selection', () async {
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('first'));
      world[LyricsProvider.kugou].reply(lineSyncedLines('second'), delay: _ms * 20);
      await provider.fetchLyrics();
      await settle();
      await provider.selectLyricsProvider(LyricsProvider.kugou);

      provider.debugSetCurrentTrack(track('Another'));
      final next = provider.fetchLyrics();
      expect(provider.currentLyrics, isNull);
      expect(provider.selectedLyricsProvider, isNull);
      expect(provider.lyricsProviderStates, isEmpty);
      await next;
    });
  });

  group('changing the sources', () {
    test('re-runs the lookup without blanking the lyrics on screen', () async {
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('first'));
      await provider.fetchLyrics();
      await settle();

      final seen = <String?>[];
      provider.addListener(() => seen.add(firstLine(provider)));
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('after the change'));

      provider.refreshLyricsForSourceChange();
      await settle(120);

      expect(seen.contains(null), isFalse);
      expect(firstLine(provider), 'after the change');
    });
  });

  group('waiting for the length', () {
    test('no lookup starts until the length is known', () async {
      provider.debugSetCurrentTrack(track('NoLength', durationMs: null));
      world[LyricsProvider.kugou].reply(lineSyncedLines('x'));

      await provider.fetchLyrics();
      await settle();

      expect(world.log, isEmpty);
      expect(provider.isLoadingLyrics, isTrue);
    });

    test('and starts as soon as the player reports one', () async {
      provider.debugSetCurrentTrack(track('NoLength', durationMs: null));
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('now'));
      await provider.fetchLyrics();

      provider.debugSetDuration(const Duration(minutes: 3));
      await settle(120);

      expect(firstLine(provider), 'now');
    });

    test('a stream that never reports one is not waited on forever', () async {
      provider.lyricsDurationPatience = _ms * 40;
      provider.debugSetCurrentTrack(track('NoLength', durationMs: null));
      world[LyricsProvider.lrcRed].reply(wordSyncedLines('anyway'));

      await provider.fetchLyrics();
      await settle(200);

      expect(firstLine(provider), 'anyway');
    });
  });

  group('the word-sync preference', () {
    test('defaults ON', () {
      expect(provider.prioritizeSyllableSync, isTrue);
    });
  });
}
