import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/glass_player_control.dart';

void main() {
  testWidgets('exposes icon and semantic label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        home: Scaffold(
          body: GlassPlayerControl(
            icon: Icons.play_arrow_rounded,
            semanticLabel: 'Play',
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
  });

  testWidgets('exposes disabled semantics', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        home: Scaffold(
          body: GlassPlayerControl(
            icon: Icons.skip_next_rounded,
            semanticLabel: 'Next track',
            onPressed: null,
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.bySemanticsLabel('Next track'));
    expect(semantics.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
    expect(semantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
  });
}
