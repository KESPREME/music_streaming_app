import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/widgets/swipe_deck.dart';

Track _t(String id, String name) => Track(
      id: id,
      trackName: name,
      artistName: 'Artist $id',
      albumName: 'Album',
      previewUrl: 'https://example.com/$id.mp4',
    );

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFCBA4))),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders current and peek tracks', (tester) async {
    await tester.pumpWidget(_wrap(SwipeDeck(
      tracks: [_t('a', 'Song A'), _t('b', 'Song B')],
      onAction: (_, __) {},
    )));
    expect(find.text('Song A'), findsOneWidget);
    expect(find.text('Song B'), findsOneWidget);
  });

  testWidgets('like button fires like action and advances deck', (tester) async {
    final actions = <(String, SwipeAction)>[];
    await tester.pumpWidget(_wrap(SwipeDeck(
      tracks: [_t('a', 'Song A'), _t('b', 'Song B')],
      onAction: (t, a) => actions.add((t.id, a)),
    )));
    await tester.tap(find.byIcon(Icons.favorite_outline_rounded));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(actions, hasLength(1));
    expect(actions.first.$1, 'a');
    expect(actions.first.$2, SwipeAction.like);
    // Deck advanced: Song A gone, Song B is now top.
    expect(find.text('Song A'), findsNothing);
    expect(find.text('Song B'), findsOneWidget);
  });

  testWidgets('skip button fires skip action', (tester) async {
    final actions = <(String, SwipeAction)>[];
    await tester.pumpWidget(_wrap(SwipeDeck(
      tracks: [_t('a', 'Song A'), _t('b', 'Song B')],
      onAction: (t, a) => actions.add((t.id, a)),
    )));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(actions.single.$2, SwipeAction.skip);
  });

  testWidgets('exhausted deck shows empty state', (tester) async {
    await tester.pumpWidget(_wrap(SwipeDeck(
      tracks: const [],
      onAction: (_, __) {},
    )));
    expect(find.text('Deck exhausted — pull down to refresh'), findsOneWidget);
  });
}
