import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/artwork_wash.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/bitchord_sliver_app_bar.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/merge_band.dart';
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

    testWidgets('BitchordSliverAppBar applies progressive eased gradient when scrolled past threshold', (tester) async {
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

      // Container inside RepaintBoundary must have progressive eased scrim gradient (BitChord SCRIM_PEAK = 0.42)
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(RepaintBoundary),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.gradient, isA<LinearGradient>());
      final gradient = decoration.gradient as LinearGradient;
      expect(gradient.colors.first, bgColor.withValues(alpha: 0.42));
      expect(gradient.colors.last, Colors.transparent);
    });

    testWidgets('MergeBand renders eased gradient join without ShaderMask or BackdropFilter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                MergeBand(
                  washColor: Color(0xFF1C272B),
                  artHeight: 300,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(MergeBand), findsOneWidget);
      // Must NOT use ShaderMask or BackdropFilter (which caused horizontal line seam & 20fps stutter)
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
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

    test('ArtworkPaletteResolver.fromColors preserves sleek charcoal for monochrome art', () {
      // Greyscale / monochrome photo (e.g. B&W artist portrait like Tame Impala)
      const monoGrey = Color(0xFF404040);
      final palette = ArtworkPaletteResolver.fromColors(
        monoGrey,
        vibrantColor: monoGrey,
        edgeColor: monoGrey,
        dark: true,
      );
      final hsl = HSLColor.fromColor(palette.background);
      // Saturation must stay 0.0 (sleek charcoal) instead of being forced into muddy reddish-brown
      expect(hsl.saturation, equals(0.0));
      expect(hsl.lightness, closeTo(0.13, 0.01));
    });

    test('ArtworkPaletteResolver.fromColors extracts rich warm tones for terracotta/sand art', () {
      // Warm terracotta/sand (e.g. The Slow Rush)
      const terracotta = Color(0xFFB8452B);
      const sandEdge = Color(0xFFD49B6A);
      final palette = ArtworkPaletteResolver.fromColors(
        terracotta,
        vibrantColor: terracotta,
        edgeColor: sandEdge,
        dark: true,
      );
      final hsl = HSLColor.fromColor(palette.background);
      expect(hsl.saturation, greaterThan(0.19));
      expect(hsl.lightness, closeTo(0.13, 0.01));
    });
  });
}
