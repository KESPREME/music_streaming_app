import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/jelly_press.dart';
import 'package:music_streaming_app/widgets/mini_player.dart';
import 'package:provider/provider.dart';

/// The mini player's buttons sit INSIDE a pill that owns a horizontal swipe
/// (skip) and a vertical pull (open). They became JellyPress, which moves with a
/// passive listener. These tests prove the pill's gestures are still its own
/// and that a button press is still only a button press.
class _Fake extends MusicProvider {
  _Fake(this.track);

  Track? track;
  int next = 0, prev = 0, resume = 0, pause = 0;
  bool playing = false;

  @override
  Track? get currentTrack => track;
  @override
  bool get isPlaying => playing;
  @override
  bool get isMiniPlayerVisible => true;
  @override
  Duration get duration => const Duration(minutes: 3);
  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();
  @override
  Future<void> skipToNext() async => next++;
  @override
  Future<void> skipToPrevious() async => prev++;
  @override
  Future<void> resumeTrack() async {
    resume++;
    playing = true;
    notifyListeners();
  }

  @override
  Future<void> pauseTrack() async {
    pause++;
    playing = false;
    notifyListeners();
  }
}
Track _track() => Track(
      id: 'abcdefghijk',
      trackName: 'Glass track',
      artistName: 'Glass artist',
      albumName: 'Glass album',
      previewUrl: '',
    );

Future<void> _pump(WidgetTester t, _Fake p, {double width = 400}) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
    value: p,
    child: MaterialApp(
      theme: GlassTheme.build(AccentColors.peach).copyWith(splashFactory: NoSplash.splashFactory),
      home: const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: MiniPlayer())),
    ),
  ));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('the transport glyphs are jellies', (tester) async {
    final p = _Fake(_track());
    await _pump(tester, p);
    expect(find.byType(JellyPress), findsWidgets);
    expect(find.bySemanticsLabel('Play'), findsOneWidget, reason: 'the label the other tests tap by stays unique');
  });

  testWidgets('play / pause still plays and pauses, once per tap', (tester) async {
    final p = _Fake(_track());
    await _pump(tester, p);
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    expect([p.resume, p.pause], [1, 0]);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pumpAndSettle();
    expect([p.resume, p.pause], [1, 1]);
  });

  testWidgets('a tap on a button is only a button press: it does not also open the player', (tester) async {
    final p = _Fake(_track());
    await _pump(tester, p);
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pumpAndSettle();
    expect(find.byType(MiniPlayer), findsOneWidget);
    // Opening would have pushed a route.
    expect(find.byType(Navigator), findsWidgets);
    expect(p.resume, 1);
  });

  testWidgets('a swipe that STARTS on a button still skips the track (the pill owns the drag)', (tester) async {
    final p = _Fake(_track());
    await _pump(tester, p);
    final at = tester.getCenter(find.bySemanticsLabel('Play'));
    await tester.flingFrom(at, const Offset(-160, 0), 1200);
    await tester.pumpAndSettle();
    expect(p.next, 1, reason: 'swiped left: next');
    expect(p.resume, 0, reason: 'and it was not a tap on Play');
  });

  testWidgets('swiping the other way goes back', (tester) async {
    final p = _Fake(_track());
    await _pump(tester, p);
    final at = tester.getCenter(find.byKey(const ValueKey('mini_player_lens')));
    await tester.flingFrom(at, const Offset(160, 0), 1200);
    await tester.pumpAndSettle();
    expect(p.prev, 1);
  });

  testWidgets('the buttons flex under the finger and settle to exactly 1', (tester) async {
    final p = _Fake(_track());
    await _pump(tester, p);
    // The play/pause jelly, found by the label that survives the glyph swap a
    // tap causes (Play becomes Pause), so the finder stays valid after release.
    final jelly = find.descendant(
      of: find.byWidgetPredicate((w) => w is Semantics && (w.properties.label == 'Play' || w.properties.label == 'Pause')),
      matching: find.byType(JellyPress),
    );
    expect(jelly, findsOneWidget);
    double scale() => tester
        .widget<Transform>(find.descendant(of: jelly, matching: find.byType(Transform)).first)
        .transform
        .storage[0];

    expect(scale(), 1);
    final g = await tester.startGesture(tester.getCenter(jelly));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    expect(scale(), lessThan(0.95), reason: 'pressed in');
    await g.up();
    await tester.pumpAndSettle();
    expect(scale(), 1);
    expect(p.resume, 1, reason: 'and releasing on it was a tap');
  });
}