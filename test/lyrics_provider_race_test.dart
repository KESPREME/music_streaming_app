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
        spec(LyricsProvider.lrcRed,
            delay: const Duration(milliseconds: 60)),
        spec(LyricsProvider.betterLyrics,
            delay: const Duration(milliseconds: 60)),
        spec(LyricsProvider.kugou, delay: const Duration(milliseconds: 60)),
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
              delay: const Duration(milliseconds: 80),
              build: () => wordSynced('from high priority')),
          spec(LyricsProvider.lyricsPlus,
              delay: const Duration(milliseconds: 5),
              build: () => lineSynced('from low priority')),
        ],
        judge: (entries) => entries.any((e) => e.isWordSynced)
            ? LyricsVerdict.accept
            : LyricsVerdict.hold,
      );

      expect(outcome.provider, LyricsProvider.lrcRed);
      expect(outcome.entries.first.text, 'from high priority');
    });

    test('the high-priority provider still wins when it is the slower one and '
        'both are acceptable', () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed,
              delay: const Duration(milliseconds: 50), build: () => lineSynced('a')),
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
      var laterAsked = false;
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('winner')),
          spec(LyricsProvider.kugou,
              onAsked: () => laterAsked = true, build: () => lineSynced('later')),
        ],
        judge: (_) => LyricsVerdict.accept,
      );

      expect(outcome.provider, LyricsProvider.lrcRed);
      // The race stopped at the winner, so the loser was never asked.
      expect(laterAsked, isFalse);
    });

    test('a held answer is returned when nothing better turns up', () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('held')),
          spec(LyricsProvider.kugou),
          spec(LyricsProvider.lrclib),
        ],
        judge: (entries) => entries.any((e) => e.isWordSynced)
            ? LyricsVerdict.accept
            : LyricsVerdict.hold,
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
        judge: (entries) => entries.any((e) => e.isWordSynced)
            ? LyricsVerdict.accept
            : LyricsVerdict.hold,
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

    test('only the first held answer is kept', () async {
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('first held')),
          spec(LyricsProvider.kugou, build: () => lineSynced('second held')),
        ],
        judge: (_) => LyricsVerdict.hold,
      );

      expect(outcome.entries.first.text, 'first held');
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
        judge: (entries) => entries.any((e) => e.isWordSynced)
            ? LyricsVerdict.accept
            : LyricsVerdict.hold,
      );

      // Everything ahead of it missed and a line-synced answer is in hand, so
      // scraping a web page for Genius would spend a rate limit for nothing.
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
        onStarted: started.add,
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
      final settled = <LyricsProvider>[];
      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => const []),
          spec(LyricsProvider.kugou, build: () => const []),
        ],
        judge: (_) => LyricsVerdict.accept,
        onSettled: (p, _) => settled.add(p),
      );

      expect(outcome.hasResult, isFalse);
      expect(settled, hasLength(2));
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
    test('a started provider reports fetching, then settled', () async {
      final started = <LyricsProvider>[];
      final settled = <(LyricsProvider, bool)>[];

      await ProviderRace.run(
        specs: [spec(LyricsProvider.lrcRed, build: () => lineSynced('x'))],
        judge: (_) => LyricsVerdict.accept,
        onStarted: started.add,
        onSettled: (p, found) => settled.add((p, found)),
      );

      expect(started, [LyricsProvider.lrcRed]);
      expect(settled, [(LyricsProvider.lrcRed, true)]);
    });

    test('a genuine miss is reported as settled with found=false', () async {
      final settled = <(LyricsProvider, bool)>[];
      await ProviderRace.run(
        specs: [spec(LyricsProvider.lrcRed)],
        judge: (_) => LyricsVerdict.accept,
        onSettled: (p, found) => settled.add((p, found)),
      );

      expect(settled, [(LyricsProvider.lrcRed, false)]);
    });

    test('a race loser is reported as abandoned, never as a miss', () async {
      // The distinction the provider sheet depends on. The loser was still
      // working when the race ended; it did not answer "no lyrics here".
      final settled = <LyricsProvider>[];
      final abandoned = <LyricsProvider>[];

      final outcome = await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed,
              delay: const Duration(milliseconds: 5), build: () => lineSynced('w')),
          spec(LyricsProvider.kugou,
              delay: const Duration(milliseconds: 120), build: () => lineSynced('l')),
        ],
        judge: (_) => LyricsVerdict.accept,
        onSettled: (p, _) => settled.add(p),
        onAbandoned: abandoned.add,
      );

      expect(outcome.provider, LyricsProvider.lrcRed);
      // Let the loser's own future land before asserting on the callbacks.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(abandoned, contains(LyricsProvider.kugou));
      expect(settled, isNot(contains(LyricsProvider.kugou)));
    });

    test('a provider nobody asked is reported neither settled nor abandoned',
        () async {
      final settled = <LyricsProvider>[];
      final abandoned = <LyricsProvider>[];

      await ProviderRace.run(
        specs: [
          spec(LyricsProvider.lrcRed, build: () => lineSynced('w')),
          spec(LyricsProvider.genius, lazy: true),
        ],
        judge: (_) => LyricsVerdict.accept,
        onSettled: (p, _) => settled.add(p),
        onAbandoned: abandoned.add,
      );

      expect(settled, [LyricsProvider.lrcRed]);
      expect(abandoned, isNot(contains(LyricsProvider.genius)));
    });
  });

  group('degenerate input', () {
    test('no providers yields no result', () async {
      final outcome = await ProviderRace.run(specs: const [], judge: (_) => LyricsVerdict.accept);
      expect(outcome.hasResult, isFalse);
    });
  });
}