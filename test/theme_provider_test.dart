import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('defaults to glassmorphism and initialized flag set', () async {
    final provider = ThemeProvider();
    await provider.initialize();

    expect(provider.currentTheme, AppThemeMode.glassmorphism);
    expect(provider.isGlassmorphism, isTrue);
    expect(provider.isMaterialYou, isFalse);
    expect(provider.isInitialized, isTrue);
  });

  test('switchTheme persists preference', () async {
    final provider = ThemeProvider();
    await provider.initialize();

    await provider.switchTheme(AppThemeMode.materialYou);

    expect(provider.currentTheme, AppThemeMode.materialYou);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('app_theme_mode'), AppThemeMode.materialYou.index);
  });

  test('toggleTheme flips between modes', () async {
    final provider = ThemeProvider();
    await provider.initialize();

    await provider.toggleTheme();
    expect(provider.currentTheme, AppThemeMode.materialYou);

    await provider.toggleTheme();
    expect(provider.currentTheme, AppThemeMode.glassmorphism);
  });

  test('initialize restores persisted theme', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'app_theme_mode': AppThemeMode.materialYou.index},
    );

    final provider = ThemeProvider();
    await provider.initialize();

    expect(provider.currentTheme, AppThemeMode.materialYou);
  });

  test('setDynamicColorEnabled persists and notifies once per change',
      () async {
    final provider = ThemeProvider();
    await provider.initialize();

    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.setDynamicColorEnabled(false);
    expect(provider.isDynamicColorEnabled, isFalse);
    expect(notifications, 1);

    // No-op change must not notify.
    await provider.setDynamicColorEnabled(false);
    expect(notifications, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('dynamic_color_enabled'), isFalse);
  });
}
