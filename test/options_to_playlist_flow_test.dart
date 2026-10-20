import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/presentation/explore/explore_top_pill.dart' show SongCodeDialog;
import 'package:music_streaming_app/widgets/glass_options_sheet.dart' show SongInfoDialog;
import 'package:music_streaming_app/widgets/themed_options_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Long-press a song -> "Add to a playlist..." -> "New playlist".
///
/// The options sheet closes itself before it opens the playlist sheet, so the
/// context it was built with is gone by the time the listener has read the second
/// sheet and tapped a row in it. The flow used to keep that dead context and give
/// up quietly: the sheet closed and nothing else happened. These tests take the
/// whole real path (the real options sheet, the real add sheet, the real editor),
/// and wait as long as a person would.
Track _t(String id, [String? title]) => Track(
      id: id,
      trackName: title ?? 'Song $id',
      artistName: 'Artist',
      albumName: 'Album',
      albumArtUrl: 'https://example.com/$id.jpg',
      previewUrl: '',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MusicProvider p;
  late ThemeProvider themes;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final ready = Completer<void>();
    final original = debugPrint;
    debugPrint = (msg, {wrapWidth}) {
      if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) ready.complete();
    };
    p = MusicProvider();
    themes = ThemeProvider();
    await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    debugPrint = original;
  });

  setUp(() {
    for (final pl in List.of(p.userPlaylists)) {
      p.deletePlaylistWithUndo(pl.id);
    }
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MusicProvider>.value(value: p),
        ChangeNotifierProvider<ThemeProvider>.value(value: themes),
      ],
      child: MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              // The long-press target: a stand-in for a Home card.
              child: GestureDetector(
                onLongPress: () => ThemedOptionsSheet.show(context, track: _t('x', 'Borderline')),
                child: const SizedBox(width: 120, height: 120, child: Text('card')),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  /// Opens the options sheet and walks to the add sheet like a person would:
  /// the sheet finishes closing (about 300 ms) while they read the next one.
  Future<void> toAddSheet(WidgetTester tester) async {
    await tester.longPress(find.text('card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Add to a playlist...'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Add to playlist'), findsOneWidget, reason: 'the add sheet is up');
    // A person takes a moment: by now the options sheet is long gone.
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('New playlist opens the editor, saves, and the song is in it', (tester) async {
    await pumpHome(tester);
    await toAddSheet(tester);

    await tester.tap(find.text('New playlist'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Starts with "Borderline"'), findsOneWidget, reason: 'the editor opened');

    await tester.enterText(find.byType(TextField).first, 'Late drive');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(p.userPlaylists.single.name, 'Late drive');
    expect(p.userPlaylists.single.tracks.map((t) => t.id), ['x']);
    expect(find.text('Created "Late drive"'), findsOneWidget, reason: 'and it says so');
  });

  testWidgets('adding to an existing playlist confirms it', (tester) async {
    final pl = (await p.createPlaylistWith(name: 'Chill', tracks: const []))!;
    await pumpHome(tester);
    await toAddSheet(tester);

    await tester.tap(find.text('Chill'));
    await tester.pump();
    await tester.tap(find.text('Add to Chill'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(p.playlistById(pl.id)!.tracks.map((t) => t.id), ['x']);
    expect(find.text('Added to Chill'), findsOneWidget, reason: 'the confirmation used to be dropped too');
  });

  // ── The rest of the sheet: every row must answer ─────────────────────────────
  //
  // Found while fixing the above: a row that "works" in a unit test can still do
  // nothing for a person. These walk the rows that have something to show and
  // check that they show it.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.longPress(find.text('card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('Play next says what it did', (tester) async {
    await pumpHome(tester);
    await openSheet(tester);
    await tester.tap(find.text('Play next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Playing "Borderline" next'), findsOneWidget);
  });

  testWidgets('Add to queue says what it did', (tester) async {
    await pumpHome(tester);
    await openSheet(tester);
    await tester.tap(find.text('Add to queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Added "Borderline" to queue'), findsOneWidget);
  });

  testWidgets('Song Info opens its dialog', (tester) async {
    await pumpHome(tester);
    await openSheet(tester);
    await tester.tap(find.text('Song Info'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SongInfoDialog), findsOneWidget);
  });

  testWidgets('the code row opens the song code', (tester) async {
    await pumpHome(tester);
    await openSheet(tester);
    await tester.tap(find.text('Mine Music Code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SongCodeDialog), findsOneWidget);
  });

  testWidgets('Sleep Timer opens its choices and Turn Off confirms', (tester) async {
    await pumpHome(tester);
    await openSheet(tester);
    await tester.ensureVisible(find.text('Sleep Timer'));
    await tester.tap(find.text('Sleep Timer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('15 Minutes'), findsOneWidget);
    await tester.tap(find.text('Turn Off'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sleep timer turned off'), findsOneWidget);
  });
}
