import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/widgets/settings/settings_search.dart';

void main() {
  const account = SettingsEntry('account', ['Account', 'sign in', 'google']);
  const quality = SettingsEntry('quality', ['Quality', 'bitrate', 'high']);
  const cellular = SettingsEntry(
      'cellular', ['Cellular Quality', 'mobile data', 'stream over mobile data']);
  const playback = SettingsEntry('playback', ['Auto Queue', 'keep playing']);

  void index(SettingsSearchIndex i, String q) {
    i.registerAll([account, quality, cellular, playback]);
    // The query is fixed at construction; every helper here shares one shape.
    expect(i.needle, q.trim());
  }

  group('SettingsSearchIndex', () {
    test('an empty query matches everything', () {
      final i = SettingsSearchIndex('');
      index(i, '');
      expect(i.matches('account'), isTrue);
      expect(i.matches('quality'), isTrue);
      expect(i.anyMatch, isTrue);
    });

    test('matches a case-insensitive substring, not just a prefix', () {
      final i = SettingsSearchIndex('QUAL');
      index(i, 'QUAL');
      // "qual" appears inside "Quality", not at the start of it.
      expect(i.matches('quality'), isTrue);
      expect(i.matches('account'), isFalse);
    });

    test('matches a hidden synonym', () {
      // The point of hidden keywords: nobody labels a row "mobile data".
      final i = SettingsSearchIndex('mobile data');
      index(i, 'mobile data');
      expect(i.matches('cellular'), isTrue);
    });

    test('an all-whitespace query does not hide the screen', () {
      final i = SettingsSearchIndex('   ');
      index(i, '   ');
      expect(i.isFiltering, isFalse);
      expect(i.matches('account'), isTrue);
      expect(i.anyMatch, isTrue);
    });

    test('an unknown row stays visible rather than vanishing', () {
      // Failing open on purpose: a row we forgot to annotate is a far better
      // outcome than a settings screen with holes in it.
      final i = SettingsSearchIndex('quality');
      index(i, 'quality');
      expect(i.matches('row-nobody-annotated'), isTrue);
      expect(i.anyMatch, isTrue);
    });

    test('anyMatch is false only when nothing at all matched', () {
      final i = SettingsSearchIndex('zzzz');
      index(i, 'zzzz');
      expect(i.anyMatch, isFalse);
      expect(i.matches('account'), isFalse);
    });

    test('matchesAny over an empty id list is permissive', () {
      final i = SettingsSearchIndex('quality');
      index(i, 'quality');
      expect(i.matchesAny(const <String>[]), isTrue);
    });

    test('a later register for the same id wins', () {
      final i = SettingsSearchIndex('queue');
      i.registerAll([playback]);
      expect(i.matches('playback'), isTrue);
      i.registerAll([
        const SettingsEntry('playback', ['Auto Queue', 'keep playing']),
      ]);
      expect(i.matches('playback'), isTrue);
    });
  });

  group('SettingsSearchScope', () {
    testWidgets('exposes the index to descendants', (tester) async {
      final index = SettingsSearchIndex('quality');
      index.registerAll([quality]);

      late SettingsSearchIndex? seen;
      await tester.pumpWidget(
        SettingsSearchScope(
          index: index,
          child: Builder(
            builder: (context) {
              seen = SettingsSearchScope.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen, same(index));
    });

    testWidgets('returns null above the scope', (tester) async {
      SettingsSearchIndex? seen = SettingsSearchIndex('x');
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = SettingsSearchScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(seen, isNull);
    });
  });

  group('SettingsSearchGate', () {
    testWidgets('shows the group when something inside it matches',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsSearchGate(
            index: SettingsSearchIndex('quality')
              ..registerAll([quality, cellular]),
            entries: const [quality, cellular],
            child: const Text('group body'),
          ),
        ),
      );
      expect(find.text('group body'), findsOneWidget);
    });

    testWidgets('hides the whole group when nothing inside matches',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsSearchGate(
            index: SettingsSearchIndex('zzzz')..registerAll([quality]),
            entries: const [quality],
            child: const Text('group body'),
          ),
        ),
      );
      expect(find.text('group body'), findsNothing);
    });
  });

  group('SettingsSearchField', () {
    testWidgets('reports what the user types', (tester) async {
      final typed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsSearchField(onChanged: typed.add),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'eq');
      expect(typed.last, 'eq');
    });

    testWidgets('clearing resets both the text and the filter', (tester) async {
      final typed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsSearchField(onChanged: typed.add),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'eq');
      await tester.pump();
      expect(typed.last, 'eq');

      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      // Text left behind while the list is unfiltered reads as a broken state.
      expect(typed.last, '');
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
    });
  });

  group('SettingsSearchEmpty', () {
    testWidgets('echoes the query back', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SettingsSearchEmpty(query: 'mobile')),
        ),
      );
      // "No settings match" with no query leaves the user guessing whether the
      // app broke or they typed something odd.
      expect(find.text('No settings match "mobile"'), findsOneWidget);
    });
  });
}