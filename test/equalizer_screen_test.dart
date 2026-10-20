import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/screens/equalizer_screen.dart';
import 'package:music_streaming_app/services/eq/eq_models.dart';
import 'package:music_streaming_app/services/eq/eq_platform.dart';
import 'package:music_streaming_app/services/equalizer_service.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/eq/eq_graph.dart';
import 'package:music_streaming_app/widgets/liquid_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(EqualizerService, FakeEqPlatform)> pumpScreen(
  WidgetTester tester, {
  EqCapabilities? caps,
  Map<String, Object> prefs = const {},
}) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefs);
  final fake = caps == null ? FakeEqPlatform() : FakeEqPlatform(capabilities: caps);
  final svc = EqualizerService.test(platform: fake);
  await tester.runAsync(svc.initialize);

  await tester.pumpWidget(MaterialApp(
    theme: GlassTheme.build(AccentColors.peach),
    home: EqualizerScreen(service: svc),
  ));
  // Let the staggered entrance finish.
  await tester.pump(const Duration(milliseconds: 1300));
  return (svc, fake);
}

Offset nodePosition(WidgetTester tester, EqualizerService svc, int band) {
  final box = find.byType(EqGraph);
  final size = tester.getSize(box);
  final plot = eqPlotRect(size);
  final x = eqXForHz(svc.bands[band].centerHz, plot);
  final y = eqYForDb(svc.profile.gains[band], plot, svc.capabilities.minDb,
      svc.capabilities.maxDb);
  return tester.getTopLeft(box) + Offset(x, y);
}

Future<void> settle(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 80));

void main() {
  testWidgets('shows the instrument: title, capability line, graph, presets',
      (tester) async {
    await pumpScreen(tester);
    expect(find.text('Equalizer'), findsOneWidget);
    expect(find.textContaining('5 bands'), findsOneWidget);
    expect(find.byType(EqGraph), findsOneWidget);
    expect(find.bySemanticsLabel('Flat preset'), findsNothing,
        reason: 'semantics are off unless a test turns them on');
    expect(find.text('Flat'), findsOneWidget);
    expect(find.text('Bass Booster'), findsOneWidget);
    expect(find.text('PRESETS'), findsOneWidget);
    expect(find.text('SOUND SHAPING'), findsOneWidget);
    expect(find.text('Pre-amp'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('choosing a preset switches the equalizer on and applies it',
      (tester) async {
    final (svc, _) = await pumpScreen(tester);
    expect(svc.isEnabled, isFalse);

    await tester.tap(find.text('Bass Booster'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(svc.isEnabled, isTrue);
    expect(svc.currentPresetId, 'bass_boost');
    expect(find.text('Bass Booster'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('dragging a node changes that band and leaves the preset',
      (tester) async {
    final (svc, _) = await pumpScreen(tester);
    await svc.selectPreset('flat');
    await tester.pump();

    final start = nodePosition(tester, svc, 2);
    await tester.dragFrom(start, const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 100));

    expect(svc.profile.gains[2], greaterThan(0));
    expect(svc.profile.gains[0], 0);
    expect(svc.currentPresetId, 'custom');
    expect(svc.isEnabled, isTrue, reason: 'playing the curve switches it on');
    await settle(tester);
  });

  testWidgets('a vertical drag on the graph is not stolen by the page scroll',
      (tester) async {
    final (svc, _) = await pumpScreen(tester);
    final scroll = find.byType(CustomScrollView);
    final before = tester.state<ScrollableState>(find.descendant(
            of: scroll, matching: find.byType(Scrollable)).first)
        .position
        .pixels;
    final start = nodePosition(tester, svc, 1);
    await tester.dragFrom(start, const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 100));
    final after = tester.state<ScrollableState>(find.descendant(
            of: scroll, matching: find.byType(Scrollable)).first)
        .position
        .pixels;
    expect(after, before);
    expect(svc.profile.gains[1], lessThan(0));
    await settle(tester);
  });

  testWidgets('a node cannot be dragged past the device range', (tester) async {
    final (svc, _) = await pumpScreen(tester);
    final start = nodePosition(tester, svc, 0);
    await tester.dragFrom(start, const Offset(0, -1200));
    await tester.pump(const Duration(milliseconds: 100));
    expect(svc.profile.gains[0], 15);
    await settle(tester);
  });

  testWidgets('double-tapping a node zeroes it', (tester) async {
    final (svc, _) = await pumpScreen(tester);
    await svc.setBandGain(3, 6);
    await tester.pump(const Duration(milliseconds: 500));
    final at = nodePosition(tester, svc, 3);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 90));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 100));
    expect(svc.profile.gains[3], 0);
    await settle(tester);
  });

  testWidgets('the header switch turns it on and off', (tester) async {
    final (svc, _) = await pumpScreen(tester);
    await tester.tap(find.byType(LiquidSwitch).first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(svc.isEnabled, isTrue);
    await tester.tap(find.byType(LiquidSwitch).first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(svc.isEnabled, isFalse);
    await settle(tester);
  });

  testWidgets('hold to compare bypasses while held and restores on release',
      (tester) async {
    final (svc, _) = await pumpScreen(tester);
    await svc.setEnabled(true);
    await svc.selectPreset('bass_boost');
    await tester.pump();

    final g = await tester.startGesture(tester.getCenter(find.text('Hold to compare')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(svc.bypass, isTrue);
    expect(find.text('Hearing the original'), findsOneWidget);

    await g.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(svc.bypass, isFalse);
    expect(find.text('Hold to compare'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('leaving the screen never leaves the bypass held', (tester) async {
    final (svc, _) = await pumpScreen(tester);
    await svc.setEnabled(true);
    svc.setBypass(true);
    await tester.pumpWidget(const SizedBox());
    expect(svc.bypass, isFalse);
    await tester.pump(const Duration(milliseconds: 100)); // the debounced writes
  });

  testWidgets('saving a preset asks for a name and adds it to the strip',
      (tester) async {
    final (svc, _) = await pumpScreen(tester);
    await svc.selectPreset('rock');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Save preset'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Gym');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(svc.userPresets.single.name, 'Gym');
    expect(find.text('Gym'), findsWidgets);
    await settle(tester);
  });

  testWidgets('Save and Reset are disabled while the curve is flat',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Save preset'), findsNothing);
    await settle(tester);
  });

  testWidgets('reset returns to Flat', (tester) async {
    final (svc, _) = await pumpScreen(tester);
    await svc.selectPreset('rock');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Reset'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(svc.currentPresetId, 'flat');
    expect(svc.profile.gains.every((g) => g == 0), isTrue);
    await settle(tester);
  });

  testWidgets('sliders drive pre-amp, and unsupported effects say so',
      (tester) async {
    final (svc, _) = await pumpScreen(tester);
    final preamp = find.byType(Slider).first;
    await tester.drag(preamp, const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(svc.profile.preampDb, greaterThan(0));
    await settle(tester);
  });

  testWidgets('a phone without bass boost shows it as unsupported', (tester) async {
    await pumpScreen(
      tester,
      caps: const EqCapabilities(
        available: true,
        bands: EqBand.typicalFive,
        minDb: -15,
        maxDb: 15,
        bassBoost: false,
        virtualizer: true,
        loudness: true,
      ),
    );
    await tester.scrollUntilVisible(find.text('Not supported'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Not supported'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('a phone with no equalizer says so plainly instead of a dead switch',
      (tester) async {
    final (svc, fake) = await pumpScreen(tester, caps: EqCapabilities.unavailable);
    expect(find.text('No equalizer on this phone'), findsOneWidget);
    expect(find.text('Not available on this phone'), findsOneWidget);
    expect(svc.isEnabled, isFalse);

    // The switch is inert; nothing reaches the platform.
    await tester.tap(find.byType(LiquidSwitch).first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(svc.isEnabled, isFalse);
    expect(fake.syncs, isEmpty);
    await settle(tester);
  });

  testWidgets('separate settings per output reveals the three profiles',
      (tester) async {
    final (svc, _) = await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('Separate settings per output'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Bluetooth'), findsNothing);
    await tester.tap(find.text('Separate settings per output'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(svc.perOutput, isTrue);
    expect(find.text('Bluetooth'), findsOneWidget);
    expect(find.text('Speaker'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('a boost shows how much headroom is being paid back',
      (tester) async {
    final (svc, _) = await pumpScreen(tester);
    await svc.selectPreset('bass_boost');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(find.text('Prevent clipping'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Lowering everything by'), findsOneWidget);
    expect(svc.headroomDb, greaterThan(0));
    await settle(tester);
  });
}
