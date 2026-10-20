import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/screens/settings_screen.dart';
import 'package:music_streaming_app/widgets/settings/settings_search.dart';
import 'package:music_streaming_app/theme/app_font.dart';
import 'package:music_streaming_app/widgets/settings/font_picker_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(AppFont.debugReset);
  tearDown(AppFont.debugReset);

  group('AppFont', () {
    test('the default is Plus Jakarta Sans, weights untouched', () {
      final s = AppFont.style(fontSize: 14, fontWeight: FontWeight.w600);
      expect(s.fontFamily, contains('PlusJakartaSans'));
      expect(s.fontWeight, FontWeight.w600);
      expect(AppFont.isDefault, isTrue);
    });

    test('the weight setting moves every weight one step, clamped', () {
      AppFont.apply(weightDelta: 1);
      expect(AppFont.shift(FontWeight.w600), FontWeight.w700);
      expect(AppFont.shift(null), FontWeight.w500, reason: 'unset reads as regular');
      expect(AppFont.shift(FontWeight.w900), FontWeight.w900);
      expect(AppFont.style(fontWeight: FontWeight.w400).fontWeight, FontWeight.w500);
      AppFont.apply(weightDelta: -1);
      expect(AppFont.shift(FontWeight.w100), FontWeight.w100);
      expect(AppFont.shift(FontWeight.w700), FontWeight.w600);
      AppFont.apply(weightDelta: 5);
      expect(AppFont.weightDelta, 1);
    });

    test('a weight from textStyle is shifted too', () {
      AppFont.apply(weightDelta: 1);
      final s = AppFont.style(textStyle: const TextStyle(fontWeight: FontWeight.w300));
      expect(s.fontWeight, FontWeight.w400);
    });

    test('an unknown family falls back to the default; each change bumps revision', () {
      final r = AppFont.revision.value;
      AppFont.apply(family: 'Comic Sans');
      expect(AppFont.family, AppFont.defaultFamily);
      AppFont.apply(weightDelta: 1);
      expect(AppFont.revision.value, r + 1);
      AppFont.apply(weightDelta: 1);
      expect(AppFont.revision.value, r + 1, reason: 'no change, no bump');
    });

    test('text theme weights shift with the setting', () {
      final base = Typography.material2021().white;
      expect(AppFont.shiftTextTheme(base), same(base));
      AppFont.apply(weightDelta: 1);
      final t = AppFont.shiftTextTheme(base.copyWith(titleLarge: const TextStyle(fontWeight: FontWeight.w600)));
      expect(t.titleLarge!.fontWeight, FontWeight.w700);
    });

    test('every offered family is a distinct name', () {
      final names = AppFont.families.map((f) => f.name).toList();
      expect(names.toSet(), hasLength(names.length));
      expect(names.first, AppFont.defaultFamily);
    });
  });

  test('Settings search finds the font rows', () {
    SettingsSearchIndex i(String q) => SettingsSearchIndex(q)..registerAll(settingsSearchEntries);
    expect(i('font').matches('prefs.font'), isTrue);
    expect(i('typeface').matches('prefs.font'), isTrue);
    expect(i('bold').matches('prefs.weight'), isTrue);
    expect(i('crossfade').matches('prefs.font'), isFalse);
  });

  group('ThemeProvider font settings', () {
    test('a family that cannot be loaded changes nothing', () async {
      SharedPreferences.setMockInitialValues({});
      final t = ThemeProvider();
      await t.initialize();
      final ok = await t.setFontFamily('Inter', preload: (_) async => false);
      expect(ok, isFalse);
      expect(t.fontFamily, AppFont.defaultFamily);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('font_family'), isNull);
    });

    test('a loaded family is applied, saved, and restored next launch', () async {
      SharedPreferences.setMockInitialValues({});
      final t = ThemeProvider();
      await t.initialize();
      var notified = 0;
      t.addListener(() => notified++);
      expect(await t.setFontFamily('Inter', preload: (_) async => true), isTrue);
      expect(AppFont.family, 'Inter');
      expect(notified, 1);
      await t.setFontWeightDelta(-1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('font_family'), 'Inter');
      expect(prefs.getInt('font_weight_delta'), -1);

      AppFont.debugReset();
      final next = ThemeProvider();
      await next.initialize();
      expect(next.fontFamily, 'Inter');
      expect(next.fontWeightDelta, -1);
    });

    test('a saved family that is no longer offered falls back', () async {
      SharedPreferences.setMockInitialValues({'font_family': 'Gone Sans', 'font_weight_delta': 7});
      final t = ThemeProvider();
      await t.initialize();
      expect(t.fontFamily, AppFont.defaultFamily);
      expect(t.fontWeightDelta, 1);
    });
  });

  testWidgets('font sheet: weight steps apply; a failed download says so and keeps the face',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeProvider();
    await tester.runAsync(theme.initialize);
    await tester.pumpWidget(ChangeNotifierProvider<ThemeProvider>.value(
      value: theme,
      child: MaterialApp(
        home: Scaffold(body: FontPickerSheet(preload: (_) async => false)),
      ),
    ));
    expect(find.text('Plus Jakarta Sans'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('weight_1')));
    await tester.pump();
    expect(theme.fontWeightDelta, 1);

    await tester.tap(find.byKey(const ValueKey('font_Inter')));
    await tester.pump();
    await tester.pump();
    expect(theme.fontFamily, AppFont.defaultFamily);
    expect(find.textContaining("Couldn't download Inter"), findsOneWidget);
  });
}
