import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'package:music_streaming_app/widgets/animated_equalizer_icon.dart';
import 'package:music_streaming_app/widgets/glass_circle_button.dart';
import 'package:music_streaming_app/widgets/search_glass_pills.dart';

void main() {
  group('SearchScopeSegmented Widget Tests', () {
    testWidgets('renders GlassSegmentedControl with Mine Music and Library and the trailing control', (tester) async {
      SearchScope currentScope = SearchScope.mineMusic;
      bool trailingTapped = false;

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
                  // Search puts the account avatar here; any 48dp control fits.
                  trailing: GlassCircleButton(
                    size: 48,
                    semanticLabel: 'Account',
                    onTap: () => trailingTapped = true,
                    child: const Icon(Icons.person_outline_rounded),
                  ),
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

      // The trailing control is there - and the equalizer that used to be is not.
      expect(find.byType(GlassCircleButton), findsOneWidget);
      expect(find.byType(AnimatedEqualizerIcon), findsNothing);

      // Tap 'Library' to verify segment switching
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(currentScope, equals(SearchScope.library));

      // Tap the trailing control
      await tester.tap(find.byType(GlassCircleButton));
      await tester.pump();
      expect(trailingTapped, isTrue);
    });

    testWidgets('with no trailing control the row is just the segmented control', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchScopeSegmented(scope: SearchScope.mineMusic, onChanged: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GlassCircleButton), findsNothing);
      expect(find.byType(AnimatedEqualizerIcon), findsNothing);
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
