import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/lyrics_screen.dart';
import 'package:music_streaming_app/widgets/lyrics_mode_discs.dart';

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
  bool get isPlaying => false;

  @override
  bool get isLoadingLyrics => false;

  @override
  List<LyricsEntry>? get currentLyrics => lines;

  @override
  bool get hasSyncedLyrics => true;
}

List<LyricsEntry> _lyric() => [
      for (var i = 0; i < 12; i++)
        LyricsEntry(
          timeMs: i * 2000,
          endMs: i * 2000 + 1800,
          text: 'line number ${i + 1}',
          words: [
            WordTiming(timeMs: i * 2000, durationMs: 600, text: 'line'),
            WordTiming(timeMs: i * 2000 + 600, durationMs: 600, text: 'number'),
            WordTiming(timeMs: i * 2000 + 1200, durationMs: 600, text: '${i + 1}'),
          ],
        ),
    ];

Widget _screen({bool? discsVisible}) =>
    ChangeNotifierProvider<MusicProvider>.value(
      value: _LyricsProvider(_lyric()),
      child: MaterialApp(
        home: Scaffold(
          body: LyricsScreen(
            isEmbedded: true,
            showHeader: false,
            showBottomScrubber: false,
            discsVisible: discsVisible,
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
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the lyric panel ends where the deck begins', () {
    // Inside the player this panel is the page ABOVE the deck - a sibling in a
    // column - so its area already stops at the deck. It used to be handed the
    // deck's height as well and reserve it a second time, which pushed the
    // globe/translate discs a deck-height up off the bottom.

    testWidgets('the only bottom clearance is the viewport tail', (tester) async {
      // BitChord reserves 80% of its own viewport under the content
      // (PlayerLyrics.kt:1796) so a reader at the end of the song can read the
      // last line rather than half of it. There is no deck term on top of that.
      await tester.pumpWidget(_screen());
      await tester.pump();

      final viewport = tester.getSize(find.byType(ListView)).height;
      expect(_listPadding(tester).bottom, closeTo(viewport * 0.8, 1));
    });

    testWidgets('the sung line is anchored well below the top edge, with the '
        'line before it peeking in above', (tester) async {
      await tester.pumpWidget(_screen());
      await tester.pump();

      expect(_listPadding(tester).top, greaterThanOrEqualTo(96));
    });

    testWidgets('the text sits in BitChord\'s 30dp gutter', (tester) async {
      await tester.pumpWidget(_screen());
      await tester.pump();

      // 18 list padding + 6 inside the row = 24; the row's own 6 above the
      // paint headroom makes the text start at 30 from the edge.
      final padding = _listPadding(tester);
      expect(padding.left, 18);
      expect(padding.right, 18);
    });

    testWidgets('a line is not cut by a hard edge: the top and bottom 28dp '
        'dissolve', (tester) async {
      await tester.pumpWidget(_screen());
      await tester.pump();

      final mask = tester.widget<ShaderMask>(
        find.ancestor(
          of: find.byType(ListView),
          matching: find.byType(ShaderMask),
        ),
      );
      expect(mask.blendMode, BlendMode.dstIn,
          reason: 'the mask multiplies the list by the gradient');

      // The gradient is opaque in the middle and clear at both ends, over 28dp.
      final height = tester.getSize(find.byType(ListView)).height;
      final shader = mask.shaderCallback(Rect.fromLTWH(0, 0, 100, height));
      expect(shader, isNotNull);
    });

    testWidgets('nothing translucent sits above the discs', (tester) async {
      // The fade is an offscreen layer. Whatever is under it is composited into
      // it - and a backdrop lens under a translucent layer goes flat. The discs
      // are outside it.
      await tester.pumpWidget(_screen(discsVisible: true));
      await tester.pump();

      expect(
        find.ancestor(
          of: find.byType(TransformDisc),
          matching: find.byType(ShaderMask),
        ),
        findsNothing,
      );
    });
  });

  group('the globe and translate discs', () {
    testWidgets('sit 12dp above the panel\'s own bottom - no deck inset',
        (tester) async {
      await tester.pumpWidget(_screen(discsVisible: true));
      await tester.pump();

      final listBox = tester.getRect(find.byType(ListView));
      final discs = tester.widgetList(find.byType(TransformDisc)).length;
      expect(discs, 2);

      for (final disc in find.byType(TransformDisc).evaluate()) {
        final rect = tester.getRect(find.byWidget(disc.widget));
        expect(listBox.bottom - rect.bottom, closeTo(12, 1),
            reason: 'at the panel foot - not a deck-height up the screen');
      }
      // One at each side, in the text gutter.
      final rects = [
        for (final d in find.byType(TransformDisc).evaluate())
          tester.getRect(find.byWidget(d.widget)),
      ]..sort((a, b) => a.left.compareTo(b.left));
      expect(rects.first.left, closeTo(listBox.left + 24, 1));
      expect(rects.last.right, closeTo(listBox.right - 24, 1));
    });

    testWidgets('the caller decides when they show', (tester) async {
      await tester.pumpWidget(_screen(discsVisible: false));
      await tester.pump(const Duration(milliseconds: 300));

      final reveal =
          tester.widget<LyricsDiscReveal>(find.byType(LyricsDiscReveal).first);
      expect(reveal.visible, isFalse);
      // Hidden means untouchable too, not just transparent.
      final ignore = tester.widget<IgnorePointer>(
        find
            .descendant(
              of: find.byType(LyricsDiscReveal).first,
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignore.ignoring, isTrue);

      await tester.pumpWidget(_screen(discsVisible: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<LyricsDiscReveal>(find.byType(LyricsDiscReveal).first).visible,
        isTrue,
      );
    });

    testWidgets('they fade and scale with the controls, not pop', (tester) async {
      await tester.pumpWidget(_screen(discsVisible: false));
      await tester.pump(const Duration(milliseconds: 300));

      Widget with0(bool visible) => ChangeNotifierProvider<MusicProvider>.value(
            value: _LyricsProvider(_lyric()),
            child: MaterialApp(
              home: Scaffold(
                body: LyricsScreen(
                  isEmbedded: true,
                  showHeader: false,
                  showBottomScrubber: false,
                  discsVisible: visible,
                ),
              ),
            ),
          );

      await tester.pumpWidget(with0(true));
      await tester.pump(const Duration(milliseconds: 80));
      final fade = tester.renderObject<RenderAnimatedOpacity>(
        find
            .descendant(
              of: find.byType(LyricsDiscReveal).first,
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );
      expect(fade.opacity.value, inExclusiveRange(0.0, 1.0),
          reason: '80ms into a 220ms arrival the disc is part-way, not popped');
      expect(lyricsDiscFadeIn, const Duration(milliseconds: 220));
      expect(lyricsDiscFadeOut, const Duration(milliseconds: 160));
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
