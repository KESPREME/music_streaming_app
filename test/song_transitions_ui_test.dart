import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/screens/song_transitions_screen.dart';
import 'package:music_streaming_app/services/transition/transition_engine.dart';
import 'package:music_streaming_app/services/transition/transition_settings.dart';
import 'package:music_streaming_app/widgets/liquid_switch.dart';
import 'package:music_streaming_app/widgets/mix_overlays.dart';
import 'package:music_streaming_app/widgets/thin_slider.dart';
import 'package:music_streaming_app/widgets/transition_chip.dart';
import 'package:music_streaming_app/widgets/transition_diagram.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// THE SCREENS THIS FILE PINS.
///
/// Song Transitions (the settings screen), the queue's chip, and what Now
/// Playing does while a mix runs. The motion rule is tested as a rule: every
/// visual is a function of the engine's progress, so it cannot drift from the
/// audio.

Future<TransitionSettings> _settings({
  bool enabled = false,
  TransitionStyle style = TransitionStyle.crossfade,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final s = TransitionSettings();
  await s.load();
  if (enabled) await s.setEnabled(true);
  await s.setStyle(style);
  return s;
}

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: child,
    );

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Track _track(String id) => Track(
      id: id,
      trackName: 'Song $id',
      artistName: 'Artist',
      albumName: 'Album',
      previewUrl: '',
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Song Transitions screen', () {
    testWidgets('transitions off: everything below the switch is asleep',
        (tester) async {
      await _tall(tester);
      final s = await _settings();
      await tester.pumpWidget(_app(SongTransitionsScreen(settings: s)));

      final style = find.text('AutoMix').first;
      await tester.tap(style, warnIfMissed: false);
      await tester.pump();
      expect(s.style, TransitionStyle.crossfade,
          reason: 'a dimmed control does not respond');

      await tester.tap(find.byType(LiquidSwitch).first);
      await tester.pump();
      expect(s.enabled, isTrue);
    });

    testWidgets('choosing AutoMix reveals its options and renames the length',
        (tester) async {
      await _tall(tester);
      final s = await _settings(enabled: true);
      await tester.pumpWidget(_app(SongTransitionsScreen(settings: s)));

      expect(find.text('Crossfade length'), findsOneWidget);
      expect(find.text('Match tempo'), findsNothing);

      await tester.tap(find.text('AutoMix').first);
      await tester.pump(const Duration(milliseconds: 400)); // the preview loops forever

      expect(s.style, TransitionStyle.automix);
      expect(find.text('Match tempo'), findsOneWidget);
      expect(find.text('Analyse on mobile data'), findsOneWidget);
      expect(find.text('Fallback length'), findsOneWidget,
          reason: 'in AutoMix the length is only a fallback');

      await tester.tap(find.text('Crossfade').first);
      await tester.pump(const Duration(milliseconds: 400)); // the preview loops forever
      expect(find.text('Match tempo'), findsNothing);
      expect(find.text('Crossfade length'), findsOneWidget);
    });

    testWidgets('the slider moves the length one whole second at a time',
        (tester) async {
      await _tall(tester);
      final s = await _settings(enabled: true);
      await tester.pumpWidget(_app(SongTransitionsScreen(settings: s)));
      expect(find.text('6 s'), findsOneWidget);

      await tester.drag(find.byType(ThinSlider), const Offset(2000, 0));
      await tester.pump(const Duration(milliseconds: 400)); // the preview loops forever
      expect(s.crossfadeSeconds, 12, reason: 'Apple Music\'s upper bound');
      expect(find.text('12 s'), findsWidgets);

      await tester.drag(find.byType(ThinSlider), const Offset(-4000, 0));
      await tester.pump(const Duration(milliseconds: 400)); // the preview loops forever
      expect(s.crossfadeSeconds, 1, reason: 'and its lower bound');
    });

    testWidgets('the independent options work with transitions off',
        (tester) async {
      await _tall(tester);
      final s = await _settings();
      await tester.pumpWidget(_app(SongTransitionsScreen(settings: s)));

      expect(s.sleepFade, isTrue);
      await tester.tap(find.text('Fade out for the sleep timer'));
      await tester.pump();
      expect(s.sleepFade, isFalse);

      expect(s.skipSilence, isFalse);
      await tester.tap(find.text('Skip silence'));
      await tester.pump();
      expect(s.skipSilence, isTrue);
    });

    testWidgets('album gapless is a visible, explained option', (tester) async {
      await _tall(tester);
      final s = await _settings(enabled: true);
      await tester.pumpWidget(_app(SongTransitionsScreen(settings: s)));
      expect(find.text('Transition between album tracks'), findsOneWidget);
      await tester.tap(find.text('Transition between album tracks'));
      await tester.pump();
      expect(s.crossfadeAlbums, isTrue);
    });

    test('the row summary names the state', () async {
      final s = await _settings();
      expect(SongTransitionsScreen.summary(s), 'Off');
      await s.setEnabled(true);
      expect(SongTransitionsScreen.summary(s), 'Crossfade · 6 s');
      await s.setStyle(TransitionStyle.automix);
      expect(SongTransitionsScreen.summary(s), 'AutoMix');
    });
  });

  group('the preview', () {
    testWidgets('sweeps only while transitions are on', (tester) async {
      Widget diagram(bool enabled) => _app(Scaffold(
            body: TransitionDiagram(
                seconds: 6, style: TransitionStyle.crossfade, enabled: enabled),
          ));

      await tester.pumpWidget(diagram(false));
      expect(tester.hasRunningAnimations, isFalse,
          reason: 'a screen at rest costs nothing');

      await tester.pumpWidget(diagram(true));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(diagram(false));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('respects reduced motion', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _app(const Scaffold(
          body: TransitionDiagram(
              seconds: 6, style: TransitionStyle.automix, enabled: true),
        )),
      ));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('the queue chip', () {
    test('steps Off -> Crossfade -> AutoMix -> Off', () async {
      final s = await _settings();
      var n = TransitionChip.next(s);
      expect((n.enabled, n.style), (true, TransitionStyle.crossfade));

      await s.setEnabled(true);
      n = TransitionChip.next(s);
      expect((n.enabled, n.style), (true, TransitionStyle.automix));

      await s.setStyle(TransitionStyle.automix);
      n = TransitionChip.next(s);
      expect(n.enabled, isFalse);
    });

    testWidgets('names its state and cycles on tap', (tester) async {
      final s = await _settings();
      await tester.pumpWidget(
          _app(Scaffold(body: Center(child: TransitionChip(settings: s)))));

      expect(find.text('Transitions'), findsOneWidget);
      await tester.tap(find.byType(TransitionChip));
      await tester.pumpAndSettle();
      expect(find.text('Crossfade · 6s'), findsOneWidget);
      await tester.tap(find.byType(TransitionChip));
      await tester.pumpAndSettle();
      expect(find.text('AutoMix'), findsOneWidget);
      await tester.tap(find.byType(TransitionChip));
      await tester.pumpAndSettle();
      expect(find.text('Transitions'), findsOneWidget);
      expect(s.enabled, isFalse);
    });

    testWidgets('a long press opens the full screen', (tester) async {
      await _tall(tester);
      final s = await _settings();
      await tester.pumpWidget(
          _app(Scaffold(body: Center(child: TransitionChip(settings: s)))));
      await tester.longPress(find.byType(TransitionChip));
      await tester.pumpAndSettle();
      expect(find.byType(SongTransitionsScreen), findsOneWidget);
    });
  });

  group('while a mix runs', () {
    final state = ValueNotifier<TransitionUiState>(TransitionUiState.idle);
    tearDown(() => state.value = TransitionUiState.idle);

    TransitionUiState fading(double p,
            {bool mix = false, bool handedOff = false}) =>
        TransitionUiState(
          phase: TransitionPhase.fading,
          progress: p,
          outgoingId: 'a',
          incomingId: 'b',
          isMix: mix,
          handedOff: handedOff,
        );

    double opacityOfArt(WidgetTester tester) =>
        tester.widget<Opacity>(find.descendant(
            of: find.byType(MixIncomingArt), matching: find.byType(Opacity))).opacity;

    Widget art() => _app(Scaffold(
          body: Stack(children: [
            MixIncomingArt(
              state: state,
              trackFor: (id) => id == 'b' ? _track('b') : null,
              buildArt: (t) => Text('art ${t.id}'),
            ),
          ]),
        ));

    test('the dissolve is finished at the handoff and never overshoots', () {
      expect(dissolveAt(0), 0);
      expect(dissolveAt(0.25), closeTo(0.5, 1e-9));
      expect(dissolveAt(0.5), 1);
      expect(dissolveAt(0.9), 1);
      expect(dissolveAt(1), 1);
      var prev = -1.0;
      for (var i = 0; i <= 100; i++) {
        final v = dissolveAt(i / 100);
        expect(v, greaterThanOrEqualTo(prev));
        prev = v;
      }
    });

    testWidgets('nothing shows when nothing is mixing', (tester) async {
      await tester.pumpWidget(art());
      expect(find.text('art b'), findsNothing);
    });

    testWidgets('the incoming art follows the audio\'s own progress',
        (tester) async {
      await tester.pumpWidget(art());
      state.value = fading(0.1);
      await tester.pump();
      expect(find.text('art b'), findsOneWidget);
      final early = opacityOfArt(tester);

      state.value = fading(0.3);
      await tester.pump();
      final later = opacityOfArt(tester);
      expect(later, greaterThan(early));

      state.value = fading(0.5);
      await tester.pump();
      expect(opacityOfArt(tester), 1.0);
    });

    testWidgets('it stays up after the handoff, covering the base layer',
        (tester) async {
      await tester.pumpWidget(art());
      state.value = fading(0.7, handedOff: true);
      await tester.pump();
      expect(find.text('art b'), findsOneWidget);
      expect(opacityOfArt(tester), 1.0);
    });

    testWidgets('and goes the moment the mix is over', (tester) async {
      await tester.pumpWidget(art());
      state.value = fading(0.7, handedOff: true);
      await tester.pump();
      state.value = TransitionUiState.idle;
      await tester.pump();
      expect(find.text('art b'), findsNothing);
    });

    testWidgets('a bailed mix removes it (no half-dissolved ghost)',
        (tester) async {
      await tester.pumpWidget(art());
      state.value = fading(0.2);
      await tester.pump();
      state.value = const TransitionUiState(
          phase: TransitionPhase.bailing, incomingId: 'b', progress: 0.2);
      await tester.pump();
      expect(find.text('art b'), findsNothing);
    });

    testWidgets('an unknown incoming track draws nothing, quietly',
        (tester) async {
      await tester.pumpWidget(_app(Scaffold(
        body: Stack(children: [
          MixIncomingArt(
              state: state, trackFor: (_) => null, buildArt: (t) => Text(t.id)),
        ]),
      )));
      state.value = fading(0.2);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the AutoMix badge appears for a real mix, not a plain fade',
        (tester) async {
      await tester.pumpWidget(
          _app(Scaffold(body: Center(child: MixBadge(state: state)))));
      expect(find.text('AutoMix'), findsNothing);

      state.value = fading(0.3, mix: false);
      await tester.pumpAndSettle();
      expect(find.text('AutoMix'), findsNothing,
          reason: 'a crossfade needs no announcement');

      state.value = fading(0.3, mix: true);
      await tester.pumpAndSettle();
      expect(find.text('AutoMix'), findsOneWidget);

      state.value = TransitionUiState.idle;
      await tester.pumpAndSettle();
      expect(find.text('AutoMix'), findsNothing);
    });
  });

  group('JumpSmoother', () {
    Widget host(double v, {bool enabled = true, required List<double> seen}) =>
        _app(JumpSmoother(
          value: v,
          enabled: enabled,
          builder: (context, s) {
            seen.add(s);
            return const SizedBox();
          },
        ));

    testWidgets('ordinary progress passes straight through', (tester) async {
      final seen = <double>[];
      await tester.pumpWidget(host(0.10, seen: seen));
      await tester.pumpWidget(host(0.11, seen: seen));
      await tester.pumpWidget(host(0.12, seen: seen));
      expect(seen.last, 0.12);
    });

    testWidgets('a jump glides rather than snaps', (tester) async {
      final seen = <double>[];
      await tester.pumpWidget(host(0.97, seen: seen));
      await tester.pumpWidget(host(0.03, seen: seen));
      expect(seen.last, greaterThan(0.5),
          reason: 'the first frame is still near where it was');

      await tester.pump(const Duration(milliseconds: 120));
      final mid = seen.last;
      expect(mid, inExclusiveRange(0.03, 0.97));

      await tester.pump(const Duration(milliseconds: 400));
      expect(seen.last, closeTo(0.03, 1e-6));
    });

    testWidgets('a drag is never smoothed: the finger is the animation',
        (tester) async {
      final seen = <double>[];
      await tester.pumpWidget(host(0.1, enabled: false, seen: seen));
      await tester.pumpWidget(host(0.9, enabled: false, seen: seen));
      expect(seen.last, 0.9);
    });

    testWidgets('reduced motion jumps', (tester) async {
      final seen = <double>[];
      Widget h(double v) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: host(v, seen: seen),
          );
      await tester.pumpWidget(h(0.97));
      await tester.pumpWidget(h(0.03));
      expect(seen.last, 0.03);
    });
  });
}
