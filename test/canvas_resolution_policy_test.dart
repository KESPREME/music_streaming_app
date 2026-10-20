import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/canvas_resolution_service.dart';

Track _t(String id) => Track(
      id: id,
      trackName: 'Song $id',
      artistName: 'Artist',
      albumName: 'Album',
      albumArtUrl: '',
      previewUrl: '',
      durationMs: 1000,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = CanvasResolutionService.instance;

  group('LatestFirstGate', () {
    test('admits up to maxConcurrent at once', () async {
      final g = LatestFirstGate(maxConcurrent: 2, maxWaiting: 4);
      expect(await g.acquire(), isTrue);
      expect(await g.acquire(), isTrue);
      expect(g.active, 2);
      var third = false;
      unawaited(g.acquire().then((v) => third = v));
      await Future<void>.delayed(Duration.zero);
      expect(third, isFalse, reason: 'third waits for a slot');
      expect(g.waiting, 1);
    });

    test('the newest waiter gets the freed slot first', () async {
      final g = LatestFirstGate(maxConcurrent: 1, maxWaiting: 4);
      await g.acquire();
      final order = <String>[];
      unawaited(g.acquire().then((_) => order.add('old')));
      unawaited(g.acquire().then((_) => order.add('new')));
      g.release();
      await Future<void>.delayed(Duration.zero);
      expect(order, ['new']);
      g.release();
      await Future<void>.delayed(Duration.zero);
      expect(order, ['new', 'old']);
    });

    test('a full queue drops the oldest waiter with false', () async {
      final g = LatestFirstGate(maxConcurrent: 1, maxWaiting: 2);
      await g.acquire();
      final results = <int, bool>{};
      for (var i = 0; i < 3; i++) {
        unawaited(g.acquire().then((v) => results[i] = v));
      }
      await Future<void>.delayed(Duration.zero);
      expect(results, {0: false});
      expect(g.waiting, 2);
    });

    test('release with no waiters frees the slot', () async {
      final g = LatestFirstGate(maxConcurrent: 1, maxWaiting: 2);
      await g.acquire();
      g.release();
      expect(g.active, 0);
      g.release();
      expect(g.active, 0, reason: 'never negative');
    });
  });

  group('CanvasResolutionService retry policy', () {
    late DateTime now;
    late int calls;

    setUp(() {
      svc.debugReset();
      svc.debugAllowInTests = true;
      now = DateTime(2026, 1, 1, 12);
      svc.debugNow = () => now;
      calls = 0;
    });
    tearDown(svc.debugReset);

    test('a found canvas is cached', () async {
      svc.debugResolver = (t) async {
        calls++;
        return (url: '/tmp/${t.id}.mp4', transient: false);
      };
      expect(await svc.resolveCanvas(_t('a')), '/tmp/a.mp4');
      expect(await svc.resolveCanvas(_t('a')), '/tmp/a.mp4');
      expect(calls, 1);
      expect(svc.cachedCanvas('a'), '/tmp/a.mp4');
    });

    test('a definite miss is remembered', () async {
      svc.debugResolver = (t) async {
        calls++;
        return (url: null, transient: false);
      };
      expect(await svc.resolveCanvas(_t('b')), isNull);
      now = now.add(const Duration(hours: 1));
      expect(await svc.resolveCanvas(_t('b')), isNull);
      expect(calls, 1);
    });

    test('a transient failure is retried after the window, not before', () async {
      var fail = true;
      svc.debugResolver = (t) async {
        calls++;
        return fail
            ? (url: null, transient: true)
            : (url: '/tmp/${t.id}.mp4', transient: false);
      };
      expect(await svc.resolveCanvas(_t('c')), isNull);
      now = now.add(const Duration(minutes: 1));
      expect(await svc.resolveCanvas(_t('c')), isNull);
      expect(calls, 1, reason: 'inside the retry window');

      fail = false;
      now = now.add(CanvasResolutionService.transientRetryAfter);
      expect(await svc.resolveCanvas(_t('c')), '/tmp/c.mp4');
      expect(calls, 2);
    });

    test('a throwing resolver counts as transient', () async {
      svc.debugResolver = (t) async {
        calls++;
        throw TimeoutException('slow');
      };
      expect(await svc.resolveCanvas(_t('d')), isNull);
      expect(svc.cachedCanvas('d'), isNull);
      now = now.add(CanvasResolutionService.transientRetryAfter);
      await svc.resolveCanvas(_t('d'));
      expect(calls, 2);
    });

    test('evict forgets a dead canvas and waits out the window', () async {
      svc.debugResolver = (t) async {
        calls++;
        return (url: 'https://cdn.example/${t.id}.mp4', transient: false);
      };
      await svc.resolveCanvas(_t('e'));
      svc.evict('e');
      expect(svc.cachedCanvas('e'), isNull);
      expect(await svc.resolveCanvas(_t('e')), isNull);
      expect(calls, 1);
      now = now.add(CanvasResolutionService.transientRetryAfter);
      expect(await svc.resolveCanvas(_t('e')), 'https://cdn.example/e.mp4');
      expect(calls, 2);
    });

    test('the settled card is resolved before cards scrolled past', () async {
      final started = <String>[];
      final gates = <String, Completer<void>>{};
      svc.debugResolver = (t) async {
        started.add(t.id);
        final c = gates[t.id] = Completer<void>();
        await c.future;
        return (url: '/tmp/${t.id}.mp4', transient: false);
      };
      // Two in flight fill both slots; three more queue while scrolling.
      final futures = [
        for (final id in ['p1', 'p2', 'q1', 'q2', 'q3']) svc.resolveCanvas(_t(id)),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(started, ['p1', 'p2']);
      gates['p1']!.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(started.last, 'q3', reason: 'newest request goes next');
      for (final g in gates.values) {
        if (!g.isCompleted) g.complete();
      }
      await Future<void>.delayed(Duration.zero);
      for (final g in gates.values) {
        if (!g.isCompleted) g.complete();
      }
      await Future.wait(futures);
    });
  });
}
