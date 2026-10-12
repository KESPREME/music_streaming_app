import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/now_playing_screen.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/lyrics_screen.dart';
import 'package:music_streaming_app/widgets/lyrics_mode_discs.dart';

/// THE MORPH THIS FILE PINS.
///
/// Reported: "if I switch lyric it dupes", "sometimes lyric dosent go before the
/// transition", and a capture of lyric text sitting ON TOP of the player header
/// mid-flight.
///
/// All three were one thing. The lyric panel was built on the frame the artwork
/// collapse started and animated in beside it - `translate(40 * (1 - t))`,
/// `scale(0.96 + 0.04 * t)` - while the artwork, the title and the two glass
/// buttons painted over it. Four layers moving at once, with the lyric reading
/// through the artwork on its way past.
///
/// The reference splits it in two: the artwork collapses (420ms), and only then
/// does the panel fade in over a further 200ms with no transform of its own
/// (NowPlayingScreen.kt:1160-1196, 3274-3293).
///
/// Every assertion here drives the REAL widget. An earlier draft re-implemented
/// the layer logic inside the test and asserted against that - which would have
/// stayed green while the screen did exactly the wrong thing.

class _Provider extends MusicProvider {
  _Provider(this.lines);

  final List<LyricsEntry> lines;

  @override
  Track? get currentTrack => Track(
        id: 'track1234567',
        trackName: 'Borderline',
        artistName: 'Tame Impala',
        albumName: 'Currents',
        previewUrl: '',
      );

  @override
  bool get isPlaying => true;

  @override
  Duration get duration => const Duration(minutes: 4);

  @override
  Duration get position => const Duration(seconds: 10);

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  bool get isLoadingLyrics => false;

  @override
  List<LyricsEntry>? get currentLyrics => lines;

  @override
  bool get hasSyncedLyrics => true;

  @override
  bool get isMiniPlayerVisible => false;
}

List<LyricsEntry> _lyric() => [
      for (var i = 0; i < 8; i++)
        LyricsEntry(
          timeMs: i * 4000,
          endMs: i * 4000 + 3000,
          text: 'lyric line ${i + 1}',
          words: [
            WordTiming(timeMs: i * 4000, durationMs: 900, text: 'lyric'),
            WordTiming(timeMs: i * 4000 + 900, durationMs: 900, text: 'line'),
            WordTiming(timeMs: i * 4000 + 1800, durationMs: 900, text: '${i + 1}'),
          ],
        ),
    ];

Widget _screen(_Provider provider) =>
    ChangeNotifierProvider<MusicProvider>.value(
      value: provider,
      child: MaterialApp(
        home: NowPlayingScreen(track: provider.currentTrack!),
      ),
    );

/// How many lyric lines are actually in the tree right now.
///
/// Not `findsNothing`-style booleans: the duplication was TWO lyric layers
/// painted in one frame, so the count is the property.
int _lyricLayersInTree(WidgetTester tester) =>
    find.byType(LyricsScreen).evaluate().length;

/// The opacity the lyric panel is being painted at, or null when it is not there.
double? _panelOpacity(WidgetTester tester) {
  final panels = find.byType(LyricsScreen);
  if (panels.evaluate().isEmpty) return null;
  final ancestors = find
      .ancestor(of: panels.first, matching: find.byType(Opacity))
      .evaluate();
  if (ancestors.isEmpty) return null;
  return tester.widget<Opacity>(find.byWidget(ancestors.first.widget)).opacity;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('the lyric panel arrives after the artwork, not beside it', () {
    testWidgets('no lyric layer exists while the collapse is running',
        (tester) async {
      final provider = _Provider(_lyric());
      await tester.pumpWidget(_screen(provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_lyricLayersInTree(tester), 0, reason: 'player, not lyrics');

      // Tap the artwork to open the lyrics, then walk the whole collapse.
      await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
      await tester.pump();

      const steps = 12;
      for (var i = 1; i <= steps; i++) {
        await tester.pump(const Duration(milliseconds: 35));
        final collapseFinished = (i * 35) >= 420;
        expect(
          _lyricLayersInTree(tester) > 0,
          collapseFinished,
          reason: 'at ${i * 35}ms of a 420ms collapse the lyric panel must be '
              '${collapseFinished ? 'allowed' : 'absent'}; the artwork is still '
              'moving and the lyric reads through it',
        );
      }
    });

    testWidgets('exactly one lyric layer, ever', (tester) async {
      final provider = _Provider(_lyric());
      await tester.pumpWidget(_screen(provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
      await tester.pump();

      // Frame by frame, open AND close. The reported duplication showed two
      // copies of the lyric on screen at once.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(_lyricLayersInTree(tester), lessThanOrEqualTo(1),
            reason: 'frame $i: ${_lyricLayersInTree(tester)} lyric layers');
      }
    });

    testWidgets('the panel fades in once, over its own short window',
        (tester) async {
      final provider = _Provider(_lyric());
      await tester.pumpWidget(_screen(provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
      await tester.pump();

      // Past the collapse: the panel is in the tree and partially faded.
      await tester.pump(const Duration(milliseconds: 430));
      final early = _panelOpacity(tester);
      expect(early, isNotNull, reason: 'the panel must be in the tree by now');
      expect(early, inInclusiveRange(0.0, 1.0));

      await tester.pump(const Duration(milliseconds: 250));
      expect(_panelOpacity(tester), 1.0, reason: 'and fully arrived after it');
    });

    testWidgets('on close the panel goes FIRST and at once, then the artwork '
        'grows back', (tester) async {
      // BitChord hides the panel the instant `lyricsOpen` goes false and only then
      // expands the sleeve (NowPlayingScreen.kt:3274). Reversing both together -
      // which this used to do - left the lyric painted UNDER the artwork as it
      // expanded: "lyrics not gone before the artwork comes".
      final provider = _Provider(_lyric());
      await tester.pumpWidget(_screen(provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
      await tester.pump();

      var arrived = false;
      for (var i = 0; i < 20 && !arrived; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        arrived = _panelOpacity(tester) == 1.0;
      }
      expect(arrived, isTrue, reason: 'the panel must fully arrive');

      // Close it the way a reader does: tap the artwork again.
      await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
      await tester.pump();

      // The very next frame: no lyric on screen at all.
      expect(_lyricLayersInTree(tester), 0,
          reason: 'the panel must be gone before the artwork starts to grow');

      // And it stays gone for the whole of the artwork's return.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(_lyricLayersInTree(tester), 0, reason: 'close frame $i');
      }
    });

    testWidgets('the panel is kept after its first open, so re-opening is '
        'free', (tester) async {
      final provider = _Provider(_lyric());
      await tester.pumpWidget(_screen(provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      Future<void> toggle() async {
        await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
        for (var i = 0; i < 24; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
      }

      await toggle(); // open
      expect(_lyricLayersInTree(tester), 1);
      final first = tester.state(find.byType(LyricsScreen));

      await toggle(); // close
      expect(_lyricLayersInTree(tester), 0, reason: 'hidden');
      expect(find.byType(LyricsScreen, skipOffstage: false), findsOneWidget,
          reason: 'but still mounted, so opening it again builds nothing new');

      await toggle(); // re-open
      expect(_lyricLayersInTree(tester), 1);
      expect(identical(tester.state(find.byType(LyricsScreen)), first), isTrue,
          reason: 'the very same State: no first-frame build on re-open');
    });

    testWidgets('a hidden panel is not on the clock', (tester) async {
      final provider = _Provider(_lyric());
      await tester.pumpWidget(_screen(provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      // The kept panel sits in a muted TickerMode, so its lines drop off the clock
      // and nothing schedules a frame for a screen nobody can see.
      final mode = tester.widget<TickerMode>(
        find
            .ancestor(
              of: find.byType(LyricsScreen, skipOffstage: false),
              matching: find.byType(TickerMode, skipOffstage: false),
            )
            .first,
      );
      expect(mode.enabled, isFalse);
    });
  });
  group('the discs never sit under a translucent layer', () {
    // The panel is faded with an Opacity and the mode discs live inside it. They
    // are flat translucent circles, not glass, so a layer above them cannot flatten
    // anything - but they are held back until the panel has LANDED regardless, or
    // they would fade in twice: once with the panel and once on their own.
    testWidgets('no disc while the panel is still faded', (tester) async {
      final provider = _Provider(_lyric());
      await tester.pumpWidget(_screen(provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('now_playing_album_art')));
      await tester.pump();

      for (var i = 1; i <= 14; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        final opacity = _panelOpacity(tester);
        if (opacity == null) continue;
        final reveal = tester.widget<LyricsDiscReveal>(
          find.byType(LyricsDiscReveal).first,
        );
        expect(
          reveal.visible,
          opacity >= 1.0,
          reason: 'at opacity $opacity the discs must still be held back',
        );
      }
    });
  });
}