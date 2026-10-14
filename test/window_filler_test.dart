import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/window_filler.dart';

/// THE WINDOW FILL THIS FILE PINS.
///
/// A track change used to resolve every missing upcoming track at once - up to
/// four stream resolutions in parallel, each a network round trip (and, for some
/// sources, a proof-of-origin computation), every few minutes for as long as the
/// player was open. They now go one at a time, in playback order, each appended
/// as soon as it is ready.
///
/// The rules that make that safe are the other half of this file: runs never
/// overlap, the latest request wins, a run for a track the listener has left
/// stops, and one failing run never poisons the next.

/// A hand-driven resolver: every call parks until the test completes it, so the
/// tests can see exactly what is in flight.
class _Resolver {
  final List<String> started = [];
  final Map<String, Completer<String?>> _pending = {};
  int inFlight = 0;
  int maxInFlight = 0;

  Future<String?> call(String id) {
    started.add(id);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final c = Completer<String?>();
    _pending[id] = c;
    return c.future.whenComplete(() => inFlight--);
  }

  void finish(String id, [String? source]) =>
      _pending[id]!.complete(source ?? 'src:$id');
  void fail(String id) => _pending[id]!.completeError(StateError('boom $id'));
  void finishNothing(String id) => _pending[id]!.complete(null);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late WindowFiller<String, String> filler;
  late _Resolver resolver;
  late List<String> appended;
  late Set<String?> loaded;
  late String current;

  Future<void> extend({
    String owner = 'a',
    List<String> upcoming = const ['b', 'c', 'd', 'e'],
  }) =>
      filler.extend(
        owner: owner,
        currentOwner: () => current,
        upcoming: () => List.of(upcoming),
        idOf: (t) => t,
        loaded: () => loaded,
        resolve: resolver.call,
        append: (s) async {
          appended.add(s);
          loaded.add(s.replaceFirst('src:', ''));
        },
      );

  setUp(() {
    filler = WindowFiller<String, String>();
    resolver = _Resolver();
    appended = [];
    loaded = {'a'};
    current = 'a';
  });

  test('resolves one track at a time, in playback order', () async {
    final done = extend();
    await _settle();
    expect(resolver.started, ['b']);

    resolver.finish('b');
    await _settle();
    expect(resolver.started, ['b', 'c']);
    resolver.finish('c');
    await _settle();
    resolver.finish('d');
    await _settle();
    resolver.finish('e');
    await done;

    expect(resolver.maxInFlight, 1, reason: 'never more than one resolve');
    expect(appended, ['src:b', 'src:c', 'src:d', 'src:e']);
  });

  test('each track is appended as soon as it is ready, not at the end',
      () async {
    final done = extend();
    await _settle();
    resolver.finish('b');
    await _settle();

    // The next track is in the window while the ones behind it are still
    // resolving - the property that keeps the first-in-line track as early as it
    // was when everything resolved together.
    expect(appended, ['src:b']);
    expect(resolver.started, ['b', 'c']);

    resolver.finish('c');
    await _settle();
    resolver.finish('d');
    await _settle();
    resolver.finish('e');
    await done;
  });

  test('tracks already in the window are not resolved again', () async {
    loaded = {'a', 'b', 'c'};
    final done = extend();
    await _settle();
    expect(resolver.started, ['d']);
    resolver.finish('d');
    await _settle();
    resolver.finish('e');
    await done;
    expect(appended, ['src:d', 'src:e']);
  });

  test('a track that will not resolve is skipped and the rest still land',
      () async {
    final done = extend();
    await _settle();
    resolver.finishNothing('b');
    await _settle();
    resolver.finish('c');
    await _settle();
    resolver.finish('d');
    await _settle();
    resolver.finish('e');
    await done;
    expect(appended, ['src:c', 'src:d', 'src:e']);
  });

  test('stops when the listener has moved to another track', () async {
    final done = extend();
    await _settle();
    resolver.finish('b');
    await _settle();
    expect(appended, ['src:b']);

    current = 'z'; // skipped away while "c" was resolving
    resolver.finish('c');
    await done;

    expect(appended, ['src:b'],
        reason: 'a track resolved for a stale owner must not be appended');
    expect(resolver.started, ['b', 'c'], reason: 'and nothing further starts');
  });

  test('does nothing at all for a stale owner', () async {
    current = 'z';
    await extend();
    expect(resolver.started, isEmpty);
    expect(appended, isEmpty);
  });

  test('the latest request wins: an older run gives way at its next step',
      () async {
    final first = extend(owner: 'a', upcoming: ['b', 'c']);
    await _settle();
    expect(resolver.started, ['b']);

    // A second request for the same owner arrives while "b" is resolving.
    final second = extend(owner: 'a', upcoming: ['b', 'c']);

    resolver.finish('b');
    await first;
    // "b" had already been resolved for the older run when it was superseded -
    // the older run discards it rather than appending behind the newer run.
    expect(appended, isEmpty);

    // The newer run now starts, and reads the window as it is NOW.
    await _settle();
    expect(resolver.started, ['b', 'b']);
    resolver.finish('b');
    await _settle();
    resolver.finish('c');
    await second;

    expect(appended, ['src:b', 'src:c'],
        reason: 'every track exactly once, in order');
  });

  test('runs never overlap, so a later run sees what an earlier one added',
      () async {
    final first = extend(owner: 'a', upcoming: ['b']);
    await _settle();
    final second = extend(owner: 'a', upcoming: ['b', 'c']);

    resolver.finish('b');
    await first;
    await _settle();
    // The second run started only after the first finished; "b" is a duplicate
    // resolve of the discarded one, then "c".
    expect(resolver.inFlight, 1);
    resolver.finish('b');
    await _settle();
    resolver.finish('c');
    await second;

    expect(appended.where((s) => s == 'src:b').length, 1,
        reason: 'no track is appended twice');
    expect(resolver.maxInFlight, 1);
  });

  test('a failing run does not poison the next one', () async {
    final failing = extend(upcoming: ['b']);
    await _settle();
    resolver.fail('b');
    await expectLater(failing, throwsStateError);

    final next = extend(upcoming: ['c']);
    await _settle();
    resolver.finish('c');
    await next;
    expect(appended, ['src:c']);
  });

  test('an empty upcoming list is a quiet no-op', () async {
    await extend(upcoming: const []);
    expect(resolver.started, isEmpty);
  });
}
