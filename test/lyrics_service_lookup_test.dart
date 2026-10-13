import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/bini_lyrics_provider.dart';
import 'package:music_streaming_app/services/lyrics/lyric_timings_codec.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_service.dart';
import 'package:music_streaming_app/services/lyrics/lyric_words.dart';
import 'package:music_streaming_app/services/lyrics/provider_race.dart';

import 'support/fake_lyrics_world.dart';

const _ms = Duration(milliseconds: 1);

/// Shorthand: a lookup of a fixed track.
Future<LyricsLookupResult> lookup(
  FakeLyricsWorld w, {
  String title = 'Borderline',
  String artist = 'Tame Impala',
  String? album,
  int? durationMs = 237000,
  String? videoId,
  bool prioritize = true,
  bool syncedOnly = false,
  LyricsProvider? only,
  bool skipCache = false,
  bool prefetch = false,
  LyricsRaceCallbacks callbacks = const LyricsRaceCallbacks(),
}) =>
    w.service.lookup(
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      videoId: videoId,
      prioritizeSyllable: prioritize,
      syncedOnly: syncedOnly,
      onlyProvider: only,
      skipCache: skipCache,
      prefetch: prefetch,
      callbacks: callbacks,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('the query is cleaned once, and the album is real', () {
    test('providers see the cleaned name, not YouTube\'s', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.kugou].reply(lineSyncedLines('x'));

      await lookup(
        w,
        title: 'Dracula (feat. JENNIE) [Official Video]',
        artist: 'Tame Impala - Topic',
        prioritize: false,
      );

      final seen = w[LyricsProvider.kugou].last!.args;
      expect(seen['title'], 'Dracula');
      expect(seen['artist'], 'Tame Impala');
    });

    test('a real album reaches the sources; the placeholder does not', () async {
      final w = FakeLyricsWorld();
      await lookup(w, album: 'Currents', prioritize: true);
      for (final p in [
        LyricsProvider.kugou,
        LyricsProvider.unison,
        LyricsProvider.lyricsPlus,
        LyricsProvider.lrcRed,
      ]) {
        expect(w[p].last!.args['album'], 'Currents', reason: '$p');
      }
      expect(w.lrcLibCalls.single['album'], 'Currents');

      final w2 = FakeLyricsWorld();
      await lookup(w2, album: 'Unknown Album');
      expect(w2[LyricsProvider.kugou].last!.args['album'], isNull);
      expect(w2[LyricsProvider.unison].last!.args['album'], isNull);
    });

    test('an unknown length is passed as null, not 0', () async {
      final w = FakeLyricsWorld();
      await lookup(w, durationMs: 0);
      expect(w[LyricsProvider.kugou].last!.args['durationMs'], isNull);
    });
  });

  group('judge', () {
    LyricsVerdict judge(List<LyricsEntry> e,
            {bool prioritize = true,
            bool syncedOnly = false,
            bool manual = false}) =>
        LyricsService.judge(e,
            prioritizeSyllable: prioritize,
            syncedOnly: syncedOnly,
            manual: manual);

    test('word-synced is accepted at once, whatever the setting', () {
      expect(judge(wordSyncedLines('a')), LyricsVerdict.accept);
      expect(judge(wordSyncedLines('a'), prioritize: false), LyricsVerdict.accept);
    });

    test('line-synced is held with prioritize ON, accepted with it OFF', () {
      expect(judge(lineSyncedLines('a')), LyricsVerdict.hold);
      expect(judge(lineSyncedLines('a'), prioritize: false), LyricsVerdict.accept);
    });

    test('plain text is the last resort, or refused with "synced only"', () {
      expect(judge(plainLines('a')), LyricsVerdict.holdPlain);
      expect(judge(plainLines('a'), prioritize: false), LyricsVerdict.holdPlain);
      expect(judge(plainLines('a'), syncedOnly: true), LyricsVerdict.reject);
    });

    test('a manual choice is accepted whatever it is', () {
      expect(judge(plainLines('a'), manual: true, syncedOnly: true),
          LyricsVerdict.accept);
      expect(judge(lineSyncedLines('a'), manual: true), LyricsVerdict.accept);
    });

    test('nothing is rejected', () {
      expect(judge(const []), LyricsVerdict.reject);
    });
  });

  group('the race, through the service', () {
    test('prioritize ON: a word-synced answer inside the grace beats a line-'
        'synced one that came first', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.kugou].reply(lineSyncedLines('line'));
      w[LyricsProvider.lyricsPlus]
          .reply(wordSyncedLines('word'), delay: _ms * 40);
      w.service.raceGrace = _ms * 500;

      final r = await lookup(w);
      expect(r.provider, LyricsProvider.lyricsPlus);
      expect(r.isFallback, isFalse);
    });

    test('prioritize ON: the line-synced answer is used when the grace runs '
        'out', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.kugou].reply(lineSyncedLines('line'));
      w[LyricsProvider.unison]
          .reply(wordSyncedLines('too late'), delay: _ms * 600);
      w.service.raceGrace = _ms * 50;

      final r = await lookup(w);
      expect(r.provider, LyricsProvider.kugou);
      expect(r.isFallback, isTrue);
    });

    test('prioritize OFF: the first line-synced answer wins at once', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.kugou].reply(lineSyncedLines('line'));
      w[LyricsProvider.unison].reply(wordSyncedLines('word'), delay: _ms * 40);

      final r = await lookup(w, prioritize: false);
      expect(r.provider, LyricsProvider.kugou);
    });

    test('a plain answer ahead of a synced one never beats it', () async {
      final w = FakeLyricsWorld();
      // LyricsPlus ranks ahead of KuGou in the default order.
      w[LyricsProvider.lyricsPlus].reply(plainLines('plain'));
      w[LyricsProvider.kugou].reply(lineSyncedLines('synced'));

      final r = await lookup(w, prioritize: false);
      expect(r.provider, LyricsProvider.kugou);
    });

    test('"synced only" refuses a plain answer; otherwise it is the fallback',
        () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.lyricsPlus].reply(plainLines('plain'));
      w.service.raceGrace = _ms * 20;

      expect((await lookup(w, syncedOnly: true)).isEmpty, isTrue);

      final w2 = FakeLyricsWorld();
      w2[LyricsProvider.lyricsPlus].reply(plainLines('plain'));
      w2.service.raceGrace = _ms * 20;
      final r = await lookup(w2);
      expect(r.provider, LyricsProvider.lyricsPlus);
      expect(r.isFallback, isTrue);
    });

    test('Genius is not asked while anything has answered, and is asked when '
        'everything missed', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.kugou].reply(lineSyncedLines('line'));
      w[LyricsProvider.genius].reply(plainLines('genius'));
      w.service.raceGrace = _ms * 20;
      await lookup(w, prioritize: false);
      expect(w[LyricsProvider.genius].calls, 0);

      final w2 = FakeLyricsWorld();
      w2[LyricsProvider.genius].reply(plainLines('genius'));
      w2.service.raceGrace = _ms * 20;
      final r = await lookup(w2);
      expect(w2[LyricsProvider.genius].calls, 1);
      expect(r.provider, LyricsProvider.genius);
    });

    test('LRCLIB is asked ONCE, not once per spelling variant', () async {
      final w = FakeLyricsWorld();
      await lookup(w, title: 'Song (feat. X) (Remastered 2011)');
      expect(w.lrcLibCalls, hasLength(1));
    });

    test('an LRC answer from LRCLIB is line-synced, never word-synced', () async {
      final w = FakeLyricsWorld();
      w.lrcLibAnswer = '[00:05.00]hello there world\n[00:09.00]second line';
      w.service.raceGrace = _ms * 20;

      final r = await lookup(w, prioritize: false);
      expect(r.provider, LyricsProvider.lrclib);
      expect(r.entries.any((e) => e.isWordSynced), isFalse);
    });

    test('a manual choice ignores the enabled set, the order and the settings',
        () async {
      final w = FakeLyricsWorld();
      await w.service.setProviderEnabled(LyricsProvider.genius, false);
      w[LyricsProvider.genius].reply(plainLines('genius'));

      final r = await lookup(w, only: LyricsProvider.genius, syncedOnly: true);

      expect(r.provider, LyricsProvider.genius);
      // Only that source was asked.
      expect(w.log.map((c) => c.provider).toSet(), {LyricsProvider.genius});
      // And it left the shared cache alone.
      expect(w.cache.puts, 0);
    });
  });

  group('recording id (ISRC)', () {
    BiniHit hit() => const BiniHit(
          isrc: 'AUUM71900956',
          lyricsUrl: 'https://lrc.red/s/AUUM71900956.ttml',
        );

    test('Bini identifies once; lrc.red and LyricsPlus get the ISRC; Bini '
        'reuses the hit', () async {
      final w = FakeLyricsWorld()..identifyAnswer = () async => hit();
      w.service.raceGrace = _ms * 20;

      await lookup(w);

      expect(w.identifyCalls, 1);
      expect(w[LyricsProvider.lrcRed].last!.args['isrc'], 'AUUM71900956');
      expect(w[LyricsProvider.lyricsPlus].last!.args['isrc'], 'AUUM71900956');
      expect(w[LyricsProvider.biniLyrics].last!.args['hit'], 'AUUM71900956');
    });

    test('a track\'s ISRC is remembered, so a second lookup does not identify '
        'again', () async {
      final w = FakeLyricsWorld()..identifyAnswer = () async => hit();
      w.service.raceGrace = _ms * 20;

      await lookup(w);
      await lookup(w, skipCache: true);

      expect(w.identifyCalls, 1);
      expect(w[LyricsProvider.lrcRed].last!.args['isrc'], 'AUUM71900956');
    });

    test('an identify miss does not stop the sources that only prefer an ISRC',
        () async {
      final w = FakeLyricsWorld()..identifyAnswer = () async => null;
      w[LyricsProvider.lrcRed].reply(wordSyncedLines('by name'));

      final r = await lookup(w);

      expect(r.provider, LyricsProvider.lrcRed);
      expect(w[LyricsProvider.lrcRed].last!.args['isrc'], isNull);
      // Bini had no recording to fetch.
      expect(w[LyricsProvider.biniLyrics].calls, 0);
    });

    test('a slow identify is abandoned at its deadline, not waited for',
        () async {
      final w = FakeLyricsWorld()
        ..identifyAnswer = () async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return hit();
        };
      w.service.identifyTimeout = _ms * 60;
      w[LyricsProvider.lrcRed].reply(wordSyncedLines('by name'));

      final stopwatch = Stopwatch()..start();
      final r = await lookup(w);

      expect(r.provider, LyricsProvider.lrcRed);
      expect(stopwatch.elapsedMilliseconds, lessThan(1500));
      expect(w[LyricsProvider.lrcRed].last!.args['isrc'], isNull);
    });

    test('the sources that do not use an ISRC start without waiting for the '
        'identify', () async {
      final w = FakeLyricsWorld()
        ..identifyAnswer = () async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return hit();
        };
      w[LyricsProvider.kugou].reply(lineSyncedLines('line'));

      final r = await lookup(w, prioritize: false);

      // KuGou answered while the identify was still out; lrc.red (ahead of it)
      // is waiting on the identify and misses, so KuGou is the winner.
      expect(r.provider, LyricsProvider.kugou);
    });

    test('Bini and lrc.red share one download of the same document', () async {
      final w = FakeLyricsWorld()..identifyAnswer = () async => hit();
      w.lrcRed.documentUrl = 'https://lrc.red/s/AUUM71900956.ttml';
      w.biniDocumentUrl = 'https://lrc.red/s/AUUM71900956.ttml';
      w.service.raceGrace = _ms * 20;

      await lookup(w);

      expect(w.documentRequests, ['https://lrc.red/s/AUUM71900956.ttml']);
    });

    test('with Bini switched off the app does not contact it', () async {
      final w = FakeLyricsWorld()..identifyAnswer = () async => hit();
      await w.service.setProviderEnabled(LyricsProvider.biniLyrics, false);

      await lookup(w);

      expect(w.identifyCalls, 0);
    });
  });

  group('in-flight lookups', () {
    test('two callers for one track share one lookup, and the second is '
        'replayed what it missed', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.kugou].reply(lineSyncedLines('line'), delay: _ms * 60);
      w.service.raceGrace = _ms * 20;

      final firstEvents = <String>[];
      final secondEvents = <String>[];
      LyricsRaceCallbacks recorder(List<String> into) => LyricsRaceCallbacks(
            onStarted: (p) => into.add('start ${p.name}'),
            onResult: (p, e) => into.add('result ${p.name} ${e != null}'),
          );

      final first = lookup(w, callbacks: recorder(firstEvents));
      await Future<void>.delayed(_ms * 20); // lrc.red etc. have started by now
      final second = lookup(w, callbacks: recorder(secondEvents));
      final results = await Future.wait([first, second]);

      expect(w[LyricsProvider.kugou].calls, 1, reason: 'one lookup, not two');
      expect(results[0].provider, results[1].provider);
      expect(secondEvents, containsAll(firstEvents),
          reason: 'the joiner is told everything the first already heard');
    });

    test('a manual fetch never joins an automatic lookup', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.kugou].reply(lineSyncedLines('auto'), delay: _ms * 80);
      w.service.raceGrace = _ms * 20;

      final auto = lookup(w, prioritize: false);
      await Future<void>.delayed(_ms * 10);
      final manual = lookup(w, only: LyricsProvider.kugou, skipCache: true);
      await Future.wait([auto, manual]);

      // Asked twice: once by the race, once on its own.
      expect(w[LyricsProvider.kugou].calls, 2);
    });
  });

  group('caching', () {
    test('a word-synced result survives the disk round trip', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.lrcRed].reply(wordSyncedLines('hello'));

      final live = await lookup(w);
      expect(live.fromCache, isFalse);
      expect(w.cache.puts, 1);

      // A fresh service over the same cache: nothing in memory.
      final w2 = FakeLyricsWorld();
      w2.cache.rows.addAll(w.cache.rows);
      final fresh = LyricsService.forTesting(
        cache: w2.cache,
        keys: w2.keys,
      );
      final cached = await fresh.lookup(
        title: 'Borderline',
        artist: 'Tame Impala',
        durationMs: 237000,
      );

      expect(cached.fromCache, isTrue);
      expect(cached.provider, LyricsProvider.lrcRed);
      expect(cached.entries.where((e) => e.isWordSynced), isNotEmpty,
          reason: 'the word timings come back with the lines');
    });

    test('the cache round trip keeps the line count, so timings align',
        () async {
      // The bug: parseLrc added its own head entry, so the stored list and the
      // parsed list differed by one and every timing payload was thrown away.
      final entries = LyricsService.withInstrumentalGaps([
        LyricsEntry.headEntry,
        LyricsEntry(timeMs: 5000, text: 'hello world', endMs: 7000, lyricWords: [
          const LyricWord(startMs: 5000, endMs: 5500, text: 'hello'),
          const LyricWord(startMs: 5500, endMs: 7000, text: 'world'),
        ]),
        LyricsEntry(timeMs: 9000, text: 'second line', endMs: 11000),
      ]);
      final buffer = StringBuffer();
      for (final e in entries) {
        final m = (e.timeMs ~/ 60000).toString().padLeft(2, '0');
        final s =
            ((e.timeMs % 60000) / 1000).toStringAsFixed(2).padLeft(5, '0');
        buffer.writeln('[$m:$s]${e.text}');
      }

      final back = decodeCachedLyrics(buffer.toString(), encodeTimings(entries));

      expect(back, hasLength(entries.length));
      expect([for (final e in back) e.text], [for (final e in entries) e.text]);
      expect([for (final e in back) e.isWordSynced],
          [for (final e in entries) e.isWordSynced]);
    });

    test('an unsynced result is kept in memory but never written to disk',
        () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.lyricsPlus].reply(plainLines('plain'));
      w.service.raceGrace = _ms * 20;

      final live = await lookup(w);
      expect(live.provider, LyricsProvider.lyricsPlus);
      expect(w.cache.puts, 0, reason: 'plain text pins a track to plain text');

      final again = await lookup(w);
      expect(again.fromCache, isTrue, reason: 'but this session need not ask twice');
    });

    test('a prefetch leaves an unsynced answer nowhere', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.lyricsPlus].reply(plainLines('plain'));
      w.service.raceGrace = _ms * 20;

      await lookup(w, prefetch: true);
      expect(w.cache.puts, 0);

      final live = await lookup(w);
      expect(live.fromCache, isFalse,
          reason: 'the real lookup is not answered by a prefetch\'s guess');
    });

    test('a prefetch of a synced answer is cached', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.lrcRed].reply(wordSyncedLines('hello'));

      await lookup(w, prefetch: true);
      expect(w.cache.puts, 1);
    });

    test('the memory hit still says who produced it', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.lrcRed].reply(wordSyncedLines('hello'));
      await lookup(w);

      final again = await lookup(w);
      expect(again.fromCache, isTrue);
      expect(again.provider, LyricsProvider.lrcRed);
    });

    test('rememberChoice records a manual pick for the next play', () async {
      final w = FakeLyricsWorld();
      await w.service.rememberChoice(
        title: 'Borderline',
        artist: 'Tame Impala',
        provider: LyricsProvider.kugou,
        entries: lineSyncedLines('chosen'),
      );

      final next = await lookup(w);
      expect(next.provider, LyricsProvider.kugou);
      expect(next.fromCache, isTrue);
    });

    test('gaps are not added twice to lyrics that already carry them', () {
      final once = LyricsService.withInstrumentalGaps([
        LyricsEntry.headEntry,
        LyricsEntry(timeMs: 9000, text: 'late first line', endMs: 11000),
        LyricsEntry(timeMs: 30000, text: 'after a break', endMs: 33000),
      ]);
      final twice = LyricsService.withInstrumentalGaps(once);
      expect(twice.length, once.length);
      expect(once.where((e) => e.text == LyricsService.gapMarker), isNotEmpty);
    });

    test('untimed lyrics get no gap markers', () {
      final entries = plainLines('plain');
      expect(LyricsService.withInstrumentalGaps(entries).length, entries.length);
    });
  });

  group('the PaxSenix key', () {
    test('the keyed sources are not asked without a key', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.paxSenixSpotify].reply(lineSyncedLines('s'));
      w[LyricsProvider.paxSenixMusixmatch].reply(wordSyncedLines('m'));

      await lookup(w);

      expect(w[LyricsProvider.paxSenixSpotify].calls, 0);
      expect(w[LyricsProvider.paxSenixMusixmatch].calls, 0);
    });

    test('with a key they are asked, with "Bearer " stripped', () async {
      final w = FakeLyricsWorld();
      w[LyricsProvider.paxSenixMusixmatch].reply(wordSyncedLines('m'));

      await w.service.setPaxSenixKey('  Bearer secret-key ');
      final r = await lookup(w);

      expect(w.service.hasPaxSenixKey, isTrue);
      expect(r.provider, LyricsProvider.paxSenixMusixmatch);
      expect(w[LyricsProvider.paxSenixMusixmatch].last!.args['apiKey'],
          'secret-key');
    });

    test('clearing the key stops them being asked again', () async {
      final w = FakeLyricsWorld();
      await w.service.setPaxSenixKey('abc');
      await w.service.setPaxSenixKey('');
      expect(w.service.hasPaxSenixKey, isFalse);

      await lookup(w);
      expect(w[LyricsProvider.paxSenixSpotify].calls, 0);
    });

    test('saving a key switches the keyed sources on', () async {
      final w = FakeLyricsWorld();
      await w.service.setProviderEnabled(LyricsProvider.paxSenixSpotify, false);
      expect(w.service.isProviderEnabled(LyricsProvider.paxSenixSpotify), isFalse);

      await w.service.setPaxSenixKey('abc');

      expect(w.service.isProviderEnabled(LyricsProvider.paxSenixSpotify), isTrue);
    });

    test('a keyed source is unavailable without a key and available with one',
        () async {
      final w = FakeLyricsWorld();
      expect(w.service.isAvailable(LyricsProvider.paxSenixSpotify), isFalse);
      expect(w.service.isAvailable(LyricsProvider.kugou), isTrue);
      await w.service.setPaxSenixKey('abc');
      expect(w.service.isAvailable(LyricsProvider.paxSenixSpotify), isTrue);
    });
  });
}
