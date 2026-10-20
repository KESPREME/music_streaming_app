import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/presentation/home/home_view_mode.dart';
import 'package:music_streaming_app/widgets/collection/collection_kit.dart';
import 'package:music_streaming_app/widgets/home_sections.dart';
import 'package:music_streaming_app/widgets/jelly_press.dart';
import 'package:music_streaming_app/widgets/library/library_filter_bar.dart';
import 'package:music_streaming_app/widgets/section_view_toggle.dart';

/// The browse surfaces (Home / Library headers, filter bar, view toggles, sort
/// row, filter chips) now share the JellyPress touch language. These tests pin
/// the two things a refactor like this can silently break: the tap still lands
/// exactly once, and the control visibly gives under the finger.
Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: c!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

/// Scale of the first JellyPress under [of], read from the Transform it paints.
double _scaleUnder(WidgetTester t, Finder of) {
  final tr = t.widget<Transform>(
    find.descendant(of: of, matching: find.byType(Transform)).first,
  );
  return tr.transform.storage[0];
}

void main() {
  testWidgets('Home "See all" gives under the finger and taps once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(HomeSectionHeader(title: 'Quick picks', onViewAll: () => taps++)));
    final pill = find.ancestor(of: find.text('See all'), matching: find.byType(JellyPress));
    expect(pill, findsOneWidget);

    final g = await tester.startGesture(tester.getCenter(find.text('See all')));
    await tester.pump(); // the ticker's first frame starts the clock
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scaleUnder(tester, pill), lessThan(0.99), reason: 'the pill must visibly compress');
    expect(taps, 0, reason: 'a tap lands on release, not on touch');

    await g.up();
    await tester.pump();
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(_scaleUnder(tester, pill), closeTo(1.0, 0.002), reason: 'it settles back to rest');
  });

  testWidgets('a trailing control still replaces "See all"', (tester) async {
    await tester.pumpWidget(_host(HomeSectionHeader(
      title: 'Quick picks',
      onViewAll: () {},
      trailing: const SizedBox(width: 34, height: 34),
    )));
    expect(find.text('See all'), findsNothing);
  });

  testWidgets('the section view toggle compresses, toggles once, keeps its label', (tester) async {
    var mode = HomeSectionViewMode.card;
    var toggles = 0;
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setState) => SectionViewToggle(
        mode: mode,
        onToggle: () => setState(() {
          toggles++;
          mode = mode.toggled;
        }),
      ),
    )));
    final toggle = find.byType(SectionViewToggle);
    expect(find.bySemanticsLabel('Switch to list view'), findsOneWidget);

    final g = await tester.startGesture(tester.getCenter(toggle));
    await tester.pump(); // the ticker's first frame starts the clock
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scaleUnder(tester, find.descendant(of: toggle, matching: find.byType(JellyPress))), lessThan(0.95),
        reason: 'a 34dp circle control is meant to give visibly');
    await g.up();
    await tester.pumpAndSettle();

    expect(toggles, 1);
    expect(find.bySemanticsLabel('Switch to card view'), findsOneWidget, reason: 'the label follows the mode');
  });

  testWidgets('reduce motion: the toggle still toggles and does not move', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(_host(
      SectionViewToggle(mode: HomeSectionViewMode.card, onToggle: () => toggles++),
      reduceMotion: true,
    ));
    final toggle = find.byType(SectionViewToggle);
    final g = await tester.startGesture(tester.getCenter(toggle));
    await tester.pump(); // the ticker's first frame starts the clock
    await tester.pump(const Duration(milliseconds: 120));
    final tr = find.descendant(of: find.descendant(of: toggle, matching: find.byType(JellyPress)), matching: find.byType(Transform));
    if (tr.evaluate().isNotEmpty) {
      expect(_scaleUnder(tester, find.descendant(of: toggle, matching: find.byType(JellyPress))), 1.0);
    }
    await g.up();
    await tester.pump();
    expect(toggles, 1);
  });

  testWidgets('every Library category is a jelly cell and selects once', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(_host(LibraryFilterBar(
      selectedCategory: 'All',
      onCategorySelected: picked.add,
      currentSort: LibrarySortOption.values.first,
      onSortChanged: (_) {},
    )));
    for (final c in LibraryFilterBar.categories) {
      expect(find.ancestor(of: find.text(c), matching: find.byType(JellyPress)), findsOneWidget, reason: c);
    }
    await tester.tap(find.text('Artists'));
    await tester.pump();
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(picked, ['Artists', 'Albums']);
  });

  testWidgets('filter chips are jellies and select once', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(_host(CollectionChips(
      chips: const [
        CollectionChipData(id: 'a', label: 'Recent'),
        CollectionChipData(id: 'b', label: 'Pinned', icon: Icons.push_pin_rounded),
      ],
      selectedId: 'a',
      onTap: (c) => picked.add(c.id),
    )));
    final pinned = find.ancestor(of: find.text('Pinned'), matching: find.byType(JellyPress));
    expect(pinned, findsOneWidget);

    final g = await tester.startGesture(tester.getCenter(find.text('Pinned')));
    await tester.pump(); // the ticker's first frame starts the clock
    await tester.pump(const Duration(milliseconds: 120));
    expect(_scaleUnder(tester, pinned), lessThan(0.99));
    await g.up();
    await tester.pumpAndSettle();
    expect(picked, ['b']);
    expect(find.bySemanticsLabel('Filter: Pinned'), findsOneWidget);
  });

  testWidgets('the sort row opens its sheet once and keeps its semantics', (tester) async {
    var sorts = 0;
    await tester.pumpWidget(_host(CollectionSortRow(label: 'Recently added', onSort: () => sorts++)));
    expect(find.ancestor(of: find.text('Recently added'), matching: find.byType(JellyPress)), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Sort: Recently added'));
    await tester.pumpAndSettle();
    expect(sorts, 1);
  });

  testWidgets('dragging off a pill cancels the tap (a scroll that starts on a pill is a scroll)', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(HomeSectionHeader(title: 'Quick picks', onViewAll: () => taps++)));
    final g = await tester.startGesture(tester.getCenter(find.text('See all')));
    await g.moveBy(const Offset(0, -120));
    await g.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
  });
}
