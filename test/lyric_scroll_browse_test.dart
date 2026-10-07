import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/lyrics_screen.dart';
import 'package:music_streaming_app/services/lyrics/lyric_sweep.dart';
import 'package:music_streaming_app/widgets/lyric_swept_line.dart';

/// THE JANK THIS FILE PINS.
///
/// The lyric panel used to decide "the reader is browsing" by watching
/// `position.isScrollingNotifier`. Our own `animateTo` sets that notifier, so
/// every line handover announced itself as a browse: the blur cleared, the alpha
/// ladder flattened, and - the actual damage - `_autoScrollEnabled` went false
/// for the whole resume window. The panel stopped following the song for 3.5
/// seconds once per line. That is what "janky, not going word by word" looked
/// like on a device.
///
/// A browse is a FINGER. Nothing else.

class _Provider extends MusicProvider {
  _Provider(this.lines, {this.playing = true});

  final List<LyricsEntry> lines;
  final bool playing;

  final StreamController<Duration> _positions =
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

  /// A real broadcast stream the test drives, rather than a single value.
  ///
  /// The panel subscribes to this AND runs a 250ms correction timer that reads
  /// [position]. With a static fake position the correction timer declares the
  /// song stalled, stops the clock and returns early - so the position only ever
  /// reached the panel on the very first tick, and a test could not move the
  /// song forward at all. Driving the stream makes each [seek] land on the next
  /// pump, deterministically.
  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  bool get isPlaying => playing;

  @override
  bool get isLoadingLyrics => false;

  @override
  List<LyricsEntry>? get currentLyrics => lines;

  @override
  bool get hasSyncedLyrics => true;

  /// Moves the song on and announces it.
  void seek(Duration to) {
    _position = to;
    _positions.add(to);
  }

  void closeStream() => _positions.close();

  @override
  void dispose() {
    _positions.close();
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
            WordTiming(timeMs: i * 4000 + 900, durationMs: 900, text: '${i + 1}'),
            WordTiming(timeMs: i * 4000 + 1800, durationMs: 900, text: 'here'),
          ],
        ),
    ];

/// A provider whose stream is torn down with the test.
_Provider _latched(List<LyricsEntry> lines, {bool playing = true}) {
  final provider = _Provider(lines, playing: playing);
  addTearDown(provider.closeStream);
  return provider;
}

Widget _screen(_Provider provider) =>
    ChangeNotifierProvider<MusicProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: LyricsScreen(
            isEmbedded: true,
            showHeader: false,
            showBottomScrubber: false,
          ),
        ),
      ),
    );

/// Whether the blur ladder is lifted, which is what "browsing" means.
///
/// Browsing lifts every row's blur to zero, so no row builds an [ImageFiltered]
/// at all; at rest the ladder is back. This is a sharper signal than comparing
/// alphas, which is a difference between floats that a tween is still moving.
///
/// Read from the RENDERED tree rather than from the ladder function: what is
/// being pinned is what reaches the screen.
bool _blurIsLifted(WidgetTester tester) =>
    find.descendant(
      of: find.byType(LyricsScreen),
      matching: find.byType(ImageFiltered),
    ).evaluate().isEmpty;

ScrollController _listController(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

/// The index of the lyric row sitting at the TOP of the list's viewport.
///
/// Found by geometry rather than by asking which index we expected: a lazy list
/// has not built the rows outside its viewport, so `find.text('line N here')`
/// only answers for rows that exist, and hard-coding an index would silently
/// assert against whatever happened to be built.
///
/// Rows ABOVE the viewport are excluded even when they are built - Flutter keeps
/// a cache extent above the top edge, so those rows have real boxes sitting at
/// negative y. Picking the smallest y without that filter returns the row before
/// the target and every anchor assertion reads a full row-pitch short.
int _topmostVisibleLineIndex(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Text),
  );
  final listTop = tester.getTopLeft(find.byType(ListView)).dy;
  var topmostDy = double.infinity;
  var topmostIndex = -1;
  for (final element in finder.evaluate()) {
    final text = element.widget as Text;
    final match = RegExp(r'^line (\d+) here$').firstMatch(text.data ?? '');
    if (match == null) continue;
    final dy = tester.getTopLeft(find.byWidget(text)).dy;
    if (dy < listTop - 1) continue;
    if (dy < topmostDy) {
      topmostDy = dy;
      topmostIndex = int.parse(match.group(1)!) - 1;
    }
  }
  return topmostIndex;
}

/// Pumps long enough for a handover to settle under ANY spec in play.
///
/// Several frames, not one long one. The panel's follow is driven by a 250ms
/// correction timer that schedules a post-frame scroll, which in turn starts a
/// 500ms animation - a single `pump(Duration)` would fire the timer, start the
/// scroll, and then stop pumping before it moved a pixel.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Moves the song and lets the panel follow it all the way.
Future<void> _seekAndSettle(WidgetTester tester, _Provider p, int ms) async {
  p.seek(Duration(milliseconds: ms));
  await _settle(tester);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('the browse state is a finger, not a movement', () {
    testWidgets('a drag flattens the alpha ladder', (tester) async {
      await tester.pumpWidget(_screen(_latched(_lyric())));
      await _settle(tester);

      expect(_blurIsLifted(tester), isFalse,
          reason: 'at rest the ladder is stepped');

      await tester.drag(find.byType(ListView), const Offset(0, -220));
      await tester.pump();

      expect(_blurIsLifted(tester), isTrue,
          reason: 'while a finger is down every line comes up to meet the '
              'reader');
    });

    testWidgets('the panel following the song does NOT flatten the ladder',
        (tester) async {
      // THE REGRESSION. This is the assertion that fails against the old
      // `isScrollingNotifier` listener: driving the song forward makes the list
      // animate, and the old code read that as the reader grabbing it - so the
      // ladder went flat once per line and stayed flat for 3.5s.
      final provider = _latched(_lyric());
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

      for (var i = 1; i <= 4; i++) {
        await _seekAndSettle(tester, provider, (30 + i * 4) * 1000);
      }

      expect(_blurIsLifted(tester), isFalse,
          reason: 'after the song advanced four lines with no finger down, the '
              'alpha ladder must be back in force');
    });

    testWidgets('a programmatic seek does not open or close a browse',
        (tester) async {
      final provider = _latched(_lyric());
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

      final before = _listController(tester).offset;
      await _seekAndSettle(tester, provider, 80000);

      expect(_listController(tester).offset, isNot(before),
          reason: 'the panel should have moved with the song');
      expect(_blurIsLifted(tester), isFalse,
          reason: 'a programmatic move must not read as the reader browsing');
    });

    testWidgets('the browse ends without yanking the reader back',
        (tester) async {
      final provider = _latched(_lyric());
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

// Park the list somewhere the singing has left, and stay there.
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      // The blur tween takes 400ms to reach zero and the resume window is 600ms, so
      // "still browsing" is readable in the gap between them.
      var lifted = false;
      for (var i = 0; i < 8 && !lifted; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        lifted = _blurIsLifted(tester);
      }
      expect(lifted, isTrue, reason: 'browsing opened by the drag');

      // Walk forward until the browse ends on its own, and compare the offset
      // across that single frame. Comparing against an offset sampled before the
      // loop instead would fold in the tail of the drag's own momentum, which has
      // nothing to do with the resume.
      var previous = _listController(tester).offset;
      var resumed = false;
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final now = _listController(tester).offset;
        if (!_blurIsLifted(tester)) {
          resumed = true;
          expect((now - previous).abs(), lessThan(2),
              reason: 'ending a browse must not move the list - the reader '
                  'moved it on purpose, and a moment of stillness is not them '
                  'changing their mind');
          break;
        }
        previous = now;
      }

      expect(resumed, isTrue, reason: 'the browse must end on its own');
    });

    testWidgets('a browse parked off-screen takes the long way back',
        (tester) async {
      // The 5s fallback, not the 600ms one: when the reader has parked the list
      // somewhere the singing has left, snapping back is the wrong answer, so
      // the ladder only comes back when they have genuinely stopped.
      final provider = _latched(_lyric());
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

      // A drag far enough that the active line leaves the viewport.
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pump();

      var lifted = false;
      for (var i = 0; i < 8 && !lifted; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        lifted = _blurIsLifted(tester);
      }
      expect(lifted, isTrue);

      // Well past the 600ms short window, and still browsing.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_blurIsLifted(tester), isTrue,
          reason: 'parked off-screen: the short resume must not fire');
    });
  });

  group('the scroll leads the singing', () {
    test('the lead is bounded by the gap it is covering', () {
      // Read from the real function rather than restated: an earlier version of
      // this file copied the numbers, so it would have kept passing after the
      // constant moved.
      expect(scrollLeadMs(_lyric(), 0), inInclusiveRange(350, 500));

      // A 200ms gap cannot lead further than 350ms or the list would run the
      // verse off the top before the voice arrives.
      final fast = [
        LyricsEntry(timeMs: 0, endMs: 1000, text: 'a'),
        LyricsEntry(timeMs: 1200, endMs: 2000, text: 'b'),
      ];
      expect(scrollLeadMs(fast, 0), 350);

      // A four-second silence leads the full 500ms rather than crawling.
      final slow = [
        LyricsEntry(timeMs: 0, endMs: 1000, text: 'a'),
        LyricsEntry(timeMs: 5000, endMs: 6000, text: 'b'),
      ];
      expect(scrollLeadMs(slow, 0), 500);
    });

    test('the top anchor is the list top inset, not a viewport fraction', () {
      // The rule, pinned without a layout pass.
      //
      // The old call was `ensureVisible(alignment: 0.32)`: a FRACTION OF THE
      // VIEWPORT, which parked the line a third of the way down and pushed
      // everything not yet sung toward the bottom edge. BitChord anchors at
      // `scrollOffset = 0` (PlayerLyrics.kt:1742, 1759).
      double anchor({required double pixels, required double rowTop}) =>
          topAnchorOffset(
            currentPixels: pixels,
            rowTopInViewport: rowTop,
            topInset: 56,
            minScrollExtent: 0,
            maxScrollExtent: 10000,
          );

      // A row sitting on the top inset must need no movement at all.
      expect(anchor(pixels: 400, rowTop: 56), 400);

      // A row 300px BELOW the inset needs 300px MORE scroll. Scrolling down moves
      // content up, so "further down the screen" means "further along the
      // content". Getting this backwards scrolls the list away from its target.
      expect(anchor(pixels: 400, rowTop: 356), 700);

      // A row 100px ABOVE the inset needs 100px LESS scroll.
      expect(anchor(pixels: 400, rowTop: -44), 300);

      // Clamped, so a handover past either end cannot throw the list.
      expect(anchor(pixels: 0, rowTop: -900), 0);
      expect(anchor(pixels: 9900, rowTop: 2000), 10000);
    });

    testWidgets('the panel never sits behind the voice', (tester) async {
      // THE LEAD THIS PINS. `_scrollToCurrentLine` used to build the lead index
      // into a local and then scroll to the line ALREADY being sung, using the
      // local only in a fallback branch that never ran. The lead therefore never
      // happened and the list TRAILED the voice: the reader was always looking at
      // what had just gone.
      //
      // PAUSED on purpose. A playing panel's clock keeps interpolating while this
      // pumps, so "which line is being sung" would be a different instant from
      // "where did the panel settle" and the assertion would be a race. Paused,
      // `LyricClock.report` snaps to the reading exactly and the two instants are
      // the same one - which is also the case that matters most, because a seek
      // while paused is when a reader most wants to land on the right line.
      final provider = _latched(_lyric(), playing: false);
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

      for (final at in <int>[11500, 20000, 28000, 35000, 43500]) {
        await _seekAndSettle(tester, provider, at);

        final topmost = _topmostVisibleLineIndex(tester);
        expect(topmost, greaterThanOrEqualTo(0), reason: 'no rows built at $at');

        final sung = activeLineIndex(_lyric(), at);
        expect(topmost, greaterThanOrEqualTo(sung),
            reason: 'at ${at}ms the list is parked on line '
                '${topmost + 1} while line ${sung + 1} is the one being sung');
      }
    });

    testWidgets('the scroll lands the target at the TOP of the content',
        (tester) async {
      // Top-anchored, matching `animateScrollToItem(focusLine, scrollOffset = 0)`.
      // The old call used `ensureVisible(alignment: 0.32)`, which parked the line
      // a third of the way down the viewport and pushed everything not yet sung
      // toward the bottom edge.
      final provider = _latched(_lyric(), playing: false);
      await tester.pumpWidget(_screen(provider));
      await _settle(tester);

      _listController(tester).jumpTo(0);
      await tester.pump();

      await _seekAndSettle(tester, provider, 43500);

      final topmost = _topmostVisibleLineIndex(tester);
      final top =
          tester.getTopLeft(find.text('line ${topmost + 1} here')).dy;
      final listTop = tester.getTopLeft(find.byType(ListView)).dy;

      // 56dp is the list's own top inset; the top row lands on it. The row is
      // keyed inside its margin, so allow for the 14dp above it.
      expect(top - listTop, closeTo(56, 20),
          reason: 'top-anchored: the row the list is resting on sits at the '
              'list\'s top inset, not at the old 0.32 viewport fraction');
    });
  });
}