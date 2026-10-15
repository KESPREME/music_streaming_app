import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/transition/transition_engine.dart';
import 'package:music_streaming_app/services/transition/transition_planner.dart';
import 'package:music_streaming_app/widgets/seek_zone.dart';
import 'package:music_streaming_app/widgets/thin_slider.dart';

/// THE TRANSITION INSIDE THE SEEK BAR.
///
/// Three things are pinned: WHICH zone is drawn (only what the engine planned
/// for this song), WHEN it animates (a sweep in, a run while mixing, a quick
/// dissolve out, none of it with reduced motion), and WHAT it looks like - read
/// back from real rendered pixels, because "the fill is dyed across the zone"
/// is a claim about colour and a test can check a colour.

const Color accent = Color(0xFFFF4F7B);

UpcomingMix up({
  PlanKind kind = PlanKind.smart,
  int start = 90000,
  int end = 96500,
  int duration = 100000,
}) =>
    UpcomingMix(
      currentId: 'a',
      nextId: 'b',
      durationMs: duration,
      kind: kind,
      reason: 'test',
      startAtMs: start,
      endAtMs: end,
    );

void main() {
  group('which zone', () {
    test('is the stretch the engine planned, as fractions of the bar', () {
      final z = seekZoneFor(up(), 100000, mixColor: accent)!;
      expect(z.from, closeTo(0.90, 1e-9));
      expect(z.to, closeTo(0.965, 1e-9));
      expect(z.mix, isTrue);
      expect(z.color, accent);
      expect(z.label, 'AutoMix begins at 1:30');
    });

    test('a plain crossfade is not a mix, and says so', () {
      final z = seekZoneFor(up(kind: PlanKind.crossfade), 100000, mixColor: accent)!;
      expect(z.mix, isFalse);
      expect(z.label, 'Crossfade begins at 1:30');
    });

    test('a beat-matched mix is a mix', () {
      expect(
          seekZoneFor(up(kind: PlanKind.beatmatched), 100000, mixColor: accent)!.mix,
          isTrue);
    });

    test('nothing planned, nothing drawn', () {
      expect(seekZoneFor(null, 100000, mixColor: accent), isNull);
      expect(seekZoneFor(up(kind: PlanKind.none), 100000, mixColor: accent), isNull);
      expect(seekZoneFor(up(), 0, mixColor: accent), isNull);
    });

    test('a plan made for another song, or another cut of it, stays off this bar', () {
      expect(seekZoneFor(up(duration: 100000), 131000, mixColor: accent), isNull);
      expect(seekZoneFor(up(duration: 100000), 100900, mixColor: accent), isNotNull,
          reason: 'renditions differ by a second or so');
    });

    test('a zone off the end of the bar is clamped, an empty one dropped', () {
      final z = seekZoneFor(up(start: 95000, end: 120000), 100000, mixColor: accent)!;
      expect(z.to, 1.0);
      expect(seekZoneFor(up(start: 100000, end: 100000), 100000, mixColor: accent), isNull);
    });
  });

  group('where it sits', () {
    const z = SeekZone(from: 0.90, to: 0.965, color: accent, mix: true);
    const track = Rect.fromLTWH(0, 10, 300, 7);

    test('on the bar, swept in from its start', () {
      final full = SeekZonePaint.geometry(track, z, 1.0);
      expect(full.x1, closeTo(270, 1e-9));
      expect(full.x2, closeTo(289.5, 1e-9));
      expect(full.xr, closeTo(289.5, 1e-9));
      final half = SeekZonePaint.geometry(track, z, 0.5);
      expect(half.xr, closeTo(279.75, 1e-9));
      expect(SeekZonePaint.geometry(track, z, 0.0).xr, 270);
    });

    test('a very short transition is widened so it can be seen, ending where it ends',
        () {
      const tiny = SeekZone(from: 0.99, to: 0.995, color: accent, mix: true);
      final g = SeekZonePaint.geometry(track, tiny, 1.0);
      expect(g.x2 - g.x1, SeekZonePaint.minWidth);
      expect(g.x2, closeTo(298.5, 1e-9));
    });

    test('and kept on the bar at the start of a very short song', () {
      const early = SeekZone(from: 0.0, to: 0.01, color: accent, mix: true);
      final g = SeekZonePaint.geometry(track, early, 1.0);
      expect(g.x1, 0);
      expect(g.x2, SeekZonePaint.minWidth);
    });
  });

  group('when it moves', () {
    Future<
        ({
          ValueNotifier<UpcomingMix?> upcoming,
          ValueNotifier<TransitionUiState> ui,
          List<SeekZoneFrame> frames,
        })> mount(WidgetTester tester, {bool reduce = false}) async {
      final upcoming = ValueNotifier<UpcomingMix?>(null);
      final ui = ValueNotifier<TransitionUiState>(TransitionUiState.idle);
      final frames = <SeekZoneFrame>[];
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SeekZoneHost(
            upcoming: upcoming,
            ui: ui,
            totalMs: 100000,
            mixColor: accent,
            builder: (context, frame) {
              frames.add(frame);
              return const SizedBox();
            },
          ),
        ),
      ));
      return (upcoming: upcoming, ui: ui, frames: frames);
    }

    testWidgets('a song that opens with a plan already made draws it from the first frame',
        (tester) async {
      final upcoming = ValueNotifier<UpcomingMix?>(up());
      final ui = ValueNotifier<TransitionUiState>(TransitionUiState.idle);
      SeekZoneFrame? seen;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: SeekZoneHost(
          upcoming: upcoming,
          ui: ui,
          totalMs: 100000,
          mixColor: accent,
          builder: (context, frame) {
            seen = frame;
            return const SizedBox();
          },
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(seen!.zone, isNotNull);
      await tester.pump(const Duration(milliseconds: 600));
      expect(seen!.reveal.value, 1.0);
    });
    testWidgets('nothing is drawn until the engine plans something', (tester) async {
      final m = await mount(tester);
      expect(m.frames.last.zone, isNull);
      expect(m.frames.last.reveal.value, 0.0);
      expect(m.frames.last.live.value, 0.0);
    });

    testWidgets('a plan sweeps the zone in; withdrawing it dissolves it, faster',
        (tester) async {
      final m = await mount(tester);
      m.upcoming.value = up();
      await tester.pump();
      expect(m.frames.last.zone, isNotNull);
      await tester.pump(const Duration(milliseconds: 200));
      final mid = m.frames.last.reveal.value;
      expect(mid, inExclusiveRange(0.0, 1.0), reason: 'part-way: a sweep, not a pop');
      await tester.pump(const Duration(milliseconds: 400));
      expect(m.frames.last.reveal.value, 1.0);

      m.upcoming.value = null;
      await tester.pump();
      expect(m.frames.last.zone, isNotNull, reason: 'still there, dissolving');
      await tester.pump(const Duration(milliseconds: 120));
      expect(m.frames.last.reveal.value, lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 200)); // leaving is quicker (240 ms)
      expect(m.frames.last.reveal.value, 0.0);
      expect(m.frames.last.zone, isNull, reason: 'and gone once it has');
    });

    testWidgets('it sweeps in with a deceleration, not linearly', (tester) async {
      final m = await mount(tester);
      m.upcoming.value = up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130)); // a quarter of 520 ms
      expect(m.frames.last.reveal.value, greaterThan(0.25),
          reason: 'ease-out: more than its share of the way early on');
    });

    testWidgets('a running mix goes live and flows; when it ends they stop',
        (tester) async {
      final m = await mount(tester);
      m.upcoming.value = up();
      await tester.pump(const Duration(milliseconds: 600));
      expect(m.frames.last.live.value, 0.0);

      m.ui.value = const TransitionUiState(
          phase: TransitionPhase.fading, progress: 0.2, incomingId: 'b', isMix: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(m.frames.last.live.value, 1.0);
      final a = m.frames.last.flow.value;
      await tester.pump(const Duration(milliseconds: 400));
      expect(m.frames.last.flow.value, isNot(a), reason: 'the hatching flows');

      // The session moves to the incoming song: the plan is withdrawn and the
      // mix is past its midpoint.
      m.ui.value = const TransitionUiState(
          phase: TransitionPhase.fading,
          progress: 0.6,
          incomingId: 'b',
          isMix: true,
          handedOff: true);
      m.upcoming.value = null;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(m.frames.last.live.value, 0.0);
      final b = m.frames.last.flow.value;
      await tester.pump(const Duration(milliseconds: 400));
      expect(m.frames.last.flow.value, b, reason: 'it has stopped flowing');
    });

    testWidgets('while nothing is planned, a fading engine does not make it live',
        (tester) async {
      final m = await mount(tester);
      m.ui.value = const TransitionUiState(
          phase: TransitionPhase.fading, progress: 0.2, incomingId: 'b');
      await tester.pump(const Duration(milliseconds: 600));
      expect(m.frames.last.live.value, 0.0);
    });

    testWidgets('with reduced motion the zone is simply there and nothing flows',
        (tester) async {
      final m = await mount(tester, reduce: true);
      m.upcoming.value = up();
      await tester.pump();
      expect(m.frames.last.reveal.value, 1.0, reason: 'no sweep');
      m.ui.value = const TransitionUiState(
          phase: TransitionPhase.fading, progress: 0.2, incomingId: 'b', isMix: true);
      await tester.pump();
      expect(m.frames.last.live.value, 1.0);
      final a = m.frames.last.flow.value;
      await tester.pump(const Duration(milliseconds: 500));
      expect(m.frames.last.flow.value, a, reason: 'and the hatching holds still');
      m.upcoming.value = null;
      await tester.pump();
      expect(m.frames.last.zone, isNull, reason: 'withdrawn at once');
    });

    testWidgets('a mix running does not rebuild the bar on every step',
        (tester) async {
      final m = await mount(tester);
      m.upcoming.value = up();
      await tester.pump(const Duration(milliseconds: 600));
      m.ui.value = const TransitionUiState(
          phase: TransitionPhase.fading, progress: 0.1, incomingId: 'b', isMix: true);
      await tester.pump();
      final builds = m.frames.length;
      for (var i = 2; i < 12; i++) {
        m.ui.value = TransitionUiState(
            phase: TransitionPhase.fading,
            progress: i / 20,
            incomingId: 'b',
            isMix: true);
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(m.frames.length - builds, lessThanOrEqualTo(2),
          reason: 'ten progress ticks, (almost) no rebuilds: painters repaint themselves');
    });

    testWidgets('a new song replaces the zone', (tester) async {
      final m = await mount(tester);
      m.upcoming.value = up();
      await tester.pump(const Duration(milliseconds: 600));
      m.upcoming.value = up(start: 80000, end: 90000);
      await tester.pump();
      expect(m.frames.last.zone!.from, closeTo(0.8, 1e-9));
    });
  });

  group('what it looks like', () {
    const width = 300.0;

    Future<ByteData> render(WidgetTester tester, double value, SeekZoneFrame frame,
        {double height = 7}) async {
      final key = GlobalKey();
      tester.view.physicalSize = const Size(width, 36);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFF1B1B1F),
            child: ThinSlider(
              value: value,
              onValueChange: (_) {},
              idleHeight: height,
              activeHeight: height,
              inactiveColor: Colors.white.withValues(alpha: 0.24),
              zone: frame,
            ),
          ),
        ),
      ));
      await tester.pump();
      late ByteData data;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });
      return data;
    }

    ({int r, int g, int b}) px(ByteData d, int x, [int y = 18]) {
      final i = (y * width.toInt() + x) * 4;
      return (r: d.getUint8(i), g: d.getUint8(i + 1), b: d.getUint8(i + 2));
    }

    SeekZoneFrame still(SeekZone? z, {double reveal = 1, double live = 0, double flow = 0}) =>
        SeekZoneFrame(
          zone: z,
          reveal: AlwaysStoppedAnimation<double>(reveal),
          live: AlwaysStoppedAnimation<double>(live),
          flow: AlwaysStoppedAnimation<double>(flow),
        );

    const mix = SeekZone(from: 0.90, to: 0.965, color: accent, mix: true);
    const fade = SeekZone(from: 0.90, to: 0.965, color: Colors.white, mix: false);

    testWidgets('an AutoMix zone is the accent colour, the rest of the bar is not',
        (tester) async {
      final d = await render(tester, 0.4, still(mix));
      final inside = px(d, 285);
      final outside = px(d, 250);
      expect(inside.r - inside.g, greaterThan(25), reason: 'pinkish');
      expect((outside.r - outside.g).abs(), lessThan(4), reason: 'plain track');
    });

    testWidgets('it is gone with no zone, and not there before it has swept in',
        (tester) async {
      final none = await render(tester, 0.4, still(null));
      expect(px(none, 285), px(none, 250));
      final unswept = await render(tester, 0.4, still(mix, reveal: 0));
      expect(px(unswept, 285), px(unswept, 250));
    });

    testWidgets('a crossfade zone is a veil, not the accent', (tester) async {
      final d = await render(tester, 0.4, still(fade));
      final inside = px(d, 285);
      final outside = px(d, 250);
      expect((inside.r - inside.g).abs(), lessThan(4), reason: 'no colour');
      expect(inside.r, greaterThan(outside.r), reason: 'but lighter');
    });

    testWidgets('the played fill is dyed toward the accent as it crosses the zone',
        (tester) async {
      final d = await render(tester, 0.985, still(mix));
      final before = px(d, 100);
      expect(before, (r: 255, g: 255, b: 255), reason: 'white until the zone');
      final early = px(d, 273);
      final late = px(d, 287);
      expect(early.g, lessThan(255));
      expect(late.g, lessThan(early.g), reason: 'and more so the deeper it goes');
      expect(late.r - late.g, greaterThan(60));
    });

    testWidgets('across a crossfade the played fill thins out instead', (tester) async {
      final d = await render(tester, 0.985, still(fade));
      final before = px(d, 100);
      final late = px(d, 287);
      expect(before.r, 255);
      expect(late.r, lessThan(before.r - 40), reason: 'this song leaving');
      expect((late.r - late.g).abs(), lessThan(4), reason: 'and never coloured');
    });

    testWidgets('a mix that is running is brighter than one that is only planned',
        (tester) async {
      final planned = px(await render(tester, 0.4, still(mix)), 285);
      final live = px(await render(tester, 0.4, still(mix, live: 1)), 285);
      expect(live.r - live.g, greaterThan(planned.r - planned.g));
    });

    testWidgets('the hatching moves with the flow phase', (tester) async {
      final a = await render(tester, 0.4, still(mix, live: 1, flow: 0.0));
      final b = await render(tester, 0.4, still(mix, live: 1, flow: 0.5));
      var differs = false;
      for (var x = 276; x < 289; x++) {
        if (px(a, x) != px(b, x)) differs = true;
      }
      expect(differs, isTrue);
    });

    testWidgets('the screen reader is told where the transition begins', (tester) async {
      final handle = tester.ensureSemantics();
      await render(tester, 0.4, still(mix.copyWithLabel('AutoMix begins at 3:52')));
      expect(find.bySemanticsLabel(RegExp('.*')).evaluate().isNotEmpty, isTrue);
      expect(
          tester.getSemantics(find.byType(ThinSlider)).hint, 'AutoMix begins at 3:52');
      handle.dispose();
    });
  });
}

extension on SeekZone {
  SeekZone copyWithLabel(String label) =>
      SeekZone(from: from, to: to, color: color, mix: mix, label: label);
}
