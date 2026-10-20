import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'package:music_streaming_app/design/glass/chrome_glass.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/providers/accent_controller.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/liquid_glass_nav_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Provider extends MusicProvider {
  _Provider(this.track);
  final Track? track;

  @override
  Track? get currentTrack => track;

  @override
  bool get isMiniPlayerVisible => track != null;

  @override
  bool get hideMiniPlayer => false;

  @override
  Duration get duration => const Duration(minutes: 3);

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();
}

Widget _bar({required bool amoled, GlassRendering? rendering, Track? track}) {
  return ChangeNotifierProvider<MusicProvider>.value(
    value: _Provider(track),
    child: MaterialApp(
      theme: GlassTheme.build(
        AccentColors.peach,
        amoled: amoled,
        glassRendering: rendering ?? GlassRendering.auto,
      ),
      home: Scaffold(
        bottomNavigationBar: LiquidGlassNavBar(
          currentIndex: 0,
          onTap: (_) {},
          searchMode: false,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Explore'),
            BottomNavigationBarItem(
                icon: Icon(Icons.library_music), label: 'Library'),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('ChromeGlassSpec.resolve', () {
    test('normal mode is the refraction look, unchanged', () {
      final s = ChromeGlassSpec.resolve(amoled: false);
      expect(s.frosted, isFalse);
      // null = the package default (premium), i.e. exactly what shipped before.
      expect(s.quality, isNull);
      expect(s.indicatorPinch, 0.45);
      expect(s.barBlur, 24);
      expect(s.barThickness, 24);
      expect(s.barChromatic, 0.04);
      expect(s.barSaturation, 1.15);
      expect(s.lensLite, isNull);
      expect(s.lensBlur, 16);
    });

    test('pure black picks frosted: a stable tier, no pinch, no chromatic fringe',
        () {
      final s = ChromeGlassSpec.resolve(amoled: true);
      expect(s.frosted, isTrue);
      expect(s.quality, lgw.GlassQuality.standard);
      expect(s.indicatorPinch, 0, reason: 'pinch only exists in the shader');
      expect(s.barChromatic, 0);
      expect(s.indicatorChromatic, 0);
      expect(s.barSaturation, 1.0, reason: 'no saturation boost on black');
      expect(s.lensLite, LiquidGlassLitePickup.blend);
      expect(s.barBlur, greaterThan(24),
          reason: 'white text on black must melt into a glow behind the bar');
    });

    test('pure black glass is visible against the canvas', () {
      final s = ChromeGlassSpec.resolve(amoled: true);
      expect(s.barTint.a, greaterThan(0.08),
          reason: 'a #000 bar on a #000 screen would be invisible');
    });

    test('the user can override Auto in either direction', () {
      expect(
        ChromeGlassSpec.resolve(amoled: true, rendering: GlassRendering.refraction)
            .frosted,
        isFalse,
      );
      expect(
        ChromeGlassSpec.resolve(amoled: false, rendering: GlassRendering.frosted)
            .frosted,
        isTrue,
      );
      expect(
        ChromeGlassSpec.resolve(amoled: false, rendering: GlassRendering.auto)
            .frosted,
        isFalse,
      );
    });

    test('an unknown stored value falls back to Auto', () {
      expect(GlassRendering.parse('nonsense'), GlassRendering.auto);
      expect(GlassRendering.parse(null), GlassRendering.auto);
      expect(GlassRendering.parse('frosted'), GlassRendering.frosted);
    });

    test('every option explains itself', () {
      for (final r in GlassRendering.values) {
        expect(r.label, isNotEmpty);
        expect(r.description.length, greaterThan(10));
      }
    });
  });

  group('ThemeProvider.glassRendering', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to Auto, persists a choice and reads it back', () async {
      final a = ThemeProvider();
      await a.initialize();
      expect(a.glassRendering, GlassRendering.auto);

      await a.setGlassRendering(GlassRendering.frosted);
      expect(a.glassRendering, GlassRendering.frosted);

      final b = ThemeProvider();
      await b.initialize();
      expect(b.glassRendering, GlassRendering.frosted);
    });

    test('announces the change before the disk write completes', () async {
      final p = ThemeProvider();
      await p.initialize();
      var notified = 0;
      p.addListener(() => notified++);
      final f = p.setGlassRendering(GlassRendering.refraction);
      expect(notified, 1);
      await f;
    });
  });

  group('the bar follows the spec', () {
    testWidgets('normal: the package default tier (refraction)', (tester) async {
      await tester.pumpWidget(_bar(amoled: false));
      await tester.pump();
      final bar = tester.widget<lgw.GlassTabBar>(find.byType(lgw.GlassTabBar));
      expect(bar.quality, isNull);
      expect(bar.indicatorPinchStrength, 0.45);
    });

    testWidgets('pure black: the standard tier, no pinch', (tester) async {
      await tester.pumpWidget(_bar(amoled: true));
      await tester.pump();
      final bar = tester.widget<lgw.GlassTabBar>(find.byType(lgw.GlassTabBar));
      expect(bar.quality, lgw.GlassQuality.standard);
      expect(bar.backgroundQuality, lgw.GlassQuality.standard);
      expect(bar.indicatorPinchStrength, 0);
    });

    testWidgets('pure black with Refraction chosen keeps the shader',
        (tester) async {
      await tester.pumpWidget(
          _bar(amoled: true, rendering: GlassRendering.refraction));
      await tester.pump();
      final bar = tester.widget<lgw.GlassTabBar>(find.byType(lgw.GlassTabBar));
      expect(bar.quality, isNull);
    });
  });

  group('the mini player lens follows the spec', () {
    final track = Track(
      id: 't1',
      trackName: 'Starboy',
      artistName: 'The Weeknd',
      albumName: 'Starboy',
      previewUrl: '',
    );

    testWidgets('pure black: lite glass, no refraction shader', (tester) async {
      await tester.pumpWidget(_bar(amoled: true, track: track));
      await tester.pumpAndSettle();
      final lens = tester
          .widget<LiquidGlassLens>(find.byKey(const ValueKey('mini_player_lens')));
      expect(lens.style.liteGlass, LiquidGlassLitePickup.blend);
    });

    testWidgets('normal: the refracting lens, as before', (tester) async {
      await tester.pumpWidget(_bar(amoled: false, track: track));
      await tester.pumpAndSettle();
      final lens = tester
          .widget<LiquidGlassLens>(find.byKey(const ValueKey('mini_player_lens')));
      expect(lens.style.liteGlass, isNull);
    });
  });
}
