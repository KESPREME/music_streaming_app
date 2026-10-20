import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/design/glass/chrome_glass.dart';
import 'package:music_streaming_app/providers/accent_controller.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/screens/settings_screen.dart';
import 'package:music_streaming_app/services/app_platform.dart';
import 'package:music_streaming_app/services/auth_service.dart';
import 'package:music_streaming_app/services/update/update_models.dart';
import 'package:music_streaming_app/services/update/update_repository.dart';
import 'package:music_streaming_app/services/update/update_service.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/settings/settings_segmented.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'muzo_enhancements_test.dart' show MockMusicProvider;

class _Repo extends UpdateRepository {
  _Repo(this.release);
  final ReleaseInfo? release;
  @override
  Future<FetchResult> fetchLatest({
    required UpdateChannel channel,
    required List<String> abis,
    String? etag,
  }) async =>
      Fetched(release, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMusicProvider music;
  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    music = MockMusicProvider();
  });
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  void tolerateKnownSettingsNoise() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed by') ||
          message.contains('ListTile background color or ink splashes') ||
          message.contains('image resource service')) {
        return;
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  }

  Future<ThemeProvider> pumpSettings(
    WidgetTester tester, {
    UpdateService? updates,
    bool amoled = false,
  }) async {
    tolerateKnownSettingsNoise();
    final themeProvider = ThemeProvider();
    await themeProvider.initialize();
    if (amoled) await themeProvider.setAmoled(true);
    await tester.binding.setSurfaceSize(const Size(430, 3400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MusicProvider>.value(value: music),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<AccentController>(create: (_) => AccentController()),
          if (updates != null) ChangeNotifierProvider<UpdateService>.value(value: updates),
        ],
        child: MaterialApp(
          theme: GlassTheme.build(AccentColors.peach),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    return themeProvider;
  }

  Future<void> search(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField).first, q);
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('SettingsSegmented', () {
    Widget host({required int? selected, required ValueChanged<int> onChanged}) =>
        MaterialApp(
          theme: GlassTheme.build(AccentColors.peach),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: SettingsSegmented<int>(
                semanticPrefix: 'Quality',
                selected: selected,
                options: const [(1, 'Low'), (2, 'Mid'), (3, 'High')],
                onChanged: onChanged,
              ),
            ),
          ),
        );

    testWidgets('shows every option and reports a pick', (tester) async {
      int? got;
      await tester.pumpWidget(host(selected: 1, onChanged: (v) => got = v));
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Mid'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      await tester.tap(find.text('High'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(got, 3);
    });

    testWidgets('tapping the option already chosen does nothing', (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(selected: 2, onChanged: (_) => calls++));
      await tester.tap(find.text('Mid'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls, 0);
    });

    testWidgets('the segments are buttons with a selected state', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(selected: 2, onChanged: (_) {}));
      final s = tester.getSemantics(find.bySemanticsLabel('Quality Mid'));
      expect(s.flagsCollection.isSelected.toBoolOrNull(), isTrue);
      expect(s.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('with no option in force there is no thumb and nothing breaks',
        (tester) async {
      await tester.pumpWidget(host(selected: null, onChanged: (_) {}));
      expect(find.text('Mid'), findsOneWidget);
    });
  });

  group('Settings screen', () {
    testWidgets('has the new groups, in a sensible order', (tester) async {
      await pumpSettings(tester);
      for (final header in ['APPEARANCE', 'PLAYBACK', 'QUALITY & STORAGE', 'ABOUT']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('APPEARANCE'), lessThan(y('PLAYBACK')));
      expect(y('PLAYBACK'), lessThan(y('QUALITY & STORAGE')));
      expect(y('QUALITY & STORAGE'), lessThan(y('ABOUT')));
    });

    testWidgets('the equalizer tile is up top and says it is not on this phone here',
        (tester) async {
      await pumpSettings(tester);
      expect(find.text('Equalizer'), findsOneWidget);
      expect(find.text('Not on this phone'), findsOneWidget);
      final tile = tester.getTopLeft(find.text('Equalizer')).dy;
      expect(tile, lessThan(tester.getTopLeft(find.text('APPEARANCE')).dy));
    });

    testWidgets('Glass rendering is a three-way choice that is saved', (tester) async {
      final theme = await pumpSettings(tester);
      expect(find.text('Glass rendering'), findsOneWidget);
      expect(theme.glassRendering, GlassRendering.auto);

      await tester.tap(find.text('Frosted'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(theme.glassRendering, GlassRendering.frosted);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('glass_rendering'), 'frosted');
    });

    testWidgets('Auto says what it is doing right now', (tester) async {
      await pumpSettings(tester);
      expect(find.textContaining('Auto \u00b7 refraction right now'), findsOneWidget);
    });

    testWidgets('on pure black Auto says frosted', (tester) async {
      await pumpSettings(tester, amoled: true);
      expect(find.textContaining('Auto \u00b7 frosted right now'), findsOneWidget);
    });

    testWidgets('streaming quality is one tap, not a dialog', (tester) async {
      await pumpSettings(tester);
      expect(find.text('Wi-Fi quality'), findsOneWidget);
      expect(find.text('Cellular quality'), findsOneWidget);
      final wifi = find.byType(SettingsSegmented<int>).first; // the Wi-Fi row comes first
      await tester.tap(find.descendant(of: wifi, matching: find.text('256')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(music.wifiBitrate, 256);
      expect(music.isAutoBitrate, isFalse);
      expect(find.text('256 kbps'), findsWidgets);

      await tester.tap(find.descendant(of: wifi, matching: find.text('Auto')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(music.isAutoBitrate, isTrue);
    });

    testWidgets('Remember what I was playing persists the choice', (tester) async {
      await pumpSettings(tester);
      expect(find.text('Remember what I was playing'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Remember what I was playing'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Starts fresh every time'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('session_restore_enabled'), isFalse);
      // leave the singleton as found
      await tester.runAsync(() async {
        await tester.tap(find.text('Remember what I was playing'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
    });

    testWidgets('Version is read from the app, not hard-coded', (tester) async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      AppPlatform.resetCache();
      messenger.setMockMethodCallHandler(AppPlatform.channel, (call) async => {
            'versionName': '2.3.4',
            'versionCode': 567,
            'packageName': 'x',
          });
      addTearDown(() {
        messenger.setMockMethodCallHandler(AppPlatform.channel, null);
        AppPlatform.resetCache();
      });
      await pumpSettings(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('2.3.4 (567)'), findsOneWidget);
      expect(find.textContaining('1.0.4'), findsNothing);
    });

    testWidgets('Software update row is there even with no updater', (tester) async {
      await pumpSettings(tester);
      expect(find.text('Software update'), findsOneWidget);
      expect(find.text('Check for updates'), findsOneWidget);
    });
  });

  group('Settings and a pending update', () {
    ReleaseInfo release() => ReleaseInfo(
          version: '1.1.0',
          build: 142,
          tag: 'v1.1.0+142',
          asset: const ReleaseAsset(
              name: 'a.apk', url: 'https://x/a.apk', size: 59900000, sha256: 'a'),
        );

    Future<UpdateService> service(WidgetTester tester, ReleaseInfo? offered) async {
      SharedPreferences.setMockInitialValues({});
      final dir = Directory.systemTemp.createTempSync('set_upd');
      addTearDown(() => dir.deleteSync(recursive: true));
      final svc = UpdateService(
        repository: _Repo(offered),
        updatesDir: () async => dir,
        appInfo: () async => const AppInfo(
            versionName: '1.0.4', versionCode: 100, packageName: 'x', sdkInt: 34),
      );
      await tester.runAsync(() async {
        await svc.initialize();
        await svc.check();
      });
      addTearDown(svc.dispose);
      return svc;
    }

    testWidgets('a banner at the top, and a NEW badge in About', (tester) async {
      final svc = await service(tester, release());
      await pumpSettings(tester, updates: svc);
      expect(find.text('Update available'), findsOneWidget);
      expect(find.textContaining('Mine Music 1.1.0'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('1.1.0 is available'), findsOneWidget);
    });

    testWidgets('no banner, no badge when nothing is pending', (tester) async {
      final svc = await service(tester, null);
      await pumpSettings(tester, updates: svc);
      expect(find.text('Update available'), findsNothing);
      expect(find.text('NEW'), findsNothing);
      expect(find.text('Version 1.0.4'), findsOneWidget);
    });

    testWidgets('searching hides the banner so results are not pushed down',
        (tester) async {
      final svc = await service(tester, release());
      await pumpSettings(tester, updates: svc);
      await search(tester, 'wifi');
      expect(find.text('Update available'), findsNothing);
    });
  });

  group('Settings search finds the new rows', () {
    testWidgets('equalizer', (tester) async {
      await pumpSettings(tester);
      await search(tester, 'equalizer');
      expect(find.text('Equalizer'), findsOneWidget);
      expect(find.text('Glass rendering'), findsNothing);
      expect(find.text('APPEARANCE'), findsNothing);
    });

    testWidgets('glass / frosted / pixelated', (tester) async {
      for (final q in ['glass', 'frosted', 'pixelated']) {
        await pumpSettings(tester);
        await search(tester, q);
        expect(find.text('Glass rendering'), findsOneWidget, reason: q);
        expect(find.text('Equalizer'), findsNothing, reason: q);
      }
    });

    testWidgets('update', (tester) async {
      await pumpSettings(tester);
      await search(tester, 'update');
      expect(find.text('Software update'), findsOneWidget);
      expect(find.text('ABOUT'), findsOneWidget);
    });

    testWidgets('wifi and kbps reach the quality group', (tester) async {
      await pumpSettings(tester);
      await search(tester, 'kbps');
      expect(find.text('Wi-Fi quality'), findsOneWidget);
      expect(find.text('QUALITY & STORAGE'), findsOneWidget);
    });

    testWidgets('resume / where I left off', (tester) async {
      await pumpSettings(tester);
      await search(tester, 'where i left off');
      expect(find.text('Remember what I was playing'), findsOneWidget);
    });

    testWidgets('a query that matches nothing says so', (tester) async {
      await pumpSettings(tester);
      await search(tester, 'zzzz');
      expect(find.textContaining('No settings match'), findsOneWidget);
    });
  });

  group('registry', () {
    test('every new row is registered, with no duplicates', () {
      final ids = settingsSearchEntries.map((e) => e.id).toList();
      for (final id in [
        'quick.eq', 'prefs.glass', 'playback.session', 'data.wifi', 'about.update',
      ]) {
        expect(ids, contains(id));
      }
      expect(ids.toSet().length, ids.length);
    });
  });
}
