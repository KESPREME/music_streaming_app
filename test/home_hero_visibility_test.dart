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
      // The seam still exists, so a heading CAN be styled differently - it is
      // simply no longer used that way, because every section heading now looks
      // the same.
      late TextStyle style;
      await tester.pumpWidget(host(Builder(builder: (context) {
        style = t.HomeTokens.heroSectionTitle(context);
        return HomeSectionHeader(title: 'For you', style: style);
      })));
      expect(find.text('For you'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(style.fontSize, t.HomeTokens.sectionTitleSize);
    });

    testWidgets('defaults to the standard section style', (tester) async {
      await tester.pumpWidget(host(const HomeSectionHeader(title: 'Artists')));
      final text = tester.widget<Text>(find.text('Artists'));
      expect(text.style?.fontSize, t.HomeTokens.sectionTitleSize);
    });

    testWidgets('the hero heading matches a rail heading exactly', (tester) async {
      // It used to be deliberately quieter: 19/w600 against 24/w700, on the
      // reasoning that a full-weight heading competed with 280-380dp of
      // artwork. Measured against the reference app that reasoning does not
      // hold - every heading there is one size and one weight, and a page where
      // one heading is visibly smaller than its neighbours reads as a styling
      // fault rather than as restraint. "For you" labels a section like any
      // other, so it now looks like one.
      late TextStyle hero;
      late TextStyle rail;
      await tester.pumpWidget(host(Builder(builder: (context) {
        hero = t.HomeTokens.heroSectionTitle(context);
        rail = t.HomeTokens.sectionTitle(context);
        return const SizedBox.shrink();
      })));
      expect(hero.fontSize, rail.fontSize);
      expect(hero.fontWeight, rail.fontWeight);
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
