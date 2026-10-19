import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/providers/accent_controller.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/screens/settings_screen.dart';
import 'package:music_streaming_app/services/auth_service.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/liquid_switch.dart';
import 'package:music_streaming_app/widgets/settings/settings_search.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'muzo_enhancements_test.dart' show MockMusicProvider;

/// THE SETTING, ON THE SCREEN.
///
/// The row is in Appearance, off until asked for, toggles the real
/// `ThemeProvider`, is found by the words people type for it, and is announced
/// to a screen reader as one labelled switch.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Built once, outside the test zone: see the note in amoled_test.dart.
  late MockMusicProvider music;
  setUpAll(() {
    // Before the provider exists: its start-up reads preferences at once.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    music = MockMusicProvider();
  });
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// Two debug-mode assertions the Settings screen raises that have nothing to do
  /// with this setting, and that are artefacts of the test environment or already
  /// there: the placeholder test font is far wider than the real one (so the
  /// profile card's title row "overflows"), and a ListTile sits inside a coloured
  /// group box. Anything else still fails the test.
  void tolerateKnownSettingsNoise() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed by') ||
          message.contains('ListTile background color or ink splashes')) {
        return;
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  }

  Future<ThemeProvider> pumpSettings(WidgetTester tester) async {
    tolerateKnownSettingsNoise();
    final themeProvider = ThemeProvider();
    await themeProvider.initialize();
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MusicProvider>.value(value: music),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<AccentController>(
              create: (_) => AccentController()),
        ],
        child: MaterialApp(
          theme: GlassTheme.build(AccentColors.peach),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return themeProvider;
  }

  final row = find.text('Pure black (AMOLED)');

  testWidgets('the row is there, and says it is off', (tester) async {
    final theme = await pumpSettings(tester);
    expect(row, findsOneWidget);
    expect(find.text('Off · backgrounds follow the album art'), findsOneWidget);
    expect(theme.isAmoled, isFalse);
  });

  testWidgets('tapping the switch turns it on, and the row says so',
      (tester) async {
    final theme = await pumpSettings(tester);

    // The switch is the one inside this row.
    final sw = find.descendant(
      of: find.ancestor(of: row, matching: find.byType(Row)).first,
      matching: find.byType(LiquidSwitch),
    );
    await tester.tap(sw);
    await tester.pump();

    expect(theme.isAmoled, isTrue);
    expect(find.text('On · true black, saves power on OLED screens'),
        findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('amoled_black_enabled'), isTrue);
  });

  testWidgets('tapping anywhere on the row toggles it, once', (tester) async {
    final theme = await pumpSettings(tester);
    await tester.tap(row);
    await tester.pump();
    expect(theme.isAmoled, isTrue);
    await tester.tap(row);
    await tester.pump();
    expect(theme.isAmoled, isFalse);
  });

  testWidgets('it is one labelled switch for a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    final theme = await pumpSettings(tester);
    final label = find.bySemanticsLabel('Pure black (AMOLED)');

    final off = tester.getSemantics(label).getSemanticsData().flagsCollection;
    // Tristate.none would mean it is not a toggle at all.
    expect(off.isToggled, Tristate.isFalse, reason: 'announced as a switch, off');

    await theme.setAmoled(true);
    await tester.pump();
    final on = tester.getSemantics(label).getSemanticsData().flagsCollection;
    expect(on.isToggled, Tristate.isTrue);
    handle.dispose();
  });
  group('search', () {
    SettingsSearchIndex search(String q) =>
        SettingsSearchIndex(q)..registerAll(settingsSearchEntries);

    test('the words people type all find it', () {
      for (final q in [
        'amoled',
        'AMOLED',
        'oled',
        'pure black',
        'true black',
        'black',
        'battery',
        'dark',
      ]) {
        expect(search(q).matches('prefs.amoled'), isTrue, reason: q);
      }
    });

    test('unrelated words do not', () {
      expect(search('lyrics').matches('prefs.amoled'), isFalse);
      expect(search('crossfade').matches('prefs.amoled'), isFalse);
    });

    testWidgets('searching "oled" keeps the Appearance group on screen',
        (tester) async {
      await pumpSettings(tester);
      await tester.enterText(find.byType(TextField).first, 'oled');
      await tester.pump(const Duration(milliseconds: 400));
      expect(row, findsOneWidget);
    });

    testWidgets('searching for something else hides it', (tester) async {
      await pumpSettings(tester);
      await tester.enterText(find.byType(TextField).first, 'crossfade');
      await tester.pump(const Duration(milliseconds: 400));
      expect(row, findsNothing);
    });
  });
}
