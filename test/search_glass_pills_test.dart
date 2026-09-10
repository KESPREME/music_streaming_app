import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'package:music_streaming_app/widgets/animated_equalizer_icon.dart';
import 'package:music_streaming_app/widgets/glass_circle_button.dart';
import 'package:music_streaming_app/widgets/search_glass_pills.dart';

void main() {
  group('SearchScopeSegmented Widget Tests', () {
    testWidgets('renders GlassSegmentedControl with Mine Music and Library and companion equalizer', (tester) async {
      SearchScope currentScope = SearchScope.mineMusic;
      bool eqTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SearchScopeSegmented(
                  scope: currentScope,
                  onChanged: (newScope) {
                    setState(() => currentScope = newScope);
                  },
                  onEqualizerTap: () => eqTapped = true,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify GlassSegmentedControl presence
      expect(find.byType(lgw.GlassSegmentedControl), findsOneWidget);
      expect(find.text('Mine Music'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);

      // Verify companion button and AnimatedEqualizerIcon
      expect(find.byType(GlassCircleButton), findsOneWidget);
      expect(find.byType(AnimatedEqualizerIcon), findsOneWidget);

      // Tap 'Library' to verify segment switching
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(currentScope, equals(SearchScope.library));

      // Tap companion equalizer button
      await tester.tap(find.byType(GlassCircleButton));
      await tester.pump();
      expect(eqTapped, isTrue);
    });
  });

  group('SearchFilterChips Widget Tests', () {
    testWidgets('renders all chips and triggers onSelected', (tester) async {
      const labels = ['Songs', 'Videos', 'Albums', 'Artists', 'Playlists'];
      int selectedIdx = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SearchFilterChips(
                  labels: labels,
                  index: selectedIdx,
                  onSelected: (idx) {
                    setState(() => selectedIdx = idx);
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }

      // Tap 'Videos' (index 1)
      await tester.tap(find.text('Videos'));
      await tester.pumpAndSettle();
      expect(selectedIdx, equals(1));
    });
  });
}
