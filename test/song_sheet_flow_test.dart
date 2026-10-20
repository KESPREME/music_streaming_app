import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/song_sheet_plan.dart';
import 'package:music_streaming_app/widgets/themed_options_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// THE SONG SHEET ON THE SCREEN: what a person sees, taps, and is asked.

Track song({String id = 'abcdefghijk', String source = 'youtube'}) => Track(
      id: id,
      trackName: 'Wavin Flag',
      artistName: "K'naan",
      albumName: 'Troubadour',
      albumArtUrl: '',
      previewUrl: '',
      source: source,
    );

class _P extends MusicProvider {
  final downloaded = <String>{};
  final deleted = <String>[];
  final started = <String>[];
  final cancelled = <String>[];
  final running = <String>{};

  @override
  bool isTrackDownloadedSync(String trackId) => downloaded.contains(trackId);

  @override
  Map<String, bool> get isDownloading => {for (final id in running) id: true};

  @override
  Future<void> deleteDownloadedTrack(String trackId) async {
    deleted.add(trackId);
    downloaded.remove(trackId);
    notifyListeners();
  }

  @override
  Future<void> downloadTrack(Track track) async => started.add(track.id);

  @override
  void cancelDownload(String trackId) {
    cancelled.add(trackId);
    running.remove(trackId);
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _P p;
  late ThemeProvider themes;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final ready = Completer<void>();
    final original = debugPrint;
    debugPrint = (msg, {wrapWidth}) {
      if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) ready.complete();
    };
    p = _P();
    themes = ThemeProvider();
    await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    debugPrint = original;
  });

  setUp(() {
    p.downloaded.clear();
    p.deleted.clear();
    p.started.clear();
    p.cancelled.clear();
    p.running.clear();
    p.debugSetCurrentTrack(null);
    p.clearQueue();
  });

  Future<void> open(
    WidgetTester tester, {
    SongSheetOrigin origin = SongSheetOrigin.auto,
    Track? track,
    String? playlistId,
    VoidCallback? onDislike,
  }) async {
    tester.view.physicalSize = const Size(1200, 2600);
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
              child: GestureDetector(
                onLongPress: () => ThemedOptionsSheet.show(
                  context,
                  track: track ?? song(),
                  origin: origin,
                  playlistId: playlistId,
                  onDislike: onDislike,
                ),
                child: const SizedBox(width: 120, height: 120, child: Text('card')),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.longPress(find.text('card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  group('what each place offers', () {
    testWidgets('Home: the song things, and no Sleep Timer or Song Info', (tester) async {
      await open(tester, origin: SongSheetOrigin.home);
      for (final t in ['Play next', 'Add to queue', 'Download', 'Share', 'Add to a playlist...', 'Go to album', 'Go to artist']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Sleep Timer'), findsNothing);
      expect(find.text('Song Info'), findsNothing);
    });

    testWidgets('Search: same as Home', (tester) async {
      await open(tester, origin: SongSheetOrigin.search);
      expect(find.text('Sleep Timer'), findsNothing);
      expect(find.text('Song Info'), findsNothing);
      expect(find.text('Add to queue'), findsOneWidget);
    });

    testWidgets('the player: Sleep Timer and Song Info, and no Add to queue for the playing song', (tester) async {
      p.debugSetCurrentTrack(song());
      await open(tester, origin: SongSheetOrigin.nowPlaying);
      expect(find.text('Sleep Timer'), findsOneWidget);
      expect(find.text('Song Info'), findsOneWidget);
      expect(find.text('Add to queue'), findsNothing);
      expect(find.text('Play next'), findsNothing);
    });

    testWidgets('a file on the phone: no Download, no Share, no Go to album', (tester) async {
      await open(tester, track: song(source: 'local'));
      expect(find.text('Download'), findsNothing);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Go to album'), findsNothing);
      expect(find.text('Add to a playlist...'), findsOneWidget);
    });

    testWidgets('Go to album names the album', (tester) async {
      await open(tester, origin: SongSheetOrigin.home);
      expect(find.text('Troubadour'), findsOneWidget);
    });

    testWidgets('Explore: Not interested, when it brings the callback', (tester) async {
      var disliked = 0;
      await open(tester, origin: SongSheetOrigin.explore, onDislike: () => disliked++);
      await tester.ensureVisible(find.text('Not interested'));
      await tester.tap(find.text('Not interested'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(disliked, 1);
    });
  });

  group('instant actions answer in place', () {
    testWidgets('Play next turns into a check, says "Playing next", then the sheet closes', (tester) async {
      await open(tester, origin: SongSheetOrigin.home);
      await tester.tap(find.text('Play next'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Playing next'), findsOneWidget, reason: 'the tile morphed to the past tense');
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      // The check holds for a beat, then the sheet's own 320 ms exit.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Add to queue'), findsNothing, reason: 'and the sheet is gone');
      expect(find.text('Playing "Wavin Flag" next'), findsOneWidget, reason: 'with the toast the sheet no longer hides');
    });

    testWidgets('a double tap does not queue the song twice', (tester) async {
      await open(tester, origin: SongSheetOrigin.home);
      final before = p.queue.length;
      await tester.tap(find.text('Add to queue'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('Added'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600));
      expect(p.queue.length, before + 1);
    });
  });

  group('downloads', () {
    testWidgets('Download starts it, shows Queued, and closes', (tester) async {
      await open(tester, origin: SongSheetOrigin.home);
      await tester.tap(find.text('Download'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(p.started, ['abcdefghijk']);
      expect(find.text('Queued'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('a downloaded song says Downloaded - and asks before it deletes', (tester) async {
      p.downloaded.add('abcdefghijk');
      await open(tester, origin: SongSheetOrigin.home);
      expect(find.text('Downloaded'), findsOneWidget);

      await tester.tap(find.text('Downloaded'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Remove this download?'), findsOneWidget, reason: 'it used to just say "already downloaded"');
      expect(find.textContaining('will no longer play offline'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(p.deleted, isEmpty, reason: 'Cancel changes nothing');
      expect(find.text('Downloaded'), findsOneWidget);

      await tester.tap(find.text('Downloaded'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(p.deleted, ['abcdefghijk']);
      expect(find.text('Download'), findsOneWidget, reason: 'the tile turned back into Download, in place');
      expect(find.text('Download removed'), findsOneWidget);
    });

    testWidgets('in the Downloads screen the tile is Remove, and it confirms then closes', (tester) async {
      p.downloaded.add('abcdefghijk');
      await open(tester, origin: SongSheetOrigin.downloads);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Remove this download?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(p.deleted, ['abcdefghijk']);
      expect(find.text('Add to queue'), findsNothing, reason: 'the sheet closed');
    });

    testWidgets('a download in progress shows its percentage and can be cancelled', (tester) async {
      p.running.add('abcdefghijk');
      await open(tester, origin: SongSheetOrigin.home);
      expect(find.text('0%'), findsOneWidget);
      await tester.tap(find.text('0%'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(p.cancelled, ['abcdefghijk']);
      expect(find.text('Download'), findsOneWidget, reason: 'and the tile is Download again');
    });
  });

  group('the queue', () {
    testWidgets('Remove from Queue appears for a song that is in it, and removes it', (tester) async {
      final t = song(id: 'queuedsong1');
      p.addToQueue(t);
      await open(tester, origin: SongSheetOrigin.queue, track: t);
      expect(find.text('Remove from Queue'), findsOneWidget);
      await tester.ensureVisible(find.text('Remove from Queue'));
      await tester.tap(find.text('Remove from Queue'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(p.queue.any((x) => x.id == t.id), isFalse);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('and not for a song that is not', (tester) async {
      await open(tester, origin: SongSheetOrigin.queue, track: song(id: 'notqueued01'));
      expect(find.text('Remove from Queue'), findsNothing);
    });
  });
}
