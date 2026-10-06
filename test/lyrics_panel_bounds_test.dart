import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/lyrics_screen.dart';
import 'package:music_streaming_app/widgets/measure_size.dart';

/// Minimal provider carrying a synced lyric and nothing else.
///
/// Subclassed rather than mocked so the screen sees a real widget tree. Every
/// surface it reads is overridden; anything it does not read does not need to be
/// a real answer.
class _LyricsProvider extends MusicProvider {
  _LyricsProvider(this.lines);

  final List<LyricsEntry> lines;

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
  Duration get position => const Duration(seconds: 17);

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  bool get isPlaying => true;

  @override
  bool get isLoadingLyrics => false;

  @override
  List<LyricsEntry>? get currentLyrics => lines;

  @override
  bool get hasSyncedLyrics => true;
}

List<LyricsEntry> _lyric() => [
      LyricsEntry(
        timeMs: 0,
        endMs: 2000,
        text: 'so here I am once again',
        words: const [
          WordTiming(timeMs: 0, durationMs: 500, text: 'so'),
          WordTiming(timeMs: 500, durationMs: 500, text: 'here'),
          WordTiming(timeMs: 1000, durationMs: 500, text: 'I'),
          WordTiming(timeMs: 1500, durationMs: 500, text: 'am'),
        ],
      ),
      LyricsEntry(
        timeMs: 2000,
        endMs: 4000,
        text: 'again feel no good',
        words: const [
          WordTiming(timeMs: 2000, durationMs: 500, text: 'again'),
          WordTiming(timeMs: 2500, durationMs: 500, text: 'feel'),
          WordTiming(timeMs: 3000, durationMs: 500, text: 'no'),
          WordTiming(timeMs: 3500, durationMs: 500, text: 'good'),
        ],
      ),
    ];

Widget _screen({double bottomInset = 0}) => ChangeNotifierProvider<MusicProvider>.value(
      value: _LyricsProvider(_lyric()),
      child: MaterialApp(
        home: Scaffold(
          body: LyricsScreen(
            isEmbedded: true,
            showHeader: false,
            showBottomScrubber: false,
            bottomInset: bottomInset,
          ),
        ),
      ),
    );

/// The padding the lyric list was actually laid out with.
EdgeInsets _listPadding(WidgetTester tester) {
  final list = tester.widget<ListView>(
    find.descendant(
      of: find.byType(LyricsScreen),
      matching: find.byType(ListView),
    ),
  );
  final padding = list.padding;
  return padding is EdgeInsets ? padding : EdgeInsets.zero;
}

void main() {
  group('MeasureSize', () {
    testWidgets('reports the child size after layout', (tester) async {
      final sizes = <Size>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              height: 240,
              width: 100,
              child: MeasureSize(
                onChange: sizes.add,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(sizes, isNotEmpty);
      expect(sizes.last.height, 240);
      expect(sizes.last.width, 100);
    });

    testWidgets('does not re-report an unchanged size', (tester) async {
      // A re-report here schedules a frame per rebuild, so the page never goes
      // idle. That is why the measurement de-jitters before it reports.
      final sizes = <Size>[];
      Widget tree() => MaterialApp(
            home: Center(
              child: SizedBox(
                height: 240,
                width: 100,
                child: MeasureSize(
                  onChange: sizes.add,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          );

      await tester.pumpWidget(tree());
      await tester.pump();
      final afterFirst = sizes.length;
      expect(afterFirst, greaterThan(0));

      await tester.pumpWidget(tree());
      await tester.pump();

      expect(sizes.length, afterFirst);
    });

    testWidgets('reports a real change', (tester) async {
      final sizes = <Size>[];
      Widget tree(double height) => MaterialApp(
            home: Center(
              child: SizedBox(
                height: height,
                width: 100,
                child: MeasureSize(
                  onChange: sizes.add,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          );

      await tester.pumpWidget(tree(240));
      await tester.pump();
      await tester.pumpWidget(tree(360));
      await tester.pump();

      expect(sizes.last.height, 360);
    });

    testWidgets('a reporting child does not schedule a build mid-frame',
        (tester) async {
      // The failure this guards against is subtle and fatal: notifying straight
      // from layout makes the caller rebuild, which schedules a frame from
      // inside the frame being painted.
      //
      // The builder deliberately does NOT feed the measured value back into the
      // measured subtree's own size - that is a genuine layout loop, not the
      // property under test, and it would fail for reasons of its own.
      final seen = <double>[];
      final notifier = ValueNotifier<double>(0);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 200,
            child: MeasureSize(
              onChange: (size) => notifier.value = size.height,
              child: ValueListenableBuilder<double>(
                valueListenable: notifier,
                builder: (context, value, _) {
                  seen.add(value);
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Reported at all, after the frame rather than during it.
      expect(seen, isNotEmpty);
    });
  });

  group('the lyric panel clears the deck', () {
    testWidgets('reserves the measured deck height at the foot', (tester) async {
      // THE BUG THIS PINS: the lyric list is full-page while the player deck is
      // an overlay above it, so with no inset the last lines of every lyric
      // scrolled underneath the seek bar.
      await tester.pumpWidget(_screen(bottomInset: 420));
      await tester.pump();

      expect(_listPadding(tester).bottom, greaterThanOrEqualTo(420));
    });

    testWidgets('a zero inset leaves only the base padding', (tester) async {
      await tester.pumpWidget(_screen());
      await tester.pump();

      // The base 8dp, not a deck's worth: a lyrics screen with nothing above it
      // must not reserve room for one.
      expect(_listPadding(tester).bottom, lessThan(24));
    });

    testWidgets('the top still clears the header discs', (tester) async {
      // Star and options are pinned in the player header, so the first lines of
      // a song scroll up beside them rather than under them.
      await tester.pumpWidget(_screen());
      await tester.pump();

      expect(_listPadding(tester).top, greaterThanOrEqualTo(48));
    });
  });
}