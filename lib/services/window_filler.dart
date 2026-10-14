// lib/services/window_filler.dart
//
// Tops the player's window up with the tracks that follow the current one.
//
// WHY THIS IS NOT JUST Future.wait
//
// The window used to be filled by resolving every missing track at once. A
// resolve is a network round trip and, for some sources, a proof-of-origin
// computation, so every track change started up to four of them together - a
// burst of radio and CPU for entries nobody needs for minutes, repeated for the
// whole listening session.
//
// They now go one at a time, in playback order, each appended as soon as it is
// ready. The next track is available as early as before (it is first in line);
// the ones behind it trickle in instead of landing together.
//
// THE RULES
//
//   * Runs are serialised. A run reads which tracks are loaded only after the
//     previous run has finished touching the window, so nothing is appended
//     twice.
//   * The latest request wins. An older run stops at its next step instead of
//     appending behind entries a newer run is about to add.
//   * A run is abandoned when the listener has moved on (the current track is
//     no longer its owner): the new current track's own run owns the window.
//   * A track that cannot be resolved is skipped, not retried here.
//   * A failing run never poisons the next one.

import 'dart:async';

class WindowFiller<T, S> {
  Future<void> _tail = Future<void>.value();
  int _latest = 0;

  /// Requests a fill. Completes when this run has finished or given way.
  ///
  /// [owner] is the id of the current track the run is for, and [currentOwner]
  /// reports the one that is current now. [upcoming] is evaluated when the run
  /// STARTS (not when it is requested), so it sees the queue as it is then.
  Future<void> extend({
    required String owner,
    required String? Function() currentOwner,
    required List<T> Function() upcoming,
    required String Function(T track) idOf,
    required Set<String?> Function() loaded,
    required Future<S?> Function(T track) resolve,
    required Future<void> Function(S source) append,
  }) {
    final run = ++_latest;
    final work = _tail.then(
      (_) => _run(
        run: run,
        owner: owner,
        currentOwner: currentOwner,
        upcoming: upcoming,
        idOf: idOf,
        loaded: loaded,
        resolve: resolve,
        append: append,
      ),
    );
    // The chain must survive a failed run; the caller still sees the failure.
    _tail = work.then<void>((_) {}, onError: (Object _) {});
    return work;
  }

  Future<void> _run({
    required int run,
    required String owner,
    required String? Function() currentOwner,
    required List<T> Function() upcoming,
    required String Function(T track) idOf,
    required Set<String?> Function() loaded,
    required Future<S?> Function(T track) resolve,
    required Future<void> Function(S source) append,
  }) async {
    bool stale() => run != _latest || currentOwner() != owner;
    if (stale()) return;

    final pending = upcoming();
    if (pending.isEmpty) return;

    final have = loaded();
    pending.removeWhere((t) => have.contains(idOf(t)));

    for (final track in pending) {
      if (stale()) return;
      final source = await resolve(track);
      // The listener may have moved on while this resolved. The newer run owns
      // the window now, and appending here would land this track behind its.
      if (stale()) return;
      if (source == null) continue;
      await append(source);
    }
  }
}
