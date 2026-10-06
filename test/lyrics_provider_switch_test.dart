import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/lyrics_screen.dart';
import 'package:music_streaming_app/widgets/lyric_swept_line.dart';

/// A provider whose lyric list can be swapped under the screen, the way
/// `useLyricsProvider` swaps it: same track, different words.
class _SwitchableLyricsProvider extends MusicProvider {
  _SwitchableLyricsProvider(this.lines);

  List<LyricsEntry> lines;
  bool loading = false;

  /// Swaps the words and says so, which is what `useLyricsProvider` does.
  void swapTo(List<LyricsEntry> next) {
    lines = next;
    notifyListeners();
  }

  void setLoading(bool value) {
    loading = value;
    notifyListeners();
  }

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
  bool get isLoadingLyrics => loading;

  @override
  List<LyricsEntry>? get currentLyrics => lines;

  @override
  bool get hasSyncedLyrics => true;

  @override
  double get playbackSpeed => 1.0;
}

List<LyricsEntry> _lines(List<String> texts, {int stepMs = 1000}) => [
      for (var i = 0; i < texts.length; i++)
        LyricsEntry(
          timeMs: i * stepMs,
          endMs: (i + 1) * stepMs,
          text: texts[i],
          words: [
            WordTiming(timeMs: i * stepMs, durationMs: stepMs, text: texts[i]),
          ],
        ),
    ];

/// The entry text of every lyric row currently laid out.
List<String?> _renderedTexts(WidgetTester tester) {
  final widgets = tester.widgetList<LyricSweptLine>(
    find.byType(LyricSweptLine),
  );
  return widgets.map((w) => w.entry.text).toList();
}

int _activeCount(WidgetTester tester) => tester
    .widgetList<LyricSweptLine>(find.byType(LyricSweptLine))
    .where((w) => w.isActive)
    .length;

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget tree(_SwitchableLyricsProvider p) =>
      ChangeNotifierProvider<MusicProvider>.value(
        value: p,
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

  testWidgets('a shorter lyric from another provider replaces the old one',
      (tester) async {
    // THE BUG THIS PINS. Changing provider changes the WORDS, not the track, so
    // nothing in the track-change path fires. The per-line keys were sized to the
    // first list and stayed sized to it, and every row past the end of the second
    // list had already been holding a key that no longer belonged to it.
    final provider = _SwitchableLyricsProvider(
      _lines(['one', 'two', 'three', 'four']),
    );
    await tester.pumpWidget(tree(provider));
    await tester.pump();

    expect(_renderedTexts(tester), hasLength(4));

    // Fewer lines, and the list is rebuilt from scratch because the key LENGTH
    // changed. Four lines' worth of state cannot survive onto two.
    provider.swapTo(_lines(['alpha', 'beta']));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_renderedTexts(tester), hasLength(2));
    expect(_renderedTexts(tester), containsAllInOrder(['alpha', 'beta']));
  });

  testWidgets('a longer lyric from another provider adds its rows',
      (tester) async {
    final provider = _SwitchableLyricsProvider(_lines(['one', 'two']));
    await tester.pumpWidget(tree(provider));
    await tester.pump();
    expect(_renderedTexts(tester), hasLength(2));

    provider.swapTo(_lines(['a', 'b', 'c', 'd', 'e', 'f']));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_renderedTexts(tester), hasLength(6));
  });

  testWidgets('swapping to the very same list is a no-op, not a rebuild storm',
      (tester) async {
    // Rebuilding per-line state on every unrelated build would re-measure every
    // visible line for nothing, so the list is adopted by IDENTITY. Holding the
    // same list instance must not disturb what is on screen.
    final provider = _SwitchableLyricsProvider(_lines(['one', 'two', 'three']));
    await tester.pumpWidget(tree(provider));
    await tester.pump();
    final before = _renderedTexts(tester);

    await tester.pump(); // an unrelated frame
    await tester.pump();

    expect(_renderedTexts(tester), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exactly one line is active after a swap', (tester) async {
    // The active line is an INDEX. Carried across from a list of a different
    // shape it points at a different line, or past the end of the new one.
    final provider = _SwitchableLyricsProvider(
      _lines(['one', 'two', 'three', 'four']),
    );
    await tester.pumpWidget(tree(provider));
    await tester.pump();

    provider.swapTo(_lines(['alpha', 'beta', 'gamma']));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_activeCount(tester), 1);
  });

  testWidgets('lyrics that arrive while still loading settle onto the rows',
      (tester) async {
    // A provider switch is not a one-frame event: the screen draws the spinner
    // while fetching, then the new list arrives a moment later. This pins that
    // sequence to settle on the NEW rows without an exception, rather than
    // holding a stale list or crashing on a length mismatch.
    final provider = _SwitchableLyricsProvider(_lines(['one', 'two']));
    await tester.pumpWidget(tree(provider));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    provider.setLoading(true);
    provider.swapTo(_lines(['alpha', 'beta', 'gamma']));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);

    provider.setLoading(false);
    await tester.pump();
    await tester.pump();

    expect(_renderedTexts(tester), containsAllInOrder(['alpha', 'beta', 'gamma']));
  });
}