import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_service.dart'
    show LyricsProvider;
import 'package:music_streaming_app/services/lyrics/provider_race.dart';

/// A line-synced answer.
List<LyricsEntry> lineSynced(String text) =>
    [LyricsEntry(timeMs: 1000, endMs: 2000, text: text)];

/// A word-synced answer.
List<LyricsEntry> wordSynced(String text) => [
      LyricsEntry(
        timeMs: 1000,
        endMs: 2000,
        text: text,
        words: [WordTiming(timeMs: 1000, durationMs: 1000, text: text)],
      ),
    ];

/// An unsynced answer: every line stamped 0.
List<LyricsEntry> plain(String text) => [LyricsEntry(timeMs: 0, text: text)];

/// The judge the service uses with "prioritize word sync" ON.
LyricsVerdict prioritizeOn(List<LyricsEntry> entries) {
  if (entries.any((e) => e.isWordSynced)) return LyricsVerdict.accept;
  if (entries.any((e) => e.timeMs > 0)) return LyricsVerdict.hold;
  return LyricsVerdict.holdPlain;
}

/// A provider that answers after [delay], recording that it was asked.
ProviderRaceSpec spec(
  LyricsProvider provider, {
  Duration delay = Duration.zero,
  List<LyricsEntry>? Function()? build,
  bool lazy = false,
  void Function()? onAsked,
  bool throwInstead = false,
}) {
  return ProviderRaceSpec(
    provider: provider,
    lazy: lazy,
    fetch: () async {
      onAsked?.call();
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (throwInstead) throw StateError('host is down');
      return build?.call();
    },
  );
}

const _ms = Duration(milliseconds: 1);

void main() {
  group('concurrency', () {
    test('every eager provider is asked before any answer is read', () async {
      final asked = <LyricsProvider>[];
      final specs = [
        spec(LyricsProvider.lrcRed, onAsked: () => asked.add(LyricsProvider.lrcRed)),
        spec(LyricsProvider.betterLyrics,
            onAsked: () => asked.add(LyricsProvider.betterLyrics)),
        spec(LyricsProvider.kugou, onAsked: () => asked.add(LyricsProvider.kugou)),
      ];

      await ProviderRace.run(
        specs: specs,
        judge: (_) => LyricsVerdict.accept,
      );

      // All three were asked. A serial implementation would have stopped after
      // the first, and the point of the race is that it does not.
      expect(asked, hasLength(3));
    });

    test('the wait is the slowest pending provider, not the sum', () async {
      // Three 60ms providers: a serial loop costs ~180ms, a race ~60ms.
      final specs = [
        spec(LyricsProvider.lrcRed, delay: _ms * 60),
        spec(LyricsProvider.betterLyrics, delay: _ms * 60),
        spec(LyricsProvider.kugou, delay: _ms * 60),
      ];

      final stopwatch = Stopwatch()..start();
      await ProviderRace.run(specs: specs, judge: (_) => LyricsVerdict.accept);
      stopwatch.stop();

      // Generous ceiling - the assertion is that it is nowhere near 180ms.
      expect(stopwatch.elapsedMilliseconds, lessThan(150));
    });
  });

  group('priority beats arrival order', () {
    test('a fast low-priority provider cannot preempt a slow high-priority one',
        () async {
      // The exact failure this class exists to prevent: LyricsPlus answers fast
      // with only line timings, LRCLIB is slower but carries word timings.
      // "First to answer" hands back the worse lyrics.
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed,
              delay: _ms * 80, build: () => wordSynced('from high priority')),
          spec(LyricsProvider.lyricsPlus,
              delay: _ms * 5, build: () => lineSynced('from low priority')),
        ],
        judge: prioritizeOn,
      );

      expect(outcome.provider, LyricsProvider.lrcRed);
      expect(outcome.entries.first.text, 'from high priority');
    });

    test('the high-priority provider still wins when it is the slower one and '
        'both are acceptable', () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed,
              delay: _ms * 50, build: () => lineSynced('a')),
          spec(LyricsProvider.lrclib, build: () => lineSynced('b')),
        ],
        judge: (_) => LyricsVerdict.accept,
      );

      expect(outcome.provider, LyricsProvider.lrcRed);
      expect(outcome.entries.first.text, 'a');
    });
  });

  group('verdicts', () {
    test('accept settles immediately without reading later providers', () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('winner')),
          spec(LyricsProvider.kugou,
              delay: _ms * 30, build: () => lineSynced('later')),
        ],
        judge: (_) => LyricsVerdict.accept,
      );

      expect(outcome.provider, LyricsProvider.lrcRed);
      expect(outcome.isFallback, isFalse);
    });

    test('a held answer is returned when nothing better turns up', () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('held')),
          spec(LyricsProvider.kugou),
          spec(LyricsProvider.lrclib),
        ],
        judge: prioritizeOn,
      );

      expect(outcome.isFallback, isTrue);
      expect(outcome.provider, LyricsProvider.lrcRed);
      expect(outcome.entries.first.text, 'held');
    });

    test('a held answer is replaced by a later accepted one', () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('held')),
          spec(LyricsProvider.kugou, build: () => wordSynced('better')),
        ],
        judge: prioritizeOn,
      );

      expect(outcome.isFallback, isFalse);
      expect(outcome.entries.first.text, 'better');
    });

    test('a rejected answer never becomes the fallback', () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('bad')),
          spec(LyricsProvider.kugou),
        ],
        // Everything is rejected: nothing is acceptable at all.
        judge: (_) => LyricsVerdict.reject,
      );

      expect(outcome.hasResult, isFalse);
    });

    test('only the first held answer of a tier is kept', () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('first held')),
          spec(LyricsProvider.kugou, build: () => lineSynced('second held')),
        ],
        judge: (_) => LyricsVerdict.hold,
      );

      expect(outcome.entries.first.text, 'first held');
    });

    test('a held line-synced answer outranks an earlier held plain one', () async {
      // YouTube Music (plain) sits ahead of a line-synced source here, and the
      // plain one answers first. Words that do not move are what you show when
      // nothing moves, not when something does.
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.youtubeMusic, build: () => plain('plain')),
          spec(LyricsProvider.kugou, build: () => lineSynced('synced')),
        ],
        judge: prioritizeOn,
      );

      expect(outcome.isFallback, isTrue);
      expect(outcome.provider, LyricsProvider.kugou);
    });

    test('a plain answer is still returned when it is all there is', () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.kugou),
          spec(LyricsProvider.youtubeMusic, build: () => plain('plain')),
        ],
        judge: prioritizeOn,
      );

      expect(outcome.provider, LyricsProvider.youtubeMusic);
      expect(outcome.isFallback, isTrue);
    });
  });

  group('grace and deadline', () {
    test('the grace period ends the wait for a word-synced answer', () async {
      // lrc.red holds a line-synced answer at once; the word-synced source
      // would take far longer than the grace allows.
      final stopwatch = Stopwatch()..start();
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('held')),
          spec(LyricsProvider.lyricsPlus,
              delay: _ms * 600, build: () => wordSynced('too late')),
        ],
        judge: prioritizeOn,
        grace: _ms * 60,
        deadline: const Duration(seconds: 5),
      );
      stopwatch.stop();

      expect(outcome.provider, LyricsProvider.lrcRed);
      expect(outcome.isFallback, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(400));
    });

    test('a word-synced answer arriving inside the grace period still wins',
        () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('held')),
          spec(LyricsProvider.lyricsPlus,
              delay: _ms * 30, build: () => wordSynced('worth the wait')),
        ],
        judge: prioritizeOn,
        grace: _ms * 400,
        deadline: const Duration(seconds: 5),
      );

      expect(outcome.provider, LyricsProvider.lyricsPlus);
      expect(outcome.isFallback, isFalse);
    });

    test('the deadline returns what has answered, and gives up on the rest',
        () async {
      final cancelled = <LyricsProvider>[];
      final outcome = await ProviderRace.run(
        specs: [
          // Hangs well past the deadline.
          spec(LyricsProvider.lrcRed,
              delay: _ms * 800, build: () => wordSynced('never seen')),
          spec(LyricsProvider.kugou, build: () => lineSynced('in hand')),
        ],
        judge: prioritizeOn,
        callbacks: LyricsRaceCallbacks(onCancelled: cancelled.add),
        grace: const Duration(seconds: 5),
        deadline: _ms * 80,
      );

      expect(outcome.provider, LyricsProvider.kugou);
      expect(cancelled, [LyricsProvider.lrcRed]);
    });

    test('at the deadline an answer from LATER in the list is not thrown away '
        'because an earlier source is still pending', () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, delay: _ms * 800),
          spec(LyricsProvider.lyricsPlus, build: () => wordSynced('arrived')),
        ],
        judge: prioritizeOn,
        deadline: _ms * 60,
      );

      // The consumer was parked on lrc.red; lyricsPlus had long since answered.
      expect(outcome.provider, LyricsProvider.lyricsPlus);
      expect(outcome.isFallback, isFalse);
    });

    test('a settled provider is never reported cancelled', () async {
      final cancelled = <LyricsProvider>[];
      final results = <LyricsProvider>[];
      await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('held')),
          spec(LyricsProvider.kugou), // a genuine miss, settled at once
          spec(LyricsProvider.lyricsPlus, delay: _ms * 400),
        ],
        judge: prioritizeOn,
        callbacks: LyricsRaceCallbacks(
          onResult: (p, _) => results.add(p),
          onCancelled: cancelled.add,
        ),
        grace: _ms * 20,
        deadline: _ms * 100,
      );

      // Let the deadline fire with the slow one still out.
      await Future<void>.delayed(_ms * 200);

      expect(cancelled, [LyricsProvider.lyricsPlus]);
      expect(results, containsAll([LyricsProvider.lrcRed, LyricsProvider.kugou]));
    });
  });

  group('lazy providers', () {
    test('a lazy provider is not asked while an eager one already won', () async {
      var lazyAsked = false;
      await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('winner')),
          spec(LyricsProvider.genius,
              lazy: true, onAsked: () => lazyAsked = true),
        ],
        judge: (_) => LyricsVerdict.accept,
      );

      expect(lazyAsked, isFalse);
    });

    test('a lazy provider is not asked when a fallback is already held',
        () async {
      var lazyAsked = false;
      await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('held')),
          spec(LyricsProvider.kugou),
          spec(LyricsProvider.genius,
              lazy: true,
              onAsked: () => lazyAsked = true,
              build: () => lineSynced('genius')),
        ],
        judge: prioritizeOn,
      );

      // Everything ahead of it missed and a line-synced answer is in hand, so
      // scraping a web page for Genius would spend a rate limit for nothing.
      expect(lazyAsked, isFalse);
    });

    test('a lazy provider is not asked when a plain fallback is already held',
        () async {
      var lazyAsked = false;
      await ProviderRace.run(
        specs: [
          spec(LyricsProvider.youtubeMusic, build: () => plain('plain')),
          spec(LyricsProvider.genius,
              lazy: true,
              onAsked: () => lazyAsked = true,
              build: () => plain('genius')),
        ],
        judge: prioritizeOn,
      );

      expect(lazyAsked, isFalse);
    });

    test('a lazy provider is asked once everything ahead of it misses', () async {
      var lazyAsked = false;
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed),
          spec(LyricsProvider.kugou),
          spec(LyricsProvider.genius,
              lazy: true,
              onAsked: () => lazyAsked = true,
              build: () => lineSynced('from genius')),
        ],
        judge: (_) => LyricsVerdict.accept,
      );

      expect(lazyAsked, isTrue);
      expect(outcome.provider, LyricsProvider.genius);
    });

    test('a lazy provider reports itself started only when it is asked', () async {
      final started = <LyricsProvider>[];
      await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('winner')),
          spec(LyricsProvider.genius, lazy: true, build: () => lineSynced('g')),
        ],
        judge: (_) => LyricsVerdict.accept,
        callbacks: LyricsRaceCallbacks(onStarted: started.add),
      );

      // Genius was never asked, so it must not be showing as fetching.
      expect(started, [LyricsProvider.lrcRed]);
    });
  });

  group('failure handling', () {
    test('a provider that throws is a miss, not a crash', () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, throwInstead: true),
          spec(LyricsProvider.kugou, build: () => lineSynced('survivor')),
        ],
        judge: (_) => LyricsVerdict.accept,
      );

      expect(outcome.provider, LyricsProvider.kugou);
    });

    test('an empty answer is a miss', () async {
      final results = <(LyricsProvider, List<LyricsEntry>?)>[];
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => const []),
          spec(LyricsProvider.kugou, build: () => const []),
        ],
        judge: (_) => LyricsVerdict.accept,
        callbacks: LyricsRaceCallbacks(onResult: (p, e) => results.add((p, e))),
      );

      expect(outcome.hasResult, isFalse);
      expect(results, hasLength(2));
      // Reported as null, never as an empty list: "found" must mean found.
      expect(results.every((r) => r.$2 == null), isTrue);
    });

    test('every provider failing yields no result rather than throwing',
        () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, throwInstead: true),
          spec(LyricsProvider.kugou, throwInstead: true),
        ],
        judge: (_) => LyricsVerdict.accept,
      );

      expect(outcome.hasResult, isFalse);
      expect(outcome.provider, isNull);
    });
  });

  group('status reporting', () {
    test('a started provider reports fetching, then its result', () async {
      final started = <LyricsProvider>[];
      final results = <(LyricsProvider, bool)>[];

      await ProviderRace.run(
        specs: [spec(LyricsProvider.lrcRed, build: () => lineSynced('x'))],
        judge: (_) => LyricsVerdict.accept,
        callbacks: LyricsRaceCallbacks(
          onStarted: started.add,
          onResult: (p, e) => results.add((p, e != null)),
        ),
      );

      expect(started, [LyricsProvider.lrcRed]);
      expect(results, [(LyricsProvider.lrcRed, true)]);
    });

    test('a genuine miss is reported with null entries', () async {
      final results = <(LyricsProvider, List<LyricsEntry>?)>[];
      await ProviderRace.run(
        specs: [spec(LyricsProvider.lrcRed)],
        judge: (_) => LyricsVerdict.accept,
        callbacks: LyricsRaceCallbacks(onResult: (p, e) => results.add((p, e))),
      );

      expect(results, [(LyricsProvider.lrcRed, null)]);
    });

    test('a race loser still reports its real answer after the race returns',
        () async {
      // The provider sheet depends on this: the loser was still working when the
      // race ended, and its answer is what makes its row switchable.
      final results = <LyricsProvider>[];
      final cancelled = <LyricsProvider>[];

      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed,
              delay: _ms * 5, build: () => lineSynced('w')),
          spec(LyricsProvider.kugou,
              delay: _ms * 120, build: () => lineSynced('l')),
        ],
        judge: (_) => LyricsVerdict.accept,
        callbacks: LyricsRaceCallbacks(
          onResult: (p, _) => results.add(p),
          onCancelled: cancelled.add,
        ),
      );

      expect(outcome.provider, LyricsProvider.lrcRed);
      expect(results, [LyricsProvider.lrcRed]);

      await Future<void>.delayed(_ms * 200);
      expect(results, [LyricsProvider.lrcRed, LyricsProvider.kugou]);
      expect(cancelled, isEmpty);
    });

    test('a provider nobody asked is reported neither as a result nor as '
        'cancelled', () async {
      final results = <LyricsProvider>[];
      final cancelled = <LyricsProvider>[];

      await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('w')),
          spec(LyricsProvider.genius, lazy: true),
        ],
        judge: (_) => LyricsVerdict.accept,
        callbacks: LyricsRaceCallbacks(
          onResult: (p, _) => results.add(p),
          onCancelled: cancelled.add,
        ),
        deadline: _ms * 40,
      );
      await Future<void>.delayed(_ms * 100);

      expect(results, [LyricsProvider.lrcRed]);
      expect(cancelled, isEmpty);
    });
  });

  group('degenerate input', () {
    test('no providers yields no result', () async {
      final outcome = await ProviderRace.run(
          specs: const [], judge: (_) => LyricsVerdict.accept);
      expect(outcome.hasResult, isFalse);
    });
  });
}
