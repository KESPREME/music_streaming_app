import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/artwork_wash.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/bitchord_sliver_app_bar.dart';
import 'package:music_streaming_app/utils/artwork_palette_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BitChord Detail Screen Wash & Frosted Bar Parity Tests', () {
    testWidgets('ArtworkWash renders CustomPaint painter and never spawns blurred image', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArtworkWash(
              backgroundColor: Color(0xFF101416),
              washColor: Color(0xFF1C272B),
              accentColor: Color(0xFF2E4E54),
              elevatedColor: Color(0xFF182226),
              imageUrl: 'https://example.com/album.jpg',
            ),
          ),
        ),
      );

      // ArtworkWash must render a CustomPaint
      expect(find.byType(CustomPaint), findsWidgets);

      // It must NOT contain ImageFiltered or Image widgets (which cause white wash out on light covers)
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('BitchordSliverAppBar is 100% transparent at rest (scrollOffset = 0)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                BitchordSliverAppBar(
                  title: 'Making Mirrors',
                  scrollOffset: 0.0,
                  artHeight: 250.0,
                  backgroundColor: const Color(0xFF101416),
                  onBack: () {},
                ),
              ],
            ),
          ),
        ),
      );

      // Title opacity must be 0
      final opacityWidget = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacityWidget.opacity, 0.0);

      // BackdropFilter must not be rendered when at rest
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('BitchordSliverAppBar applies dark tinted frosted glass when scrolled past threshold', (tester) async {
      const bgColor = Color(0xFF101416);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                BitchordSliverAppBar(
                  title: 'Making Mirrors',
                  scrollOffset: 350.0,
                  artHeight: 250.0,
                  backgroundColor: bgColor,
                  onBack: () {},
                ),
              ],
            ),
          ),
        ),
      );

      // Title opacity must be 1.0
      final opacityWidget = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacityWidget.opacity, 1.0);

      // BackdropFilter must be present
      expect(find.byType(BackdropFilter), findsOneWidget);

      // Container inside BackdropFilter must have tinted background to prevent white milky haze
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, bgColor.withValues(alpha: 0.72));
    });
  });

  group('BitChord Palette & Fallback Tests', () {
    test('ArtworkPalette.defaultDark returns cohesive dark palette', () {
      const defaultDark = ArtworkPalette.defaultDark;
      expect(defaultDark.background, const Color(0xFF0A080C));
      expect(defaultDark.wash, const Color(0xFF131018));
      expect(defaultDark.accent, const Color(0xFFFF5252));
    });

    test('ArtworkPaletteResolver.fromColors resolves dark palette with dark theme parity', () {
      final palette = ArtworkPaletteResolver.fromColors(
        const Color(0xFF1A3B44),
        vibrantColor: const Color(0xFF2E6573),
        dark: true,
      );
      expect(palette.accent, isNotNull);
      expect(palette.background.computeLuminance(), lessThan(0.06));
    });
  });
}
