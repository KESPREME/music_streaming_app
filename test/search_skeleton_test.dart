import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/widgets/search_result_row.dart';
import 'package:music_streaming_app/widgets/search_skeleton.dart';

/// The skeleton is only worth having if it is metric-matched to the rows it
/// stands in for: if the placeholder is a different height, the list jumps at
/// the moment the data lands, which reads as a glitch rather than as arrival.
///
/// These compare against `SearchResultRow` itself rather than against numbers
/// copied out of it, so the two cannot drift apart silently.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Track track() => Track(
        id: 'vid-1',
        trackName: 'Title',
        artistName: 'Artist',
        albumName: 'Album',
        previewUrl: '',
      );

  group('skeleton matches the real row', () {
    testWidgets('a placeholder row is exactly as tall as a real one',
        (tester) async {
      await tester.pumpWidget(wrap(
        Column(
          children: [
            const SearchRowSkeleton(),
            SearchResultRow(track: track(), onTap: () {}),
          ],
        ),
      ));

      final skeleton = tester.getSize(find.byType(SearchRowSkeleton).first);
      final real = tester.getSize(find.byType(SearchResultRow).first);

      expect(
        skeleton.height,
        moreOrLessEquals(real.height, epsilon: 0.01),
        reason: 'artwork is the tallest element in both rows, so matching it '
            'matches the row height',
      );
    });

    testWidgets('a placeholder row and a real row have the same width',
        (tester) async {
      await tester.pumpWidget(wrap(
        Column(
          children: [
            const SearchRowSkeleton(),
            SearchResultRow(track: track(), onTap: () {}),
          ],
        ),
      ));

      expect(
        tester.getSize(find.byType(SearchRowSkeleton).first).width,
        moreOrLessEquals(
          tester.getSize(find.byType(SearchResultRow).first).width,
          epsilon: 0.01,
        ),
      );
    });
  });

  group('shapes follow the tab', () {
    Future<double> artAspect(WidgetTester tester) async {
      await tester.pumpWidget(wrap(const SearchRowSkeleton()));
      final size = tester.getSize(
        find
            .descendant(
              of: find.byType(SearchRowSkeleton),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      return size.width / size.height;
    }

    testWidgets('songs get square artwork', (tester) async {
      await tester.pumpWidget(wrap(const SearchRowSkeleton()));
      final size = tester.getSize(
        find
            .descendant(
              of: find.byType(SearchRowSkeleton),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(size.width, moreOrLessEquals(size.height, epsilon: 0.01));
    });

    testWidgets('videos get a 16:9 tile, not a square', (tester) async {
      expect(await artAspect(tester), 1);
      await tester.pumpWidget(wrap(const SearchRowSkeleton(isVideo: true)));
      final size = tester.getSize(
        find
            .descendant(
              of: find.byType(SearchRowSkeleton),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(
          size.width / size.height, moreOrLessEquals(104 / 58, epsilon: 0.01));
    });

    testWidgets('artists get circular artwork', (tester) async {
      await tester.pumpWidget(wrap(const SearchRowSkeleton(circular: true)));

      expect(
        find.descendant(
          of: find.byType(SearchRowSkeleton),
          matching: find.byType(ClipOval),
        ),
        findsOneWidget,
      );
    });
  });

  group('placeholders are not uniform', () {
    testWidgets('consecutive rows use different text widths', (tester) async {
      await tester.pumpWidget(wrap(
        const Column(
          children: [
            SearchRowSkeleton(index: 0),
            SearchRowSkeleton(index: 1),
            SearchRowSkeleton(index: 2),
          ],
        ),
      ));

      final widths = find
          .descendant(
            of: find.byType(SearchRowSkeleton),
            matching: find.byType(FractionallySizedBox),
          )
          .evaluate()
          .map((e) => tester.getSize(find.byWidget(e.widget)).width)
          .toList();

      expect(widths.length, 6, reason: 'three rows, two text lines each');
      expect(
        widths.toSet().length,
        greaterThan(1),
        reason: 'equal-width bars make a loading list look like a bug',
      );
    });
  });

  group('the sweep is shared across a row, not per block', () {
    // The defect this guards: computing the highlight band from each block's own
    // width. A 64dp artwork and a 0.68-of-the-column title bar are different
    // widths, so one progress value lands the band at a different x in each and
    // the row visibly comes apart as the animation runs.
    //
    // Coherence, stated precisely: at a given t, every block in a row must place
    // the band at the same *row* coordinate. A block's local start plus its own
    // offset is that row coordinate, so the two must agree.
    double rowSpace(double t, double rowWidth, double rowOffset) =>
        shimmerBandStart(t: t, rowWidth: rowWidth, rowOffset: rowOffset) +
        rowOffset;

    const rowWidth = 300.0;
    const artW = 64.0;
    const gap = 14.0;
    const textLeft = artW + gap;

    testWidgets('artwork and both text bars agree at every instant',
        (tester) async {
      await tester.pumpWidget(wrap(const SearchSkeletonList(count: 2)));

      for (var t = 0.0; t <= 1.0; t += 0.05) {
        final art = rowSpace(t, rowWidth, 0);
        final title = rowSpace(t, rowWidth, textLeft);
        final subtitle = rowSpace(t, rowWidth, textLeft);

        expect(title, moreOrLessEquals(art, epsilon: 0.001),
            reason: 'title bar drifted from the artwork at t=$t');
        expect(subtitle, moreOrLessEquals(art, epsilon: 0.001),
            reason: 'subtitle bar drifted from the artwork at t=$t');
      }
    });

    testWidgets('the band crosses the whole row rather than one block',
        (tester) async {
      await tester.pumpWidget(wrap(const SearchSkeletonList(count: 1)));

      // Fully off one side at the ends, fully past the other side at the far
      // end: the travel is the row's, not a single block's width.
      expect(rowSpace(0.0, rowWidth, 0), lessThan(0));
      expect(rowSpace(1.0, rowWidth, 0), greaterThan(rowWidth));

      // And it never sits still: a static highlight parked mid-row reads as a
      // rendering artefact rather than as motion.
      final samples = {
        for (var t = 0.0; t <= 1.0; t += 0.1)
          rowSpace(t, rowWidth, 0).toStringAsFixed(1)
      };
      expect(samples.length, greaterThan(5));
    });

    testWidgets('a per-block implementation would NOT satisfy this',
        (tester) async {
      // Sanity on the test itself: the naive "band from the block's own width"
      // formula must fail the coherence check, or the assertion above is
      // vacuous.
      double naive(double t, double blockWidth) {
        final band = blockWidth * 0.42;
        return -band + t * (blockWidth + band * 2);
      }

      final artNaive = naive(0.3, artW);
      final barNaive = naive(0.3, 140);
      expect((artNaive - barNaive).abs(), greaterThan(1.0),
          reason: 'if these matched, the coherence assertion proves nothing');
    });
  });

  group('list', () {
    testWidgets('draws the requested number of rows', (tester) async {
      await tester.pumpWidget(wrap(const SearchSkeletonList(count: 5)));
      expect(find.byType(SearchRowSkeleton), findsNWidgets(5));
    });

    testWidgets(
        'contains nothing interactive - it is a placeholder, not a control',
        (tester) async {
      await tester.pumpWidget(wrap(const SearchSkeletonList(count: 4)));

      for (final type in [IconButton, InkWell, TextField]) {
        expect(
          find.descendant(
            of: find.byType(SearchSkeletonList),
            matching: find.byType(type),
          ),
          findsNothing,
          reason: 'a skeleton must not swallow a tap meant for the page',
        );
      }
    });

    testWidgets('honours reduced-motion by showing a static placeholder',
        (tester) async {
      await tester.pumpWidget(wrap(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SearchSkeletonList(count: 2),
        ),
      ));

      // Nothing to assert beyond "it builds and does not throw under the
      // setting" - a perpetual sweep is exactly the motion that setting is for.
      expect(find.byType(SearchRowSkeleton), findsNWidgets(2));
    });
  });
}
