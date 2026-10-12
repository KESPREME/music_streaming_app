import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:music_streaming_app/widgets/lyric_line/animated_lyric_row.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_line_style.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_typography.dart';

/// Stand-in for the Jakarta face so the sizes can be read without resolving it.
TextStyle _stubFont(double fontSize, FontWeight weight) =>
    TextStyle(fontSize: fontSize, fontWeight: weight);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the falloff ladders', () {
    test('alpha never falls below the readable floor', () {
      // A line that fades to invisible cannot be read without scrolling.
      for (var d = 0; d < 50; d++) {
        expect(LyricLineStyle.alphaForDistance(d), greaterThanOrEqualTo(0.46),
            reason: 'distance $d');
      }
    });

    test('the ladder is BitChord\'s, to the digit', () {
      expect(LyricLineStyle.alphaLadder, [1.0, 0.8, 0.7, 0.58, 0.46]);
      expect(LyricLineStyle.blurLadder, [0.0, 1.0, 1.0, 1.7, 2.4]);
      expect(LyricLineStyle.inactiveScale, 0.98);
      expect(LyricLineStyle.browsingAlpha, 0.8);
    });

    test('lines ABOVE the active one are on the ladder too', () {
      // The old panel passed a SIGNED distance, and `alphaForDistance` returns
      // full alpha for anything <= 0 - so every line already sung stayed at 1.0
      // and only the upcoming lines faded. The caller now passes |distance|.
      expect(
        LyricLineStyle.alphaFor(distance: 3, isBrowsing: false, isSynced: true),
        LyricLineStyle.alphaForDistance(3),
      );
      expect(LyricLineStyle.alphaForDistance(-3), 1.0,
          reason: 'documents WHY the caller must take abs()');
    });

    test('blur is capped so distant lines stay legible', () {
      for (var d = 0; d < 50; d++) {
        expect(LyricLineStyle.blurForDistance(d), lessThanOrEqualTo(2.4));
      }
    });

    test('browsing lifts blur to zero at any distance', () {
      for (var d = 0; d < 20; d++) {
        expect(LyricLineStyle.blurFor(distance: d, isBrowsing: true), 0.0);
      }
    });

    test('browsing flattens every line to one uniform alpha', () {
      final resting = {
        for (var d = 1; d < 6; d++) LyricLineStyle.alphaForDistance(d),
      };
      expect(resting.length, greaterThan(1), reason: 'at rest it must vary');

      final browsing = {
        for (var d = 1; d < 6; d++)
          LyricLineStyle.alphaFor(distance: d, isBrowsing: true, isSynced: true),
      };
      expect(browsing, {0.8});
      // A lift, not a dim: browsing is never darker than rest.
      for (var d = 1; d < 6; d++) {
        expect(
          LyricLineStyle.alphaFor(distance: d, isBrowsing: true, isSynced: true),
          greaterThanOrEqualTo(
            LyricLineStyle.alphaFor(distance: d, isBrowsing: false, isSynced: true),
          ),
        );
      }
    });

    test('an unsynced lyric stays readable rather than faded to the floor', () {
      expect(
        LyricLineStyle.alphaFor(distance: 3, isBrowsing: false, isSynced: false),
        LyricLineStyle.unsyncedAlpha,
      );
    });

    test('every dimension settles on ONE spec, and it never overshoots', () {
      expect(LyricLineStyle.lyricSettle, const Duration(milliseconds: 400));
      expect(LyricLineStyle.lyricEase, isA<Cubic>());
      expect(LyricLineStyle.lyricEase.transform(0.0), 0.0);
      expect(LyricLineStyle.lyricEase.transform(1.0), 1.0);
      var previous = -1.0;
      for (var i = 0; i <= 40; i++) {
        final v = LyricLineStyle.lyricEase.transform(i / 40);
        expect(v, greaterThanOrEqualTo(previous));
        expect(v, lessThanOrEqualTo(1.0));
        previous = v;
      }
    });
  });

  group('the blur radius becomes a Skia sigma the way Android does it', () {
    test('zero stays zero', () {
      expect(LyricLineStyle.sigmaFor(0, 2.75), 0.0);
    });

    test('HWUI: sigma = 0.57735 * radius_px + 0.5, in logical px', () {
      // 1dp on a 2.75 device is 2.75 device px of radius -> sigma 2.088 px ->
      // 0.759 logical px.
      expect(LyricLineStyle.sigmaFor(1.0, 2.75), closeTo(0.759, 0.005));
      expect(LyricLineStyle.sigmaFor(2.4, 2.75), closeTo(1.567, 0.005));
    });

    test('is always below the naive sigma = radius at these sizes', () {
      for (final r in LyricLineStyle.blurLadder.where((r) => r > 0)) {
        expect(LyricLineStyle.sigmaFor(r, 2.75), lessThan(r),
            reason: 'feeding the ladder straight in over-blurs');
      }
    });
  });

  group('typography', () {
    test('ONE size and weight for a synced line at every distance', () {
      // The font must not change between active and inactive: a different face
      // invalidates the cached glyph geometry on every handover. Emphasis is
      // alpha, blur and scale, which are free.
      final style = LyricTypography.synced(fontBuilder: _stubFont);
      expect(style.fontSize, 32);
      expect(style.fontWeight, FontWeight.w800);
      expect(style.height, 1.22);
      expect(style.letterSpacing, closeTo(-0.64, 0.001));
      expect(LyricLineStyle.scaleFor(distance: 0), 1.0);
      expect(LyricLineStyle.scaleFor(distance: 4), 0.98);
    });

    test('every role is defined here and only here', () {
      expect(LyricTypography.strip(fontBuilder: _stubFont).fontSize, 17);
      expect(LyricTypography.subLine(fontBuilder: _stubFont).fontSize, 19);
      expect(LyricTypography.unsynced(fontBuilder: _stubFont).fontSize, 28);
      expect(LyricTypography.background(fontBuilder: _stubFont).fontSize, 22);
      expect(LyricTypography.caption(fontBuilder: _stubFont).fontSize, 15);
    });

    test('the real face is Plus Jakarta Sans, not a fallback', () {
      expect(LyricTypography.synced().fontFamily, contains('PlusJakartaSans'));
    });

    test('the face is BUNDLED, so no line re-lays-out when a download lands',
        () {
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
        expect(
          File('assets/google_fonts/PlusJakartaSans-$weight.ttf').existsSync(),
          isTrue,
          reason: '$weight must ship in the app',
        );
      }
      expect(File('assets/google_fonts/OFL.txt').existsSync(), isTrue,
          reason: 'the licence ships with the font');
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('assets/google_fonts/'));
    });
  });

  group('AnimatedLyricRow', () {
    testWidgets('a handover mid-settle continues from what is on screen',
        (tester) async {
      var alpha = 1.0;
      final seen = <double>[];
      late StateSetter set;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return AnimatedLyricRow(
                alpha: alpha,
                blurDp: 0,
                scale: 1,
                lit: 1,
                builder: (context, v) {
                  seen.add(v.alpha);
                  return const SizedBox(width: 10, height: 10);
                },
              );
            },
          ),
        ),
      );

      set(() => alpha = 0.4);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final midway = seen.last;
      expect(midway, lessThan(1.0));
      expect(midway, greaterThan(0.4));

      // Reverse course 160ms in. A row that restarted from the old TARGET would
      // jump here.
      set(() => alpha = 1.0);
      await tester.pump();
      expect((seen.last - midway).abs(), lessThan(0.05),
          reason: 'continues from the on-screen value, no jump');

      await tester.pump(const Duration(milliseconds: 500));
      expect(seen.last, closeTo(1.0, 0.001));
    });

    testWidgets('settled, it draws exactly its targets', (tester) async {
      late LyricRowValues values;
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedLyricRow(
            alpha: 0.58,
            blurDp: 1.7,
            scale: 0.98,
            lit: 0,
            builder: (context, v) {
              values = v;
              return const SizedBox(width: 10, height: 10);
            },
          ),
        ),
      );
      expect(values.alpha, 0.58);
      expect(values.lit, 0);
      expect(values.blurSigma, greaterThan(0));
    });
  });
}
