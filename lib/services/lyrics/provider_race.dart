// lib/services/lyrics/provider_race.dart
// Asking every enabled lyrics provider at once, and taking the answers in
// priority order.
//
// Port of `LyricsRepository.lyrics` (BitChord, L159-176), with two deliberate
// additions (a grace period and a deadline) described below.
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
// FOUR OUTCOMES, NOT TWO
//
// [LyricsVerdict] has two "keep, but keep looking" cases that a boolean would
// lose. When "prioritize word sync" is on, a line-synced answer is neither
// accepted nor discarded: it is held as a fallback while the search continues
// for a word-synced one. A plain-text answer is held the same way but ranks
// below it, because words that do not move are what you show when nothing moves.
// Collapsing hold into accept would show line-synced lyrics on a word-sync
// setting; collapsing it into reject would blank the screen for a song that
// does have lyrics.
//
// A LAZY PROVIDER IS NOT STARTED, NOT JUST NOT PRIORITISED
//
// Genius scrapes a web page. Starting it with everything else spends bandwidth
// and risks a rate limit on a source that is only ever wanted when nothing
// better exists. [ProviderRaceSpec.lazy] holds it back until the consumer
// actually reaches it - which, because the consumer walks the priority order,
// means every provider ahead of it has already missed. If a fallback is already
// in hand by then it is skipped outright and never asked at all.
//
// WHAT THE REFERENCE DOES NOT HAVE: A GRACE PERIOD AND A DEADLINE
//
// With "prioritize word sync" on (the default) a line-synced answer is held and
// every remaining source is awaited. With thirteen sources and a six-second
// timeout each, that is up to six seconds spent on a song nobody has word-synced
// - for lyrics that were in hand after one. [prioritizeGrace] caps the extra wait
// at four seconds after the first held answer, and [overallDeadline] caps the
// whole lookup at ten however slow the sources are. When either fires, whatever
// has ALREADY answered is judged once more (in priority order, so a word-synced
// answer that arrived while an earlier source was still pending is not thrown
// away) and the best of it is returned.
//
// LOSERS KEEP RUNNING, AND THEIR ANSWERS ARE KEPT
//
// Nothing can cancel a Dart Future, and there is no reason to want to: a source
// that is still working when the race is settled is about to tell us something
// the provider sheet can show ("found" on that row, instantly switchable). So a
// loser is left to finish and reports through [LyricsRaceCallbacks.onResult] when
// it does. Only at the deadline is a straggler given up on and reported through
// `onCancelled` - it never said "no lyrics here", it ran out of time - and its
// late answer is dropped.

import 'dart:async';

import '../../models/lyrics_entry.dart';
import 'lyrics_service.dart' show LyricsProvider;

/// How long past the first held answer the race keeps looking for a better one.
const Duration prioritizeGrace = Duration(seconds: 4);

/// The longest a lookup may take to return, however slow the sources are.
const Duration overallDeadline = Duration(seconds: 10);

/// What the race should do with an answer it has just read.
enum LyricsVerdict {
  /// Good enough. Settle the race with this.
  accept,

  /// A line-synced answer: keep as a fallback, keep looking for something
  /// better.
  hold,

  /// A plain-text answer: the last resort. Kept, but ranks below [hold].
  holdPlain,

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

/// The three things the provider sheet needs to hear, per provider.
class LyricsRaceCallbacks {
  const LyricsRaceCallbacks({this.onStarted, this.onResult, this.onCancelled});

  /// The provider has just been asked. For a lazy provider that is the moment
  /// it is finally asked, not when it was queued: a row showing "fetching" for a
  /// source that has not issued a request yet is lying about the network.
  final void Function(LyricsProvider provider)? onStarted;

  /// The provider answered. `entries == null` is a genuine miss.
  ///
  /// Called for every provider that settles before the deadline - including
  /// ones that settle after the race has already returned its answer.
  final void Function(LyricsProvider provider, List<LyricsEntry>? entries)?
      onResult;

  /// The provider was still working at the deadline and has been given up on.
  ///
  /// Deliberately not a miss: it never said it had no lyrics.
  final void Function(LyricsProvider provider)? onCancelled;
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

  /// Whether this is a held answer rather than a settled win.
  final bool isFallback;

  bool get hasResult => provider != null && entries.isNotEmpty;
}

/// Runs the providers concurrently and resolves one answer in priority order.
class ProviderRace {
  /// Starts every non-lazy spec, then walks [specs] in order awaiting each.
  ///
  /// [judge] is consulted once per answer, in priority order, and decides
  /// whether that answer settles the race.
  ///
  /// [grace] and [deadline] default to [prioritizeGrace] and [overallDeadline];
  /// tests pass short ones.
  static Future<LyricsRaceOutcome> run({
    required List<ProviderRaceSpec> specs,
    required LyricsVerdict Function(List<LyricsEntry> entries) judge,
    LyricsRaceCallbacks callbacks = const LyricsRaceCallbacks(),
    Duration grace = prioritizeGrace,
    Duration deadline = overallDeadline,
  }) async {
    if (specs.isEmpty) return const LyricsRaceOutcome.none();

    // Completed by the grace timer or the deadline: "stop waiting, use what you
    // have".
    final stop = Completer<void>();
    Timer? graceTimer;
    Timer? deadlineTimer;

    late final List<_Attempt> attempts;

    // Once nobody is pending the deadline has nothing left to do, and a timer
    // that outlives its race is a leak (and, in a widget test, a failure).
    void settled() {
      if (attempts.every((a) => a.isDone)) deadlineTimer?.cancel();
    }

    attempts = <_Attempt>[
      for (final spec in specs) _Attempt(spec, callbacks, onSettled: settled),
    ];

    deadlineTimer = Timer(deadline, () {
      if (!stop.isCompleted) stop.complete();
      for (final attempt in attempts) {
        attempt.cancelIfPending();
      }
    });

    // Everything except the lazy spec goes out now. This is the whole point of
    // the class: the requests overlap, so the wait is a maximum rather than a sum.
    for (final attempt in attempts) {
      attempt.start();
    }

    _Held? held;

    try {
      for (var i = 0; i < attempts.length; i++) {
        final attempt = attempts[i];
        if (stop.isCompleted) break;

        // Reaching a lazy spec means every provider ahead of it has missed. If a
        // fallback is already in hand, skip it: asking Genius to scrape a page
        // when lyrics are already in hand spends a rate limit for nothing.
        if (attempt.spec.lazy && held != null) {
          attempt.skip();
          continue;
        }

        // Reading this future is what starts a lazy spec.
        final answer = await Future.any<Object?>([
          attempt.result(),
          stop.future.then<Object?>((_) => _stopped),
        ]);
        if (identical(answer, _stopped)) break;

        final entries = answer as List<LyricsEntry>?;
        if (entries == null || entries.isEmpty) continue;

        switch (judge(entries)) {
          case LyricsVerdict.accept:
            return LyricsRaceOutcome.accepted(attempt.spec.provider, entries);
          case LyricsVerdict.hold:
            held = _Held.better(held, attempt.spec.provider, entries, plain: false);
            graceTimer ??= Timer(grace, () {
              if (!stop.isCompleted) stop.complete();
            });
          case LyricsVerdict.holdPlain:
            held = _Held.better(held, attempt.spec.provider, entries, plain: true);
            graceTimer ??= Timer(grace, () {
              if (!stop.isCompleted) stop.complete();
            });
          case LyricsVerdict.reject:
            continue;
        }
      }

      // Stopped early, or walked the whole list. In the first case there may be
      // providers after the one we were waiting on that have ALREADY answered;
      // an answer in hand is worth more than one we were still waiting for.
      if (stop.isCompleted) {
        for (final attempt in attempts) {
          final entries = attempt.settledEntries;
          if (entries == null || entries.isEmpty) continue;
          switch (judge(entries)) {
            case LyricsVerdict.accept:
              return LyricsRaceOutcome.accepted(attempt.spec.provider, entries);
            case LyricsVerdict.hold:
              held = _Held.better(held, attempt.spec.provider, entries, plain: false);
            case LyricsVerdict.holdPlain:
              held = _Held.better(held, attempt.spec.provider, entries, plain: true);
            case LyricsVerdict.reject:
              break;
          }
        }
      }

      if (held != null) {
        return LyricsRaceOutcome.held(held.provider, held.entries);
      }
      return const LyricsRaceOutcome.none();
    } finally {
      graceTimer?.cancel();
      // Losers are NOT abandoned: they finish and report. The deadline timer
      // stays armed for as long as somebody is still pending, so a host that
      // hangs is eventually reported as cancelled rather than fetching forever.
      //
      // A lazy spec nobody reached is never going to be asked.
      for (final attempt in attempts) {
        if (attempt.spec.lazy && !attempt.wasStarted) attempt.skip();
      }
      settled();
    }
  }

  static final Object _stopped = Object();
}

/// The best answer that was held rather than accepted.
class _Held {
  const _Held(this.provider, this.entries, this.plain);

  final LyricsProvider provider;
  final List<LyricsEntry> entries;
  final bool plain;

  /// Keeps the existing answer unless the new one ranks strictly higher: a
  /// line-synced answer beats a plain one, and between equals the first (the
  /// one the listener put higher) stays.
  static _Held better(
    _Held? current,
    LyricsProvider provider,
    List<LyricsEntry> entries, {
    required bool plain,
  }) {
    if (current == null) return _Held(provider, entries, plain);
    if (current.plain && !plain) return _Held(provider, entries, plain);
    return current;
  }
}

/// One provider's attempt, as a future the consumer can await in order.
class _Attempt {
  _Attempt(
    this.spec,
    this._callbacks, {
    required void Function() onSettled,
  }) : _onSettled = onSettled;

  final ProviderRaceSpec spec;
  final LyricsRaceCallbacks _callbacks;
  final void Function() _onSettled;
  final Completer<List<LyricsEntry>?> _completer =
      Completer<List<LyricsEntry>?>();

  bool _started = false;
  bool _skipped = false;
  bool _cancelled = false;
  bool _settled = false;
  List<LyricsEntry>? _entries;

  /// Whether this attempt was ever asked. A lazy spec nobody reached is not
  /// asked, and must not be reported as a miss.
  bool get wasStarted => _started;

  /// Nothing more will happen to this attempt.
  bool get isDone => _settled || _cancelled || _skipped;

  /// The answer, if one has landed and was not given up on.
  List<LyricsEntry>? get settledEntries => _settled ? _entries : null;

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
    if (_started || _skipped) return;
    _started = true;
    _callbacks.onStarted?.call(spec.provider);

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

      // Given up on at the deadline: its answer is no longer wanted, and the
      // sheet has already been told it was cancelled.
      if (_cancelled) return;

      if (entries != null && entries.isEmpty) entries = null;
      _entries = entries;
      _settled = true;
      if (!_completer.isCompleted) _completer.complete(entries);
      _callbacks.onResult?.call(spec.provider, entries);
      _onSettled();
    }).ignore();
  }

  /// Skips a lazy spec without asking it.
  void skip() {
    if (_started || _skipped) return;
    _skipped = true;
    if (!_completer.isCompleted) _completer.complete(null);
    _onSettled();
  }

  /// Gives up on an attempt that was asked and has not answered.
  ///
  /// Fires `onCancelled` only for an attempt that was started and has NOT
  /// settled. An attempt that already answered reports its real result and is
  /// left alone: calling this after the fact used to repaint a finished miss as
  /// "cancelled" and a finished hit as "never asked".
  void cancelIfPending() {
    if (!_started || _settled || _cancelled) return;
    _cancelled = true;
    // Unblock a consumer that is somehow still waiting.
    if (!_completer.isCompleted) _completer.complete(null);
    _callbacks.onCancelled?.call(spec.provider);
    _onSettled();
  }
}
