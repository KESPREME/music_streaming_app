import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/app_platform.dart';
import 'package:music_streaming_app/services/update/update_downloader.dart';
import 'package:music_streaming_app/services/update/update_http.dart';
import 'package:music_streaming_app/services/update/update_models.dart';
import 'package:music_streaming_app/services/update/update_repository.dart';
import 'package:music_streaming_app/services/update/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UPDATES: the state machine. Real UpdateService, real SharedPreferences
/// (in-memory), real files in a temp folder - fake network and fake installer.

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeRepository extends UpdateRepository {
  FakeRepository();

  FetchResult next = const Fetched(null, null);
  int calls = 0;
  final List<({UpdateChannel channel, List<String> abis, String? etag})> requests = [];
  Completer<void>? gate;
  Object? throwError;
  ReleaseInfo? tagResult;
  Completer<void>? tagGate;
  final List<String> tagCalls = [];

  @override
  Future<FetchResult> fetchLatest({
    required UpdateChannel channel,
    required List<String> abis,
    String? etag,
  }) async {
    calls++;
    requests.add((channel: channel, abis: abis, etag: etag));
    final g = gate;
    if (g != null) await g.future;
    final err = throwError;
    if (err != null) throw err;
    return next;
  }

  @override
  Future<ReleaseInfo?> fetchByTag(String tag, List<String> abis) async {
    tagCalls.add(tag);
    final g = tagGate;
    if (g != null) await g.future;
    return tagResult;
  }
}

class FakeDownloader extends UpdateDownloader {
  FakeDownloader(this.bytes);

  Uint8List bytes;
  DownloadOutcome? forced;
  Object? throwError;
  int steps = 4;
  Duration stepDelay = Duration.zero;
  Completer<void>? gate;
  int downloads = 0;

  @override
  Future<DownloadOutcome> download(
    ReleaseAsset asset, {
    required Directory dir,
    void Function(DownloadProgress)? onProgress,
    void Function()? onVerifying,
    CancelToken? cancel,
  }) async {
    downloads++;
    final err = throwError;
    if (err != null) throw err;
    await dir.create(recursive: true);
    final part = File(joinPath(dir, '${asset.name}.part'));
    for (var i = 1; i <= steps; i++) {
      onProgress?.call(DownloadProgress(
        received: asset.size * i ~/ steps,
        total: asset.size,
        bytesPerSecond: 1000.0 * i,
        etaSeconds: steps - i,
      ));
      if (i == steps ~/ 2) {
        part.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
        final g = gate;
        if (g != null) {
          await Future.any([g.future, cancel?.onCancel ?? Completer<void>().future]);
          if (cancel?.isCancelled ?? false) return DownloadOutcome.cancelled;
        }
      }
      if (stepDelay > Duration.zero) await Future<void>.delayed(stepDelay);
    }
    final f = forced;
    if (f != null && f is! DownloadCompleted) {
      if (f is DownloadCorrupt) onVerifying?.call();
      return f;
    }
    onVerifying?.call();
    await Future<void>.delayed(Duration.zero);
    final out = File(joinPath(dir, asset.name))..writeAsBytesSync(bytes);
    if (part.existsSync()) part.deleteSync();
    return DownloadOutcome.completed(out);
  }
}

/// Preferences that fail on every touch.
class _ThrowingPrefs implements SharedPreferences {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('prefs are broken: ${invocation.memberName}');
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final Uint8List _apk = Uint8List.fromList(List<int>.generate(4000, (i) => (i * 7) % 251));
String _sha(List<int> b) => crypto.sha256.convert(b).toString();

const _installedInfo = AppInfo(
  versionName: '1.0.0',
  versionCode: 100,
  packageName: 'app.minemusic',
  abis: ['arm64-v8a', 'armeabi-v7a'],
  sdkInt: 34,
);

const _notes = ReleaseNotes(
  title: 'Glass that behaves',
  summary: 'A calmer player.',
  highlights: ['Equalizer', 'Sleep timer'],
  sections: [
    ReleaseSection(title: 'New', icon: 'sparkle', items: ['Equalizer', 'Sleep timer']),
  ],
  notesMarkdown: '## New\n- Equalizer\n- Sleep timer',
);

ReleaseInfo _rel({
  String version = '1.1.0',
  int build = 142,
  int? minSdk,
  bool withAsset = true,
  ReleaseNotes notes = _notes,
  Uint8List? bytes,
}) {
  final data = bytes ?? _apk;
  final name = 'MineMusic-$version-b$build.apk';
  return ReleaseInfo(
    version: version,
    build: build,
    tag: 'v$version+$build',
    minSdk: minSdk,
    notes: notes,
    asset: withAsset
        ? ReleaseAsset(
            name: name,
            url: 'https://example.com/$name',
            size: data.length,
            sha256: _sha(data),
          )
        : null,
    releaseUrl: 'https://github.com/KESPREME/music_streaming_app/releases/tag/v$version%2B$build',
  );
}

Future<void> until(bool Function() cond, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for a condition');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory root;
  late Directory updates;
  late FakeRepository repo;
  late FakeDownloader dl;
  late AppInfo app;
  late DateTime clock;
  late InstallResult installResult;
  late bool canInstall;
  late List<String> installerPaths;
  late int appInfoCalls;
  final created = <UpdateService>[];

  setUp(() {
    root = Directory.systemTemp.createTempSync('update_svc_');
    updates = Directory('${root.path}${Platform.pathSeparator}updates');
    repo = FakeRepository();
    dl = FakeDownloader(_apk);
    app = _installedInfo;
    clock = DateTime.utc(2026, 10, 20, 12);
    installResult = InstallResult.started;
    canInstall = false;
    installerPaths = [];
    appInfoCalls = 0;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    for (final s in created) {
      s.dispose();
    }
    created.clear();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  UpdateService make({
    Future<SharedPreferences> Function()? prefs,
    Future<AppInfo> Function()? appInfo,
    Future<Directory> Function()? dir,
    Duration interval = const Duration(hours: 6),
  }) {
    final s = UpdateService(
      repository: repo,
      downloader: dl,
      prefs: prefs ?? SharedPreferences.getInstance,
      updatesDir: dir ?? () async => updates,
      appInfo: appInfo ??
          () async {
            appInfoCalls++;
            return app;
          },
      installer: (path) async {
        installerPaths.add(path);
        return installResult;
      },
      canInstall: () async => canInstall,
      now: () => clock,
      minCheckInterval: interval,
    );
    created.add(s);
    return s;
  }

  void seedFile(String name, List<int> bytes) {
    updates.createSync(recursive: true);
    File('${updates.path}${Platform.pathSeparator}$name').writeAsBytesSync(bytes);
  }

  List<String> filesInUpdates() => updates.existsSync()
      ? (updates.listSync().whereType<File>().map((f) => baseName(f.path)).toList()..sort())
      : <String>[];

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  /// A service that has already found `_rel()` and is `available`.
  Future<UpdateService> available({ReleaseInfo? release, String etag = '"e1"'}) async {
    repo.next = Fetched(release ?? _rel(), etag);
    final s = make();
    await s.check(force: true);
    expect(s.status, UpdateStatus.available);
    return s;
  }

  /// ... and has downloaded it: `ready`.
  Future<UpdateService> ready() async {
    final s = await available();
    await s.download();
    expect(s.status, UpdateStatus.ready);
    return s;
  }

  // -------------------------------------------------------------------------

  group('initialize', () {
    test('starts from sensible defaults and reports what is installed', () async {
      final s = make();
      expect(s.initialized, isFalse);
      await s.initialize();
      expect(s.initialized, isTrue);
      expect(s.status, UpdateStatus.idle);
      expect(s.release, isNull);
      expect(s.progress, 0);
      expect(s.autoCheck, isTrue);
      expect(s.channel, UpdateChannel.stable);
      expect(s.lastChecked, isNull);
      expect(s.hasUpdate, isFalse);
      expect(s.shouldPrompt, isFalse);
      expect(s.whatsNew, isNull);
      expect(s.installed, _installedInfo);
      expect(s.state, const UpdateState());
    });

    test('is idempotent, even when called twice at once', () async {
      final s = make();
      await Future.wait([s.initialize(), s.initialize()]);
      await s.initialize();
      expect(appInfoCalls, 1);
    });

    test('loads the stored settings', () async {
      final ms = DateTime.utc(2026, 10, 19, 8).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'update_channel': 'beta',
        'update_last_check_ms': ms,
      });
      final s = make();
      await s.initialize();
      expect(s.autoCheck, isFalse);
      expect(s.channel, UpdateChannel.beta);
      expect(s.lastChecked!.millisecondsSinceEpoch, ms);
      expect(s.status, UpdateStatus.upToDate); // a check has happened before
    });

    test('ignores stored values of the wrong type', () async {
      SharedPreferences.setMockInitialValues({
        'update_auto_check': 'yes',
        'update_channel': 7,
        'update_last_check_ms': 'yesterday',
        'update_etag': 5,
      });
      final s = make();
      await s.initialize();
      expect(s.autoCheck, isTrue);
      expect(s.channel, UpdateChannel.stable);
      expect(s.lastChecked, isNull);
    });

    test('records the running version', () async {
      await make().initialize();
      expect((await prefs()).getString('update_last_run_version'), '1.0.0+100');
    });

    test('does not throw when the preferences cannot be opened', () async {
      final s = make(prefs: () async => throw Exception('disk is gone'));
      await s.initialize();
      expect(s.initialized, isTrue);
      repo.next = Fetched(_rel(), '"e"');
      await s.check();
      expect(s.status, UpdateStatus.available);
      await s.setAutoCheck(false);
      expect(s.autoCheck, isFalse);
      await s.skipThisVersion();
      await s.markPrompted();
      await s.setChannel(UpdateChannel.beta);
      expect(s.channel, UpdateChannel.beta);
    });

    test('does not throw when every preference call throws', () async {
      final s = make(prefs: () async => _ThrowingPrefs());
      await s.initialize();
      expect(s.initialized, isTrue);
      repo.next = Fetched(_rel(), '"e"');
      await s.check();
      expect(s.status, UpdateStatus.available);
      await s.setAutoCheck(false);
      await s.skipThisVersion();
      await s.markPrompted();
      await s.setChannel(UpdateChannel.beta);
      await s.download();
      await s.refreshAfterResume();
      await s.dismissWhatsNew();
      await s.loadWhatsNewNotes();
    });

    test('does not throw when the host cannot say what is installed', () async {
      final s = make(appInfo: () async => throw Exception('host is not answering'));
      await s.initialize();
      expect(s.installed, AppInfo.unknown);
      repo.next = Fetched(_rel(), '"e"');
      await s.check();
      expect(s.status, UpdateStatus.available); // unknown install is older than anything
    });

    test('does not throw when the updates folder cannot be located', () async {
      final s = make(dir: () async => throw const FileSystemException('no cache dir'));
      await s.initialize();
      repo.next = Fetched(_rel(), '"e"');
      await s.check();
      expect(s.status, UpdateStatus.available);
      await s.download();
      expect(s.status, UpdateStatus.failed);
      expect(s.state.error, isNotEmpty);
      expect(s.state.failedDuring, UpdateStatus.downloading);
      expect(dl.downloads, 0);
    });
  });

  group('check', () {
    test('finds an update, remembers it, and publishes it', () async {
      repo.next = Fetched(_rel(), '"e1"');
      final s = make();
      final seen = <UpdateStatus>[];
      s.addListener(() => seen.add(s.status));

      await s.check();

      expect(seen, containsAllInOrder([UpdateStatus.checking, UpdateStatus.available]));
      expect(s.status, UpdateStatus.available);
      expect(s.release!.id, '1.1.0+142');
      expect(s.hasUpdate, isTrue);
      expect(s.shouldPrompt, isTrue);
      expect(s.lastChecked, clock);
      expect(s.state.checkedAt, clock);
      expect(s.state.error, isNull);
      expect(repo.requests.single.channel, UpdateChannel.stable);
      expect(repo.requests.single.abis, ['arm64-v8a', 'armeabi-v7a']);
      expect(repo.requests.single.etag, isNull);

      final p = await prefs();
      expect(p.getString('update_etag'), '"e1"');
      expect(p.getInt('update_last_check_ms'), clock.millisecondsSinceEpoch);
      final cached = ReleaseInfo.fromJson(jsonDecode(p.getString('update_cached_release')!) as Map<String, dynamic>);
      expect(cached, _rel());
    });

    final notNewer = <String, ReleaseInfo?>{
      'the same version': _rel(version: '1.0.0', build: 100),
      'an older version': _rel(version: '0.9.0', build: 99),
      'a lower build of the same name': _rel(version: '1.0.0', build: 99),
      'no release at all': null,
    };
    notNewer.forEach((why, release) {
      test('is up to date given $why', () async {
        repo.next = Fetched(release, null);
        final s = make();
        await s.check();
        expect(s.status, UpdateStatus.upToDate);
        expect(s.release, isNull);
        expect(s.hasUpdate, isFalse);
        expect(s.shouldPrompt, isFalse);
        expect(s.lastChecked, clock);
      });
    });

    test('a higher build of the same version name IS an update', () async {
      repo.next = Fetched(_rel(version: '1.0.0', build: 101), null);
      final s = make();
      await s.check();
      expect(s.status, UpdateStatus.available);
    });

    test('"no releases" clears a previously cached release', () async {
      final s = await available();
      repo.next = const Fetched(null, null);
      await s.check(force: true);
      expect(s.status, UpdateStatus.upToDate);
      expect((await prefs()).getString('update_cached_release'), isNull);
      expect((await prefs()).getString('update_etag'), isNull);
    });

    test('is throttled: nothing within the minimum interval, a check after it', () async {
      repo.next = Fetched(_rel(), '"e1"');
      final s = make();
      await s.check();
      expect(repo.calls, 1);

      await s.check();
      expect(repo.calls, 1);
      expect(s.status, UpdateStatus.available); // the cached state is still published

      clock = clock.add(const Duration(hours: 5, minutes: 59));
      await s.check();
      expect(repo.calls, 1);

      clock = clock.add(const Duration(minutes: 2));
      await s.check();
      expect(repo.calls, 2);
      expect(repo.requests.last.etag, '"e1"'); // conditional
    });

    test('the throttle survives a restart', () async {
      repo.next = Fetched(_rel(), '"e1"');
      await make().check();
      final again = make();
      await again.check();
      expect(repo.calls, 1);
      expect(again.status, UpdateStatus.available); // restored from the cache
    });

    test('force bypasses the throttle', () async {
      repo.next = Fetched(_rel(), '"e1"');
      final s = make();
      await s.check();
      await s.check(force: true);
      expect(repo.calls, 2);
    });

    test('with auto-check off only a forced check runs', () async {
      repo.next = Fetched(_rel(), '"e1"');
      final s = make();
      await s.setAutoCheck(false);
      await s.check();
      expect(repo.calls, 0);
      expect(s.status, UpdateStatus.idle);
      await s.check(force: true);
      expect(repo.calls, 1);
      expect(s.status, UpdateStatus.available);
    });

    test('a clock set backwards does not freeze checking', () async {
      repo.next = Fetched(_rel(), '"e1"');
      final s = make();
      await s.check();
      clock = clock.subtract(const Duration(days: 2));
      await s.check();
      expect(repo.calls, 2);
    });

    test('304 keeps the cached update and refreshes the timestamp', () async {
      final s = await available();
      clock = clock.add(const Duration(hours: 7));
      repo.next = const NotModified();
      await s.check();
      expect(repo.requests.last.etag, '"e1"');
      expect(s.status, UpdateStatus.available);
      expect(s.release!.id, '1.1.0+142');
      expect(s.lastChecked, clock);
    });

    test('304 with nothing cached is simply up to date', () async {
      SharedPreferences.setMockInitialValues({'update_etag': '"old"'});
      repo.next = const NotModified();
      final s = make();
      await s.check();
      expect(repo.requests.single.etag, '"old"');
      expect(s.status, UpdateStatus.upToDate);
    });

    test('offline with nothing cached is a failure with a plain sentence', () async {
      repo.next = const Failed('You appear to be offline.', offline: true);
      final s = make();
      await s.check();
      expect(s.status, UpdateStatus.failed);
      expect(s.state.error, 'You appear to be offline.');
      expect(s.state.failedDuring, UpdateStatus.checking);
      expect(s.release, isNull);
      expect(s.hasUpdate, isFalse);
      expect(s.lastChecked, isNull); // a failed check does not count as a check
    });

    test('GitHub being unreachable carries its own sentence', () async {
      repo.next = const Failed('GitHub could not be reached. Try again in a moment.');
      final s = make();
      await s.check();
      expect(s.state.error, 'GitHub could not be reached. Try again in a moment.');
    });

    test('offline with a cached update keeps offering it and only notes the error', () async {
      final s = await available();
      repo.next = const Failed('You appear to be offline.', offline: true);
      await s.check(force: true);
      expect(s.status, UpdateStatus.available);
      expect(s.release!.id, '1.1.0+142');
      expect(s.state.error, 'You appear to be offline.');
      expect(s.hasUpdate, isTrue);

      repo.next = Fetched(_rel(), '"e1"');
      await s.check(force: true);
      expect(s.state.error, isNull);
    });

    test('a restart while offline still shows the cached update, with its notes', () async {
      await available();
      repo.next = const Failed('You appear to be offline.', offline: true);
      final again = make();
      await again.initialize();
      expect(again.status, UpdateStatus.available);
      expect(again.release!.notes.title, 'Glass that behaves');
      await again.check(force: true);
      expect(again.status, UpdateStatus.available);
      expect(again.release!.notes.sections.single.items, ['Equalizer', 'Sleep timer']);
    });

    test('an unexpected exception from the repository becomes a failure, not a crash', () async {
      repo.throwError = StateError('bug in the repository');
      final s = make();
      await s.check();
      expect(s.status, UpdateStatus.failed);
      expect(s.state.error, 'GitHub could not be reached. Try again in a moment.');
    });

    test('a failed check is retried at the next launch, not after six hours', () async {
      repo.next = const Failed('You appear to be offline.', offline: true);
      final s = make();
      await s.check();
      repo.next = Fetched(_rel(), '"e"');
      await s.check();
      expect(repo.calls, 2);
      expect(s.status, UpdateStatus.available);
    });

    group('rate limiting', () {
      test('is remembered: the next automatic check stays quiet until the time given', () async {
        final s = await available();
        clock = clock.add(const Duration(hours: 7));
        repo.next = RateLimited(clock.add(const Duration(minutes: 30)));
        await s.check();
        expect(repo.calls, 2);
        // The cached update is untouched; the user sees nothing wrong.
        expect(s.status, UpdateStatus.available);
        expect(s.state.error, isNull);

        clock = clock.add(const Duration(minutes: 10));
        await s.check();
        expect(repo.calls, 2);

        clock = clock.add(const Duration(minutes: 21));
        repo.next = Fetched(_rel(), '"e2"');
        await s.check();
        expect(repo.calls, 3);
      });

      test('a forced check goes ahead anyway', () async {
        final s = await available();
        clock = clock.add(const Duration(hours: 7));
        repo.next = RateLimited(clock.add(const Duration(hours: 1)));
        await s.check();
        repo.next = Fetched(_rel(), '"e2"');
        await s.check(force: true);
        expect(repo.calls, 3);
      });

      test('with no retry time it backs off for a default while', () async {
        final s = await available();
        clock = clock.add(const Duration(hours: 7));
        repo.next = const RateLimited(null);
        await s.check();
        clock = clock.add(const Duration(minutes: 5));
        await s.check();
        expect(repo.calls, 2);
        clock = clock.add(const Duration(minutes: 11));
        await s.check();
        expect(repo.calls, 3);
      });

      test('survives a restart', () async {
        final s = await available();
        clock = clock.add(const Duration(hours: 7));
        repo.next = RateLimited(clock.add(const Duration(hours: 2)));
        await s.check();
        final again = make();
        await again.check();
        expect(repo.calls, 2);
      });

      test('a forced check with nothing cached says so in plain words', () async {
        repo.next = RateLimited(clock.add(const Duration(minutes: 30)));
        final s = make();
        await s.check(force: true);
        expect(s.status, UpdateStatus.failed);
        expect(s.state.error, 'GitHub is limiting requests right now. Try again in about 30 minutes.');
        expect(s.state.failedDuring, UpdateStatus.checking);
      });

      test('an automatic check with nothing cached stays silent', () async {
        repo.next = RateLimited(clock.add(const Duration(minutes: 30)));
        final s = make();
        await s.check();
        expect(s.status, UpdateStatus.idle);
        expect(s.state.error, isNull);
      });

      test('a forced check with a cached update keeps it', () async {
        final s = await available();
        repo.next = RateLimited(clock.add(const Duration(minutes: 30)));
        await s.check(force: true);
        expect(s.status, UpdateStatus.available);
      });
    });

    group('minSdk', () {
      test('a release this phone cannot run is reported, never offered', () async {
        repo.next = Fetched(_rel(minSdk: 35), '"e"');
        final s = make();
        await s.check();
        expect(s.status, UpdateStatus.upToDate);
        expect(s.release, isNull);
        expect(s.state.error, 'Needs Android 15');
        expect(s.hasUpdate, isFalse);
        expect(s.shouldPrompt, isFalse);
        await s.download();
        expect(dl.downloads, 0);
      });

      test('the note clears once the phone qualifies', () async {
        repo.next = Fetched(_rel(minSdk: 35), '"e"');
        final s = make();
        await s.check();
        app = const AppInfo(versionName: '1.0.0', versionCode: 100, abis: ['arm64-v8a'], sdkInt: 35);
        final fresh = make();
        await fresh.check(force: true);
        expect(fresh.status, UpdateStatus.available);
        expect(fresh.state.error, isNull);
      });

      test('exactly the phone\'s level is fine; an unknown level does not block', () async {
        repo.next = Fetched(_rel(minSdk: 34), '"e"');
        final ok = make();
        await ok.check();
        expect(ok.status, UpdateStatus.available);

        app = const AppInfo(versionName: '1.0.0', versionCode: 100, sdkInt: 0);
        repo.next = Fetched(_rel(minSdk: 99), '"e"');
        final unknown = make();
        await unknown.check(force: true);
        expect(unknown.status, UpdateStatus.available);
      });

      test('Android names', () {
        const table = {24: '7.0', 25: '7.1', 26: '8.0', 27: '8.1', 28: '9', 29: '10', 33: '13', 34: '14', 35: '15', 36: '16', 99: '(API 99)', 21: '5.0', 22: '5.1', 23: '6'};
        table.forEach((sdk, name) => expect(androidVersionName(sdk), name, reason: '$sdk'));
      });
    });

    test('a release with no APK for this phone is not offered', () async {
      repo.next = Fetched(_rel(withAsset: false), '"e"');
      final s = make();
      await s.check();
      expect(s.status, UpdateStatus.upToDate);
      expect(s.release, isNull);
    });

    test('when a verified file is already on disk the update is ready at once', () async {
      final s = make();
      await s.initialize();
      seedFile(_rel().asset!.name, _apk);
      repo.next = Fetched(_rel(), '"e"');
      await s.check();
      expect(s.status, UpdateStatus.ready);
      expect(s.progress, 1);
      expect(s.downloadedPath, endsWith(_rel().asset!.name));
      expect(dl.downloads, 0);
    });

    test('two checks at once make one request', () async {
      repo.gate = Completer<void>();
      repo.next = Fetched(_rel(), '"e"');
      final s = make();
      final a = s.check();
      final b = s.check(force: true);
      await until(() => repo.calls >= 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      repo.gate!.complete();
      await Future.wait([a, b]);
      expect(repo.calls, 1);
    });

    test('a check that finishes after the channel changed is discarded', () async {
      repo.gate = Completer<void>();
      repo.next = Fetched(_rel(), '"e"');
      final s = make();
      final running = s.check();
      await until(() => repo.calls == 1);
      await s.setChannel(UpdateChannel.beta);
      repo.gate!.complete();
      await running;
      expect(s.status, UpdateStatus.idle);
      expect(s.release, isNull);
      expect((await prefs()).getString('update_cached_release'), isNull);
    });

    test('does nothing while a download is running', () async {
      final s = await available();
      dl.gate = Completer<void>();
      final downloading = s.download();
      await until(() => s.status == UpdateStatus.downloading && partExists(updates));
      final before = repo.calls;
      await s.check(force: true);
      expect(repo.calls, before);
      dl.gate!.complete();
      await downloading;
    });
  });

  group('download', () {
    test('goes downloading -> verifying -> ready, with the file in place', () async {
      final s = await available();
      final seen = <UpdateStatus>[];
      final progress = <double>[];
      s.addListener(() {
        seen.add(s.status);
        progress.add(s.progress);
      });

      await s.download();

      expect(seen, containsAllInOrder([UpdateStatus.downloading, UpdateStatus.verifying, UpdateStatus.ready]));
      expect(s.status, UpdateStatus.ready);
      expect(s.progress, 1);
      expect(s.state.receivedBytes, _apk.length);
      expect(s.state.totalBytes, _apk.length);
      expect(s.state.error, isNull);
      expect(s.hasUpdate, isTrue);
      final path = s.downloadedPath!;
      expect(File(path).readAsBytesSync(), _apk);
      expect(filesInUpdates(), [_rel().asset!.name]); // the .part is gone
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
    });

    test('exposes live speed and ETA, and clears them when done', () async {
      final s = await available();
      final speeds = <double>[];
      final etas = <int?>[];
      s.addListener(() {
        if (s.status == UpdateStatus.downloading) {
          speeds.add(s.state.bytesPerSecond);
          etas.add(s.state.etaSeconds);
        }
      });
      dl.stepDelay = const Duration(milliseconds: 120);
      await s.download();
      expect(speeds.any((v) => v > 0), isTrue);
      expect(etas.any((v) => v != null), isTrue);
      expect(s.state.bytesPerSecond, 0);
      expect(s.state.etaSeconds, isNull);
    });

    test('notifies at most about ten times a second, but the state is always current', () async {
      final s = await available();
      dl.steps = 40;
      dl.stepDelay = const Duration(milliseconds: 15);
      var notifications = 0;
      s.addListener(() => notifications++);
      final sw = Stopwatch()..start();

      await s.download();

      sw.stop();
      // 40 progress events + a handful of status changes; throttled to ~10/s.
      expect(notifications, lessThan(sw.elapsedMilliseconds ~/ 100 + 10));
      expect(notifications, lessThan(40));
      expect(s.state.receivedBytes, _apk.length);
    });

    test('is a no-op unless there is something available to download', () async {
      final idle = make();
      await idle.download();
      expect(dl.downloads, 0);

      repo.next = Fetched(_rel(version: '1.0.0', build: 100), null);
      final upToDate = make();
      await upToDate.check();
      await upToDate.download();
      expect(dl.downloads, 0);

      final s = await ready();
      final before = dl.downloads;
      await s.download(); // already ready
      expect(dl.downloads, before);
    });

    test('two download() calls at once start one transfer', () async {
      final s = await available();
      dl.gate = Completer<void>();
      final a = s.download();
      final b = s.download();
      await until(() => partExists(updates));
      dl.gate!.complete();
      await Future.wait([a, b]);
      expect(dl.downloads, 1);
      expect(s.status, UpdateStatus.ready);
    });

    test('cancel() returns to available at once and keeps the partial file for resuming', () async {
      final s = await available();
      dl.gate = Completer<void>();
      final running = s.download();
      await until(() => s.status == UpdateStatus.downloading && partExists(updates));

      s.cancel();
      expect(s.status, UpdateStatus.available);
      expect(s.progress, 0);
      await running;
      expect(s.status, UpdateStatus.available);
      expect(s.state.error, isNull);
      expect(partExists(updates), isTrue);
      expect(s.hasUpdate, isTrue);

      dl.gate = null;
      await s.download();
      expect(s.status, UpdateStatus.ready);
    });

    test('cancel() with nothing running does nothing', () async {
      final s = await available();
      expect(s.cancel, returnsNormally);
      expect(s.status, UpdateStatus.available);
    });

    test('a damaged download is removed, reported, and can be retried', () async {
      final s = await available();
      dl.forced = DownloadOutcome.corrupt;
      await s.download();
      expect(s.status, UpdateStatus.failed);
      expect(s.state.error, 'The download was damaged and was removed. Try again.');
      expect(s.state.failedDuring, UpdateStatus.verifying);
      expect(s.release, isNotNull);
      expect(s.hasUpdate, isTrue);
      expect(s.downloadedPath, isNull);

      dl.forced = null;
      await s.download();
      expect(s.status, UpdateStatus.ready);
      expect(s.state.error, isNull);
      expect(s.state.failedDuring, isNull);
    });

    test('a dropped connection fails keeping the partial file, and can be retried', () async {
      final s = await available();
      dl.forced = DownloadOutcome.failed('You appear to be offline.');
      await s.download();
      expect(s.status, UpdateStatus.failed);
      expect(s.state.error, 'You appear to be offline.');
      expect(s.state.failedDuring, UpdateStatus.downloading);
      expect(partExists(updates), isTrue);
      expect(s.hasUpdate, isTrue);

      dl.forced = null;
      await s.download();
      expect(s.status, UpdateStatus.ready);
    });

    test('a downloader that throws is a failure, not a crash', () async {
      final s = await available();
      dl.throwError = StateError('boom');
      await s.download();
      expect(s.status, UpdateStatus.failed);
      expect(s.state.error, kDownloadInterruptedMessage);
    });

    test('choosing to download overrides an earlier "skip this version"', () async {
      final s = await available();
      await s.skipThisVersion();
      expect(s.hasUpdate, isFalse);
      await s.download();
      expect(s.hasUpdate, isTrue);
      expect((await prefs()).getString('update_skipped_version'), isNull);
    });

    test('a manual check after a failed download goes back to a clean state', () async {
      final s = await available();
      dl.forced = DownloadOutcome.failed('You appear to be offline.');
      await s.download();
      repo.next = Fetched(_rel(), '"e1"');
      await s.check(force: true);
      expect(s.status, UpdateStatus.available);
      expect(s.state.error, isNull);
      expect(s.state.failedDuring, isNull);
    });
  });

  group('install', () {
    test('hands the verified file to the installer and stays "installing"', () async {
      final s = await ready();
      final seen = <UpdateStatus>[];
      s.addListener(() => seen.add(s.status));

      final r = await s.install();

      expect(r, InstallResult.started);
      expect(s.status, UpdateStatus.installing);
      expect(installerPaths, [s.downloadedPath]);
      expect(seen, contains(UpdateStatus.installing));
      expect(s.hasUpdate, isTrue);
    });

    test('is refused unless an update is ready', () async {
      final s = await available();
      expect(await s.install(), InstallResult.unavailable);
      expect(installerPaths, isEmpty);
      expect(s.status, UpdateStatus.available);

      final idle = make();
      expect(await idle.install(), InstallResult.unavailable);
    });

    test('needing permission is its own state; allow it and install again', () async {
      installResult = InstallResult.needsPermission;
      final s = await ready();
      expect(await s.install(), InstallResult.needsPermission);
      expect(s.status, UpdateStatus.needsPermission);
      expect(s.hasUpdate, isTrue);

      // Back from settings without having allowed it: still waiting.
      canInstall = false;
      await s.refreshAfterResume();
      expect(s.status, UpdateStatus.needsPermission);

      // Back from settings having allowed it.
      canInstall = true;
      await s.refreshAfterResume();
      expect(s.status, UpdateStatus.ready);

      installResult = InstallResult.started;
      expect(await s.install(), InstallResult.started);
      expect(s.status, UpdateStatus.installing);
      expect(installerPaths, hasLength(2));
    });

    test('install() works straight from needsPermission too', () async {
      installResult = InstallResult.needsPermission;
      final s = await ready();
      await s.install();
      installResult = InstallResult.started;
      expect(await s.install(), InstallResult.started);
      expect(s.status, UpdateStatus.installing);
    });

    test('an installer that cannot start fails with a sentence, and may be tried again', () async {
      installResult = InstallResult.unavailable;
      final s = await ready();
      expect(await s.install(), InstallResult.unavailable);
      expect(s.status, UpdateStatus.failed);
      expect(s.state.error, 'This phone could not start the installer.');
      expect(s.state.failedDuring, UpdateStatus.installing);
      expect(s.hasUpdate, isTrue);

      installResult = InstallResult.started;
      expect(await s.install(), InstallResult.started);
      expect(s.status, UpdateStatus.installing);
    });

    test('an installer that throws counts as unavailable', () async {
      final s = UpdateService(
        repository: repo,
        downloader: dl,
        prefs: SharedPreferences.getInstance,
        updatesDir: () async => updates,
        appInfo: () async => app,
        installer: (_) async => throw Exception('no installer'),
        now: () => clock,
      );
      created.add(s);
      repo.next = Fetched(_rel(), '"e"');
      await s.check();
      await s.download();
      expect(await s.install(), InstallResult.unavailable);
      expect(s.status, UpdateStatus.failed);
    });

    test('if the file vanished, the update goes back to "available"', () async {
      final s = await ready();
      File(s.downloadedPath!).deleteSync();
      expect(await s.install(), InstallResult.unavailable);
      expect(s.status, UpdateStatus.available);
      expect(installerPaths, isEmpty);
      await s.download();
      expect(s.status, UpdateStatus.ready);
    });

    test('resuming without having been replaced returns to "ready"', () async {
      final s = await ready();
      await s.install();
      expect(s.status, UpdateStatus.installing);
      canInstall = true;
      await s.refreshAfterResume();
      expect(s.status, UpdateStatus.ready);
      expect(s.state.error, isNull);
    });

    test('resuming as the new version clears the update', () async {
      final s = await ready();
      await s.install();
      app = const AppInfo(versionName: '1.1.0', versionCode: 142, abis: ['arm64-v8a'], sdkInt: 34);
      await s.refreshAfterResume();
      expect(s.status, UpdateStatus.upToDate);
      expect(s.release, isNull);
      expect(s.hasUpdate, isFalse);
      expect(s.installed.versionName, '1.1.0');
      expect(filesInUpdates(), isEmpty);
      expect((await prefs()).getString('update_cached_release'), isNull);
    });

    test('refreshAfterResume does nothing in any other state', () async {
      final s = await ready();
      await s.refreshAfterResume();
      expect(s.status, UpdateStatus.ready);
      SharedPreferences.setMockInitialValues({}); // a fresh install: nothing cached
      final idle = make();
      await idle.refreshAfterResume();
      expect(idle.status, UpdateStatus.idle);
    });
  });

  group('choices the user makes', () {
    test('"skip this version" hides the prompt and persists until something newer', () async {
      final s = await available();
      expect(s.shouldPrompt, isTrue);
      await s.skipThisVersion();
      expect(s.hasUpdate, isFalse);
      expect(s.shouldPrompt, isFalse);
      expect(s.release, isNotNull); // still known, for a manual look in settings
      expect((await prefs()).getString('update_skipped_version'), '1.1.0+142');

      final again = make();
      await again.initialize();
      expect(again.hasUpdate, isFalse);
      expect(again.shouldPrompt, isFalse);

      repo.next = Fetched(_rel(version: '1.1.1', build: 150), '"e2"');
      await again.check(force: true);
      expect(again.hasUpdate, isTrue);
      expect(again.shouldPrompt, isTrue);
    });

    test('a skipped version stays skipped when the same release is fetched again', () async {
      final s = await available();
      await s.skipThisVersion();
      await s.check(force: true);
      expect(s.hasUpdate, isFalse);
    });

    test('skip with nothing to skip is harmless', () async {
      final s = make();
      await s.skipThisVersion();
      await s.markPrompted();
      expect(s.hasUpdate, isFalse);
    });

    test('the prompt is shown once per version', () async {
      final s = await available();
      expect(s.shouldPrompt, isTrue);
      await s.markPrompted();
      expect(s.shouldPrompt, isFalse);
      expect(s.hasUpdate, isTrue); // still an update, just not a nag
      expect((await prefs()).getString('update_prompted_version'), '1.1.0+142');

      final again = make();
      await again.initialize();
      expect(again.shouldPrompt, isFalse);

      repo.next = Fetched(_rel(version: '1.1.1', build: 150), '"e2"');
      await again.check(force: true);
      expect(again.shouldPrompt, isTrue);
    });

    test('setAutoCheck persists and notifies', () async {
      final s = make();
      var n = 0;
      s.addListener(() => n++);
      await s.setAutoCheck(false);
      expect(s.autoCheck, isFalse);
      expect(n, greaterThan(0));
      expect((await prefs()).getBool('update_auto_check'), isFalse);
      await s.setAutoCheck(true);
      expect((await prefs()).getBool('update_auto_check'), isTrue);
    });

    test('changing channel forgets the cache, the ETag and the throttle', () async {
      final s = await available();
      seedFile('stale.apk', [1, 2, 3]);
      expect(await prefs().then((p) => p.getString('update_etag')), '"e1"');

      await s.setChannel(UpdateChannel.beta);

      expect(s.channel, UpdateChannel.beta);
      expect(s.status, UpdateStatus.idle);
      expect(s.release, isNull);
      expect(s.lastChecked, isNull);
      expect(s.hasUpdate, isFalse);
      final p = await prefs();
      expect(p.getString('update_channel'), 'beta');
      expect(p.getString('update_cached_release'), isNull);
      expect(p.getString('update_etag'), isNull);
      expect(p.getInt('update_last_check_ms'), isNull);
      expect(filesInUpdates(), isEmpty);

      // Immediately afterwards - inside the 6 h window - the next check runs,
      // on the new channel, unconditionally.
      repo.next = Fetched(_rel(version: '1.2.0-beta.1', build: 150), '"b1"');
      await s.check();
      expect(repo.calls, 2);
      expect(repo.requests.last.channel, UpdateChannel.beta);
      expect(repo.requests.last.etag, isNull);
      expect(s.release!.version, '1.2.0-beta.1');
    });

    test('choosing the channel already chosen changes nothing', () async {
      final s = await available();
      var n = 0;
      s.addListener(() => n++);
      await s.setChannel(UpdateChannel.stable);
      expect(n, 0);
      expect(s.status, UpdateStatus.available);
    });

    test('switching channel mid-download stops it', () async {
      final s = await available();
      dl.gate = Completer<void>();
      final running = s.download();
      await until(() => s.status == UpdateStatus.downloading && partExists(updates));
      await s.setChannel(UpdateChannel.beta);
      await running;
      expect(s.status, UpdateStatus.idle);
      expect(s.release, isNull);
    });

    test('the channel survives a restart', () async {
      await make().setChannel(UpdateChannel.beta);
      final again = make();
      await again.initialize();
      expect(again.channel, UpdateChannel.beta);
    });
  });

  group('startup clean-up and restore', () {
    Future<void> seedCache(ReleaseInfo r, {String? etag = '"e1"', bool checked = true}) async {
      SharedPreferences.setMockInitialValues({
        'update_cached_release': jsonEncode(r.toJson()),
        if (etag != null) 'update_etag': etag,
        if (checked) 'update_last_check_ms': clock.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        'update_last_run_version': '1.0.0+100',
      });
    }

    test('deletes stale files and keeps only the verified one for the cached release', () async {
      await seedCache(_rel());
      final name = _rel().asset!.name;
      seedFile('MineMusic-1.0.0-b99.apk', [1]); // older than what is installed
      seedFile('MineMusic-0.9.0-b50.apk', [2]);
      seedFile(name, _apk); // verified, for the cached release
      seedFile('$name.part', _apk.sublist(0, 100)); // its partial: resumable
      seedFile('MineMusic-1.1.1-b150.apk.part', [3]); // some other release
      seedFile('junk.tmp', [4]);

      final s = make();
      await s.initialize();

      expect(filesInUpdates(), [name, '$name.part']);
      expect(s.status, UpdateStatus.ready);
      expect(s.release!.id, '1.1.0+142');
      expect(s.downloadedPath, endsWith(name));
      expect(s.progress, 1);
      expect(dl.downloads, 0);
    });

    test('a leftover file that fails verification is deleted and the update stays "available"', () async {
      await seedCache(_rel());
      final name = _rel().asset!.name;
      seedFile(name, Uint8List.fromList(_apk)..[10] ^= 0xFF);

      final s = make();
      await s.initialize();

      expect(s.status, UpdateStatus.available);
      expect(filesInUpdates(), isEmpty);
    });

    test('a cached release no longer newer than the installed app is dropped with its files', () async {
      app = const AppInfo(versionName: '1.1.0', versionCode: 142, abis: ['arm64-v8a'], sdkInt: 34);
      await seedCache(_rel());
      seedFile(_rel().asset!.name, _apk);
      seedFile('other.apk', [1]);

      final s = make();
      await s.initialize();

      expect(s.release, isNull);
      expect(s.status, UpdateStatus.upToDate);
      expect(filesInUpdates(), isEmpty);
      expect((await prefs()).getString('update_cached_release'), isNull);
    });

    test('before any check has finished, "nothing cached" is idle, not "up to date"', () async {
      final s = make();
      await s.initialize();
      expect(s.status, UpdateStatus.idle);
    });

    test('restores a cached update as "available" without touching the network', () async {
      await seedCache(_rel());
      final s = make();
      await s.initialize();
      expect(s.status, UpdateStatus.available);
      expect(s.release!.notes.title, 'Glass that behaves');
      expect(s.hasUpdate, isTrue);
      expect(repo.calls, 0);
    });

    test('a cached release the phone cannot run is not offered', () async {
      await seedCache(_rel(minSdk: 40));
      final s = make();
      await s.initialize();
      expect(s.status, UpdateStatus.upToDate);
      expect(s.release, isNull);
      expect(s.state.error, 'Needs Android (API 40)');
    });

    test('an unreadable cache is ignored and takes the ETag with it', () async {
      SharedPreferences.setMockInitialValues({
        'update_cached_release': 'not json {{{',
        'update_etag': '"stale"',
      });
      repo.next = Fetched(_rel(), '"fresh"');
      final s = make();
      await s.initialize();
      expect(s.status, UpdateStatus.idle);
      await s.check();
      expect(repo.requests.single.etag, isNull); // a 304 would have promised data we lack
      expect(s.status, UpdateStatus.available);
    });

    test('a cache of the wrong shape is ignored', () async {
      for (final junk in [jsonEncode({'foo': 1}), jsonEncode([1, 2]), jsonEncode('x'), '', '{}']) {
        SharedPreferences.setMockInitialValues({'update_cached_release': junk});
        final s = make();
        await s.initialize();
        expect(s.release, isNull, reason: junk);
        expect(s.initialized, isTrue);
      }
    });
  });

  group("what's new", () {
    test('appears the first time a different version runs, then not again', () async {
      SharedPreferences.setMockInitialValues({'update_last_run_version': '1.0.0+99'});
      final s = make();
      await s.initialize();

      final w = s.whatsNew!;
      expect(w.id, '1.0.0+100');
      expect(w.tag, 'v1.0.0+100');
      expect(w.notes.isEmpty, isTrue); // not fetched yet
      expect(w.asset, isNull);
      expect((await prefs()).getString('update_last_run_version'), '1.0.0+100');

      final again = make();
      await again.initialize();
      expect(again.whatsNew, isNull);
    });

    test('is absent on the very first launch and on an unchanged version', () async {
      final first = make();
      await first.initialize();
      expect(first.whatsNew, isNull);

      SharedPreferences.setMockInitialValues({'update_last_run_version': '1.0.0+100'});
      final same = make();
      await same.initialize();
      expect(same.whatsNew, isNull);
    });

    test('a new build of the same version name counts', () async {
      SharedPreferences.setMockInitialValues({'update_last_run_version': '1.0.0+99'});
      final s = make();
      await s.initialize();
      expect(s.whatsNew, isNotNull);
    });

    test('uses the cached release\'s notes when that is the build just installed', () async {
      SharedPreferences.setMockInitialValues({
        'update_last_run_version': '1.0.0+99',
        'update_cached_release': jsonEncode(_rel(version: '1.0.0', build: 100).toJson()),
      });
      final s = make();
      await s.initialize();
      expect(s.whatsNew!.notes.title, 'Glass that behaves');
      expect(s.whatsNew!.notes.sections.single.title, 'New');
      expect(s.release, isNull); // and the cache has done its job
    });

    test('an unknown host never shows it', () async {
      app = AppInfo.unknown;
      SharedPreferences.setMockInitialValues({'update_last_run_version': '1.0.0+99'});
      final s = make();
      await s.initialize();
      expect(s.whatsNew, isNull);
    });

    test('loadWhatsNewNotes fills the notes from the running version\'s tag', () async {
      SharedPreferences.setMockInitialValues({'update_last_run_version': '1.0.0+99'});
      repo.tagResult = _rel(version: '1.0.0', build: 100, withAsset: false);
      final s = make();
      await s.initialize();
      var n = 0;
      s.addListener(() => n++);

      await s.loadWhatsNewNotes();

      expect(repo.tagCalls, ['v1.0.0+100']);
      expect(s.whatsNew!.notes.title, 'Glass that behaves');
      expect(n, 1);

      await s.loadWhatsNewNotes(); // already has notes: no second request
      expect(repo.tagCalls, hasLength(1));
    });

    test('loadWhatsNewNotes leaves it alone when the release cannot be found', () async {
      SharedPreferences.setMockInitialValues({'update_last_run_version': '1.0.0+99'});
      final s = make();
      await s.initialize();
      await s.loadWhatsNewNotes();
      expect(s.whatsNew, isNotNull);
      expect(s.whatsNew!.notes.isEmpty, isTrue);
    });

    test('loadWhatsNewNotes without anything to load does not ask', () async {
      final s = make();
      await s.loadWhatsNewNotes();
      expect(repo.tagCalls, isEmpty);
    });

    test('dismissing it clears it, and a late answer does not bring it back', () async {
      SharedPreferences.setMockInitialValues({'update_last_run_version': '1.0.0+99'});
      repo.tagResult = _rel(version: '1.0.0', build: 100, withAsset: false);
      repo.tagGate = Completer<void>();
      final s = make();
      await s.initialize();
      final loading = s.loadWhatsNewNotes();
      await until(() => repo.tagCalls.isNotEmpty);
      await s.dismissWhatsNew();
      repo.tagGate!.complete();
      await loading;
      expect(s.whatsNew, isNull);
    });

    test('dismissWhatsNew with nothing to dismiss does not notify', () async {
      final s = make();
      await s.initialize();
      var n = 0;
      s.addListener(() => n++);
      await s.dismissWhatsNew();
      expect(n, 0);
    });
  });

  group('the whole journey', () {
    test('check, prompt, download, install - then the app restarts as the new version', () async {
      final s = await available();
      expect(s.shouldPrompt, isTrue);
      await s.markPrompted();
      await s.download();
      expect(s.status, UpdateStatus.ready);
      expect(await s.install(), InstallResult.started);
      created.remove(s);
      s.dispose(); // the OS kills the process

      app = const AppInfo(versionName: '1.1.0', versionCode: 142, abis: ['arm64-v8a'], sdkInt: 34);
      final after = make();
      await after.initialize();

      expect(after.hasUpdate, isFalse);
      expect(after.release, isNull);
      expect(after.status, UpdateStatus.upToDate);
      expect(after.whatsNew!.id, '1.1.0+142');
      expect(after.whatsNew!.notes.title, 'Glass that behaves'); // the notes came along in the cache
      expect(filesInUpdates(), isEmpty);
      expect((await prefs()).getString('update_cached_release'), isNull);
      expect((await prefs()).getString('update_last_run_version'), '1.1.0+142');
    });
  });

  group('lifecycle', () {
    test('with every default (no host, no plugins) startup is still safe', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      AppPlatform.resetCache();
      SharedPreferences.setMockInitialValues({});
      final s = UpdateService(); // real AppPlatform, path_provider and clients
      await s.initialize();
      expect(s.initialized, isTrue);
      expect(s.installed, AppInfo.unknown); // the channel has no native side here
      expect(s.status, UpdateStatus.idle);
      expect(await s.install(), InstallResult.unavailable);
      s.dispose(); // closes the clients it created
      AppPlatform.resetCache();
    });

    test('after dispose nothing notifies and nothing throws', () async {
      repo.gate = Completer<void>();
      repo.next = Fetched(_rel(), '"e"');
      final s = make();
      var n = 0;
      s.addListener(() => n++);
      final running = s.check();
      await until(() => repo.calls == 1);
      final before = n;

      created.remove(s);
      s.dispose();
      repo.gate!.complete();
      await running;

      expect(n, before);
      await s.check(); // returns quietly
      await s.download();
      expect(await s.install(), InstallResult.unavailable);
    });

    test('dispose cancels a running download', () async {
      final s = await available();
      dl.gate = Completer<void>();
      final running = s.download();
      await until(() => partExists(updates));
      created.remove(s);
      s.dispose();
      await running.timeout(const Duration(seconds: 5)); // unblocked by the cancelled token
    });

    test('UpdateState.copyWith keeps what is omitted and clears what is set to null', () {
      final base = const UpdateState().copyWith(
        status: UpdateStatus.failed,
        release: _rel(),
        error: 'x',
        etaSeconds: 5,
        failedDuring: UpdateStatus.downloading,
        checkedAt: DateTime.utc(2026),
      );
      final kept = base.copyWith(progress: 0.5);
      expect(kept.release, isNotNull);
      expect(kept.error, 'x');
      expect(kept.etaSeconds, 5);
      final cleared = base.copyWith(release: null, error: null, etaSeconds: null, failedDuring: null, checkedAt: null);
      expect(cleared.release, isNull);
      expect(cleared.error, isNull);
      expect(cleared.etaSeconds, isNull);
      expect(cleared.failedDuring, isNull);
      expect(cleared.checkedAt, isNull);
      expect(cleared.status, UpdateStatus.failed);
      expect(base.isBusy, isFalse);
      expect(const UpdateState(status: UpdateStatus.downloading).isBusy, isTrue);
    });
  });
}

bool partExists(Directory dir) =>
    dir.existsSync() && dir.listSync().any((e) => e.path.endsWith('.part'));
