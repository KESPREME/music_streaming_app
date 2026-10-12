import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/now_playing_screen.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/lyrics_screen.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_translation_service.dart';
import 'package:music_streaming_app/widgets/lower_half_tap.dart';
import 'package:music_streaming_app/widgets/lyric_caption.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_line.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_typography.dart';
import 'package:music_streaming_app/widgets/lyric_providers_sheet.dart';
import 'package:music_streaming_app/widgets/lyrics_mode_discs.dart';
import 'package:music_streaming_app/widgets/scroll_collapse_tracker.dart';
import 'package:music_streaming_app/widgets/thin_slider.dart';

/// THE CONTROLS THIS FILE PINS.
///
/// While the lyric panel is open the player's controls (the deck, and the two
/// mode discs floating over the panel's foot) come and go on four triggers:
///
///   * five seconds of stillness put them away;
///   * a finger carrying the lyric 20dp forward puts them away, and 20dp back
///     brings them back;
///   * a tap in the lower half of the panel brings them back;
///   * and NOTHING ELSE does - above all not the panel's own auto-scroll, which
///     moves the list every line and is not somebody reading on.
///
/// They used to be two flags (a scroll flag and an idle flag) ANDed together, and
/// every pointer-down un-hid the idle one. Both had a failure that could not be
/// seen from the other: a deck brought back by one while the other still held it
/// away, and a hide-by-scroll that flickered the controls back in on the touch
/// that started the scroll. Every assertion here goes through the real player.

class _Provider extends MusicProvider {
  _Provider(this.lines);

  final List<LyricsEntry> lines;

  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _seeks =
      StreamController<Duration>.broadcast();
  Duration _position = const Duration(seconds: 10);

  /// Every seek the panel asked for, so "a tap on a line still seeks" is
  /// observable.
  final List<Duration> seeksRequested = [];

  @override
  Track? get currentTrack => Track(
        id: 'track1234567',
        trackName: 'Borderline',
        artistName: 'Tame Impala',
        albumName: 'Currents',
        previewUrl: '',
      );

  @override
  bool get isPlaying => false;

  @override
  Duration get duration => const Duration(minutes: 4);

  @override
  Duration get position => _position;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration> get seekEvents => _seeks.stream;

  @override
  bool get isLoadingLyrics => false;

  @override
  String? get lyricsTrackId => 'track1234567';

  @override
  String? get lyricsSourceName => 'LRCLIB';

  @override
  List<LyricsEntry>? get currentLyrics => lines;

  @override
  bool get hasSyncedLyrics => true;

  @override
  bool get isMiniPlayerVisible => false;

  @override
  Future<void> seekTo(Duration position) async {
    seeksRequested.add(position);
    _position = position;
  }

  /// Moves the song on and announces it, as the real player does.
  void jump(Duration to) {
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

List<LyricsEntry> _lyric() => [
      for (var i = 0; i < 14; i++)
        LyricsEntry(
          timeMs: i * 4000,
          endMs: i * 4000 + 3000,
          text: 'lyric line ${i + 1}',
          words: [
            WordTiming(timeMs: i * 4000, durationMs: 900, text: 'lyric'),
            WordTiming(timeMs: i * 4000 + 900, durationMs: 900, text: 'line'),
            WordTiming(
                timeMs: i * 4000 + 1800, durationMs: 900, text: '${i + 1}'),
          ],
        ),
    ];

const _deckKey = Key('npPlayerDeck');
const _riseKey = Key('npPlayerDeckRise');

Widget _player(_Provider provider) =>
    ChangeNotifierProvider<MusicProvider>.value(
      value: provider,
      child: MaterialApp(
        home: NowPlayingScreen(track: provider.currentTrack!),
      ),
    );

Future<_Provider> _openedPlayer(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final provider = _Provider(_lyric());
  addTearDown(provider.closeStreams);
  await tester.pumpWidget(_player(provider));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
  // The collapse (420ms) and then the panel's fade (200ms), with room to spare.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
  return provider;
}

/// Whether the controls are ON, as the player decided it: the deck is in the tree
/// AND takes touches. (A deck mid-hide is still in the tree for its 420ms, but it
/// stopped taking touches on the first frame, so this flips with the decision
/// rather than with the animation.)
bool _controlsShown(WidgetTester tester) {
  final deck = find.byKey(_deckKey);
  if (deck.evaluate().isEmpty) return false;
  return !tester.widget<IgnorePointer>(deck).ignoring;
}

bool _discsVisible(WidgetTester tester) => tester
    .widget<LyricsDiscReveal>(find.byType(LyricsDiscReveal).first)
    .visible;

bool _deckInTree() => find.byKey(_deckKey).evaluate().isNotEmpty;

/// Runs a deck animation (420ms; the hide's first pump only starts its ticker).
Future<void> _settleDeck(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

Finder get _lyricList => find.descendant(
      of: find.byType(LyricsScreen),
      matching: find.byType(ListView),
    );

double _offset(WidgetTester tester) =>
    tester.widget<ListView>(_lyricList).controller!.offset;

/// Carries the lyric forward by dragging a finger UP by [dy], returning how far
/// the LIST actually moved. The drag recognizer swallows the first slop of
/// travel, so the finger's distance and the list's are not the same number, and
/// the controls care about the list's.
Future<double> _fingerForward(WidgetTester tester, double dy) async {
  final before = _offset(tester);
  await tester.drag(_lyricList, Offset(0, -dy));
  await tester.pump();
  return _offset(tester) - before;
}

Future<double> _fingerBack(WidgetTester tester, double dy) async {
  final before = _offset(tester);
  await tester.drag(_lyricList, Offset(0, dy));
  await tester.pump();
  return before - _offset(tester);
}

// ── Tracker notifications, for the arithmetic ────────────────────────────────

ScrollMetrics _metrics(double pixels) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 2000,
      pixels: pixels,
      viewportDimension: 600,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

ScrollStartNotification _start(BuildContext c, {bool finger = true}) =>
    ScrollStartNotification(
      metrics: _metrics(0),
      context: c,
      dragDetails:
          finger ? DragStartDetails(globalPosition: Offset.zero) : null,
    );

ScrollUpdateNotification _update(
  BuildContext c,
  double pixels,
  double delta, {
  bool finger = true,
}) =>
    ScrollUpdateNotification(
      metrics: _metrics(pixels),
      context: c,
      scrollDelta: delta,
      dragDetails: finger
          ? DragUpdateDetails(
              globalPosition: Offset.zero, delta: Offset(0, -delta))
          : null,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the arithmetic of the lyric panel\'s scroll direction', () {
    testWidgets('20dp forward hides, 20dp back reveals, in either order',
        (tester) async {
      await tester.pumpWidget(Container());
      final c = tester.element(find.byType(Container));
      final t = ScrollCollapseTracker.directional();
      final reported = <bool>[];

      t.handle(_start(c), reported.add);
      t.handle(_update(c, 10, 10), reported.add);
      expect(reported, isEmpty, reason: '10dp is a nudge');
      t.handle(_update(c, 19, 9), reported.add);
      expect(reported, isEmpty, reason: '19dp is still a nudge');
      t.handle(_update(c, 21, 2), reported.add);
      expect(reported, [true], reason: 'past 20dp it is reading on: hide');

      t.handle(_update(c, 10, -11), reported.add);
      expect(reported, [true], reason: '11dp back is a nudge');
      t.handle(_update(c, 0, -10), reported.add);
      expect(reported, [true, false], reason: '21dp back: reveal');
    });

    testWidgets('a flip of direction throws the tally away', (tester) async {
      // 15 forward, 5 back, 15 forward. Net travel is 25dp and would hide on the
      // wobble; but no 20dp of it was in one direction, so it is a wandering
      // finger and not somebody reading on.
      await tester.pumpWidget(Container());
      final c = tester.element(find.byType(Container));
      final t = ScrollCollapseTracker.directional();
      final reported = <bool>[];

      t.handle(_start(c), reported.add);
      t.handle(_update(c, 100, 15), reported.add);
      t.handle(_update(c, 95, -5), reported.add);
      t.handle(_update(c, 110, 15), reported.add);
      expect(reported, isEmpty);

      // The queue's dialect banks it: that is the difference being pinned.
      final queue = ScrollCollapseTracker();
      final queueReported = <bool>[];
      queue.handle(_start(c), queueReported.add);
      queue.handle(_update(c, 100, 15), queueReported.add);
      queue.handle(_update(c, 95, -5), queueReported.add);
      queue.handle(_update(c, 110, 15), queueReported.add);
      expect(queueReported, [true]);
    });

    testWidgets('it does not care where in the list it is', (tester) async {
      // A lyric starts near its top. The queue's headroom rule would refuse to
      // hide for the first lines of every song.
      await tester.pumpWidget(Container());
      final c = tester.element(find.byType(Container));
      final t = ScrollCollapseTracker.directional();
      final reported = <bool>[];
      t.handle(_start(c), reported.add);
      t.handle(_update(c, 22, 22), reported.add);
      expect(reported, [true]);
    });

    testWidgets('programmatic scrolls never report', (tester) async {
      await tester.pumpWidget(Container());
      final c = tester.element(find.byType(Container));
      final t = ScrollCollapseTracker.directional();
      final reported = <bool>[];
      t.handle(_start(c, finger: false), reported.add);
      t.handle(_update(c, 300, 300, finger: false), reported.add);
      t.handle(_update(c, 0, -300, finger: false), reported.add);
      expect(reported, isEmpty,
          reason:
              'the panel scrolls itself every line; that is not reading on');
    });

    testWidgets(
        'a lyric that coasts back to its top does not reveal on its own',
        (tester) async {
      // The queue does ("a flick home never strands the list topless"). A song
      // has no such thing as home.
      await tester.pumpWidget(Container());
      final c = tester.element(find.byType(Container));
      final t = ScrollCollapseTracker.directional();
      final reported = <bool>[];
      t.handle(_start(c), reported.add);
      t.handle(_update(c, 300, 30), reported.add);
      expect(reported, [true]);
      t.handle(_update(c, 4, -2, finger: false), reported.add);
      expect(reported, [true]);
    });
  });

  group('the controls, through the real player', () {
    testWidgets('they hide after 5s of stillness, and the discs go with them',
        (tester) async {
      await _openedPlayer(tester);
      expect(_controlsShown(tester), isTrue);
      expect(_discsVisible(tester), isTrue);

      await tester.pump(const Duration(seconds: 5));
      expect(_controlsShown(tester), isFalse,
          reason: 'the decision is taken the moment the countdown ends');
      expect(_discsVisible(tester), isFalse,
          reason: 'and the discs are told in the same frame');

      await _settleDeck(tester);
      expect(_deckInTree(), isFalse, reason: 'a hidden deck builds nothing');
    });

    testWidgets('activity restarts the countdown', (tester) async {
      await _openedPlayer(tester); // 1.2s in
      // 4.2s in, a finger touches the glass; the 5s starts again from there.
      await tester.pump(const Duration(seconds: 3));
      expect(_controlsShown(tester), isTrue);
      await tester.tapAt(const Offset(200, 120));
      await tester.pump(const Duration(seconds: 3));
      expect(_controlsShown(tester), isTrue,
          reason: '7.2s after opening, but only 3s after the last touch');
      await tester.pump(const Duration(seconds: 3));
      expect(_controlsShown(tester), isFalse);
    });

    testWidgets(
        'a finger carrying the lyric forward hides them; carrying it '
        'back reveals them', (tester) async {
      await _openedPlayer(tester);

      final forward = await _fingerForward(tester, 90);
      expect(forward, greaterThan(20),
          reason: 'the drag really moved the list');
      expect(_controlsShown(tester), isFalse);
      expect(_discsVisible(tester), isFalse);

      await _settleDeck(tester);
      final back = await _fingerBack(tester, 90);
      expect(back, greaterThan(20));
      expect(_controlsShown(tester), isTrue);
      expect(_discsVisible(tester), isTrue);
      await _settleDeck(tester);
      expect(_deckInTree(), isTrue);
    });

    testWidgets('a nudge under 20dp does not', (tester) async {
      await _openedPlayer(tester);

      // Found by measuring the LIST, not the finger: the recognizer swallows its
      // slop, so a 30px drag moves the list by less.
      var nudge = 0.0;
      for (final dy in <double>[22, 28, 34]) {
        // Fresh gesture each time; stop at the largest that stays under 20.
        final before = _offset(tester);
        await tester.drag(_lyricList, Offset(0, -dy));
        await tester.pump();
        final moved = _offset(tester) - before;
        if (moved <= 20 && moved > nudge) nudge = moved;
        if (!_controlsShown(tester)) break;
        // Put the list back so the next try starts where this one did.
        await tester.drag(_lyricList, Offset(0, dy));
        await tester.pump();
        await _settleDeck(tester);
      }
      expect(nudge, greaterThan(0), reason: 'a sub-20dp scroll was exercised');
      expect(_controlsShown(tester), isTrue,
          reason: 'travel of $nudge dp is a nudge, not a decision to read on');
    });

    testWidgets('the panel scrolling ITSELF never hides them', (tester) async {
      // THE REGRESSION. The list moves on its own every line. If that counted as
      // reading on, the controls would go away every time the singing moved.
      final provider = await _openedPlayer(tester);
      final before = _offset(tester);

      for (var line = 4; line <= 8; line++) {
        provider.jump(Duration(milliseconds: line * 4000 + 500));
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(_controlsShown(tester), isTrue, reason: 'after line $line');
      }
      expect(_offset(tester), greaterThan(before + 200),
          reason: 'the list did follow the song, five lines');
      expect(_discsVisible(tester), isTrue);
    });

    testWidgets(
        'a tap in the lower half brings them back; the upper half does '
        'not', (tester) async {
      await _openedPlayer(tester);
      await tester.pump(const Duration(seconds: 5));
      await _settleDeck(tester);
      expect(_controlsShown(tester), isFalse);

      // Upper half of the panel (the panel is the whole screen now).
      await tester.tapAt(const Offset(200, 120));
      await tester.pump();
      expect(_controlsShown(tester), isFalse,
          reason: 'only the lower half is a request for the controls');

      await tester.tapAt(const Offset(200, 760));
      await tester.pump();
      expect(_controlsShown(tester), isTrue);
      expect(_discsVisible(tester), isTrue);
      await _settleDeck(tester);
      expect(_deckInTree(), isTrue);
    });

    testWidgets('a lower-half tap on a lyric line still seeks to it',
        (tester) async {
      // The reveal listens to raw pointer events and claims nothing, so the line
      // underneath gets the tap it was aimed at.
      final provider = await _openedPlayer(tester);
      await tester.pump(const Duration(seconds: 5));
      await _settleDeck(tester);
      expect(_controlsShown(tester), isFalse);

      final lowerLines = find
          .byWidgetPredicate((w) => w is LyricLine)
          .evaluate()
          .map((e) => e.widget as LyricLine)
          .where((l) => tester.getCenter(find.byWidget(l)).dy > 500)
          .toList();
      expect(lowerLines, isNotEmpty, reason: 'a line sits in the lower half');
      final target = lowerLines.first;

      await tester.tap(find.byWidget(target));
      await tester.pump();

      expect(provider.seeksRequested,
          [Duration(milliseconds: target.entry.timeMs)],
          reason: 'the line sought');
      expect(_controlsShown(tester), isTrue,
          reason: 'and the controls came back');
    });

    testWidgets('a lower-half DRAG is a scroll, not a tap', (tester) async {
      await _openedPlayer(tester);
      await tester.pump(const Duration(seconds: 5));
      await _settleDeck(tester);
      expect(_controlsShown(tester), isFalse);

      // 30px of travel is inside 2.5 touch slops - and the list took the gesture
      // at one. Forward, so the scroll rule would hide them anyway: this pins that
      // the TAP rule did not fire on a finger that was scrolling.
      final gesture = await tester.startGesture(const Offset(200, 760));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(_controlsShown(tester), isFalse);
    });

    testWidgets('a held scrub does not run out the clock', (tester) async {
      await _openedPlayer(tester); // 1.2s in
      await tester.pump(const Duration(seconds: 3));

      // A finger on the scrubber for longer than the whole countdown.
      final slider = find.byType(ThinSlider).first;
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await tester.pump(const Duration(seconds: 7));
      expect(_controlsShown(tester), isTrue,
          reason: 'holding the scrubber is use, not stillness');
      await gesture.up();
      await tester.pump();
    });

    testWidgets('the discs are always exactly as shown as the deck',
        (tester) async {
      await _openedPlayer(tester);
      final steps = <String, Future<void> Function()>{
        'start': () async {},
        'idle hide': () async {
          await tester.pump(const Duration(seconds: 5));
        },
        'tap reveal': () async {
          await _settleDeck(tester);
          await tester.tapAt(const Offset(200, 760));
          await tester.pump();
        },
        'scroll hide': () async {
          await _settleDeck(tester);
          await _fingerForward(tester, 90);
        },
        'scroll reveal': () async {
          await _settleDeck(tester);
          await _fingerBack(tester, 90);
        },
      };
      for (final step in steps.entries) {
        await step.value();
        expect(_discsVisible(tester), _controlsShown(tester),
            reason: 'after "${step.key}" the discs and the deck disagree');
      }
    });
  });

  group('how the deck arrives and leaves', () {
    testWidgets(
        'it is sized and slid, never faded: nothing translucent over the '
        'glass', (tester) async {
      await _openedPlayer(tester);
      await tester.pump(const Duration(seconds: 5));
      await _settleDeck(tester);

      await tester.tapAt(const Offset(200, 760));
      await tester.pump(); // reveal begins
      await tester.pump(const Duration(milliseconds: 120));

      final transition = tester.widget<SizeTransition>(
        find.ancestor(
            of: find.byKey(_deckKey), matching: find.byType(SizeTransition)),
      );
      expect(transition.sizeFactor.value, inExclusiveRange(0.0, 1.0),
          reason: '120ms into a 420ms reveal the deck is part-way');

      final rise = tester.widget<Transform>(find.byKey(_riseKey));
      final lift = rise.transform.getTranslation().y;
      expect(lift, inExclusiveRange(0.0, 24.0),
          reason: 'sliding up from 24dp below, not fading in');

      // Walked up from the deck to the player, not `find.ancestor` over the whole
      // tree: the ROUTE's own page transition is a FadeTransition above everything
      // and says nothing about the deck.
      final translucent = <Type>[];
      tester.element(find.byKey(_deckKey)).visitAncestorElements((element) {
        if (element.widget is NowPlayingScreen) return false;
        final widget = element.widget;
        if (widget is Opacity ||
            widget is AnimatedOpacity ||
            widget is FadeTransition) {
          translucent.add(widget.runtimeType);
        }
        return true;
      });
      expect(translucent, isEmpty,
          reason:
              'alpha over the deck would flatten the glass pill (invariant 1)');

      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester
            .widget<SizeTransition>(find.ancestor(
                of: find.byKey(_deckKey),
                matching: find.byType(SizeTransition)))
            .sizeFactor
            .value,
        1.0,
      );
      expect(
          tester
              .widget<Transform>(find.byKey(_riseKey))
              .transform
              .getTranslation()
              .y,
          0.0);
    });

    testWidgets('the lyric panel grows into the space the deck gives up',
        (tester) async {
      await _openedPlayer(tester);
      final withDeck = tester.getSize(_lyricList).height;

      await tester.pump(const Duration(seconds: 5));
      await _settleDeck(tester);
      expect(tester.getSize(_lyricList).height, greaterThan(withDeck + 100),
          reason: 'the Expanded above the deck takes the freed height');
    });

    testWidgets('hiding eases out without overshoot', (tester) async {
      await _openedPlayer(tester);
      await tester.pump(const Duration(seconds: 5));

      var previous = 1.0;
      await tester.pump(); // the ticker starts
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final finder = find.ancestor(
            of: find.byKey(_deckKey), matching: find.byType(SizeTransition));
        if (finder.evaluate().isEmpty) break;
        final value = tester.widget<SizeTransition>(finder).sizeFactor.value;
        expect(value, lessThanOrEqualTo(previous + 1e-9),
            reason: 'a state change never overshoots (invariant 16)');
        expect(value, greaterThanOrEqualTo(0.0));
        previous = value;
      }
    });

    testWidgets(
        'returning to the main view with the deck away snaps it to full '
        'height and slides it in', (tester) async {
      await _openedPlayer(tester);
      await tester.pump(const Duration(seconds: 5));
      await _settleDeck(tester);
      expect(_deckInTree(), isFalse);

      await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final transition = tester.widget<SizeTransition>(
        find.ancestor(
            of: find.byKey(_deckKey), matching: find.byType(SizeTransition)),
      );
      expect(transition.sizeFactor.value, 1.0,
          reason:
              'the artwork is flying to a rect derived from the page height; a '
              'deck still growing under it would move the destination mid-flight');
      final lift = tester
          .widget<Transform>(find.byKey(_riseKey))
          .transform
          .getTranslation()
          .y;
      expect(lift, inExclusiveRange(0.0, 24.0),
          reason: 'but it arrives gently');

      await tester.pump(const Duration(milliseconds: 900));
      expect(
          tester
              .widget<Transform>(find.byKey(_riseKey))
              .transform
              .getTranslation()
              .y,
          0.0);
      expect(_controlsShown(tester), isTrue);
    });
  });

  group('the lower-half tap detector', () {
    Future<void> pumpDetector(
      WidgetTester tester, {
      required bool enabled,
      required VoidCallback onTap,
      Widget? child,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 400,
              child: LowerHalfTap(
                enabled: enabled,
                onTap: onTap,
                child: child ?? const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a tap below the middle counts; above it does not',
        (tester) async {
      var taps = 0;
      await pumpDetector(tester, enabled: true, onTap: () => taps++);
      final box = tester.getRect(find.byType(LowerHalfTap));

      await tester.tapAt(box.topCenter + const Offset(0, 40));
      expect(taps, 0);
      await tester.tapAt(box.center + const Offset(0, 40));
      expect(taps, 1);
    });

    testWidgets(
        'it follows a finger that wanders inside 2.5 slops, and no '
        'further', (tester) async {
      var taps = 0;
      await pumpDetector(tester, enabled: true, onTap: () => taps++);
      final start = tester.getRect(find.byType(LowerHalfTap)).center +
          const Offset(0, 100);

      var gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(kTouchSlop * 2.4, 0));
      await gesture.up();
      expect(taps, 1, reason: 'a wobble inside 2.5 slops is a tap');

      gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(kTouchSlop * 2.6, 0));
      await gesture.up();
      expect(taps, 1, reason: 'past it, it is a drag');
    });

    testWidgets('a second finger spoils it', (tester) async {
      var taps = 0;
      await pumpDetector(tester, enabled: true, onTap: () => taps++);
      final center = tester.getRect(find.byType(LowerHalfTap)).center;

      final first = await tester.startGesture(center + const Offset(0, 80));
      final second = await tester.startGesture(center + const Offset(20, 100));
      await first.up();
      await second.up();
      expect(taps, 0);
    });

    testWidgets('a scroll the finger started spoils it, however short',
        (tester) async {
      var taps = 0;
      await pumpDetector(
        tester,
        enabled: true,
        onTap: () => taps++,
        child: ListView(children: const [SizedBox(height: 2000)]),
      );
      final start = tester.getRect(find.byType(LowerHalfTap)).center +
          const Offset(0, 100);

      final gesture = await tester.startGesture(start);
      // Past the list's one slop, inside the detector's 2.5.
      await gesture.moveBy(const Offset(0, -kTouchSlop * 1.8));
      await gesture.up();
      await tester.pump();
      expect(taps, 0, reason: 'the list took it: that was a scroll');
    });

    testWidgets('disabled, it watches nothing', (tester) async {
      var taps = 0;
      await pumpDetector(tester, enabled: false, onTap: () => taps++);
      await tester.tapAt(tester.getRect(find.byType(LowerHalfTap)).center +
          const Offset(0, 100));
      expect(taps, 0);
    });

    testWidgets('it claims nothing: a button underneath still gets its tap',
        (tester) async {
      var revealed = 0;
      var pressed = 0;
      await pumpDetector(
        tester,
        enabled: true,
        onTap: () => revealed++,
        child: Align(
          alignment: Alignment.bottomCenter,
          child:
              TextButton(onPressed: () => pressed++, child: const Text('seek')),
        ),
      );
      await tester.tap(find.text('seek'));
      expect(pressed, 1);
      expect(revealed, 1);
    });
  });

  group('the status caption', () {
    String say({
      LyricTransformStatus transform = LyricTransformStatus.none,
      bool hasLyrics = true,
      String? source = 'LRCLIB',
      bool loading = false,
    }) =>
        LyricCaption.resolve(
          transform: transform,
          hasLyrics: hasLyrics,
          source: source,
          loading: loading,
          languageName: (code) => code == 'fr' ? 'French' : code.toUpperCase(),
        ).text;

    test('Translating / Romanizing outrank everything', () {
      expect(
        say(
            transform:
                const LyricTransformStatus(LyricTransformPhase.translating)),
        'Translating…',
      );
      expect(
        say(
            transform:
                const LyricTransformStatus(LyricTransformPhase.romanizing)),
        'Romanizing…',
      );
      // Even over a lyric that is also on screen, a source, and a lookup.
      expect(
        say(
          transform:
              const LyricTransformStatus(LyricTransformPhase.translating),
          loading: true,
        ),
        'Translating…',
      );
    });

    test('Translated to {language} / Romanized come next', () {
      expect(
        say(
          transform: const LyricTransformStatus(
            LyricTransformPhase.translated,
            language: 'fr',
          ),
        ),
        'Translated to French',
      );
      expect(
        say(
            transform:
                const LyricTransformStatus(LyricTransformPhase.romanized)),
        'Romanized',
      );
      // An unknown code is said as it is, never guessed.
      expect(
        say(
          transform: const LyricTransformStatus(
            LyricTransformPhase.translated,
            language: 'xx',
          ),
        ),
        'Translated to XX',
      );
    });

    test('then Lyrics by {source}', () {
      expect(say(), 'Lyrics by LRCLIB');
      expect(say(source: 'Better Lyrics'), 'Lyrics by Better Lyrics');
    });

    test('lyrics of unknown origin are not credited to anyone', () {
      expect(say(source: null), 'Lyrics');
      expect(say(source: ''), 'Lyrics');
    });

    test('then No lyrics found, once the lookup is over', () {
      expect(say(hasLyrics: false, source: null), 'No lyrics found');
    });

    test('and only while it is still looking, the quiet loading text', () {
      expect(say(hasLyrics: false, source: null, loading: true),
          'Finding lyrics…');
      // A miss is NEVER announced while the lookup is running.
      expect(say(hasLyrics: false, source: null, loading: true),
          isNot('No lyrics found'));
    });

    test('a transform with no lyric under it says nothing about the transform',
        () {
      // A shown transform needs words to be shown on.
      expect(
        say(
          transform: const LyricTransformStatus(LyricTransformPhase.translated),
          hasLyrics: false,
          source: null,
        ),
        'No lyrics found',
      );
    });

    test('the whole priority table, by kind', () {
      LyricCaptionKind kind({
        LyricTransformPhase phase = LyricTransformPhase.none,
        bool hasLyrics = true,
        String? source = 'S',
        bool loading = false,
      }) =>
          LyricCaption.resolve(
            transform: LyricTransformStatus(phase, language: 'fr'),
            hasLyrics: hasLyrics,
            source: source,
            loading: loading,
          ).kind;

      expect(kind(phase: LyricTransformPhase.translating),
          LyricCaptionKind.translating);
      expect(kind(phase: LyricTransformPhase.romanizing),
          LyricCaptionKind.romanizing);
      expect(kind(phase: LyricTransformPhase.translated),
          LyricCaptionKind.translated);
      expect(kind(phase: LyricTransformPhase.romanized),
          LyricCaptionKind.romanized);
      expect(kind(), LyricCaptionKind.source);
      expect(kind(hasLyrics: false, source: null), LyricCaptionKind.noLyrics);
      expect(kind(hasLyrics: false, source: null, loading: true),
          LyricCaptionKind.loading);
    });

    testWidgets(
        'it is one underlined line in the caption style, with no icon '
        'and no chevron', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              child: LyricCaptionText(
                data: const LyricCaptionData(
                  LyricCaptionKind.source,
                  'Lyrics by A Rather Long Provider Name',
                ),
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.style!.decoration, TextDecoration.underline);
      final caption = LyricTypography.caption();
      expect(text.style!.fontSize, caption.fontSize);
      expect(text.style!.fontWeight, caption.fontWeight);
      expect(find.byType(Icon), findsNothing);
      expect(find.byType(Image), findsNothing);

      await tester.tap(find.byType(LyricCaptionText));
      expect(taps, 1);
    });

    testWidgets('the loading text is quiet: not underlined, not tappable',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricCaptionText(
              data: const LyricCaptionData(
                LyricCaptionKind.loading,
                LyricCaption.loading,
              ),
              onTap: () => taps++,
            ),
          ),
        ),
      );
      expect(tester.widget<Text>(find.byType(Text)).style!.decoration,
          TextDecoration.none);
      await tester.tap(find.byType(Text));
      expect(taps, 0);
    });

    testWidgets('in the player it names the source and carries no chevron',
        (tester) async {
      await _openedPlayer(tester);
      expect(find.text('Lyrics by LRCLIB'), findsOneWidget);
      expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);
      expect(find.text('Lyrics unavailable'), findsNothing);
    });

    testWidgets('tapping it opens the provider sheet', (tester) async {
      await _openedPlayer(tester);
      expect(find.byType(LyricProvidersSheet), findsNothing);

      await tester.tap(find.text('Lyrics by LRCLIB'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(LyricProvidersSheet), findsOneWidget);
      // What the sheet builds inside is the sheet's own business (it reads
      // providers this harness does not supply); this test is about the caption
      // reaching it.
      tester.takeException();
    });
    testWidgets('and it follows the status the lyric panel publishes',
        (tester) async {
      await _openedPlayer(tester);
      final panel = tester.widget<LyricsScreen>(find.byType(LyricsScreen));
      final publish = panel.onTransformStatusChanged!;

      publish(const LyricTransformStatus(LyricTransformPhase.translating));
      await tester.pump();
      expect(find.text('Translating…'), findsOneWidget);
      expect(find.text('Lyrics by LRCLIB'), findsNothing);

      publish(const LyricTransformStatus(LyricTransformPhase.romanized));
      await tester.pump();
      expect(find.text('Romanized'), findsOneWidget);

      publish(LyricTransformStatus.none);
      await tester.pump();
      expect(find.text('Lyrics by LRCLIB'), findsOneWidget);
    });

    // KEEP THIS TEST LAST IN THE FILE. It seeds SharedPreferences, which is global
    // to the isolate, and a seeded store lets MusicProvider's start-up run on into
    // periodic timers that every later test would then fail on.
    testWidgets(
        'the REAL panel says Translating… while the request is out, and '
        'goes back to the source when it ends', (tester) async {
      // End to end through the disc, the sub-line controller, the panel's
      // publish and the caption. The service is swapped for one whose only
      // request waits on a completer, so "in flight" can be held for as long as
      // it takes to look.
      final reply = Completer<http.Response>();
      LyricsTranslationService.debugOverrideInstance(
        LyricsTranslationService(
          client: MockClient((_) => reply.future),
          cacheDirectory: () async => null,
        ),
      );
      addTearDown(() => LyricsTranslationService.debugOverrideInstance(null));

      await _openedPlayer(tester);
      expect(find.text('Lyrics by LRCLIB'), findsOneWidget);

      // The target language is read from the stored setting on every tap. Seeded
      // AFTER the player is up: the provider's own start-up reads the same store,
      // and a seeded store lets it run on into timers this test has no business
      // owning.
      SharedPreferences.setMockInitialValues({});
      await tester.tap(find.bySemanticsLabel('Show translated lyrics'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Translating…'), findsOneWidget,
          reason: 'work in flight outranks the source');
      expect(find.text('Lyrics by LRCLIB'), findsNothing);

      // The request fails: nothing was translated, so the caption is the
      // source's again - not stuck on a job that is no longer running.
      reply.complete(http.Response('[]', 500));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Translating…'), findsNothing);
      expect(find.text('Lyrics by LRCLIB'), findsOneWidget);
    });
  });
}
