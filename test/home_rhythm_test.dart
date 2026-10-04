import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/presentation/home/home_tokens.dart' as t;
import 'package:music_streaming_app/widgets/home_sections.dart';

/// Regression cover for the Home vertical rhythm.
///
/// Every number here was wrong in a way that only showed up as a visual
/// defect, so they are pinned explicitly. The failure mode this file exists to
/// prevent is an artist rail reserving 142dp for 99dp of content: not an
/// exception, not a failed assertion, just a band of dead space under every
/// artist shelf that nobody could point at in a test.
void main() {
  group('rhythm tokens', () {
    test('screen gutter matches the floating chrome gutter', () {
      // One constant, shared with the nav bar and mini player, so a card edge
      // lines up with the bar below it instead of stepping in from it.
      expect(t.HomeTokens.contentPadding, 10.0);
    });

    test('a section title sits flush against its content', () {
      // A gap here reads as the header labelling whatever is below the gap
      // rather than what is directly under it.
      expect(t.HomeTokens.headerToContent, 0.0);
    });

    test('sections are separated by 26dp', () {
      expect(t.HomeTokens.sectionGap, 26.0);
    });

    test('contentWidth subtracts the gutter twice', () {
      expect(t.HomeTokens.contentWidth(400), 380);
    });
  });

  group('artist portrait metric', () {
    /// Reads both metrics with a real BuildContext at a given text scale.
    Future<(double, double)> measure(WidgetTester tester, double scale) async {
      late double portrait;
      late double rail;
      await tester.pumpWidget(
        _ScaleHost(
          scale: scale,
          onMeasure: (context) {
            portrait = homeArtistPortraitHeight(context);
            rail = homeRailTextBlockHeight(context);
          },
        ),
      );
      return (portrait, rail);
    }

    testWidgets('is the circle plus one metadata line, not a two-line block',
        (tester) async {
      final (portrait, rail) = await measure(tester, 1.0);
      // 72 circle + 8 gap + one 20dp line + 4 slack.
      expect(portrait, 104.0);
      // A two-line block was 46. The old rail reserved `96 + rail`; this must
      // be materially smaller than that, which is the dead band being gone.
      expect(portrait, lessThan(96 + rail));
      expect(96 + rail - portrait, greaterThan(30));
    });

    testWidgets('saves the dead band the two-line block reserved',
        (tester) async {
      final (portrait, rail) = await measure(tester, 1.0);
      // Old reservation was 96 + 46.
      expect(portrait, lessThan(96 + rail));
    });

    testWidgets('scales with the text scaler', (tester) async {
      final (at1, _) = await measure(tester, 1.0);
      final (at15, _) = await measure(tester, 1.5);
      expect(at15, greaterThan(at1));
    });

    testWidgets('a real portrait fits inside the height it reserves',
        (tester) async {
      // The metric and the widget are pinned together deliberately. Deriving the
      // line as `fontSize * 1.2` came out 3px short of what the font actually
      // produced and overflowed this Column; only rendering catches that.
      await tester.pumpWidget(const _PortraitHost(scale: 1.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('and still fits at 1.3x text scale', (tester) async {
      await tester.pumpWidget(const _PortraitHost(scale: 1.3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long name still fits', (tester) async {
      await tester
          .pumpWidget(const _PortraitHost(scale: 1.0, name: 'Tame Impala'));
      expect(tester.takeException(), isNull);
    });
  });
}

/// Measures the metrics with a genuine [BuildContext] so the helpers read the
/// real MediaQuery text scaler rather than a stand-in.
class _ScaleHost extends StatelessWidget {
  const _ScaleHost({required this.scale, required this.onMeasure});

  final double scale;
  final void Function(BuildContext) onMeasure;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Builder(builder: (context) {
        onMeasure(context);
        return const SizedBox.shrink();
      }),
    );
  }
}

/// Wraps a real [ArtistPortrait] in exactly the box the rail reserves for it.
class _PortraitHost extends StatelessWidget {
  const _PortraitHost({required this.scale, this.name = 'Tame Impala'});

  final double scale;
  final String name;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(
          body: SizedBox(
            height: homeArtistPortraitHeight(context),
            child: ArtistPortrait(name: name, imageUrl: '', onTap: () {}),
          ),
        ),
      ),
    );
  }
}
