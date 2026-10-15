import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:music_streaming_app/screens/song_transitions_screen.dart';
import 'package:music_streaming_app/services/transition/level_plan.dart';
import 'package:music_streaming_app/services/transition/transition_engine.dart';
import 'package:music_streaming_app/services/transition/transition_planner.dart';
import 'package:music_streaming_app/services/transition/transition_settings.dart';
import 'package:music_streaming_app/widgets/liquid_switch.dart';
import 'package:music_streaming_app/widgets/queue_transition_connector.dart';
import 'package:music_streaming_app/widgets/thin_slider.dart';
import 'package:music_streaming_app/widgets/track_swap.dart';
import 'package:music_streaming_app/widgets/transition_trace_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// THE PIECES THAT TELL THE LISTENER WHAT THE ENGINE IS DOING.
///
/// The scrubber's bracket, the queue's connector, the title exchange and the
/// "last transition" card. Each speaks only from what the engine has planned or
/// done (UpcomingMix, MixTrace), so most of what is tested is the wording and
/// the rule that nothing is shown that the engine has not decided.

Future<TransitionSettings> _settings({bool enabled = true}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final s = TransitionSettings();
  await s.load();
  await s.setEnabled(enabled);
  return s;
}

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(body: child),
    );

UpcomingMix _up({
  PlanKind kind = PlanKind.crossfade,
  String reason = 'crossfade',
  int start = 94000,
  int end = 100000,
  double rate = 1.0,
  bool analysed = false,
}) =>
    UpcomingMix(
      currentId: 'a',
      nextId: 'b',
      durationMs: 100000,
      kind: kind,
      reason: reason,
      startAtMs: start,
      endAtMs: end,
      incomingRate: rate,
      analysed: analysed,
    );

MixTrace _trace({
  PlanKind kind = PlanKind.beatmatched,
  LevelPlan level = LevelPlan.none,
  bool completed = true,
  double? first = 90,
  double? last = 6,
  double trim = 0.03,
  bool released = false,
  double rate = 1.0,
}) =>
    MixTrace(
      plan: TransitionPlan(
        kind: kind,
        reason: 'test',
        startAtMs: 92000,
        endAtMs: 98000,
        incomingRate: rate,
      ),
      level: level,
      fadeMs: 6000,
      startedLateMs: 12,
      completed: completed,
      ticks: 200,
      maxTickGapMs: 31,
      firstPhaseErrorMs: first,
      lastPhaseErrorMs: last,
      peakTrim: trim,
      phaseReleased: released,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the words for what is coming', () {
    final s = TransitionSettings();

    test('a plain crossfade says its length', () {
      final d = describeUpcoming(_up(), s)!;
      expect(d.label, 'Crossfade · 6 s');
      expect(d.detail, isNull);
    });

    test('an AutoMix mix says it is over the ending', () {
      final d = describeUpcoming(
          _up(kind: PlanKind.smart, reason: 'smart', start: 92000, end: 99000), s)!;
      expect(d.label, 'AutoMix · 7 s');
      expect(d.detail, contains('ending'));
    });

    test('a beat-matched mix says so, and says how much the tempo moves', () {
      final same = describeUpcoming(
          _up(kind: PlanKind.beatmatched, reason: 'beats-aligned'), s)!;
      expect(same.label, 'AutoMix · on the beat');
      expect(same.detail, contains('Same tempo'));

      final faster = describeUpcoming(
          _up(kind: PlanKind.beatmatched, reason: 'beats-matched', rate: 1.025), s)!;
      expect(faster.detail, contains('+2.5 %'));
      final slower = describeUpcoming(
          _up(kind: PlanKind.beatmatched, reason: 'beats-matched', rate: 0.97), s)!;
      expect(slower.detail, contains('−3.0 %'));
    });

    test('AutoMix that has not heard the songs yet says it is listening', () {
      final d = describeUpcoming(
          _up(reason: 'automix-fallback', analysed: false), s)!;
      expect(d.label, 'AutoMix · 6 s');
      expect(d.detail, contains('Listening'));
    });

    test('AutoMix that heard them and found nothing to go on says that', () {
      final d = describeUpcoming(
          _up(reason: 'automix-fallback', analysed: true), s)!;
      expect(d.detail, contains('plain fade'));
    });

    test('an album that stays gapless explains why nothing is blending', () {
      final d = describeUpcoming(
          _up(kind: PlanKind.none, reason: 'album-gapless'), s)!;
      expect(d.label, 'Gapless');
    });

    test('a song too short to mix has nothing to say', () {
      expect(describeUpcoming(_up(kind: PlanKind.none, reason: 'too-short'), s),
          isNull);
    });
  });

  group('the queue connector', () {
    testWidgets('shows nothing while transitions are off', (tester) async {
      final s = await _settings(enabled: false);
      final up = ValueNotifier<UpcomingMix?>(_up());
      await tester.pumpWidget(
          _app(QueueTransitionConnector(upcoming: up, settings: s)));
      expect(find.textContaining('Crossfade'), findsNothing);
    });

    testWidgets('names the transition and follows the engine', (tester) async {
      final s = await _settings();
      final up = ValueNotifier<UpcomingMix?>(null);
      await tester.pumpWidget(
          _app(QueueTransitionConnector(upcoming: up, settings: s)));
      expect(find.textContaining('Crossfade'), findsNothing,
          reason: 'nothing planned, nothing said');

      up.value = _up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Crossfade · 6 s'), findsOneWidget);

      up.value = _up(kind: PlanKind.beatmatched, reason: 'beats-aligned');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('AutoMix · on the beat'), findsOneWidget);
      expect(find.text('Crossfade · 6 s'), findsNothing);

      up.value = null;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('AutoMix'), findsNothing);
    });

    testWidgets('turning transitions off clears it at once', (tester) async {
      final s = await _settings();
      final up = ValueNotifier<UpcomingMix?>(_up());
      await tester.pumpWidget(
          _app(QueueTransitionConnector(upcoming: up, settings: s)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Crossfade · 6 s'), findsOneWidget);
      await s.setEnabled(false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Crossfade · 6 s'), findsNothing);
    });

    testWidgets('is read out as one sentence', (tester) async {
      final s = await _settings();
      final up = ValueNotifier<UpcomingMix?>(
          _up(kind: PlanKind.beatmatched, reason: 'beats-aligned'));
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
          _app(QueueTransitionConnector(upcoming: up, settings: s)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
          find.bySemanticsLabel(RegExp(r'Transition to the next song: AutoMix · on the beat')),
          findsOneWidget);
      handle.dispose();
    });
  });

  group('the title exchange', () {
    Widget swap(String id) => _app(Align(
          alignment: Alignment.topLeft,
          child: TrackTextSwap(identity: id, child: Text('Title of $id')),
        ));

    testWidgets('the old words leave and the new ones arrive', (tester) async {
      await tester.pumpWidget(swap('a'));
      expect(find.text('Title of a'), findsOneWidget);

      await tester.pumpWidget(swap('b'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Title of a'), findsOneWidget, reason: 'still leaving');
      expect(find.text('Title of b'), findsOneWidget, reason: 'already arriving');

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Title of a'), findsNothing);
      expect(find.text('Title of b'), findsOneWidget);
    });

    testWidgets('leaving is quicker than arriving', (tester) async {
      expect(TrackTextSwap.leave, lessThan(TrackTextSwap.enter));
      await tester.pumpWidget(swap('a'));
      await tester.pumpWidget(swap('b'));
      await tester.pump(TrackTextSwap.leave + const Duration(milliseconds: 20));
      expect(find.text('Title of a'), findsNothing);
      // ...while the new one is still on its way.
      final fade = tester.widget<FadeTransition>(
          find.ancestor(of: find.text('Title of b'), matching: find.byType(FadeTransition)).first);
      expect(fade.opacity.value, lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the same song redrawn is not an exchange', (tester) async {
      await tester.pumpWidget(swap('a'));
      await tester.pumpWidget(swap('a'));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Title of a'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with reduced motion the words just change', (tester) async {
      Widget reduced(String id) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: swap(id),
          );
      await tester.pumpWidget(reduced('a'));
      await tester.pumpWidget(reduced('b'));
      await tester.pump();
      expect(find.text('Title of a'), findsNothing);
      expect(find.text('Title of b'), findsOneWidget);
    });
  });

  group('the scrubber\'s bracket', () {
    testWidgets('a track with a mark builds and paints', (tester) async {
      await tester.pumpWidget(_app(SizedBox(
        width: 300,
        child: ThinSlider(
          value: 0.4,
          onValueChange: (_) {},
          marks: const [
            ThinSliderMark(from: 0.9, to: 0.96, color: Colors.teal, progress: 0.5),
          ],
        ),
      )));
      expect(tester.takeException(), isNull);
      expect(find.byType(ThinSlider), findsOneWidget);
    });

    test('marks compare by value, so an unchanged plan does not repaint', () {
      const a = ThinSliderMark(from: 0.9, to: 0.96, color: Colors.teal);
      const b = ThinSliderMark(from: 0.9, to: 0.96, color: Colors.teal);
      const c = ThinSliderMark(from: 0.9, to: 0.96, color: Colors.teal, progress: 0.1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(listEquals(<ThinSliderMark>[a], <ThinSliderMark>[b]), isTrue);
    });
  });

  group('the last-transition card', () {
    test('tells the plan, the levels, the timing and the beat', () {
      final lines = describeMix(_trace(
        level: const LevelPlan(incomingDb: -9.0, reason: 'x'),
        rate: 1.02,
      ));
      expect(lines.map((l) => l.label), ['Plan', 'Levels', 'Timing', 'Beat']);
      expect(lines[0].text, contains('AutoMix on the beat'));
      expect(lines[0].text, contains('6.0 s'));
      expect(lines[0].text, contains('+2.0 %'));
      expect(lines[1].text, contains('9.0 dB louder'));
      expect(lines[2].text, contains('12 ms'));
      expect(lines[2].text, contains('31 ms'));
      expect(lines[3].text, contains('90 ms'));
      expect(lines[3].text, contains('6 ms'));
      expect(lines[3].text, contains('3.0 %'));
    });

    test('a quieter incoming song is described from the other side', () {
      final lines = describeMix(_trace(
        kind: PlanKind.crossfade,
        level: const LevelPlan(outgoingDb: -7.5, reason: 'x'),
        first: null,
        last: null,
        trim: 0,
      ));
      expect(lines.map((l) => l.label), ['Plan', 'Levels', 'Timing'],
          reason: 'no beat line without a beat lock');
      expect(lines[1].text, contains('7.5 dB quieter'));
      expect(lines[1].text, contains('brought down'));
    });

    test('matched loudness, an interrupted mix and a lock that gave up say so', () {
      final lines = describeMix(_trace(
        completed: false,
        released: true,
        first: 400,
        last: 400,
      ));
      expect(lines[0].text, contains('interrupted'));
      expect(lines[1].text, contains('already close'));
      expect(lines[3].text, contains('too far to correct'));
    });

    testWidgets('is absent until there has been a transition', (tester) async {
      final n = ValueNotifier<MixTrace?>(null);
      await tester.pumpWidget(_app(TransitionTraceCard(trace: n)));
      expect(find.text('Last transition'), findsNothing);
      n.value = _trace();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Last transition'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
    });

    testWidgets('a tap copies the raw trace for sending along', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final n = ValueNotifier<MixTrace?>(_trace());
      await tester.pumpWidget(_app(TransitionTraceCard(trace: n)));
      await tester.tap(find.text('Last transition'));
      await tester.pump();
      expect(copied, startsWith('MIX_TRACE beatmatched'));
      expect(find.text('Copied'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1700));
      expect(find.text('Tap to copy'), findsOneWidget);
    });
  });

  group('the settings screen after this change', () {
    Future<void> tall(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('balancing loudness is a switch, on by default, for either style',
        (tester) async {
      await tall(tester);
      final s = await _settings();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: SongTransitionsScreen(settings: s, trace: ValueNotifier<MixTrace?>(null)),
      ));
      expect(s.levelMatching, isTrue);
      expect(find.text('Balance loudness'), findsOneWidget);
      expect(find.text('Analyse on mobile data'), findsOneWidget,
          reason: 'balancing reads the songs too, so this is not AutoMix-only');
      expect(find.text('Match tempo'), findsNothing, reason: 'that one is AutoMix-only');

      final row = find.ancestor(
          of: find.text('Balance loudness'), matching: find.byType(InkWell));
      expect(row, findsWidgets);
      await tester.tap(find.byType(LiquidSwitch).at(1));
      await tester.pump(const Duration(milliseconds: 400));
      expect(s.levelMatching, isFalse);
    });

    testWidgets('the last transition appears at the bottom once there is one',
        (tester) async {
      await tall(tester);
      final s = await _settings();
      final n = ValueNotifier<MixTrace?>(null);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: SongTransitionsScreen(settings: s, trace: n),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Last transition'), findsNothing);
      n.value = _trace();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Last transition'), findsOneWidget);
    });
  });
}
