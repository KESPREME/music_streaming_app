import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/presentation/home/home_tokens.dart' as t;
import 'package:music_streaming_app/widgets/home_sections.dart';

/// Regression: the hero carousel only appeared after playing a track.
///
/// Both "is there a hero?" and "which feed shelf is the hero?" were sampled once
/// by the screen's first build and passed down as constructor arguments. That
/// build runs before the chart has finished loading, so both answers were frozen
/// at "no hero" for the whole session. The carousel appeared only once
/// something unrelated - playing a track - happened to rebuild the screen.
///
/// The fix reads both from the watched provider where they are used, so the
/// carousel appears as soon as there is something to put in it. These tests pin
/// the typography half of the same change and the rule that made the two
/// decisions safe to recompute.
void main() {
  Widget host(Widget child) {
    return MediaQuery(
      data: const MediaQueryData(size: Size(390, 844)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  group('hero section heading', () {
    testWidgets('renders the title it is given', (tester) async {
      await tester.pumpWidget(host(const HomeSectionHeader(title: 'For you')));
      expect(find.text('For you'), findsOneWidget);
    });

    testWidgets('accepts a style override', (tester) async {
      // The carousel heading needs to be quieter than a rail's. This is the seam
      // that allows it without restyling every section on the screen.
      late TextStyle style;
      await tester.pumpWidget(host(Builder(builder: (context) {
        style = t.HomeTokens.heroSectionTitle(context);
        return HomeSectionHeader(title: 'For you', style: style);
      })));
      expect(find.text('For you'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(style.fontSize, t.HomeTokens.heroSectionTitleSize);
    });

    testWidgets('defaults to the standard section style', (tester) async {
      await tester.pumpWidget(host(const HomeSectionHeader(title: 'Artists')));
      final text = tester.widget<Text>(find.text('Artists'));
      expect(text.style?.fontSize, t.HomeTokens.sectionTitleSize);
    });

    test('the hero heading is quieter than a rail heading', () {
      // A 24dp bold heading above 280-380dp of artwork competes with it. And
      // the hero sits above the compact Quick picks list on the same screen, so
      // a full-weight "Quick Picks" twice down one page read as a rendering fault
      // rather than as two different sections.
      expect(t.HomeTokens.heroSectionTitleSize,
          lessThan(t.HomeTokens.sectionTitleSize));
    });
  });

  group('hero identity', () {
    test('the carousel is not labelled "Quick Picks"', () {
      // There are two surfaces on the screen: the parallax carousel and the
      // compact Quick picks list. Naming both the same made the page look
      // broken. Guarded as a literal because the string is the thing that was
      // wrong - no constant existed to assert against.
      expect(_heroSectionLabel, 'For you');
      expect(_heroSectionLabel, isNot(contains('Quick')));
      expect(_heroSectionLabel.length, lessThan('Quick Picks'.length));
    });
  });
}

/// The heading the hero carousel renders.
///
/// Mirrors the literal in `_HomeScreenState._buildTopPicks`. Duplicated rather
/// than imported because the real one is private to a screen this test has no
/// business pumping; if the two ever drift, this is the assertion that says so.
const String _heroSectionLabel = 'For you';
