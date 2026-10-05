import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/presentation/home/home_tokens.dart' as t;
import 'package:music_streaming_app/presentation/home/home_view_mode.dart';
import 'package:music_streaming_app/widgets/home_sections.dart';
import 'package:music_streaming_app/widgets/section_view_toggle.dart';
import 'package:music_streaming_app/widgets/track_list_column.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mode defaults', () {
    test('a fresh install opens both shelves as cards', () {
      final store = HomeViewModeStore();
      expect(store.modeOf(HomeViewSection.jumpBackIn),
          HomeSectionViewMode.card);
      expect(
          store.modeOf(HomeViewSection.quickPicks), HomeSectionViewMode.card);
    });

    test('the two shelves are independent', () {
      final store = HomeViewModeStore();
      store.toggle(HomeViewSection.jumpBackIn);
      expect(store.modeOf(HomeViewSection.jumpBackIn),
          HomeSectionViewMode.list);
      expect(
          store.modeOf(HomeViewSection.quickPicks), HomeSectionViewMode.card);
    });
  });

  group('persistence', () {
    testWidgets('a toggle survives a reload', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = HomeViewModeStore(prefs: prefs);
      await first.toggle(HomeViewSection.quickPicks);

      // A second store over the same store is what a relaunch looks like.
      final second = HomeViewModeStore(prefs: prefs);
      await second.initialize();
      expect(second.modeOf(HomeViewSection.quickPicks),
          HomeSectionViewMode.list);
    });

    test('the two sections use distinct keys', () {
      // One shared key would mean toggling one shelf silently re-lays-out the
      // other on the next launch.
      expect(HomeViewSection.jumpBackIn.storageKey,
          isNot(HomeViewSection.quickPicks.storageKey));
    });

    testWidgets('an unrecognised stored value falls back to the default',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        HomeViewSection.jumpBackIn.storageKey: 'grid',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = HomeViewModeStore(prefs: prefs);
      await store.initialize();
      expect(store.modeOf(HomeViewSection.jumpBackIn),
          HomeSectionViewMode.card);
    });
  });

  group('toggle control', () {
    Future<void> mount(WidgetTester tester, HomeSectionViewMode mode,
        VoidCallback onToggle) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SectionViewToggle(mode: mode, onToggle: onToggle),
        ),
      ));
    }

    testWidgets('the icon offers the layout it will switch TO', (tester) async {
      await mount(tester, HomeSectionViewMode.list, () {});
      // Showing list means "you are in list mode, tap for cards".
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    });

    /// The toggle's own Semantics node, not one MaterialApp injects above it.
    String? labelOf(WidgetTester tester) {
      return tester
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byType(SectionViewToggle),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .label;
    }

    testWidgets('the label names the destination', (tester) async {
      await mount(tester, HomeSectionViewMode.list, () {});
      // The label must describe the layout the tap PRODUCES, not the one on
      // screen. A screen reader announcing "switch to card view" while the user
      // is looking at a card rail is the opposite of helpful.
      expect(labelOf(tester), 'Switch to card view');
    });

    testWidgets('the label follows the mode', (tester) async {
      await mount(tester, HomeSectionViewMode.card, () {});
      expect(labelOf(tester), 'Switch to list view');
    });

    testWidgets('a tap reports itself and is the only target', (tester) async {
      var taps = 0;
      await mount(tester, HomeSectionViewMode.list, () => taps++);
      await tester.tap(find.byType(SectionViewToggle));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('header trailing slot', () {
    testWidgets('renders a supplied control', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: HomeSectionHeader(
            title: 'Jump back in',
            trailing: Icon(Icons.tune),
          ),
        ),
      ));
      expect(find.text('Jump back in'), findsOneWidget);
      expect(find.byIcon(Icons.tune), findsOneWidget);
    });

    testWidgets('a trailing control replaces "See all"', (tester) async {
      // Both cannot hold the row at once, and the toggle is the primary
      // affordance on a shelf that has one.
      var viewAllTaps = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HomeSectionHeader(
              title: 'Jump back in',
              onViewAll: () => viewAllTaps++,
              trailing: const Icon(Icons.tune),
            ),
          ),
      ));
      expect(find.text('See all'), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });
  });

  group('track list columns', () {
    // Measured inside a real tree because the helper takes a BuildContext.
    Future<double> heightFor(WidgetTester tester, int count) async {
      late double measured;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          measured = trackListColumnsHeight(context, count);
          return const SizedBox.shrink();
        }),
      ));
      return measured;
    }

    final rowHeight = t.HomeTokens.rowArtSize +
        t.HomeTokens.rowVerticalPadding * 2;
    final perColumn = t.HomeTokens.tracksPerColumn;

    testWidgets('reserves exactly the rows it draws', (tester) async {
      expect(await heightFor(tester, 1), rowHeight);
      expect(await heightFor(tester, 3), 3 * rowHeight);
      expect(await heightFor(tester, perColumn), perColumn * rowHeight);
    });

    testWidgets('height never exceeds ONE column', (tester) async {
      // Columns scroll sideways, so more tracks means more columns, not more
      // rows. Treating the count as if it stacked is what left a screen-tall
      // gap under a four-row list: 10 tracks reserved ceil(10/4)*4 = 12 rows
      // where only 4 were ever drawn.
      expect(await heightFor(tester, perColumn * 3), perColumn * rowHeight);
      expect(await heightFor(tester, perColumn * 10),
          perColumn * rowHeight);
    });

    testWidgets('an empty shelf still reserves one column', (tester) async {
      // Deliberately NOT zero, and deliberately a FULL column: the section keeps
      // its shape while its content loads, so the header does not rise to meet
      // an empty gap, and the real content then lands in space already reserved.
      expect(await heightFor(tester, 0), perColumn * rowHeight);
    });

    testWidgets('the rail reserves no more than it draws', (tester) async {
      // The symptom as reported: a four-row list with a screen-tall hole under
      // it. Ten tracks go into three columns of 4/4/2, so the rail is four rows
      // tall - not twelve. Asserted against the rendered widget's actual box so
      // a future edit to the reservation cannot drift from the content again.
      final tracks = _tracks(10);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            // Height derived from the same helper the screen uses, evaluated
            // inside the build so it sees a real context.
            child: Builder(
              builder: (context) => SizedBox(
                width: 390,
                height: trackListColumnsHeight(context, tracks.length),
                child: TrackListColumns(
                  tracks: tracks,
                  onPlay: (_) {},
                  onOptions: (_) {},
                ),
              ),
            ),
          ),
        ),
      ));

      final railHeight = tester.getSize(find.byType(TrackListColumns)).height;
      final perColumn = t.HomeTokens.tracksPerColumn;
      final rowHeight = t.HomeTokens.rowArtSize +
          t.HomeTokens.rowVerticalPadding * 2;
      expect(railHeight, perColumn * rowHeight);

      // Every row really is inside the box: no clipping, no overflow stripes.
      expect(tester.takeException(), isNull);
      expect(find.byType(TrackListRow), findsWidgets);
      final railBottom = tester.getBottomLeft(find.byType(TrackListColumns)).dy;
      final lastRowBottom =
          tester.getBottomLeft(find.byType(TrackListRow).at(perColumn - 1)).dy;
      expect(lastRowBottom, lessThanOrEqualTo(railBottom + 0.5));
    });
  });
}

List<Track> _tracks(int count) => List.generate(
      count,
      (i) => Track(
        id: 'vid${i.toString().padLeft(8, '0')}',
        trackName: 'Track $i',
        artistName: 'Artist $i',
        albumName: 'Album $i',
        previewUrl: '',
      ),
    );
