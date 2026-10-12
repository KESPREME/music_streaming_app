import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/lyrics_screen.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_line_style.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_stagger.dart';

/// THE FAN-OUT THIS FILE PINS.
///
/// As the panel scrolls to a new line the rows below it set off a beat after it
/// (BitChord `PlayerLyrics.kt:359-366, 1801-1868`). Three properties matter and
/// each one has a way to be quietly wrong:
///
///  * It must be PAINT-time. A layout-time shift re-lays-out the list on every
///    frame of every handover.
///  * It must settle to EXACTLY zero. Evaluated at the end of the curve, a
///    millionth of a pixel is a row that drifts off its slot over a song.
///  * It must belong to OUR scroll. A finger on the list owns it, and a row
///    pulled around under a finger is the panel fighting the reader.

const _ease = LyricLineStyle.lyricEase;

double _shift({
  required double delta,
  required int behind,
  required double at,
  double d = 400,
}) =>
    lyricStaggerShift(
      delta: delta,
      rowsBehind: behind,
      elapsedMs: at,
      durationMs: d,
    );

class _Provider extends MusicProvider {
  _Provider(this.lines);

  final List<LyricsEntry> lines;

  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _seeks =
      StreamController<Duration>.broadcast();
  Duration _position = const Duration(seconds: 30);

  @override
  Track? get currentTrack => Track(
        id: 'track1234567',
        trackName: 'My Old Ways',
        artistName: 'Tame Impala',
        albumName: 'Currents',
        previewUrl: '',
      );

  @override
  Duration get duration => const Duration(minutes: 5);

  @override
  Duration get position => _position;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration> get seekEvents => _seeks.stream;

  @override
  bool get isPlaying => false;

  @override
  bool get isLoadingLyrics => false;

  @override
  List<LyricsEntry>? get currentLyrics => lines;

  @override
  bool get hasSyncedLyrics => true;

  void seek(Duration to) {
    _position = to;
    _seeks.add(to);
    _positions.add(to);
  }

  void closeStreams() {
    _positions.close();
    _seeks.close();
  }

  @override
  void dispose() {
    closeStreams();
    super.dispose();
  }
}

/// Twelve lines, four seconds apart, each word-timed.
List<LyricsEntry> _lyric() => [
      for (var i = 0; i < 12; i++)
        LyricsEntry(
          timeMs: i * 4000,
          endMs: i * 4000 + 3000,
          text: 'line ${i + 1} here',
          words: [
            WordTiming(timeMs: i * 4000, durationMs: 900, text: 'line'),
            WordTiming(
                timeMs: i * 4000 + 900, durationMs: 900, text: '${i + 1}'),
            WordTiming(timeMs: i * 4000 + 1800, durationMs: 900, text: 'here'),
          ],
        ),
    ];

Widget _screen(_Provider provider, {bool reduceMotion = false}) =>
    ChangeNotifierProvider<MusicProvider>.value(
      value: provider,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: const Scaffold(
          body: LyricsScreen(
            isEmbedded: true,
            showHeader: false,
            showBottomScrubber: false,
          ),
        ),
      ),
    );

/// Every row's shift as it will be PAINTED, by lyric index.
///
/// Read off the render objects: what reaches the screen is the thing to pin, not
/// the function that is supposed to produce it.
Map<int, double> _shifts(WidgetTester tester) => {
      for (final box
          in tester.allRenderObjects.whereType<RenderLyricStaggerShift>())
        box.index: box.shift,
    };

ScrollController _controller(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the arithmetic', () {
    test('the focus row and everything the list is leaving never move', () {
      for (final at in <double>[0, 50, 200, 400, 700]) {
        expect(_shift(delta: 100, behind: 0, at: at), 0.0);
        expect(_shift(delta: 100, behind: -3, at: at), 0.0);
      }
    });

    test('it is the plan\'s formula: delta * (E(t/d) - E((t - 0.06*k*d)/d))',
        () {
      // Restated from the plan text, not from the implementation.
      double expected(double delta, int k, double t, double d) =>
          delta *
          (_ease.transform((t / d).clamp(0.0, 1.0)) -
              _ease.transform(((t - 0.06 * k * d) / d).clamp(0.0, 1.0)));

      for (final k in [1, 2, 3]) {
        for (final t in [40.0, 120.0, 230.0, 380.0, 450.0]) {
          expect(
            _shift(delta: 120, behind: k, at: t, d: 420),
            closeTo(expected(120, k, t, 420), 1e-9),
            reason: 'k=$k t=$t',
          );
        }
      }
    });

    test('a row is held back behind the list, never ahead of it', () {
      // Forward travel: a lagging row is LOWER than the list put it, so the
      // shift is positive. Backward travel mirrors it.
      for (var t = 10.0; t < 470; t += 10) {
        expect(_shift(delta: 120, behind: 2, at: t), greaterThanOrEqualTo(0));
        expect(_shift(delta: -120, behind: 2, at: t), lessThanOrEqualTo(0));
      }
    });

    test('it fans OUT: a row further behind is never nearer the list', () {
      // The property that makes clamping, rather than skipping, the right call:
      // the delay is non-decreasing in k, so neighbours are only ever pulled
      // apart and can never run into each other.
      for (var t = 0.0; t <= 480; t += 8) {
        var previous = 0.0;
        for (var k = 0; k <= 8; k++) {
          final shift = _shift(delta: 140, behind: k, at: t);
          expect(shift, greaterThanOrEqualTo(previous - 1e-9),
              reason: 'k=$k at ${t}ms');
          previous = shift;
        }
      }
    });

    test('rows past the third share the third\'s delay', () {
      for (final t in [60.0, 160.0, 300.0]) {
        final third = _shift(delta: 100, behind: 3, at: t);
        expect(_shift(delta: 100, behind: 4, at: t), third);
        expect(_shift(delta: 100, behind: 40, at: t), third);
      }
    });

    test('a row never moves backwards on screen', () {
      // Where a row is drawn is the list's position minus its shift, which is the
      // list's position `k` steps ago. That must advance monotonically, or a row
      // would reverse mid-handover.
      for (final k in [1, 2, 3]) {
        var previous = double.negativeInfinity;
        for (var t = 0.0; t <= 480; t += 4) {
          final list = 120 * _ease.transform((t / 400).clamp(0.0, 1.0));
          final drawn = list - _shift(delta: 120, behind: k, at: t);
          expect(drawn, greaterThanOrEqualTo(previous - 1e-9),
              reason: 'k=$k at ${t}ms');
          previous = drawn;
        }
      }
    });

    test('it starts at zero and settles to EXACTLY zero', () {
      for (final k in [1, 2, 3, 9]) {
        expect(_shift(delta: 120, behind: k, at: 0), 0.0);
        // The last row arrives at 1.18 * d.
        final span = 400 * 1.18;
        expect(_shift(delta: 120, behind: k, at: span), 0.0);
        expect(_shift(delta: 120, behind: k, at: span + 1), 0.0);
        expect(_shift(delta: 120, behind: k, at: 9999), 0.0);
        // Not merely small: a residual would be a row off its slot for good.
        expect(_shift(delta: 120, behind: k, at: span - 0.0001).abs(),
            lessThan(0.01));
      }
    });

    test('a row never travels further than the list does', () {
      for (var t = 0.0; t <= 480; t += 4) {
        expect(
            _shift(delta: 120, behind: 3, at: t).abs(), lessThanOrEqualTo(120));
      }
    });
  });

  group('the run', () {
    testWidgets('settles to exactly zero and drops the run', (tester) async {
      late LyricStagger stagger;
      await tester.pumpWidget(
        _Host(onReady: (s) => stagger = s),
      );

      stagger.start(
        const LyricScrollRun(focusIndex: 2, delta: 100, durationMs: 400),
      );
      expect(stagger.isRunning, isTrue);

      await tester.pump(); // first tick: elapsed 0
      await tester.pump(const Duration(milliseconds: 150));
      expect(stagger.shiftFor(4), greaterThan(1.0),
          reason: 'mid-handover the rows below the focus are held back');
      expect(stagger.shiftFor(2), 0.0,
          reason: 'the focus row travels with the list');
      expect(stagger.shiftFor(0), 0.0, reason: 'so does everything above it');

      await tester.pump(const Duration(milliseconds: 600));
      expect(stagger.isRunning, isFalse);
      for (var i = 0; i < 10; i++) {
        expect(stagger.shiftFor(i), 0.0, reason: 'row $i');
      }
    });

    testWidgets('cancel puts every row back at once', (tester) async {
      late LyricStagger stagger;
      await tester.pumpWidget(_Host(onReady: (s) => stagger = s));

      stagger.start(
        const LyricScrollRun(focusIndex: 0, delta: 100, durationMs: 400),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(stagger.shiftFor(3), greaterThan(1.0));

      stagger.cancel();
      expect(stagger.shiftFor(3), 0.0);
      expect(stagger.isRunning, isFalse);

      // And nothing wakes it up again.
      await tester.pump(const Duration(milliseconds: 600));
      expect(stagger.shiftFor(3), 0.0);
    });

    testWidgets('a newer run replaces the one in flight', (tester) async {
      late LyricStagger stagger;
      await tester.pumpWidget(_Host(onReady: (s) => stagger = s));

      stagger.start(
        const LyricScrollRun(focusIndex: 0, delta: 100, durationMs: 400),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      const next = LyricScrollRun(focusIndex: 5, delta: 90, durationMs: 350);
      stagger.start(next);
      expect(identical(stagger.run, next), isTrue);
      expect(stagger.elapsedMs, 0.0,
          reason: 'the new run starts from its start');
      expect(stagger.shiftFor(8), 0.0);
    });
  });

  group('the row', () {
    testWidgets('is hit-tested and measured where it is DRAWN', (tester) async {
      // A shift painted but not reported would leave a tap landing where the row
      // WAS, and the panel's own measuring (`localToGlobal` in the top-anchor
      // maths) reading a row that is not where it is drawn.
      late LyricStagger stagger;
      Offset? localTap;
      await tester.pumpWidget(
        _Host(
          onReady: (s) => stagger = s,
          builder: (stagger) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 80,
              child: LyricStaggerShift(
                stagger: stagger,
                index: 3,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => localTap = d.localPosition,
                  child: const SizedBox.expand(key: Key('row')),
                ),
              ),
            ),
          ),
        ),
      );

      final slot = tester.getTopLeft(find.byKey(const Key('row')));
      stagger.start(
        const LyricScrollRun(focusIndex: 0, delta: 100, durationMs: 400),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final shift = stagger.shiftFor(3);
      expect(shift, greaterThan(5), reason: 'the row is held back');
      expect(tester.getTopLeft(find.byKey(const Key('row'))).dy,
          closeTo(slot.dy + shift, 0.001),
          reason: 'localToGlobal reports the painted position');

      // A tap on the row where it is drawn lands that far into the row.
      await tester.tapAt(Offset(100, slot.dy + shift + 10));
      expect(localTap, isNotNull);
      expect(localTap!.dy, closeTo(10, 0.001),
          reason: 'the pointer is translated into the shifted row');

      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.getTopLeft(find.byKey(const Key('row'))).dy, slot.dy,
          reason: 'and it is back in its slot, exactly');
    });
  });
  group('on the real panel', () {
    testWidgets('a line handover fans the rows out, then settles to zero',
        (tester) async {
      final provider = _Provider(_lyric());
      addTearDown(provider.closeStreams);
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

      expect(_shifts(tester).values.every((s) => s == 0.0), isTrue,
          reason: 'at rest nothing is held back');
      final restOffset = _controller(tester).offset;

      provider.seek(const Duration(milliseconds: 34500));

      var peak = 0.0;
      var peakIndex = -1;
      var frames = 0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
        final shifts = _shifts(tester);
        final byIndex = shifts.keys.toList()..sort();
        var previous = 0.0;
        for (final index in byIndex) {
          final shift = shifts[index]!;
          expect(shift, greaterThanOrEqualTo(previous - 1e-6),
              reason: 'frame $i: row $index is nearer the list than row '
                  '${index - 1}; rows must fan out, never close up');
          previous = shift;
          if (shift > peak) {
            peak = shift;
            peakIndex = index;
          }
        }
      }
      expect(frames, 60);
      expect(peak, greaterThan(2.0),
          reason: 'the list moved a line and the rows below it must have '
              'lagged it (peak $peak on row $peakIndex)');
      expect(_controller(tester).offset, greaterThan(restOffset),
          reason: 'the list itself did scroll forward');

      // Settled: EXACTLY zero, and the list has stopped.
      for (final entry in _shifts(tester).entries) {
        expect(entry.value, 0.0, reason: 'row ${entry.key} drifted');
      }
      final landed = _controller(tester).offset;
      await tester.pump(const Duration(milliseconds: 400));
      expect(_controller(tester).offset, landed);
    });

    testWidgets('the follow GLIDES to the next line instead of hard-cutting it',
        (tester) async {
      // THE BUG THE FAN-OUT EXPOSED. `_scrollRunUp` answered Duration.zero
      // whenever the lead line was already on screen, and zero means `jumpTo`.
      // At a line change the lead line IS the line just entered, so it is always
      // on screen: every handover hard-cut one whole line in a single frame and
      // there was never a scroll to fan out from.
      final provider = _Provider(_lyric());
      addTearDown(provider.closeStreams);
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

      final from = _controller(tester).offset;
      provider.seek(const Duration(milliseconds: 34500));

      var previous = from;
      var biggestStep = 0.0;
      var framesMoving = 0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = _controller(tester).offset;
        if ((now - previous).abs() > 0.01) framesMoving++;
        biggestStep = (now - previous).abs() > biggestStep
            ? (now - previous).abs()
            : biggestStep;
        previous = now;
      }
      final travelled = previous - from;
      expect(travelled, greaterThan(20), reason: 'the list followed the song');
      expect(framesMoving, greaterThan(8),
          reason: 'a 350-500ms glide is many frames, not one');
      expect(biggestStep, lessThan(travelled * 0.5),
          reason: 'no frame carries the move: that is a jump');
    });

    testWidgets('the shift is paint-time: no row is laid out again',
        (tester) async {
      // A shift that went through layout would change a row's SIZE or the list's
      // extent. Neither may move while the rows fan out.
      final provider = _Provider(_lyric());
      addTearDown(provider.closeStreams);
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

      final extentBefore = _controller(tester).position.maxScrollExtent;
      final sizes = {
        for (final box
            in tester.allRenderObjects.whereType<RenderLyricStaggerShift>())
          box.index: box.size,
      };

      provider.seek(const Duration(milliseconds: 34500));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        for (final box
            in tester.allRenderObjects.whereType<RenderLyricStaggerShift>()) {
          final before = sizes[box.index];
          if (before != null) {
            expect(box.size, before,
                reason: 'row ${box.index} was re-laid-out');
          }
        }
        expect(_controller(tester).position.maxScrollExtent, extentBefore);
      }
      await _settle(tester);
    });

    testWidgets('a finger ends it: nothing is pulled around under the reader',
        (tester) async {
      final provider = _Provider(_lyric());
      addTearDown(provider.closeStreams);
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

      provider.seek(const Duration(milliseconds: 34500));
      // Into the run.
      var held = false;
      for (var i = 0; i < 30 && !held; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        held = _shifts(tester).values.any((s) => s > 1.0);
      }
      expect(held, isTrue,
          reason: 'the run must be under way to be interrupted');

      // A drag, not a touch: only a finger that actually moves the list opens a
      // browse.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();

      for (final entry in _shifts(tester).entries) {
        expect(entry.value, 0.0,
            reason: 'row ${entry.key} still held back while dragging');
      }
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_shifts(tester).values.every((s) => s == 0.0), isTrue);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 800));
    });

    testWidgets('a touch that stops the list dead ends it too', (tester) async {
      // No drag, no browse: the finger only lands. A touch still halts the
      // scroll animation (the list goes into a hold), and with the list frozen
      // part-way the rows must not go on to finish a fan-out it never made.
      final provider = _Provider(_lyric());
      addTearDown(provider.closeStreams);
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

      provider.seek(const Duration(milliseconds: 34500));
      var held = false;
      for (var i = 0; i < 30 && !held; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        held = _shifts(tester).values.any((s) => s > 1.0);
      }
      expect(held, isTrue);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      // The scroll's future completes on a microtask; one frame paints the result.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      for (final entry in _shifts(tester).entries) {
        expect(entry.value, 0.0, reason: 'row ${entry.key} kept fanning out');
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 800));
    });
    testWidgets('a drag on its own never starts one', (tester) async {
      final provider = _Provider(_lyric());
      addTearDown(provider.closeStreams);
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(0, -18));
        await tester.pump(const Duration(milliseconds: 16));
        expect(_shifts(tester).values.every((s) => s == 0.0), isTrue,
            reason: 'step $i: a finger scroll is not a handover');
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_shifts(tester).values.every((s) => s == 0.0), isTrue);
    });

    testWidgets('reduced motion gets the handover without the fan-out',
        (tester) async {
      final provider = _Provider(_lyric());
      addTearDown(provider.closeStreams);
      await tester.pumpWidget(_screen(provider, reduceMotion: true));
      await _settle(tester);
      final restOffset = _controller(tester).offset;

      provider.seek(const Duration(milliseconds: 34500));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_shifts(tester).values.every((s) => s == 0.0), isTrue,
            reason: 'frame $i');
      }
      expect(_controller(tester).offset, greaterThan(restOffset),
          reason: 'the list still follows the song');
    });
  });
}

/// A bare host that hands out a [LyricStagger] on a real ticker.
class _Host extends StatefulWidget {
  const _Host({required this.onReady, this.builder});

  final ValueChanged<LyricStagger> onReady;
  final Widget Function(LyricStagger stagger)? builder;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final LyricStagger _stagger = LyricStagger(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.onReady(_stagger);
  }

  @override
  void dispose() {
    _stagger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder?.call(_stagger) ?? const SizedBox.shrink();
}
