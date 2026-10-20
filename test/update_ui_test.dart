import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/core/navigation/root_navigator.dart';
import 'package:music_streaming_app/screens/software_update_screen.dart';
import 'package:music_streaming_app/services/app_platform.dart';
import 'package:music_streaming_app/services/update/update_downloader.dart';
import 'package:music_streaming_app/services/update/update_models.dart';
import 'package:music_streaming_app/services/update/update_repository.dart';
import 'package:music_streaming_app/services/update/update_service.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/utils/update_format.dart';
import 'package:music_streaming_app/widgets/update/update_coordinator.dart';
import 'package:music_streaming_app/widgets/update/update_copy.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── fakes ───────────────────────────────────────────────────────────────────

class _Repo extends UpdateRepository {
  _Repo(this.result);
  FetchResult result;
  int calls = 0;

  @override
  Future<FetchResult> fetchLatest({
    required UpdateChannel channel,
    required List<String> abis,
    String? etag,
  }) async {
    calls++;
    return result;
  }

  @override
  Future<ReleaseInfo?> fetchByTag(String tag, List<String> abis) async => null;
}

class _Downloader extends UpdateDownloader {
  Completer<DownloadOutcome>? gate;
  void Function(DownloadProgress)? emit;

  @override
  Future<DownloadOutcome> download(
    ReleaseAsset asset, {
    required Directory dir,
    void Function(DownloadProgress)? onProgress,
    void Function()? onVerifying,
    CancelToken? cancel,
  }) {
    emit = onProgress;
    gate = Completer<DownloadOutcome>();
    cancel?.onCancel.then((_) {
      if (!gate!.isCompleted) gate!.complete(const DownloadCancelled());
    });
    return gate!.future;
  }

  @override
  Future<bool> isVerified(File file, ReleaseAsset asset) async => false;
}

ReleaseInfo release({
  String version = '1.1.0',
  int build = 142,
  ReleaseNotes notes = const ReleaseNotes(
    title: 'Glass that behaves',
    summary: 'A calmer bottom bar and a real equalizer.',
    highlights: ['Equalizer', 'Software update', 'Frosted glass'],
    sections: [
      ReleaseSection(title: 'New', icon: 'sparkle', items: ['Equalizer with presets']),
      ReleaseSection(title: 'Fixed', icon: 'fix', items: ['Pure black no longer tears']),
    ],
  ),
}) =>
    ReleaseInfo(
      version: version,
      build: build,
      tag: 'v$version+$build',
      publishedAt: DateTime.utc(2026, 10, 20),
      notes: notes,
      releaseUrl: 'https://github.com/o/r/releases/tag/v$version%2B$build',
      asset: ReleaseAsset(
        name: 'MineMusic-$version-b$build.apk',
        url: 'https://github.com/o/r/releases/download/x/a.apk',
        size: 59900000,
        sha256: 'a' * 64,
      ),
    );

Future<(UpdateService, _Repo, _Downloader, List<String>)> boot(
  WidgetTester tester, {
  ReleaseInfo? offered,
  Map<String, Object> prefs = const {},
  InstallResult install = InstallResult.started,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final dir = Directory.systemTemp.createTempSync('upd_ui');
  addTearDown(() => dir.deleteSync(recursive: true));
  final repo = _Repo(Fetched(offered, 'e1'));
  final dl = _Downloader();
  final installed = <String>[];
  final svc = UpdateService(
    repository: repo,
    downloader: dl,
    updatesDir: () async => dir,
    appInfo: () async => const AppInfo(
        versionName: '1.0.4', versionCode: 100, packageName: 'x', sdkInt: 34, abis: ['arm64-v8a']),
    installer: (p) async {
      installed.add(p);
      return install;
    },
    canInstall: () async => true,
  );
  await tester.runAsync(svc.initialize);
  addTearDown(svc.dispose);
  return (svc, repo, dl, installed);
}

Future<void> pumpScreen(WidgetTester tester, UpdateService svc) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The updater's file and preference I/O is real asynchrony, which the fake
  // clock does not advance, so the first look happens in real time. The screen's
  // own look on opening is then (correctly) throttled.
  await tester.runAsync(svc.check);
  await tester.pumpWidget(MaterialApp(
    theme: GlassTheme.build(AccentColors.peach),
    home: SoftwareUpdateScreen(service: svc, now: () => DateTime.utc(2026, 10, 20, 12)),
  ));
  await tester.pump(const Duration(milliseconds: 1200));
}

/// Lets the coordinator's timers fire and the chains they start (a preference
/// write, a route being built) run to the end.
Future<void> letItRun(WidgetTester tester) async {
  // The updater's futures complete in the real zone and the coordinator's timers
  // live in the fake one; each needs its own clock to move, so take turns.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('formatting', () {
    test('bytes', () {
      expect(formatBytes(0), '');
      expect(formatBytes(-4), '');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(812000), '812 KB');
      expect(formatBytes(59900000), '59.9 MB');
      expect(formatBytes(120000000), '120 MB');
      expect(formatBytes(2500000000), '2.5 GB');
    });

    test('speed and eta', () {
      expect(formatSpeed(0), '');
      expect(formatSpeed(double.nan), '');
      expect(formatSpeed(4200000), '4.2 MB/s');
      expect(formatSpeed(380000), '380 KB/s');
      expect(formatEta(null), '');
      expect(formatEta(2), 'almost done');
      expect(formatEta(12), 'about 10 seconds left');
      expect(formatEta(95), 'about 2 minutes left');
      expect(formatEta(60), 'about 1 minute left');
      expect(formatEta(7300), 'about 2 hours left');
    });

    test('relative time', () {
      final now = DateTime.utc(2026, 10, 20, 12);
      expect(formatAgo(null, now), 'never');
      expect(formatAgo(now, now), 'just now');
      expect(formatAgo(now.subtract(const Duration(minutes: 3)), now), '3 minutes ago');
      expect(formatAgo(now.subtract(const Duration(hours: 1)), now), '1 hour ago');
      expect(formatAgo(now.subtract(const Duration(days: 1)), now), 'yesterday');
      expect(formatAgo(now.subtract(const Duration(days: 3)), now), '3 days ago');
      expect(formatAgo(DateTime.utc(2026, 9, 2), now), '2 Sep');
      expect(formatAgo(now.add(const Duration(hours: 2)), now), 'just now');
    });

    test('version label', () {
      expect(versionLabel('1.1.0', 142), '1.1.0 (142)');
      expect(versionLabel('1.1.0', 0), '1.1.0');
    });
  });

  group('describeUpdate', () {
    const installed = AppInfo(versionName: '1.0.4', versionCode: 100);
    final now = DateTime.utc(2026, 10, 20, 12);
    UpdateCopy d(UpdateState s) => describeUpdate(s, installed, now);

    test('up to date says when it last looked', () {
      final c = d(UpdateState(
          status: UpdateStatus.upToDate,
          checkedAt: now.subtract(const Duration(minutes: 5))));
      expect(c.title, 'Mine Music is up to date');
      expect(c.subtitle, 'Version 1.0.4 (100)');
      expect(c.detail, 'Last checked 5 minutes ago');
      expect(c.action, UpdateAction.check);
      expect(c.actionLabel, 'Check for updates');
      expect(c.tone, UpdateTone.good);
    });

    test('before any check it does not claim to be up to date', () {
      final c = d(const UpdateState());
      expect(c.title, 'Software Update');
      expect(c.detail, 'Not checked yet');
    });

    test('a release that needs a newer Android is explained, not offered', () {
      final c = d(const UpdateState(
          status: UpdateStatus.upToDate, error: 'Needs Android 15'));
      expect(c.title, 'A newer version is out');
      expect(c.subtitle, contains('needs Android 15'));
      expect(c.action, UpdateAction.check);
    });

    test('available offers the download with its size', () {
      final c = d(UpdateState(status: UpdateStatus.available, release: release()));
      expect(c.title, 'Mine Music 1.1.0');
      expect(c.subtitle, 'Build 142 \u00b7 59.9 MB \u00b7 20 Oct 2026');
      expect(c.actionLabel, 'Download \u00b7 59.9 MB');
      expect(c.action, UpdateAction.download);
    });

    test('downloading shows percent, bytes, speed and time left', () {
      final c = d(UpdateState(
        status: UpdateStatus.downloading,
        release: release(),
        progress: 0.42,
        receivedBytes: 25200000,
        totalBytes: 59900000,
        bytesPerSecond: 4200000,
        etaSeconds: 8,
      ));
      expect(c.title, 'Downloading 1.1.0');
      expect(c.subtitle, '42% \u00b7 25.2 MB of 59.9 MB');
      expect(c.detail, '4.2 MB/s \u00b7 about 10 seconds left');
      expect(c.action, UpdateAction.cancel);
    });

    test('verifying and installing are busy, with nothing to press', () {
      for (final s in [UpdateStatus.checking, UpdateStatus.verifying, UpdateStatus.installing]) {
        final c = d(UpdateState(status: s, release: release()));
        expect(c.busy, isTrue, reason: '$s');
        expect(c.action, UpdateAction.none, reason: '$s');
      }
    });

    test('ready installs; needs-permission opens settings', () {
      expect(d(UpdateState(status: UpdateStatus.ready, release: release())).actionLabel, 'Install');
      final p = d(UpdateState(status: UpdateStatus.needsPermission, release: release()));
      expect(p.action, UpdateAction.allow);
      expect(p.actionLabel, 'Open settings');
    });

    test('each failure names the step that broke and the way to retry it', () {
      UpdateCopy f(UpdateStatus during) => d(UpdateState(
          status: UpdateStatus.failed,
          failedDuring: during,
          release: release(),
          error: 'A sentence.'));
      expect(f(UpdateStatus.checking).title, 'Couldn\u2019t check for updates');
      expect(f(UpdateStatus.checking).action, UpdateAction.check);
      expect(f(UpdateStatus.downloading).actionLabel, 'Resume download');
      expect(f(UpdateStatus.downloading).action, UpdateAction.retry);
      expect(f(UpdateStatus.verifying).title, 'The download was damaged');
      expect(f(UpdateStatus.installing).title, 'Couldn\u2019t start the installer');
      expect(f(UpdateStatus.installing).subtitle, 'A sentence.');
      expect(f(UpdateStatus.installing).tone, UpdateTone.bad);
    });
  });

  group('Software Update screen', () {
    testWidgets('up to date: says so and offers a check', (tester) async {
      final (svc, repo, _, _) = await boot(tester);
      await pumpScreen(tester, svc);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Mine Music is up to date'), findsOneWidget);
      expect(find.text('Check for updates'), findsOneWidget);
      expect(repo.calls, 1, reason: 'a recent look is enough: opening does not repeat it');

      await tester.runAsync(() async {
        await tester.tap(find.text('Check for updates'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 200));
      expect(repo.calls, 2, reason: 'the button forces a look');
    });

    testWidgets('available: the release, its notes and the download button',
        (tester) async {
      final (svc, _, _, _) = await boot(tester, offered: release());
      await pumpScreen(tester, svc);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Mine Music 1.1.0'), findsOneWidget);
      expect(find.text('Download \u00b7 59.9 MB'), findsOneWidget);
      expect(find.text('WHAT\u2019S NEW'), findsOneWidget);
      expect(find.text('Glass that behaves'), findsOneWidget);
      expect(find.text('Equalizer with presets'), findsOneWidget);
      expect(find.text('Pure black no longer tears'), findsOneWidget);
      expect(find.text('Skip this version'), findsOneWidget);
    });

    testWidgets('download -> progress -> cancel -> download -> ready -> install',
        (tester) async {
      final (svc, _, dl, installed) = await boot(tester, offered: release());
      await pumpScreen(tester, svc);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.runAsync(() async {
        await tester.tap(find.text('Download \u00b7 59.9 MB'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(svc.status, UpdateStatus.downloading);
      expect(find.text('Cancel'), findsOneWidget);

      dl.emit!(const DownloadProgress(
          received: 30000000, total: 59900000, bytesPerSecond: 3000000, etaSeconds: 10));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('50%'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(svc.status, UpdateStatus.available);

      await tester.runAsync(() async {
        await tester.tap(find.text('Download \u00b7 59.9 MB'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 100));
      final file = File('${Directory.systemTemp.path}/upd_ready.apk')..writeAsBytesSync([1]);
      addTearDown(() => file.deleteSync());
      await tester.runAsync(() async {
        dl.gate!.complete(DownloadOutcome.completed(file));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump(const Duration(milliseconds: 600));
      expect(svc.status, UpdateStatus.ready);
      expect(find.text('Ready to install'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Install'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(installed, [file.path]);
      expect(svc.status, UpdateStatus.installing);
      expect(find.text('Installing\u2026'), findsOneWidget);
    });

    testWidgets('a failed download says what happened and offers to resume',
        (tester) async {
      final (svc, _, dl, _) = await boot(tester, offered: release());
      await pumpScreen(tester, svc);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        await tester.tap(find.text('Download \u00b7 59.9 MB'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        dl.gate!.complete(DownloadOutcome.failed('Your connection dropped.'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('The download stopped'), findsOneWidget);
      expect(find.text('Your connection dropped.'), findsOneWidget);
      expect(find.text('Resume download'), findsOneWidget);
    });

    testWidgets('skipping a version hides the offer and leaves the screen',
        (tester) async {
      final (svc, _, _, _) = await boot(tester, offered: release());
      await tester.runAsync(svc.check);
      await tester.pumpWidget(MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => SoftwareUpdateScreen(service: svc)),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 1400));

      await tester.runAsync(() async {
        await tester.tap(find.text('Skip this version'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(svc.hasUpdate, isFalse);
      expect(find.text('Skip this version'), findsNothing);
      expect(find.text('open'), findsOneWidget, reason: 'popped back');
    });

    testWidgets('the automatic-check and early-builds switches persist',
        (tester) async {
      final (svc, _, _, _) = await boot(tester);
      await pumpScreen(tester, svc);
      await tester.scrollUntilVisible(find.text('Get early builds'), 300,
          scrollable: find.byType(Scrollable).first);

      await tester.runAsync(() async {
        await tester.tap(find.text('Check automatically'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.tap(find.text('Get early builds'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(svc.autoCheck, isFalse);
      expect(svc.channel, UpdateChannel.beta);
    });
  });

  group('UpdateCoordinator', () {
    Future<void> pumpApp(WidgetTester tester, UpdateService svc) async {
      await tester.pumpWidget(MaterialApp(
        navigatorKey: rootNavigatorKey,
        theme: GlassTheme.build(AccentColors.peach),
        builder: (context, child) => UpdateCoordinator(
          service: svc,
          settleDelay: const Duration(milliseconds: 50),
          retryDelay: const Duration(milliseconds: 50),
          child: child!,
        ),
        home: const Scaffold(body: Center(child: Text('home'))),
      ));
    }

    testWidgets('tells you about an update once, and only once per version',
        (tester) async {
      final (svc, _, _, _) = await boot(tester, offered: release());
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.runAsync(svc.check);
      await pumpApp(tester, svc);
      await letItRun(tester);

      expect(find.text('Update available'), findsOneWidget);
      expect(find.textContaining('Mine Music 1.1.0'), findsWidgets);
      expect(find.text('Equalizer'), findsOneWidget, reason: 'the highlights');
      expect(svc.shouldPrompt, isFalse, reason: 'prompted: it will not nag again');

      // Swipe it away; nothing re-opens it.
      await tester.tap(find.text('Later'));
      await letItRun(tester);
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('the first launch after an update shows what changed',
        (tester) async {
      final (svc, _, _, _) = await boot(tester, prefs: {
        'update_last_run_version': '1.0.3+90',
      });
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      expect(svc.whatsNew, isNotNull);
      await pumpApp(tester, svc);
      await letItRun(tester);

      expect(find.text('Mine Music was updated'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await letItRun(tester);
      expect(svc.whatsNew, isNull);
    });

    testWidgets('does not open over another screen; waits and tries again',
        (tester) async {
      final (svc, _, _, _) = await boot(tester, offered: release());
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.runAsync(svc.check);
      await pumpApp(tester, svc);
      rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('another screen'))));
      await letItRun(tester);
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('without an updater in the tree it is invisible', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: UpdateCoordinator(child: Text('hello')),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('hello'), findsOneWidget);
    });
  });
}
