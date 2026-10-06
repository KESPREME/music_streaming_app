// lib/services/lyrics/provider_race.dart
// Asking every enabled lyrics provider at once, and taking the answers in
// priority order.
//
// WHY THIS EXISTS
//
// Asked one after another, a miss costs its own round trip before the next
// provider is even tried. A track nobody has lyrics for spends the sum of every
// provider's timeout before the panel admits defeat - and a track somebody DOES
// have lyrics for is still shown late, because the providers ahead of the winner
// were asked serially and all of them missed.
//
// So every provider is asked at the same time, and the ANSWERS are consumed in
// the user's priority order. Those are two different things and conflating them
// is the bug this file exists to prevent:
//
//   - Asking concurrently means the wall-clock cost is that of the slowest
//     provider still pending ahead of the winner, not the sum of all of them.
//   - Consuming in priority order means a fast low-priority provider CANNOT
//     preempt a slow high-priority one. If LyricsPlus answers in 400ms with
//     line timings while LRCLIB is still working and would have answered in 900ms
//     with word timings, "first to answer" hands back the worse lyrics. Priority
//     is a promise about which answer is preferred, and it can only be kept by
//     reading the futures in order and stopping at the first acceptable one.
//
// The two together are not "take whichever arrives first". They are "wait as
// long as the best answer so far takes to arrive, then use it".
//
// THREE OUTCOMES, NOT TWO
//
// [LyricsVerdict] has a third case that a boolean would lose. When "prioritize
// word sync" is on, a line-synced answer is neither accepted nor discarded: it
// is kept as a fallback while the search continues for a word-synced one, which
// is a decision that only makes sense if the race can go on after a good-enough
// answer has already arrived. Collapsing hold into accept would show
// line-synced lyrics on a word-sync setting; collapsing it into reject would
// blank the screen for a song that does have lyrics.
//
// A LAZY PROVIDER IS NOT STARTED, NOT JUST NOT PRIORITISED
//
// Genius scrapes a web page. Starting it with everything else spends bandwidth
// and risks a rate limit on a source that is only ever wanted when nothing
// better exists. [ProviderRaceSpec.lazy] holds it back until the consumer
// actually reaches it - which, because the consumer walks the priority order,
// means every provider ahead of it has already missed. If a fallback is already
// in hand by then it is skipped outright and never asked at all.

import 'dart:async';

import '../../models/lyrics_entry.dart';
import 'lyrics_service.dart' show LyricsProvider;

/// What the race should do with an answer it has just read.
enum LyricsVerdict {
  /// Good enough. Settle the race with this.
  accept,

  /// Keep as a fallback, but keep looking for something better.
  hold,

  /// Not usable. Discard it and keep looking.
  reject,
}

/// What to ask one provider for, and when to ask.
class ProviderRaceSpec {
  const ProviderRaceSpec({
    required this.provider,
    required this.fetch,
    this.lazy = false,
  });

  final LyricsProvider provider;

  /// The provider's own lookup. Must not throw: a throwing provider is a miss,
  /// and [ProviderRace] converts a throw into one so a single dead host cannot
  /// take the whole race down with it.
  final Future<List<LyricsEntry>?> Function() fetch;

  /// Held back until the consumer reaches this spec in priority order.
  final bool lazy;
}

/// The provider that won, and what it returned.
class LyricsRaceOutcome {
  const LyricsRaceOutcome.accepted(this.provider, this.entries)
      : isFallback = false;

  /// Nothing was accepted; this is the best answer that was merely held.
  const LyricsRaceOutcome.held(this.provider, this.entries)
      : isFallback = true;

  const LyricsRaceOutcome.none()
      : provider = null,
        entries = const [],
        isFallback = false;

  final LyricsProvider? provider;
  final List<LyricsEntry> entries;

  /// Whether this is a held line-synced answer rather than a settled win.
  final bool isFallback;

  bool get hasResult => provider != null && entries.isNotEmpty;
}

/// Runs the providers concurrently and resolves one answer in priority order.
class ProviderRace {
  /// Starts every non-lazy spec, then walks [specs] in order awaiting each.
  ///
  /// [judge] is consulted once per answer, in priority order, and decides
  /// whether that answer settles the race. It is never consulted for a provider
  /// the race abandoned first.
  ///
  /// [onStarted] / [onSettled] / [onAbandoned] drive the provider sheet's
  /// per-source status. The distinction between [onSettled] and [onAbandoned] is
  /// load-bearing: a settled null is a genuine miss, while an abandoned provider
  /// lost a race it was still winning. Reporting the second as the first paints
  /// "no lyrics here" on sources nobody ever finished asking.
  static Future<LyricsRaceOutcome> run({
    required List<ProviderRaceSpec> specs,
    required LyricsVerdict Function(List<LyricsEntry> entries) judge,
    void Function(LyricsProvider provider)? onStarted,
    void Function(LyricsProvider provider, bool found)? onSettled,
    void Function(LyricsProvider provider)? onAbandoned,
  }) async {
    if (specs.isEmpty) return const LyricsRaceOutcome.none();

    final attempts = <_Attempt>[
      for (final spec in specs)
        _Attempt(spec, onStarted: onStarted, onSettled: onSettled),
    ];

    // Everything except the lazy spec goes out now. This is the whole point of
    // the class: the requests overlap, so the wait is a maximum rather than a sum.
    for (final attempt in attempts) {
      attempt.start();
    }

    List<LyricsEntry>? fallbackEntries;
    LyricsProvider? fallbackProvider;

    try {
      for (final attempt in attempts) {
        // Reaching a lazy spec means every provider ahead of it has missed. If a
        // fallback is already in hand, skip it: asking Genius to scrape a page
        // when line-synced lyrics are already in hand spends a rate limit for
        // nothing.
        if (attempt.spec.lazy && fallbackEntries != null) {
          attempt.skip();
          continue;
        }

        // Reading this future is what starts a lazy spec.
        final entries = await attempt.result();

        if (entries == null || entries.isEmpty) continue;

        switch (judge(entries)) {
          case LyricsVerdict.accept:
            return LyricsRaceOutcome.accepted(attempt.spec.provider, entries);
          case LyricsVerdict.hold:
            fallbackEntries ??= entries;
            fallbackProvider ??= attempt.spec.provider;
            continue;
          case LyricsVerdict.reject:
            continue;
        }
      }

      if (fallbackEntries != null) {
        return LyricsRaceOutcome.held(
          fallbackProvider!,
          fallbackEntries,
        );
      }
      return const LyricsRaceOutcome.none();
    } finally {
      // The losers are no longer worth waiting on. Nothing can cancel a Dart
      // Future, so "abandoned" means their late answer is discarded and reported
      // as abandoned rather than as a miss - and their requests are already
      // bounded by each provider's own timeout, so nothing is left hanging.
      for (final attempt in attempts) {
        attempt.abandon(onAbandoned);
      }
    }
  }
}

/// One provider's attempt, as a future the consumer can await in order.
class _Attempt {
  _Attempt(
    this.spec, {
    required void Function(LyricsProvider)? onStarted,
    required void Function(LyricsProvider, bool)? onSettled,
  })  : _onStarted = onStarted,
        _onSettled = onSettled;

  final ProviderRaceSpec spec;
  final void Function(LyricsProvider provider)? _onStarted;
  final void Function(LyricsProvider provider, bool found)? _onSettled;
  final Completer<List<LyricsEntry>?> _completer =
      Completer<List<LyricsEntry>?>();

  bool _started = false;
  bool _abandoned = false;

  /// Whether this attempt was ever asked. A lazy spec nobody reached is not
  /// asked, and must not be reported as a miss.
  bool get wasStarted => _started;

  void start() {
    if (spec.lazy || _started) return;
    _begin();
  }

  /// Reads the answer, starting a lazy spec on first read.
  Future<List<LyricsEntry>?> result() {
    _begin();
    return _completer.future;
  }

  void _begin() {
    if (_started) return;
    _started = true;
    // Reported for a lazy provider too, at the moment it is finally asked -
    // not at construction, when it was not. A row that shows "fetching" for a
    // source that has not issued a request yet would be lying.
    _onStarted?.call(spec.provider);

    // Deliberately detached: the provider's own error boundary is inside, and
    // a rejection from a loser has no listener left by the time it arrives.
    // Left unhandled it becomes an uncaught zone error, which in a test takes
    // the isolate down rather than failing one assertion.
    Future<void>(() async {
      List<LyricsEntry>? entries;
      try {
        entries = await spec.fetch();
      } catch (_) {
        // A dead host is a miss, not a crash.
        entries = null;
      }

      if (_abandoned) return;

      final found = entries != null && entries.isNotEmpty;
      _completer.complete(entries);
      _onSettled?.call(spec.provider, found);
    }).ignore();
  }

  /// Skips a lazy spec without asking it.
  void skip() {
    if (_started) return;
    _abandoned = true;
    if (!_completer.isCompleted) _completer.complete(null);
  }

  void abandon(void Function(LyricsProvider)? onAbandoned) {
    if (_abandoned) return;
    _abandoned = true;
    // Unblock a consumer that is somehow still waiting. There is nothing left to
    // get, and a completer nobody completes is a leak.
    if (!_completer.isCompleted) _completer.complete(null);
    if (wasStarted) onAbandoned?.call(spec.provider);
  }
}