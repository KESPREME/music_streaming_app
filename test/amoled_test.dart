import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/theme/amoled_theme.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/ambient_backdrop.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'muzo_enhancements_test.dart' show MockMusicProvider, sampleTrack;

/// PURE BLACK (AMOLED).
///
/// A setting that is off by default, persists, and turns the app's grounds
/// `#000000` - the backdrop behind every tab and the full-screen pages - with
/// raised surfaces one step up and outlined so they can still be seen. These pin
/// each of those, the fade that gets there, and that it costs the GPU less, not
/// more.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('ThemeProvider.isAmoled', () {
    test('is OFF by default', () async {
      final p = ThemeProvider();
      await p.initialize();
      expect(p.isAmoled, isFalse);
    });

    test('setAmoled applies, announces once, and persists', () async {
      final p = ThemeProvider();
      await p.initialize();
      var notified = 0;
      p.addListener(() => notified++);

      await p.setAmoled(true);

      expect(p.isAmoled, isTrue);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('amoled_black_enabled'), isTrue);
    });

    test('setting the value it already has does nothing', () async {
      final p = ThemeProvider();
      await p.initialize();
      var notified = 0;
      p.addListener(() => notified++);
      await p.setAmoled(false);
      expect(notified, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('amoled_black_enabled'), isFalse);
    });

    test('the choice survives a restart', () async {
      final first = ThemeProvider();
      await first.initialize();
      await first.setAmoled(true);

      final second = ThemeProvider();
      expect(second.isAmoled, isFalse, reason: 'before it loads, the default');
      await second.initialize();
      expect(second.isAmoled, isTrue);
    });

    test('it is independent of the theme and dynamic-colour choices', () async {
      final p = ThemeProvider();
      await p.initialize();
      await p.setAmoled(true);
      await p.toggleTheme();
      await p.setDynamicColorEnabled(false);
      expect(p.isAmoled, isTrue);
    });
  });

  group('GlassTheme carries it', () {
    test('off: the theme is exactly what it always was', () {
      final t = GlassTheme.build(AccentColors.peach);
      expect(t.extension<AmoledTheme>()?.enabled, isFalse);
      expect(t.dialogTheme.backgroundColor, const Color(0xFF161616));
      expect(t.bottomSheetTheme.backgroundColor, const Color(0xFF161616));
      expect(t.snackBarTheme.backgroundColor, const Color(0xFF1C1C1E));
      expect(t.colorScheme.surfaceContainerHighest, const Color(0xFF141414));
      expect((t.dialogTheme.shape! as RoundedRectangleBorder).side,
          BorderSide.none);
    });

    test('on: raised surfaces step up from the canvas and are outlined', () {
      final t = GlassTheme.build(AccentColors.peach, amoled: true);
      expect(t.extension<AmoledTheme>()?.enabled, isTrue);
      expect(t.scaffoldBackgroundColor, Colors.black);
      expect(t.colorScheme.surface, Colors.black);
      for (final c in [
        t.dialogTheme.backgroundColor,
        t.bottomSheetTheme.backgroundColor,
        t.bottomSheetTheme.modalBackgroundColor,
        t.snackBarTheme.backgroundColor,
        t.colorScheme.surfaceContainerHighest,
      ]) {
        expect(c, AmoledTheme.surface);
      }
      // One step off black - a black panel on a black page has no edge at all.
      expect(AmoledTheme.surface, isNot(Colors.black));
      expect(AmoledTheme.surface.computeLuminance(), lessThan(0.01));

      for (final shape in [
        t.dialogTheme.shape,
        t.bottomSheetTheme.shape,
        t.snackBarTheme.shape,
      ]) {
        expect((shape! as RoundedRectangleBorder).side.color,
            AmoledTheme.hairline);
      }
    });

    test('on: no elevation tint is laid over the panels', () {
      final t = GlassTheme.build(AccentColors.peach, amoled: true);
      expect(t.dialogTheme.surfaceTintColor, Colors.transparent);
      expect(t.bottomSheetTheme.surfaceTintColor, Colors.transparent);
    });

    test('the accent is untouched', () {
      final a = GlassTheme.build(AccentColors.peach);
      final b = GlassTheme.build(AccentColors.peach, amoled: true);
      expect(b.colorScheme.primary, a.colorScheme.primary);
      expect(b.colorScheme.onPrimary, a.colorScheme.onPrimary);
    });
  });

  group('AmoledTheme helpers', () {
    Future<BuildContext> contextWith(WidgetTester tester, ThemeData theme) async {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (c) {
          captured = c;
          return const SizedBox();
        }),
      ));
      return captured;
    }

    testWidgets('a theme that did not come from GlassTheme reads as off',
        (tester) async {
      final c = await contextWith(tester, ThemeData.dark());
      expect(AmoledTheme.isOn(c), isFalse);
    });

    testWidgets('off: every helper returns what it was given', (tester) async {
      final c = await contextWith(tester, GlassTheme.build(AccentColors.peach));
      const grey = Color(0xFF1E1E1E);
      expect(AmoledTheme.isOn(c), isFalse);
      expect(AmoledTheme.surfaceOf(c, grey), grey);
      expect(AmoledTheme.canvasOf(c, grey), grey);
      expect(AmoledTheme.edge(c), BorderSide.none);
      const g = [Color(0xFF121212), Color(0xFF1E1E1E), Color(0xFF000000)];
      expect(AmoledTheme.gradient(c, g), g);
    });

    testWidgets('on: surfaces, canvases and gradients go dark', (tester) async {
      final c = await contextWith(
          tester, GlassTheme.build(AccentColors.peach, amoled: true));
      const grey = Color(0xFF1E1E1E);
      expect(AmoledTheme.isOn(c), isTrue);
      expect(AmoledTheme.surfaceOf(c, grey), AmoledTheme.surface);
      expect(AmoledTheme.canvasOf(c, grey), Colors.black);
      expect(AmoledTheme.edge(c).color, AmoledTheme.hairline);
      // Same number of stops, so a gradient's own `stops` stay valid.
      final g = AmoledTheme.gradient(c, const [
        Color(0xFF121212),
        Color(0xFF1E1E1E),
        Color(0xFF000000),
      ]);
      expect(g, hasLength(3));
      expect(g, everyElement(Colors.black));
    });

    test('lerp switches at the midpoint and equality is by value', () {
      const off = AmoledTheme();
      const on = AmoledTheme(enabled: true);
      expect(off.lerp(on, 0.4).enabled, isFalse);
      expect(off.lerp(on, 0.6).enabled, isTrue);
      expect(off.lerp(null, 0.9).enabled, isFalse);
      expect(const AmoledTheme(enabled: true), on);
      expect(on.copyWith(enabled: false), off);
    });
  });

  group('the backdrop', () {
    // Built once, outside the test zone. A MusicProvider starts retry timers as it
    // initialises; made inside a test they are fake-async timers that outlive the
    // widget tree and fail the pending-timer check. The backdrop only reads the
    // current track from it.
    late MockMusicProvider playing;
    late MockMusicProvider idle;
    setUpAll(() {
      playing = MockMusicProvider(initialTrack: sampleTrack());
      idle = MockMusicProvider();
    });

    MockMusicProvider withArt() => playing;
    Widget mount(
      MockMusicProvider music, {
      required bool amoled,
      bool reduceMotion = false,
      GlobalKey? key,
    }) {
      return MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ChangeNotifierProvider<MusicProvider>.value(
            value: music,
            child: Theme(
              data: GlassTheme.build(AccentColors.peach, amoled: amoled),
              child: RepaintBoundary(
                key: key,
                child: const SizedBox(
                  width: 200,
                  height: 400,
                  child: AmbientBackdrop(),
                ),
              ),
            ),
          ),
        ),
      );
    }
    Future<List<int>> pixel(WidgetTester tester, GlobalKey key) async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => b.toImage());
      final data = (await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      // Centre pixel (r, g, b).
      final w = image!.width, h = image.height;
      final i = ((h ~/ 2) * w + (w ~/ 2)) * 4;
      return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)];
    }


    testWidgets('off: the artwork wash is built (blurred art)', (tester) async {
      await tester.pumpWidget(mount(withArt(), amoled: false));
      await tester.pump();
      expect(find.byType(ImageFiltered), findsOneWidget);
    });

    testWidgets('on: nothing is built but black - no blur, no art', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(mount(withArt(), amoled: true, key: key));
      await tester.pump();
      expect(find.byType(ImageFiltered), findsNothing,
          reason: 'the 48-sigma blur is the shell\'s most expensive op');
      expect(find.byType(DecoratedBox), findsNothing,
          reason: 'no scrim and no accent bloom either');
      expect(await pixel(tester, key), [0, 0, 0],
          reason: 'true black, not near black');
    });

    testWidgets('a cold start in either mode does not animate', (tester) async {
      await tester.pumpWidget(mount(withArt(), amoled: true));
      // First frame, no settling: already black.
      expect(find.byType(ImageFiltered), findsNothing);

      await tester.pumpWidget(Container()); // tear down
      await tester.pumpWidget(mount(withArt(), amoled: false));
      expect(find.byType(ImageFiltered), findsOneWidget);
    });

    testWidgets('switching on fades to black over the ambient duration',
        (tester) async {
      final music = withArt();
      await tester.pumpWidget(mount(music, amoled: false));
      await tester.pump();

      await tester.pumpWidget(mount(music, amoled: true));
      await tester.pump(); // start
      await tester.pump(const Duration(milliseconds: 450)); // about half-way

      // Mid-fade: the art is still there under a veil that is neither clear nor
      // opaque.
      expect(find.byType(ImageFiltered), findsOneWidget);
      final veils = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((b) => b.color.a > 0.05 && b.color.a < 0.95)
          .toList();
      expect(veils, isNotEmpty, reason: 'a partly-opaque black veil');

      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(ImageFiltered), findsNothing,
          reason: 'once black, the blur is dropped');
    });

    testWidgets('switching off brings the art back', (tester) async {
      final music = withArt();
      await tester.pumpWidget(mount(music, amoled: true));
      await tester.pump();
      expect(find.byType(ImageFiltered), findsNothing);

      await tester.pumpWidget(mount(music, amoled: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.byType(ImageFiltered), findsOneWidget);
    });

    testWidgets('reduce motion: it cuts, it does not fade', (tester) async {
      final music = withArt();
      await tester.pumpWidget(mount(music, amoled: false, reduceMotion: true));
      await tester.pump();
      await tester.pumpWidget(mount(music, amoled: true, reduceMotion: true));
      await tester.pump(); // one frame, no settling
      expect(find.byType(ImageFiltered), findsNothing);
    });

    testWidgets('with nothing playing it is black as well', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
          mount(idle, amoled: true, key: key));
      await tester.pump();
      expect(await pixel(tester, key), [0, 0, 0]);
    });
  });
}
