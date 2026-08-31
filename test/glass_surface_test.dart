import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/glass_surface.dart';

void main() {
  Future<void> pumpSurface(WidgetTester tester, GlassTier tier) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        home: Scaffold(
          body: GlassSurface(
            tier: tier,
            child: const Text('glass'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('GlassSurface renders child in card tier', (tester) async {
    await pumpSurface(tester, GlassTier.card);
    expect(find.text('glass'), findsOneWidget);
  });

  testWidgets('GlassSurface renders child in chrome tier', (tester) async {
    await pumpSurface(tester, GlassTier.chrome);
    expect(find.text('glass'), findsOneWidget);
  });

  testWidgets('GlassSurface renders child in floating tier', (tester) async {
    await pumpSurface(tester, GlassTier.floating);
    expect(find.text('glass'), findsOneWidget);
  });

  testWidgets('GlassSurface renders child in sheet tier', (tester) async {
    await pumpSurface(tester, GlassTier.sheet);
    expect(find.text('glass'), findsOneWidget);
  });
}
