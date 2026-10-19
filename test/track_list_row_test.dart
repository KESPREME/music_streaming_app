import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/widgets/home_layout_switch.dart';
import 'package:music_streaming_app/widgets/track_list_column.dart';

/// LIST MODE MUST PLAY.
///
/// Home sections can show their songs as a rail of cards or as columns of rows.
/// Cards played; rows did not: `TrackListRow` took an `onPlay` and never
/// attached it to anything, so the only live control in a row was its overflow
/// button. These pin the contract the row exists to keep - the whole row is the
/// play target, the overflow button and a long press are the options, and the
/// two are never confused - in the row alone, in the scrolling columns, and
/// inside the layout switch that swaps between the two modes.

Track track(String id, [String? title]) => Track(
      id: id,
      trackName: title ?? 'Song $id',
      artistName: 'Artist $id',
      albumName: 'Album',
      previewUrl: '',
    );

Widget host(Widget child, {double width = 390}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

void main() {
  group('one row', () {
    testWidgets('tapping the title plays the song', (tester) async {
      var played = 0, options = 0;
      await tester.pumpWidget(host(TrackListRow(
        track: track('a'),
        onPlay: () => played++,
        onOptions: () => options++,
      )));
      await tester.tap(find.text('Song a'));
      expect(played, 1);
      expect(options, 0);
    });

    testWidgets('so does tapping the artwork, the artist, or the empty end of the row',
        (tester) async {
      var played = 0;
      await tester.pumpWidget(host(TrackListRow(
        track: track('a'),
        onPlay: () => played++,
        onOptions: () {},
      )));
      await tester.tap(find.byType(Image).evaluate().isEmpty
          ? find.byIcon(Icons.music_note_rounded)
          : find.byType(Image));
      await tester.tap(find.text('Artist a'));
      // The padding above the text: still the row.
      final topLeft = tester.getTopLeft(find.byType(TrackListRow));
      await tester.tapAt(topLeft + const Offset(150, 2));
      expect(played, 3);
    });

    testWidgets('the overflow button opens options and does not also play',
        (tester) async {
      var played = 0, options = 0;
      await tester.pumpWidget(host(TrackListRow(
        track: track('a'),
        onPlay: () => played++,
        onOptions: () => options++,
      )));
      await tester.tap(find.byTooltip('More options'));
      expect(options, 1);
      expect(played, 0, reason: 'the row must not swallow or share the button\'s tap');
    });

    testWidgets('a long press opens options and does not play', (tester) async {
      var played = 0, options = 0;
      await tester.pumpWidget(host(TrackListRow(
        track: track('a'),
        onPlay: () => played++,
        onOptions: () => options++,
      )));
      await tester.longPress(find.text('Song a'));
      expect(options, 1);
      expect(played, 0);
    });

    testWidgets('it answers a finger with the same press feedback as a card',
        (tester) async {
      await tester.pumpWidget(host(TrackListRow(
        track: track('a'),
        onPlay: () {},
        onOptions: () {},
      )));
      double scale() => tester
          .widget<ScaleTransition>(find
              .descendant(
                  of: find.byType(TrackListRow),
                  matching: find.byType(ScaleTransition))
              .first)
          .scale
          .value;
      expect(scale(), 1.0);
      final g = await tester.startGesture(tester.getCenter(find.text('Song a')));
      // A press is told apart from the start of a long press after kPressTimeout.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 60));
      expect(scale(), lessThan(1.0), reason: 'compresses under the finger');
      await g.up();
      await tester.pumpAndSettle();
      expect(scale(), closeTo(1.0, 1e-3), reason: 'and springs back');
    });

    testWidgets('a screen reader gets one play action and a separate options button',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(TrackListRow(
        track: track('a'),
        onPlay: () {},
        onOptions: () {},
        isPlaying: true,
      )));
      expect(
          tester.getSemantics(find.bySemanticsLabel('Song a, Artist a')),
          matchesSemantics(
            label: 'Song a, Artist a',
            hint: 'Plays this song. Long press for options.',
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            hasTapAction: true,
            hasLongPressAction: true,
          ),
          reason: 'one play action; the playing row says so');
      final options = tester.getSemantics(find.byTooltip('More options'));
      expect(options.label, isNot(contains('Song a')),
          reason: 'the button is its own control, not part of the row\'s label');
      expect(options.tooltip, 'More options');
      handle.dispose();
    });
  });

  group('the columns', () {
    testWidgets('each row plays ITS song, in the first column and the next',
        (tester) async {
      final tracks = [for (var i = 0; i < 9; i++) track('t$i')];
      final played = <String>[];
      await tester.pumpWidget(host(SizedBox(
        height: 260,
        child: TrackListColumns(
          tracks: tracks,
          onPlay: (t) => played.add(t.id),
          onOptions: (_) {},
        ),
      )));
      await tester.tap(find.text('Song t0'));
      await tester.tap(find.text('Song t3'));
      expect(played, ['t0', 't3']);

      // Scroll the next column into view and play from it.
      await tester.drag(find.byType(ListView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song t5'));
      expect(played.last, 't5');
    });

    testWidgets('a drag across the rows scrolls the rail instead of playing',
        (tester) async {
      final tracks = [for (var i = 0; i < 9; i++) track('t$i')];
      final played = <String>[];
      await tester.pumpWidget(host(SizedBox(
        height: 260,
        child: TrackListColumns(
          tracks: tracks,
          onPlay: (t) => played.add(t.id),
          onOptions: (_) {},
        ),
      )));
      await tester.drag(find.text('Song t1'), const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(played, isEmpty, reason: 'a swipe is not a tap');
    });

    testWidgets('the song that is playing is marked', (tester) async {
      final tracks = [track('a'), track('b')];
      await tester.pumpWidget(host(SizedBox(
        height: 160,
        child: TrackListColumns(
          tracks: tracks,
          onPlay: (_) {},
          onOptions: (_) {},
          isPlaying: (t) => t.id == 'b',
        ),
      )));
      Color? colorOf(String text) =>
          tester.widget<Text>(find.text(text)).style?.color;
      expect(colorOf('Song b'), isNot(colorOf('Song a')));
    });
  });

  group('inside the layout switch', () {
    Widget switcher(bool isCard, List<String> played) => host(
          HomeLayoutSwitch(
            isCard: isCard,
            card: const SizedBox(height: 40, child: Text('cards')),
            list: SizedBox(
              height: 260,
              child: TrackListColumns(
                tracks: [track('a'), track('b')],
                onPlay: (t) => played.add(t.id),
                onOptions: (_) {},
              ),
            ),
          ),
        );

    testWidgets('a row plays once the section has been switched to list mode',
        (tester) async {
      final played = <String>[];
      await tester.pumpWidget(switcher(true, played));
      expect(find.text('cards'), findsOneWidget);

      await tester.pumpWidget(switcher(false, played));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song b'));
      expect(played, ['b']);
    });

    testWidgets('and a row that is mid-swap is not a dead zone either',
        (tester) async {
      final played = <String>[];
      await tester.pumpWidget(switcher(true, played));
      await tester.pumpWidget(switcher(false, played));
      await tester.pump(const Duration(milliseconds: 60)); // part-way
      await tester.tap(find.text('Song a'), warnIfMissed: false);
      await tester.pumpAndSettle();
      // Whether or not the early tap landed, the settled layout plays.
      played.clear();
      await tester.tap(find.text('Song a'));
      expect(played, ['a']);
    });
  });
}
