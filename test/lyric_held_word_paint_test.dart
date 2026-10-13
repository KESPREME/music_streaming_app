// What a held word actually DRAWS. Found on a device: the letters of a held word
// were the whole line's paragraph clipped to each letter's caret box. With the
// lyric's tracking and kerning a glyph's ink spills past that box, so the clip
// cut ink off (a flat edge on the first "s", "y"'s arm, "f"'s hook) and let a
// neighbour's overhang through, which then moved with the WRONG letter's lift -
// a ghost sliver beside the real glyph. Each letter is now its own glyph.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyric_clock.dart';
import 'package:music_streaming_app/services/lyrics/lyric_words.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_line.dart';

void main() {
  group('the lean stays inside the row', () {
    double lean({
      required double want,
      double left = 0,
      double right = 20,
      double scale = 1.08,
    }) =>
        clampLean(
          want: want,
          left: left,
          right: right,
          rowLeft: 0,
          rowRight: 300,
          scale: scale,
        );

    test('the first letter of a row does not lean out past the margin', () {
      final dx = lean(want: -6);
      // After scaling about its centre its left edge may not be left of the row.
      final leftEdge = 10 + dx - 10 * 1.08;
      expect(leftEdge, greaterThanOrEqualTo(-1e-9));
    });

    test('the last letter of a row does not lean out past the right edge', () {
      final dx = lean(want: 6, left: 280, right: 300);
      final rightEdge = 290 + dx + 10 * 1.08;
      expect(rightEdge, lessThanOrEqualTo(300 + 1e-9));
    });

    test('a letter in the middle leans as asked', () {
      expect(lean(want: 3.5, left: 140, right: 160), 3.5);
      expect(lean(want: -3.5, left: 140, right: 160), -3.5);
    });
  });

  testWidgets('a held word\'s letters are drawn whole, with no neighbour\'s '
      'overhang riding on them', (tester) async {
    final font = FontLoader('PJS')
      ..addFont(Future.value(ByteData.sublistView(
          File('assets/google_fonts/PlusJakartaSans-ExtraBold.ttf')
              .readAsBytesSync())));
    await tester.runAsync(font.load);

    final clock = LyricClock(now: () => 0);
    addTearDown(clock.dispose);
    final words = wordsFromWordTimings([
      (timeMs: 0, durationMs: 4000, text: 'skyfall'),
    ]);
    final entry =
        LyricsEntry(timeMs: 0, text: 'skyfall', endMs: 4000, lyricWords: words);
    final key = GlobalKey();

    Widget app(int lifted) => MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: RepaintBoundary(
              key: key,
              child: Container(
                color: Colors.black,
                padding: const EdgeInsets.fromLTRB(30, 30, 30, 30),
                alignment: Alignment.centerLeft,
                child: LyricLine(
                  entry: entry,
                  clock: clock,
                  style: const TextStyle(
                    fontFamily: 'PJS',
                    fontSize: 44,
                    height: 1.22,
                    letterSpacing: -0.64,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  rise: true,
                  glow: false,
                  feather: false,
                ),
              ),
            ),
          ),
        );

    await tester.binding.setSurfaceSize(const Size(420, 130));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(0));

    // Mid-hold: the wave is on several letters at once, each at a different
    // lift - the situation in which a neighbour's sliver shows.
    clock.reset(2600);
    await tester.pump();

    final image = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      return boundary.toImage(pixelRatio: 2.0);
    });
    final data = (await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    final w = image!.width;
    final h = image.height;

    // The left margin of the text column: nothing may be inked left of it. The
    // first letter used to lean out of the column and be cut flat there.
    const marginPx = 30 * 2;
    var inkLeftOfMargin = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < marginPx - 2; x++) {
        final a = data.getUint8((y * w + x) * 4 + 3);
        final r = data.getUint8((y * w + x) * 4);
        if (a > 40 && r > 40) inkLeftOfMargin++;
      }
    }
    expect(inkLeftOfMargin, 0,
        reason: 'a letter leaned out past the text column');
  });
}
