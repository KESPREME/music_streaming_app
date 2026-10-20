import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/services/app_platform.dart';
import 'package:music_streaming_app/services/session/session_snapshot.dart';
import 'package:music_streaming_app/services/session/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track t(String id, {String? name}) => Track(
      id: id,
      trackName: name ?? 'Song $id',
      artistName: 'Artist',
      albumName: 'Album',
      previewUrl: '',
    );

SessionCore core({
  String current = 'c',
  int n = 3,
  bool shuffle = false,
  List<String> order = const [],
  List<Track> queue = const [],
}) =>
    SessionCore(
      track: t(current),
      context: [for (var i = 0; i < n; i++) t('s$i')],
      order: order,
      playlistId: 'PL1',
      queue: queue,
      shuffle: shuffle,
      repeat: 1,
      durationMs: 200000,
    );

Future<void> until(bool Function() ok, {int ms = 4000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!ok() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionCore', () {
    test('survives a round trip with the track, list, queue and modes', () {
      final c = core(shuffle: true, order: ['s2', 's0', 's1'], queue: [t('q1')]);
      final back = SessionCore.decode(c.encode())!;
      expect(back.track.id, 'c');
      expect(back.context.map((e) => e.id), ['s0', 's1', 's2']);
      expect(back.order, ['s2', 's0', 's1']);
      expect(back.queue.map((e) => e.id), ['q1']);
      expect(back.playlistId, 'PL1');
      expect(back.shuffle, isTrue);
      expect(back.repeat, 1);
      expect(back.durationMs, 200000);
    });

    test('damaged, empty, foreign or future data is ignored, never thrown', () {
      expect(SessionCore.decode(null), isNull);
      expect(SessionCore.decode(''), isNull);
      expect(SessionCore.decode('{not json'), isNull);
      expect(SessionCore.decode('[]'), isNull);
      expect(SessionCore.decode('{"v":99,"track":{}}'), isNull);
      expect(SessionCore.decode('{"v":1}'), isNull);
      expect(SessionCore.decode('{"v":1,"track":{"id":""}}'), isNull);
    });

    test('a track that will not decode is dropped, the rest survive', () {
      final good = jsonDecode(jsonEncode(core().toJson())) as Map<String, dynamic>;
      (good['context'] as List).insert(1, 'garbage');
      final back = SessionCore.decode(jsonEncode(good))!;
      expect(back.context.length, 3);
    });

    test('a long list is windowed around the current song, not truncated at the top',
        () {
      final big = [for (var i = 0; i < 1000; i++) t('s$i')];
      final c = SessionCore(track: t('s700'), context: big, playlistId: 'x');
      final trimmed = c.trimmed();
      expect(trimmed.context.length, SessionCore.maxContext);
      expect(trimmed.context.any((e) => e.id == 's700'), isTrue);
      expect(trimmed.context.last.id, isNot('s199'));
      // What plays next is still there.
      final at = trimmed.context.indexWhere((e) => e.id == 's700');
      expect(trimmed.context.length - at, greaterThan(100));
    });

    test('a window at the very end of the list stays full', () {
      final big = [for (var i = 0; i < 500; i++) t('s$i')];
      final c = SessionCore(track: t('s499'), context: big).trimmed();
      expect(c.context.length, SessionCore.maxContext);
      expect(c.context.last.id, 's499');
    });

    test('the shuffle order drops ids that fell out of the window', () {
      final big = [for (var i = 0; i < 400; i++) t('s$i')];
      final c = SessionCore(
        track: t('s350'),
        context: big,
        order: [for (final x in big) x.id],
        shuffle: true,
      ).trimmed();
      expect(c.order.length, c.context.length);
      expect(c.order.every((id) => c.context.any((e) => e.id == id)), isTrue);
    });

    test('the queue is capped', () {
      final q = [for (var i = 0; i < 300; i++) t('q$i')];
      expect(core(queue: q).trimmed().queue.length, SessionCore.maxQueue);
    });

    test('the signature changes when the song, list, queue or a mode does', () {
      final base = core().signature;
      expect(core(current: 'z').signature, isNot(base));
      expect(core(n: 4).signature, isNot(base));
      expect(core(shuffle: true).signature, isNot(base));
      expect(core(queue: [t('q')]).signature, isNot(base));
      expect(core().signature, base);
    });
  });

  group('SessionSnapshot.resumeAt', () {
    SessionSnapshot snap(int pos, {int dur = 200000}) => SessionSnapshot(
          SessionCore(track: t('a'), durationMs: dur),
          positionMs: pos,
        );

    test('resumes in the middle of a song exactly', () {
      expect(snap(95000).resumeAt, const Duration(milliseconds: 95000));
    });

    test('a few seconds in is just the start', () {
      expect(snap(3000).resumeAt, Duration.zero);
    });

    test('a few seconds from the end restarts rather than resuming into silence',
        () {
      expect(snap(197000).resumeAt, Duration.zero);
    });

    test('an unknown duration still resumes, and a negative position is zero', () {
      expect(snap(60000, dur: 0).resumeAt, const Duration(seconds: 60));
      expect(snap(-5).resumeAt, Duration.zero);
    });

    test('a position past the end is clamped', () {
      expect(snap(900000).position, const Duration(milliseconds: 200000));
    });
  });

  group('UiSession', () {
    test('round trips', () {
      const ui = UiSession(tab: 2, libraryFilter: 'Albums', librarySort: 1);
      expect(UiSession.decode(jsonEncode(ui.toJson())), ui);
    });

    test('garbage and out-of-range tabs fall back to the defaults', () {
      expect(UiSession.decode('nope'), const UiSession());
      expect(UiSession.decode(null), const UiSession());
      expect(UiSession.decode('{"tab":9}').tab, 0);
      expect(UiSession.decode('{"tab":-1}').tab, 0);
    });
  });

  group('SessionStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('is inert until enabled', () async {
      final store = SessionStore();
      await store.saveCore(core());
      await store.savePosition(5000);
      expect(await store.loadPlayback(), isNull);
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys(), isEmpty);
    });

    test('stores and restores the core and the playhead', () async {
      final store = SessionStore()..enable();
      await store.saveCore(core());
      await store.savePosition(61000);
      final reader = SessionStore()..enable();
      final loaded = await reader.loadPlayback();
      expect(loaded, isNotNull);
      expect(loaded!.core.track.id, 'c');
      expect(loaded.positionMs, 61000);
    });

    test('turning the feature off forgets the session and stops writing',
        () async {
      final store = SessionStore()..enable();
      await store.saveCore(core());
      await store.setRestoreEnabled(false);
      expect(await store.loadPlayback(), isNull);
      await store.saveCore(core());
      final p = await SharedPreferences.getInstance();
      expect(p.getString('session_v1_core'), isNull);
      expect(p.getBool('session_restore_enabled'), isFalse);

      final next = SessionStore()..enable();
      await next.preload();
      expect(next.restoreEnabled, isFalse, reason: 'the choice survives a restart');
    });

    test('identical consecutive cores are written once', () async {
      var writes = 0;
      final store = SessionStore(prefs: () async {
        writes++;
        return SharedPreferences.getInstance();
      })
        ..enable();
      await store.saveCore(core());
      await store.saveCore(core());
      expect(writes, 1);
    });

    test('a failing preferences read never throws', () async {
      final store = SessionStore(prefs: () async => throw StateError('disk'))
        ..enable();
      await store.preload();
      expect(await store.loadPlayback(), isNull);
      await store.saveCore(core());
      await store.savePosition(1);
      await store.clearPlayback();
    });

    test('UI session is read synchronously after preload and saved on change',
        () async {
      final a = SessionStore()..enable();
      await a.saveUi(const UiSession(tab: 2, libraryFilter: 'Playlists'));
      final b = SessionStore()..enable();
      expect(b.ui.tab, 0, reason: 'not loaded yet');
      await b.preload();
      expect(b.ui.tab, 2);
      expect(b.ui.libraryFilter, 'Playlists');
    });
  });

  group('SessionRecorder', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    late SessionStore store;
    late SessionRecorder rec;
    SessionCore? live;
    var pos = 0;

    SessionRecorder make() => SessionRecorder(
          store: store,
          capture: () => live,
          positionMs: () => pos,
          debounce: const Duration(milliseconds: 30),
          tick: const Duration(milliseconds: 40),
        );

    Future<String?> core0() async =>
        (await SharedPreferences.getInstance()).getString('session_v1_core');
    Future<int?> pos0() async =>
        (await SharedPreferences.getInstance()).getInt('session_v1_pos');

    setUp(() {
      store = SessionStore()..enable();
      live = core();
      pos = 0;
      rec = make();
    });
    tearDown(() => rec.dispose());

    test('a burst of changes is one write, after the debounce', () async {
      for (final id in ['a', 'b', 'c', 'd']) {
        live = core(current: id);
        rec.note(playing: false);
      }
      expect(await core0(), isNull, reason: 'not yet');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(jsonDecode((await core0())!)['track']['id'], 'd');
    });

    test('nothing changed, nothing written', () async {
      rec.note(playing: false);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final first = await core0();
      await (await SharedPreferences.getInstance()).remove('session_v1_core');
      rec.note(playing: false);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(first, isNotNull);
      expect(await core0(), isNull, reason: 'same signature: not rewritten');
    });

    test('while playing the playhead is written on a tick', () async {
      rec.note(playing: true);
      pos = 12000;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await pos0(), 12000);
    });

    test('pausing writes everything immediately, with the final position',
        () async {
      rec.note(playing: true);
      pos = 77000;
      rec.note(playing: false);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(await pos0(), 77000);
      expect(await core0(), isNotNull);
    });

    test('flush writes now (the OS is about to take the process)', () async {
      pos = 4242;
      await rec.flush();
      expect(await pos0(), 4242);
    });

    test('with nothing loaded the stored session is cleared', () async {
      await rec.flush();
      expect(await core0(), isNotNull);
      live = null;
      await rec.flush();
      expect(await core0(), isNull);
      expect(await pos0(), isNull);
    });

    test('a disabled store records nothing and starts no timers', () async {
      final off = SessionStore();
      final r = SessionRecorder(
        store: off,
        capture: () => live,
        positionMs: () => pos,
        debounce: const Duration(milliseconds: 5),
        tick: const Duration(milliseconds: 5),
      );
      r.note(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      r.dispose();
    });

    test('after dispose it is silent', () async {
      rec.dispose();
      rec.note(playing: true);
      await rec.flush();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(await core0(), isNull);
    });
  });

  group('MusicProvider restores the session', () {
    Future<MusicProvider> boot(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final store = SessionStore()..enable();
      await store.preload();
      return MusicProvider(sessionStore: store);
    }

    Map<String, Object> saved({int pos = 95000, bool shuffle = false}) => {
          'session_v1_core': core(
            current: 's1',
            shuffle: shuffle,
            order: shuffle ? ['s2', 's1', 's0'] : const [],
            queue: [t('q1')],
          ).encode(),
          'session_v1_pos': pos,
          if (shuffle) 'shuffleEnabled': true,
        };

    test('the song, queue and playhead come back - paused, never playing',
        () async {
      final p = await boot(saved());
      await until(() => p.currentTrack != null);
      expect(p.currentTrack?.id, 's1');
      expect(p.isPlaying, isFalse);
      expect(p.position, const Duration(milliseconds: 95000));
      expect(p.queue.map((e) => e.id), ['q1']);
      expect(p.currentPlayingTracks?.length, 3);
      expect(p.restoredResumePoint, const Duration(milliseconds: 95000));
      p.dispose();
    });

    test('the shuffle order comes back as it was', () async {
      final p = await boot(saved(shuffle: true));
      await until(() => p.currentTrack != null);
      expect(p.currentTrack?.id, 's1');
      expect(p.shuffleEnabled, isTrue);
      p.dispose();
    });

    test('a song restored near its start begins from the top', () async {
      final p = await boot(saved(pos: 2000));
      await until(() => p.currentTrack != null);
      expect(p.restoredResumePoint, isNull);
      expect(p.position, Duration.zero);
      p.dispose();
    });

    test('with "remember what I was playing" off, nothing is restored',
        () async {
      final p = await boot({...saved(), 'session_restore_enabled': false});
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(p.currentTrack, isNull);
      p.dispose();
    });

    test('with nothing saved the player starts empty, as before', () async {
      final p = await boot({});
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(p.currentTrack, isNull);
      p.dispose();
    });

    test('damaged data starts empty and does not break init', () async {
      final p = await boot({'session_v1_core': '{broken'});
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(p.currentTrack, isNull);
      p.dispose();
    });

    test('a default provider (tests, previews) restores and records nothing',
        () async {
      SharedPreferences.setMockInitialValues(saved());
      final p = MusicProvider();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(p.currentTrack, isNull);
      p.dispose();
    });
  });

  group('AppPlatform', () {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    setUp(AppPlatform.resetCache);
    tearDown(() {
      messenger.setMockMethodCallHandler(AppPlatform.channel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('reads the installed version from the host, once', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(AppPlatform.channel, (call) async {
        calls++;
        return {
          'versionName': '1.2.3',
          'versionCode': 45,
          'packageName': 'x.y',
          'abis': ['arm64-v8a', 'armeabi-v7a'],
          'sdkInt': 34,
        };
      });
      final a = await AppPlatform.info();
      final b = await AppPlatform.info();
      expect(a.versionName, '1.2.3');
      expect(a.versionCode, 45);
      expect(a.abis.first, 'arm64-v8a');
      expect(identical(a, b), isTrue);
      expect(calls, 1);
    });

    test('without a host it reports the unknown version instead of throwing',
        () async {
      final info = await AppPlatform.info();
      expect(info.isKnown, isFalse);
      expect(info.versionName, '0.0.0');
    });

    test('leaving moves to the background when the host can', () async {
      var popped = false;
      messenger.setMockMethodCallHandler(AppPlatform.channel, (c) async {
        return c.method == 'moveToBack';
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        if (c.method == 'SystemNavigator.pop') popped = true;
        return null;
      });
      await AppPlatform.leaveApp();
      expect(popped, isFalse);
    });

    test('leaving falls back to the normal exit when it cannot', () async {
      var popped = false;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        if (c.method == 'SystemNavigator.pop') popped = true;
        return null;
      });
      await AppPlatform.leaveApp();
      expect(popped, isTrue);
    });

    test('install results map to the enum', () async {
      messenger.setMockMethodCallHandler(AppPlatform.channel, (c) async {
        return switch (c.arguments['path']) {
          'ok' => 'started',
          'perm' => 'needs_permission',
          _ => 'unavailable',
        };
      });
      expect(await AppPlatform.installApk('ok'), InstallResult.started);
      expect(await AppPlatform.installApk('perm'), InstallResult.needsPermission);
      expect(await AppPlatform.installApk('nope'), InstallResult.unavailable);
    });
  });
}
