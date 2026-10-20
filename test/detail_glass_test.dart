import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'package:music_streaming_app/widgets/bitchord_detail/detail_glass.dart';

/// What can be proven about the glass chrome without a phone: it builds under
/// the app's glass setup, taps and holds reach the right callback, a tap on a
/// capsule slot goes to the slot and not the capsule body, and the menu opens.
/// How the jelly FEELS is the package's physics with the nav bar's settings; it
/// is not something a test can see.
Widget _host(Widget child, {Size size = const Size(400, 800)}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          backgroundColor: const Color(0xFF201010),
          body: Stack(children: [child]),
        ),
      ),
    );

void main() {
  group('DetailGlassCircle', () {
    testWidgets('tap calls back; the label is the semantics label', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(Center(
        child: DetailGlassScope(
          accent: Colors.orange,
          child: DetailGlassCircle(icon: Icons.shuffle_rounded, label: 'Shuffle', onTap: () => taps++),
        ),
      )));
      await tester.tap(find.bySemanticsLabel('Shuffle'));
      await tester.pump();
      expect(taps, 1);
      expect(find.byType(lgw.GlassButton), findsOneWidget);
    });

    testWidgets('a hold does not tap, and releasing it inside does', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(Center(
        child: DetailGlassScope(
          accent: Colors.orange,
          child: DetailGlassCircle(icon: Icons.shuffle_rounded, label: 'Shuffle', onTap: () => taps++),
        ),
      )));
      final g = await tester.startGesture(tester.getCenter(find.byType(lgw.GlassButton)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 0, reason: 'held down: nothing fires yet');
      await g.up();
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('a progress child replaces the icon', (tester) async {
      await tester.pumpWidget(_host(Center(
        child: DetailGlassScope(
          accent: Colors.orange,
          child: DetailGlassCircle(
            label: 'Downloading',
            size: 56,
            onTap: () {},
            child: const SizedBox(key: ValueKey('ring'), width: 20, height: 20),
          ),
        ),
      )));
      expect(find.byKey(const ValueKey('ring')), findsOneWidget);
      expect(find.bySemanticsLabel('Downloading'), findsOneWidget);
    });
  });

  group('DetailGlassPill', () {
    testWidgets('Play takes its width and calls back', (tester) async {
      var plays = 0;
      await tester.pumpWidget(_host(Center(
        child: DetailGlassPill(width: 200, onTap: () => plays++),
      )));
      expect(tester.getSize(find.byType(lgw.GlassButton)).width, 200);
      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      expect(plays, 1);
    });
  });

  group('DetailActionRow', () {
    testWidgets('lays out shuffle . Play . trailing and fits a narrow phone', (tester) async {
      var shuffled = 0, played = 0, tail = 0;
      await tester.pumpWidget(_host(
        Center(
          child: DetailActionRow(
            accent: Colors.orange,
            onPlay: () => played++,
            leading: DetailGlassCircle(
                icon: Icons.shuffle_rounded, label: 'Shuffle', size: 56, onTap: () => shuffled++),
            trailing: DetailGlassCircle(
                icon: Icons.download_rounded, label: 'Download', size: 56, onTap: () => tail++),
          ),
        ),
        size: const Size(320, 700),
      ));
      expect(tester.takeException(), isNull, reason: 'no overflow at 320dp');
      await tester.tap(find.bySemanticsLabel('Shuffle'));
      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.tap(find.bySemanticsLabel('Download'));
      await tester.pump();
      expect([shuffled, played, tail], [1, 1, 1]);
    });
  });

  group('DetailGlassCapsule', () {
    Widget capsule(List<int> taps, {List<Widget>? menu}) => _host(Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DetailGlassScope(
              accent: Colors.orange,
              child: DetailGlassCapsule(slots: [
                DetailGlassSlot(icon: Icons.search_rounded, label: 'Search', onTap: () => taps[0]++),
                DetailGlassSlot(icon: Icons.sort_rounded, label: 'Sort', onTap: () => taps[1]++),
                if (menu != null)
                  DetailGlassSlot(icon: Icons.more_horiz_rounded, label: 'More', menuItems: menu)
                else
                  DetailGlassSlot(icon: Icons.more_horiz_rounded, label: 'More', onTap: () => taps[2]++),
              ]),
            ),
          ),
        ));

    testWidgets('is ONE glass body, as wide as its slots', (tester) async {
      await tester.pumpWidget(capsule([0, 0, 0]));
      expect(find.byType(lgw.GlassButton), findsOneWidget);
      expect(tester.getSize(find.byType(lgw.GlassButton)).width, DetailGlassCapsule.widthFor(3));
    });

    testWidgets('a tap on each slot goes to that slot and nowhere else', (tester) async {
      final taps = [0, 0, 0];
      await tester.pumpWidget(capsule(taps));
      await tester.tap(find.bySemanticsLabel('Search'));
      await tester.pump();
      expect(taps, [1, 0, 0]);
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pump();
      expect(taps, [1, 0, 1]);
      await tester.tap(find.bySemanticsLabel('Sort'));
      await tester.pump();
      expect(taps, [1, 1, 1]);
    });

    testWidgets('pressing a slot pops it; letting go settles it', (tester) async {
      await tester.pumpWidget(capsule([0, 0, 0]));
      double scaleOf() => tester
          .widget<AnimatedScale>(find.descendant(
            of: find.bySemanticsLabel('Search'),
            matching: find.byType(AnimatedScale),
          ))
          .scale;
      expect(scaleOf(), 1.0);
      final g = await tester.startGesture(tester.getCenter(find.bySemanticsLabel('Search')));
      await tester.pump();
      expect(scaleOf(), greaterThan(1.1), reason: 'inflated under the finger');
      await g.up();
      await tester.pump();
      expect(scaleOf(), 1.0);
    });

    testWidgets('dragging off a slot and releasing taps nothing', (tester) async {
      final taps = [0, 0, 0];
      await tester.pumpWidget(capsule(taps));
      final g = await tester.startGesture(tester.getCenter(find.bySemanticsLabel('Search')));
      await g.moveBy(const Offset(-200, 120));
      await g.up();
      await tester.pump();
      expect(taps, [0, 0, 0]);
    });

    testWidgets('a menu slot opens its liquid menu and an item runs', (tester) async {
      var next = 0;
      await tester.pumpWidget(capsule([0, 0, 0], menu: [
        lgw.GlassMenuItem(title: 'Play next', icon: const Icon(Icons.queue_play_next_rounded), onTap: () => next++),
        lgw.GlassMenuItem(title: 'Add to queue', onTap: () {}),
      ]));
      expect(find.text('Play next'), findsNothing);
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      expect(find.text('Play next'), findsOneWidget);
      expect(find.text('Add to queue'), findsOneWidget);
      await tester.tap(find.text('Play next'));
      await tester.pumpAndSettle();
      expect(next, 1);
    });
  });

  group('DetailTopBar', () {
    testWidgets('back and slots work; the title appears only after the header leaves', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var shared = 0;
      await tester.pumpWidget(_host(Stack(children: [
        ListView(controller: controller, children: const [SizedBox(height: 3000)]),
        DetailTopBar(
          controller: controller,
          title: 'Dawn FM',
          background: const Color(0xFF101010),
          titleAppearsAt: 200,
          slots: [DetailGlassSlot(icon: Icons.ios_share_rounded, label: 'Share', onTap: () => shared++)],
        ),
      ])));
      double titleOpacity() => tester.widget<Opacity>(find.ancestor(of: find.text('Dawn FM'), matching: find.byType(Opacity)).first).opacity;
      expect(titleOpacity(), 0.0);
      await tester.tap(find.bySemanticsLabel('Share'));
      await tester.pump();
      expect(shared, 1);

      controller.jumpTo(400);
      await tester.pump();
      expect(titleOpacity(), 1.0);
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
    });
  });
}
